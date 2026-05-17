import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:xterm/flutter.dart';
import 'package:xterm/xterm.dart';

import '../models/workspace_config.dart';
import '../services/terminal_service.dart';

class TerminalPane extends StatefulWidget {
  final String leafId;
  final PaneLeaf config;

  const TerminalPane({
    super.key,
    required this.leafId,
    required this.config,
  });

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  late final Terminal _terminal;
  Timer? _pollTimer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      onOutput: _onOutput,
      theme: TerminalTheme(
        background: const Color(0xFF1E1E1E),
        foreground: const Color(0xFF00FF00),
        cursor: const Color(0xFF00FF00),
        selection: const Color(0xFF6A8759),
      ),
    );
    _startTerminal();
  }

  Future<void> _startTerminal() async {
    try {
      await TerminalService.instance.start(widget.leafId, widget.config);
      _started = true;
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => _poll(),
      );
    } catch (e) {
      _terminal.write('Failed to start terminal: $e\r\n');
    }
  }

  void _poll() {
    if (!_started) return;
    try {
      final data = TerminalService.instance.read(widget.leafId);
      if (data.isNotEmpty) {
        _terminal.write(utf8.decode(data));
      }
    } catch (_) {}
  }

  void _onOutput(String data) {
    if (_started) {
      TerminalService.instance.write(widget.leafId, utf8.encode(data));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_started) {
      TerminalService.instance.stop(widget.leafId);
    }
    _terminal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      _terminal,
      autofocus: true,
    );
  }
}
