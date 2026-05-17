import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
        black: const Color(0xFF000000),
        red: const Color(0xFFAA0000),
        green: const Color(0xFF00AA00),
        yellow: const Color(0xFFAA5500),
        blue: const Color(0xFF0000AA),
        magenta: const Color(0xFFAA00AA),
        cyan: const Color(0xFF00AAAA),
        white: const Color(0xFFAAAAAA),
        brightBlack: const Color(0xFF555555),
        brightRed: const Color(0xFFFF5555),
        brightGreen: const Color(0xFF55FF55),
        brightYellow: const Color(0xFFFFFF55),
        brightBlue: const Color(0xFF5555FF),
        brightMagenta: const Color(0xFFFF55FF),
        brightCyan: const Color(0xFF55FFFF),
        brightWhite: const Color(0xFFFFFFFF),
        searchHitForeground: const Color(0xFF000000),
        searchHitBackground: const Color(0xFFFFD700),
        searchHitBackgroundCurrent: const Color(0xFFFFA500),
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
