#pragma once
#include <gtk/gtk.h>

// -1 means the session does not expose global idle information and no recent
// controller activity is known.
gint64 desktop_idle_milliseconds();
void stop_desktop_controller_monitor();
