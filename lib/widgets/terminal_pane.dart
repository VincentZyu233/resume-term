import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_xterm/flutter_xterm.dart';

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
  late final TerminalController _controller;
  Timer? _pollTimer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
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
      _controller.write('Failed to start terminal: $e\r\n');
    }
  }

  void _poll() {
    if (!_started) return;
    try {
      final data = TerminalService.instance.read(widget.leafId);
      if (data.isNotEmpty) {
        _controller.write(utf8.decode(data));
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Terminal(
      controller: _controller,
      onOutput: _onOutput,
      style: const TerminalStyle(
        background: Colors.black87,
        foreground: Colors.greenAccent,
        cursor: Colors.greenAccent,
        fontSize: 13.0,
        fontFamily: 'monospace',
      ),
    );
  }
}
