#include "desktop_idle.h"

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <gdk/gdkx.h>
#include <gdk/gdkwayland.h>
#include <X11/extensions/scrnsaver.h>
#include <linux/joystick.h>
#include <unistd.h>
#include "../../desktop/controller_idle.h"
#include "ext-idle-notify-v1-client-protocol.h"

namespace {
constexpr gint64 kIdleTimeout = send_desktop::kDesktopIdleTimeoutMillis;
ext_idle_notifier_v1* notifier = nullptr;
ext_idle_notification_v1* notification = nullptr;
wl_seat* seat = nullptr;
bool idle = false;
uint32_t notifier_name = 0;
uint32_t seat_name = 0;

// joydev exposes joystick events only. Do not open keyboard/mouse event
// devices or request additional permissions if a controller is inaccessible.
struct Joystick {
  int fd = -1;
  std::array<send_desktop::ControllerAxis, 256> axes{};
  std::array<bool, 256> buttons{};
};
std::array<Joystick, 32> joysticks;
send_desktop::ControllerIdleClock controller_idle;
guint joystick_timer = 0;
gint64 next_joystick_open = 0;

gboolean PollJoysticks(gpointer) {
  const gint64 now = g_get_monotonic_time() / 1000;
  if (now >= next_joystick_open) {
    next_joystick_open = now + 2000;
    for (size_t i = 0; i < joysticks.size(); ++i) {
      auto& joystick = joysticks[i];
      if (joystick.fd >= 0) continue;
      char path[32];
      std::snprintf(path, sizeof(path), "/dev/input/js%zu", i);
      joystick.fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
    }
  }

  for (auto& joystick : joysticks) {
    if (joystick.fd < 0) continue;
    js_event events[64];
    const auto bytes = read(joystick.fd, events, sizeof(events));
    if (bytes < 0 && (errno == EAGAIN || errno == EWOULDBLOCK ||
                      errno == EINTR)) {
      continue;
    }
    if (bytes <= 0) {
      close(joystick.fd);
      joystick = Joystick{};
      continue;
    }
    for (size_t i = 0; i < static_cast<size_t>(bytes) / sizeof(js_event); ++i) {
      const auto& event = events[i];
      const bool initial = (event.type & JS_EVENT_INIT) != 0;
      switch (event.type & ~JS_EVENT_INIT) {
        case JS_EVENT_BUTTON: {
          auto& previous = joystick.buttons[event.number];
          const bool pressed = event.value != 0;
          if (!initial && pressed != previous) controller_idle.RecordInput(now);
          previous = pressed;
          break;
        }
        case JS_EVENT_AXIS: {
          auto& axis = joystick.axes[event.number];
          if (initial) {
            axis.Baseline(event.value);
          } else if (axis.Moved(event.value, 8000, 4096)) {
            controller_idle.RecordInput(now);
          }
          break;
        }
      }
    }
  }
  return G_SOURCE_CONTINUE;
}

void OnIdle(void*, ext_idle_notification_v1*) { idle = true; }
void OnResumed(void*, ext_idle_notification_v1*) { idle = false; }
const ext_idle_notification_v1_listener idle_listener = {OnIdle, OnResumed};

void WatchSeat() {
  if (!notifier || !seat || notification) return;
  notification = ext_idle_notifier_v1_get_version(notifier) >= 2
      ? ext_idle_notifier_v1_get_input_idle_notification(notifier, kIdleTimeout, seat)
      : ext_idle_notifier_v1_get_idle_notification(notifier, kIdleTimeout, seat);
  ext_idle_notification_v1_add_listener(notification, &idle_listener, nullptr);
}

void OnGlobal(void*, wl_registry* registry, uint32_t name,
              const char* interface, uint32_t version) {
  if (!std::strcmp(interface, ext_idle_notifier_v1_interface.name)) {
    notifier_name = name;
    notifier = static_cast<ext_idle_notifier_v1*>(wl_registry_bind(
        registry, name, &ext_idle_notifier_v1_interface, std::min(version, 2u)));
  } else if (!seat && !std::strcmp(interface, wl_seat_interface.name)) {
    seat_name = name;
    seat = static_cast<wl_seat*>(wl_registry_bind(registry, name, &wl_seat_interface, 1));
  }
  WatchSeat();
}

void OnGlobalRemove(void*, wl_registry*, uint32_t name) {
  if (name != notifier_name && name != seat_name) return;
  if (notification) ext_idle_notification_v1_destroy(notification);
  notification = nullptr;
  idle = false;
  if (name == notifier_name && notifier) {
    ext_idle_notifier_v1_destroy(notifier);
    notifier = nullptr;
  }
  if (name == seat_name && seat) {
    wl_seat_destroy(seat);
    seat = nullptr;
  }
}
const wl_registry_listener registry_listener = {OnGlobal, OnGlobalRemove};

// GNOME does not expose ext-idle-notify. Query its session service
// asynchronously so a missing/slow bus never stalls Flutter's platform thread.
gint64 gnome_idle = -1;
gint64 gnome_sample_at = 0;
bool gnome_pending = false;
void QueryGnome() {
  if (gnome_pending) return;
  gnome_pending = true;
  g_bus_get(G_BUS_TYPE_SESSION, nullptr, [](GObject*, GAsyncResult* result, gpointer) {
    GError* error = nullptr;
    GDBusConnection* connection = g_bus_get_finish(result, &error);
    if (!connection) {
      g_clear_error(&error);
      gnome_pending = false;
      return;
    }
    g_dbus_connection_call(connection, "org.gnome.Mutter.IdleMonitor",
        "/org/gnome/Mutter/IdleMonitor/Core", "org.gnome.Mutter.IdleMonitor",
        "GetIdletime", nullptr, G_VARIANT_TYPE("(t)"), G_DBUS_CALL_FLAGS_NO_AUTO_START,
        1500, nullptr, [](GObject* source, GAsyncResult* result, gpointer) {
          GError* error = nullptr;
          GVariant* reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
          gnome_idle = -1;
          if (reply) {
            guint64 milliseconds = 0;
            g_variant_get(reply, "(t)", &milliseconds);
            gnome_idle = static_cast<gint64>(milliseconds);
            gnome_sample_at = g_get_monotonic_time();
            g_variant_unref(reply);
          }
          g_clear_error(&error);
          gnome_pending = false;
        }, nullptr);
    g_object_unref(connection);
  }, nullptr);
}
gint64 session_idle_milliseconds() {
  GdkDisplay* display = gdk_display_get_default();
  if (!display) return -1;
  if (GDK_IS_X11_DISPLAY(display) && !g_getenv("WAYLAND_DISPLAY") &&
      g_strcmp0(g_getenv("XDG_SESSION_TYPE"), "wayland") != 0) {
    // Dynamic loading keeps minimal/AppImage hosts without libXss launchable.
    static void* library = dlopen("libXss.so.1", RTLD_LAZY | RTLD_LOCAL);
    using Query = Status (*)(Display*, Drawable, XScreenSaverInfo*);
    static Query query = library ? reinterpret_cast<Query>(dlsym(library, "XScreenSaverQueryInfo")) : nullptr;
    if (query) {
      XScreenSaverInfo info{};
      Display* xdisplay = gdk_x11_display_get_xdisplay(display);
      if (query(xdisplay, DefaultRootWindow(xdisplay), &info)) return info.idle;
    }
  } else if (GDK_IS_WAYLAND_DISPLAY(display)) {
    static wl_registry* registry = nullptr;
    if (!registry) {
      // GTK dispatches the default Wayland queue; no roundtrip or extra thread.
      auto* wayland = gdk_wayland_display_get_wl_display(display);
      registry = wl_display_get_registry(wayland);
      wl_registry_add_listener(registry, &registry_listener, nullptr);
      wl_display_flush(wayland);
    }
    if (notification) return idle ? kIdleTimeout : 0;
  }
  QueryGnome();
  return gnome_idle >= 0 && g_get_monotonic_time() - gnome_sample_at < 15000000
      ? gnome_idle : -1;
}
}  // namespace

gint64 desktop_idle_milliseconds() {
  if (!joystick_timer) {
    PollJoysticks(nullptr);
    joystick_timer =
        g_timeout_add_full(G_PRIORITY_LOW, 100, PollJoysticks, nullptr, nullptr);
  }
  return controller_idle.Merge(session_idle_milliseconds(),
                               g_get_monotonic_time() / 1000);
}

void stop_desktop_controller_monitor() {
  if (joystick_timer) g_source_remove(joystick_timer);
  joystick_timer = 0;
  next_joystick_open = 0;
  controller_idle = {};
  for (auto& joystick : joysticks) {
    if (joystick.fd >= 0) close(joystick.fd);
    joystick = Joystick{};
  }
}
