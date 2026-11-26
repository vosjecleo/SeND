#ifndef SEND_DESKTOP_CONTROLLER_IDLE_H_
#define SEND_DESKTOP_CONTROLLER_IDLE_H_

#include <algorithm>
#include <cstdint>
#include <cstdlib>

namespace send_desktop {

constexpr int64_t kDesktopIdleTimeoutMillis = 600000;

// Operates on changes, not held values. Remember the last accepted position
// so slow deliberate motion can accumulate without counting stick jitter.
class ControllerAxis {
 public:
  void Baseline(int value) {
    last_ = value;
    initialized_ = true;
  }

  bool Moved(int value, int dead_zone, int minimum_delta) {
    if (!initialized_) {
      Baseline(value);
      return false;
    }
    const bool either_outside = std::abs(last_) > dead_zone ||
                                std::abs(value) > dead_zone;
    if (!either_outside || std::abs(value - last_) < minimum_delta) {
      return false;
    }
    last_ = value;
    return true;
  }

 private:
  int last_ = 0;
  bool initialized_ = false;
};

class ControllerIdleClock {
 public:
  void RecordInput(int64_t now) { last_activity_ = now; }

  // Negative session time means unknown. A controller can prove recent
  // activity, but silence from it cannot prove the whole session is idle.
  int64_t Merge(int64_t session_idle, int64_t now) const {
    if (last_activity_ < 0 || now < last_activity_) return session_idle;
    const auto elapsed = now - last_activity_;
    if (session_idle >= 0) return std::min(session_idle, elapsed);
    return elapsed < kDesktopIdleTimeoutMillis ? elapsed : session_idle;
  }

 private:
  int64_t last_activity_ = -1;
};

}  // namespace send_desktop

#endif  // SEND_DESKTOP_CONTROLLER_IDLE_H_
