import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../models/workspace_config.dart';
import '../services/terminal_service.dart';

TerminalTheme convertTheme(TerminalThemeConfig cfg) {
  Color hex(String s) => Color(int.parse(s.replaceFirst('#', '0xFF')));
  return TerminalTheme(
    background: hex(cfg.background),
    foreground: hex(cfg.foreground),
    cursor: hex(cfg.cursor),
    selection: hex(cfg.selection),
    black: hex(cfg.black),
    red: hex(cfg.red),
    green: hex(cfg.green),
    yellow: hex(cfg.yellow),
    blue: hex(cfg.blue),
    magenta: hex(cfg.magenta),
    cyan: hex(cfg.cyan),
    white: hex(cfg.white),
    brightBlack: hex(cfg.brightBlack),
    brightRed: hex(cfg.brightRed),
    brightGreen: hex(cfg.brightGreen),
    brightYellow: hex(cfg.brightYellow),
    brightBlue: hex(cfg.brightBlue),
    brightMagenta: hex(cfg.brightMagenta),
    brightCyan: hex(cfg.brightCyan),
    brightWhite: hex(cfg.brightWhite),
    searchHitForeground: hex(cfg.searchHitForeground),
    searchHitBackground: hex(cfg.searchHitBackground),
    searchHitBackgroundCurrent: hex(cfg.searchHitBackgroundCurrent),
  );
}

class TerminalPane extends StatefulWidget {
  final String leafId;
  final PaneLeaf config;
  final TerminalThemeConfig? themeConfig;

  const TerminalPane({
    super.key,
    required this.leafId,
    required this.config,
    this.themeConfig,
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
    final theme = widget.themeConfig ?? TerminalThemeConfig.defaults();
    return TerminalView(
      _terminal,
      autofocus: true,
      theme: convertTheme(theme),
    );
  }
}
