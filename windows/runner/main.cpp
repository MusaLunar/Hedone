#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdlib>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

std::wstring GetEnvVar(const wchar_t* name) {
  DWORD size = ::GetEnvironmentVariableW(name, nullptr, 0);
  if (size == 0) {
    return L"";
  }
  std::vector<wchar_t> buffer(size);
  DWORD written = ::GetEnvironmentVariableW(name, buffer.data(), size);
  if (written == 0) {
    return L"";
  }
  return std::wstring(buffer.data(), written);
}

// Flutter CLI debug runs inject `enable-dart-profiling`, which activates the
// Dart VM sampling stack walker (`ProfilerNativeStackWalker`) that can trigger
// an access violation in `flutter_windows.dll` on Windows x64. Stripping that
// switch before delay-loaded `flutter_windows.dll` initializes preserves Hot
// Reload and DevTools while keeping debug execution stable.
void StripUnsupportedDartProfilerSwitch() {
  std::wstring count_str = GetEnvVar(L"FLUTTER_ENGINE_SWITCHES");
  if (count_str.empty()) {
    return;
  }
  int count = _wtoi(count_str.c_str());
  if (count <= 0) {
    return;
  }

  std::vector<std::wstring> kept;
  kept.reserve(static_cast<size_t>(count));
  for (int i = 1; i <= count; ++i) {
    std::wstring key = L"FLUTTER_ENGINE_SWITCH_" + std::to_wstring(i);
    std::wstring val = GetEnvVar(key.c_str());
    if (val.empty()) {
      continue;
    }
    if (val == L"enable-dart-profiling" ||
        val == L"enable-dart-profiling=true" ||
        val == L"--enable-dart-profiling" ||
        val == L"--enable-dart-profiling=true") {
      continue;
    }
    kept.push_back(std::move(val));
  }

  if (static_cast<int>(kept.size()) == count) {
    return;
  }

  for (size_t i = 0; i < kept.size(); ++i) {
    std::wstring key = L"FLUTTER_ENGINE_SWITCH_" + std::to_wstring(i + 1);
    ::SetEnvironmentVariableW(key.c_str(), kept[i].c_str());
  }
  for (int i = static_cast<int>(kept.size()) + 1; i <= count; ++i) {
    std::wstring key = L"FLUTTER_ENGINE_SWITCH_" + std::to_wstring(i);
    ::SetEnvironmentVariableW(key.c_str(), nullptr);
  }
  if (kept.empty()) {
    ::SetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCHES", nullptr);
  } else {
    std::wstring next_count = std::to_wstring(kept.size());
    ::SetEnvironmentVariableW(L"FLUTTER_ENGINE_SWITCHES", next_count.c_str());
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  StripUnsupportedDartProfilerSwitch();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Hedone", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
