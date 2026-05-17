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
      theme: const TerminalTheme(
        background: Color(0xFF1E1E1E),
        foreground: Color(0xFF00FF00),
        cursor: Color(0xFF00FF00),
        selection: Color(0xFF6A8759),
        black: Color(0xFF000000),
        red: Color(0xFFAA0000),
        green: Color(0xFF00AA00),
        yellow: Color(0xFFAA5500),
        blue: Color(0xFF0000AA),
        magenta: Color(0xFFAA00AA),
        cyan: Color(0xFF00AAAA),
        white: Color(0xFFAAAAAA),
        brightBlack: Color(0xFF555555),
        brightRed: Color(0xFFFF5555),
        brightGreen: Color(0xFF55FF55),
        brightYellow: Color(0xFFFFFF55),
        brightBlue: Color(0xFF5555FF),
        brightMagenta: Color(0xFFFF55FF),
        brightCyan: Color(0xFF55FFFF),
        brightWhite: Color(0xFFFFFFFF),
        searchHitForeground: Color(0xFF000000),
        searchHitBackground: Color(0xFFFFD700),
        searchHitBackgroundCurrent: Color(0xFFFFA500),
      ),
    );
  }
}
