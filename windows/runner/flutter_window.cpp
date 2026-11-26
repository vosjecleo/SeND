#include "flutter_window.h"

#include <optional>
#include <Xinput.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT_PTR kControllerTimer = 0x534E;
constexpr UINT kControllerPollMs = 50;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "net.deltie.deltiecord/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "idleMilliseconds") {
          if (!controller_timer_) {
            SampleControllers();
            controller_timer_ = ::SetTimer(
                GetHandle(), kControllerTimer, kControllerPollMs, nullptr);
          }
          LASTINPUTINFO input{sizeof(LASTINPUTINFO), 0};
          // Unsigned subtraction also handles the 49-day DWORD rollover.
          const int64_t session_idle = ::GetLastInputInfo(&input)
              ? static_cast<int64_t>(::GetTickCount() - input.dwTime)
              : -1;
          const auto idle = controller_idle_.Merge(
              session_idle, static_cast<int64_t>(::GetTickCount64()));
          if (idle >= 0) {
            result->Success(flutter::EncodableValue(idle));
          } else {
            result->Success();
          }
          return;
        }
        if (call.method_name() == "present") {
          HWND handle = GetHandle();
          if (::IsIconic(handle)) ::ShowWindow(handle, SW_RESTORE);
          ::ShowWindow(handle, SW_SHOW);
          ::SetForegroundWindow(handle);
          result->Success();
          return;
        }
        if (call.method_name() == "configure") {
          // Native-title-bar and persistent geometry toggles are currently a
          // GTK runner feature. Treat them as a safe no-op on Windows.
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (controller_timer_ && GetHandle()) {
    ::KillTimer(GetHandle(), controller_timer_);
  }
  controller_timer_ = 0;
  controllers_ = {};
  controller_idle_ = {};
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SampleControllers() {
  const auto now = static_cast<int64_t>(::GetTickCount64());
  for (DWORD index = 0; index < XUSER_MAX_COUNT; ++index) {
    auto& controller = controllers_[index];
    if (now < controller.retry_at) continue;
    XINPUT_STATE state{};
    if (::XInputGetState(index, &state) != ERROR_SUCCESS) {
      controller = {};
      controller.retry_at = now + 2000;
      continue;
    }
    const auto& gamepad = state.Gamepad;
    const int values[] = {gamepad.sThumbLX, gamepad.sThumbLY, gamepad.sThumbRX,
                          gamepad.sThumbRY, gamepad.bLeftTrigger,
                          gamepad.bRightTrigger};
    const int zones[] = {XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE,
                         XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE,
                         XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE,
                         XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE,
                         XINPUT_GAMEPAD_TRIGGER_THRESHOLD,
                         XINPUT_GAMEPAD_TRIGGER_THRESHOLD};
    bool moved = controller.connected && controller.buttons != gamepad.wButtons;
    for (size_t i = 0; i < controller.axes.size(); ++i) {
      if (!controller.connected) {
        controller.axes[i].Baseline(values[i]);
      } else if (controller.axes[i].Moved(values[i], zones[i], i < 4 ? 4096 : 24)) {
        moved = true;
      }
    }
    if (moved) controller_idle_.RecordInput(now);
    controller.buttons = gamepad.wButtons;
    controller.connected = true;
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_TIMER && controller_timer_ && wparam == controller_timer_) {
    SampleControllers();
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = 900;
      info->ptMinTrackSize.y = 600;
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
