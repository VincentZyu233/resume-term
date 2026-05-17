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
        foreground: Color(0xFFCCCCCC),
        cursor: Color(0xFFCCCCCC),
        selection: Color(0xFF264F78),
        black: Color(0xFF000000),
        red: Color(0xFFCD3131),
        green: Color(0xFF0DBC79),
        yellow: Color(0xFFE5E510),
        blue: Color(0xFF2472C8),
        magenta: Color(0xFFBC3FBC),
        cyan: Color(0xFF11A8CD),
        white: Color(0xFFE5E5E5),
        brightBlack: Color(0xFF666666),
        brightRed: Color(0xFFF14C4C),
        brightGreen: Color(0xFF23D18B),
        brightYellow: Color(0xFFF5F543),
        brightBlue: Color(0xFF3B8EEA),
        brightMagenta: Color(0xFFD670D6),
        brightCyan: Color(0xFF29B8DB),
        brightWhite: Color(0xFFE5E5E5),
        searchHitForeground: Color(0xFF000000),
        searchHitBackground: Color(0xFFFFD700),
        searchHitBackgroundCurrent: Color(0xFFFFA500),
      ),
    );
  }
}
