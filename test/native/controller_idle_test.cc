#include "../../desktop/controller_idle.h"

#include <cassert>

int main() {
  send::ControllerAxis stick;
  assert(!stick.Moved(0, 8000, 4096));
  assert(!stick.Moved(3200, 8000, 4096));  // Center drift.
  assert(!stick.Moved(7900, 8000, 4096));
  assert(stick.Moved(8300, 8000, 4096));  // Deliberate movement.
  assert(!stick.Moved(7900, 8000, 4096));  // Jitter across the boundary.
  assert(!stick.Moved(8300, 8000, 4096));  // Held.
  assert(stick.Moved(0, 8000, 4096));  // Return to center.
  assert(!stick.Moved(500, 8000, 4096));

  send::ControllerAxis trigger;
  trigger.Baseline(-32767);  // Some Linux triggers rest at the negative end.
  assert(!trigger.Moved(-32650, 8000, 4096));
  assert(trigger.Moved(-16000, 8000, 4096));
  assert(!trigger.Moved(-16020, 8000, 4096));

  send::ControllerIdleClock clock;
  const auto limit = send::kDesktopIdleTimeoutMillis;
  assert(clock.Merge(limit, 1000) == limit);
  assert(clock.Merge(-1, 1000) == -1);
  clock.RecordInput(1000);
  assert(clock.Merge(limit, 1100) == 100);  // Controller wakes idle session.
  assert(clock.Merge(5, 1100) == 5);  // Newer keyboard input still wins.
  assert(clock.Merge(-1, 1100) == 100);
  assert(clock.Merge(limit, 1000 + limit - 1) == limit - 1);
  assert(clock.Merge(limit * 2, 1000 + limit) == limit);  // AFK still works.
  assert(clock.Merge(-1, 1000 + limit) == -1);  // Unknown keyboard stays unknown.
}
