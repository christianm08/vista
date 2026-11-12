#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Schermo intero senza bordi sul monitor della finestra; all'uscita la
  // finestra torna com'era (posizione, dimensioni, massimizzata o no).
  void SetFullScreen(bool on);

  // Finestra piccola, sempre in primo piano, nell'angolo in basso a destra
  // (l'equivalente del Picture-in-Picture); all'uscita torna com'era.
  void SetMini(bool on);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Canale "vista/window": setFullScreen(bool), isFullScreen().
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  bool full_screen_ = false;
  bool mini_ = false;
  WINDOWPLACEMENT mini_saved_{sizeof(WINDOWPLACEMENT)};
  LONG saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_{sizeof(WINDOWPLACEMENT)};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
