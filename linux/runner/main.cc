#include "my_application.h"

#include <glib.h>
#include <sys/prctl.h>

int main(int argc, char** argv) {
  // XWayland's idle counter cannot see input directed to native Wayland
  // clients. Prefer the compositor's session-wide signal, with X11 fallback.
  // Respect a backend explicitly selected by the user.
  if (g_getenv("WAYLAND_DISPLAY") && !g_getenv("GDK_BACKEND")) {
    gdk_set_allowed_backends("wayland,x11");
  }
  // Keep desktop integration on the reverse-DNS application id while making
  // process monitors display the human-readable application name.
  g_set_prgname("SeND");
  prctl(PR_SET_NAME, "SeND", 0, 0, 0);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
