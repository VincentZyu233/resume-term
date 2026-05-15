import 'dart:io';

class ShellDefaults {
  static String defaultShell() {
    if (Platform.isWindows) return 'pwsh';
    return 'bash';
  }

  static List<String> shellPriority() {
    if (Platform.isWindows) {
      return <String>['pwsh', 'powershell', 'cmd'];
    }
    return <String>['$SHELL', 'bash', 'zsh', 'sh', 'ash'];
  }
}

