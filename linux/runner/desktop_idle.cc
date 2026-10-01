#include "desktop_idle.h"

#include <algorithm>
#include <cstring>
#include <dlfcn.h>
#include <gdk/gdkx.h>
#include <gdk/gdkwayland.h>
#include <X11/extensions/scrnsaver.h>
#include "ext-idle-notify-v1-client-protocol.h"

namespace {
constexpr gint64 kIdleTimeout = 600000;
ext_idle_notifier_v1* notifier = nullptr;
ext_idle_notification_v1* notification = nullptr;
wl_seat* seat = nullptr;
bool idle = false;
uint32_t notifier_name = 0;
uint32_t seat_name = 0;

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
}  // namespace

gint64 desktop_idle_milliseconds() {
  GdkDisplay* display = gdk_display_get_default();
  if (!display) return -1;
  if (GDK_IS_X11_DISPLAY(display)) {
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
