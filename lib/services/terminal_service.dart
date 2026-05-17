import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../ffi/native_bridge.dart';
import '../models/workspace_config.dart';

class TerminalService {
  TerminalService._();

  static final TerminalService _instance = TerminalService._();
  static TerminalService get instance => _instance;

  final NativeBridge _bridge = NativeBridge.instance;

  final Set<String> _activeSessions = {};

  Future<void> start(String id, PaneLeaf config) async {
    final result = _bridge.spawn(
      id,
      config.shell,
      executable: config.executable.isEmpty ? null : config.executable,
      workingDir: config.workingDir.isEmpty ? null : config.workingDir,
      cols: 80,
      rows: 24,
    );

    if (result != 0) {
      throw Exception('PTY spawn failed (error $result) for pane: ${config.title}');
    }

    _activeSessions.add(id);

    if (config.command.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 300));
      write(id, utf8.encode('${config.command}\r\n'));
    }
  }

  Uint8List read(String id) {
    if (!_activeSessions.contains(id)) return Uint8List(0);

    final available = _bridge.available(id);
    if (available <= 0) return Uint8List(0);

    final buf = Uint8List(available);
    final n = _bridge.read(id, buf);
    if (n <= 0) return Uint8List(0);

    return Uint8List.sublistView(buf, 0, n);
  }

  void write(String id, Uint8List data) {
    if (!_activeSessions.contains(id)) return;
    _bridge.write(id, data);
  }

  void stop(String id) {
    if (!_activeSessions.contains(id)) return;
    _bridge.close(id);
    _activeSessions.remove(id);
  }

  void stopAll() {
    for (final id in _activeSessions.toList()) {
      stop(id);
    }
  }
}
