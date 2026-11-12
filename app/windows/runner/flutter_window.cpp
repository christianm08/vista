#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

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
          flutter_controller_->engine()->messenger(), "vista/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setFullScreen") {
          const auto* on = std::get_if<bool>(call.arguments());
          SetFullScreen(on != nullptr && *on);
          result->Success(flutter::EncodableValue(full_screen_));
        } else if (call.method_name() == "isFullScreen") {
          result->Success(flutter::EncodableValue(full_screen_));
        } else if (call.method_name() == "freeSpace") {
          // Spazio libero (byte) sull'unità della cartella indicata.
          const auto* path = std::get_if<std::string>(call.arguments());
          if (path == nullptr) {
            result->Success();
            return;
          }
          const int n = MultiByteToWideChar(CP_UTF8, 0, path->c_str(), -1,
                                            nullptr, 0);
          std::wstring wide(n, L'\0');
          MultiByteToWideChar(CP_UTF8, 0, path->c_str(), -1, wide.data(), n);
          ULARGE_INTEGER free_bytes;
          if (GetDiskFreeSpaceExW(wide.c_str(), &free_bytes, nullptr,
                                  nullptr)) {
            result->Success(flutter::EncodableValue(
                static_cast<int64_t>(free_bytes.QuadPart)));
          } else {
            result->Success();
          }
        } else if (call.method_name() == "setMini") {
          const auto* on = std::get_if<bool>(call.arguments());
          SetMini(on != nullptr && *on);
          result->Success(flutter::EncodableValue(mini_));
        } else {
          result->NotImplemented();
        }
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

void FlutterWindow::SetFullScreen(bool on) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || on == full_screen_) {
    return;
  }
  if (on) {
    saved_style_ = GetWindowLong(hwnd, GWL_STYLE);
    saved_placement_.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(hwnd, &saved_placement_);
    MONITORINFO monitor{sizeof(MONITORINFO)};
    GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                   &monitor);
    const RECT& r = monitor.rcMonitor;
    SetWindowLong(hwnd, GWL_STYLE, saved_style_ & ~WS_OVERLAPPEDWINDOW);
    SetWindowPos(hwnd, HWND_TOP, r.left, r.top, r.right - r.left,
                 r.bottom - r.top, SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    SetWindowLong(hwnd, GWL_STYLE, saved_style_);
    SetWindowPlacement(hwnd, &saved_placement_);
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_FRAMECHANGED);
  }
  full_screen_ = on;
}

void FlutterWindow::SetMini(bool on) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || on == mini_) {
    return;
  }
  if (on) {
    if (full_screen_) {
      SetFullScreen(false);
    }
    mini_saved_.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(hwnd, &mini_saved_);
    MONITORINFO monitor{sizeof(MONITORINFO)};
    GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                   &monitor);
    const RECT& work = monitor.rcWork;
    const UINT dpi = GetDpiForWindow(hwnd);
    const int width = MulDiv(480, dpi, 96);
    const int height = MulDiv(300, dpi, 96);
    const int margin = MulDiv(24, dpi, 96);
    ShowWindow(hwnd, SW_RESTORE);
    SetWindowPos(hwnd, HWND_TOPMOST, work.right - width - margin,
                 work.bottom - height - margin, width, height,
                 SWP_SHOWWINDOW);
  } else {
    SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE);
    SetWindowPlacement(hwnd, &mini_saved_);
  }
  mini_ = on;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
