import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

enum SplitDirection { horizontal, vertical }

String _newId(String prefix) {
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

String _platformDefaultShell() {
  return Platform.isWindows ? 'pwsh' : 'bash';
}

String _platformDefaultExecutable() {
  return _platformDefaultShell();
}

String _quote(String value) {
  final escaped = value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

String _scalar(dynamic value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  final text = value.toString();
  if (text.isEmpty) return '""';
  if (RegExp(r'^[A-Za-z0-9_./:\\-]+$').hasMatch(text)) {
    return text;
  }
  return _quote(text);
}

String _yamlFromValue(dynamic value, {int indent = 0}) {
  final pad = ' ' * indent;
  if (value is Map) {
    final buffer = StringBuffer();
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final child = entry.value;
      if (child is Map || child is List) {
        buffer.writeln('$pad$key:');
        buffer.write(_yamlFromValue(child, indent: indent + 2));
      } else {
        buffer.writeln('$pad$key: ${_scalar(child)}');
      }
    }
    return buffer.toString();
  }
  if (value is List) {
    final buffer = StringBuffer();
    for (final item in value) {
      if (item is Map || item is List) {
        buffer.writeln('$pad-');
        buffer.write(_yamlFromValue(item, indent: indent + 2));
      } else {
        buffer.writeln('$pad- ${_scalar(item)}');
      }
    }
    return buffer.toString();
  }
  return '$pad${_scalar(value)}\n';
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw FormatException('Expected map, got ${value.runtimeType}');
}

List<dynamic> _list(dynamic value) {
  if (value is List) return value;
  throw FormatException('Expected list, got ${value.runtimeType}');
}

String _string(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  return value.toString();
}

int _int(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  return int.tryParse(value.toString()) ?? fallback;
}

double _double(dynamic value, {double fallback = 0.5}) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

abstract class PaneNode {
  String get id;

  Map<String, dynamic> toMap();

  PaneNode? replaceLeaf(String targetId, PaneNode Function(PaneLeaf leaf) replacer);

  PaneLeaf? findLeaf(String targetId);

  PaneLeaf? firstLeaf();
}

class PaneLeaf extends PaneNode {
  PaneLeaf({
    required this.id,
    required this.title,
    required this.shell,
    required this.executable,
    required this.command,
    required this.workingDir,
    required this.args,
  });

  factory PaneLeaf.defaultLeaf({String? title}) {
    final shell = _platformDefaultShell();
    return PaneLeaf(
      id: _newId('leaf'),
      title: title ?? 'Pane',
      shell: shell,
      executable: _platformDefaultExecutable(),
      command: '',
      workingDir: '',
      args: const [],
    );
  }

  factory PaneLeaf.fromMap(Map<String, dynamic> json) {
    return PaneLeaf(
      id: _string(json['id'], fallback: _newId('leaf')),
      title: _string(json['title'], fallback: 'Pane'),
      shell: _string(json['shell'], fallback: _platformDefaultShell()),
      executable:
          _string(json['executable'], fallback: _platformDefaultExecutable()),
      command: _string(json['command']),
      workingDir: _string(json['working_dir']),
      args: json['args'] == null
          ? const []
          : _list(json['args']).map((item) => item.toString()).toList(),
    );
  }

  @override
  final String id;
  final String title;
  final String shell;
  final String executable;
  final String command;
  final String workingDir;
  final List<String> args;

  PaneLeaf copyWith({
    String? id,
    String? title,
    String? shell,
    String? executable,
    String? command,
    String? workingDir,
    List<String>? args,
  }) {
    return PaneLeaf(
      id: id ?? this.id,
      title: title ?? this.title,
      shell: shell ?? this.shell,
      executable: executable ?? this.executable,
      command: command ?? this.command,
      workingDir: workingDir ?? this.workingDir,
      args: args ?? this.args,
    );
  }

  @override
  Map<String, dynamic> toMap() => <String, dynamic>{
        'type': 'leaf',
        'id': id,
        'title': title,
        'shell': shell,
        'executable': executable,
        'command': command,
        'working_dir': workingDir,
        'args': args,
      };

  @override
  PaneNode? replaceLeaf(String targetId, PaneNode Function(PaneLeaf leaf) replacer) {
    if (id == targetId) return replacer(this);
    return null;
  }

  @override
  PaneLeaf? findLeaf(String targetId) => id == targetId ? this : null;

  @override
  PaneLeaf? firstLeaf() => this;
}

class PaneSplit extends PaneNode {
  PaneSplit({
    required this.id,
    required this.direction,
    required this.ratio,
    required this.first,
    required this.second,
  });

  factory PaneSplit.fromMap(Map<String, dynamic> json) {
    return PaneSplit(
      id: _string(json['id'], fallback: _newId('split')),
      direction: _string(json['direction'], fallback: 'horizontal') == 'vertical'
          ? SplitDirection.vertical
          : SplitDirection.horizontal,
      ratio: _double(json['ratio'], fallback: 0.5),
      first: paneNodeFromMap(_map(json['first'])),
      second: paneNodeFromMap(_map(json['second'])),
    );
  }

  @override
  final String id;
  final SplitDirection direction;
  final double ratio;
  final PaneNode first;
  final PaneNode second;

  @override
  Map<String, dynamic> toMap() => <String, dynamic>{
        'type': 'split',
        'id': id,
        'direction': direction.name,
        'ratio': ratio,
        'first': first.toMap(),
        'second': second.toMap(),
      };

  @override
  PaneNode? replaceLeaf(String targetId, PaneNode Function(PaneLeaf leaf) replacer) {
    final nextFirst = first.replaceLeaf(targetId, replacer);
    if (nextFirst != null) {
      return PaneSplit(
        id: id,
        direction: direction,
        ratio: ratio,
        first: nextFirst,
        second: second,
      );
    }
    final nextSecond = second.replaceLeaf(targetId, replacer);
    if (nextSecond != null) {
      return PaneSplit(
        id: id,
        direction: direction,
        ratio: ratio,
        first: first,
        second: nextSecond,
      );
    }
    return null;
  }

  @override
  PaneLeaf? findLeaf(String targetId) {
    return first.findLeaf(targetId) ?? second.findLeaf(targetId);
  }

  @override
  PaneLeaf? firstLeaf() {
    return first.firstLeaf() ?? second.firstLeaf();
  }
}

PaneNode paneNodeFromMap(Map<String, dynamic> json) {
  final type = _string(json['type'], fallback: 'leaf');
  if (type == 'split') {
    return PaneSplit.fromMap(json);
  }
  return PaneLeaf.fromMap(json);
}

class WorkspaceSession {
  WorkspaceSession({required this.id, required this.name, required this.root});

  factory WorkspaceSession.fromMap(Map<String, dynamic> json) {
    return WorkspaceSession(
      id: _string(json['id'], fallback: _newId('session')),
      name: _string(json['name'], fallback: 'Session'),
      root: paneNodeFromMap(_map(json['root'])),
    );
  }

  final String id;
  final String name;
  final PaneNode root;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'root': root.toMap(),
      };

  WorkspaceSession copyWith({String? id, String? name, PaneNode? root}) {
    return WorkspaceSession(
        id: id ?? this.id, name: name ?? this.name, root: root ?? this.root);
  }

  PaneLeaf? firstLeaf() => root.firstLeaf();

  PaneLeaf? findLeaf(String id) => root.findLeaf(id);

  WorkspaceSession replaceLeaf(String targetId, PaneNode Function(PaneLeaf leaf) replacer) {
    final nextRoot = root.replaceLeaf(targetId, replacer);
    if (nextRoot == null) return this;
    return copyWith(root: nextRoot);
  }
}

class TerminalThemeConfig {
  TerminalThemeConfig({
    required this.background,
    required this.foreground,
    required this.cursor,
    required this.selection,
    required this.black,
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.magenta,
    required this.cyan,
    required this.white,
    required this.brightBlack,
    required this.brightRed,
    required this.brightGreen,
    required this.brightYellow,
    required this.brightBlue,
    required this.brightMagenta,
    required this.brightCyan,
    required this.brightWhite,
    required this.searchHitForeground,
    required this.searchHitBackground,
    required this.searchHitBackgroundCurrent,
  });

  factory TerminalThemeConfig.defaults() => TerminalThemeConfig(
        background: '#1E1E1E',
        foreground: '#CCCCCC',
        cursor: '#CCCCCC',
        selection: '#264F78',
        black: '#000000',
        red: '#CD3131',
        green: '#0DBC79',
        yellow: '#E5E510',
        blue: '#2472C8',
        magenta: '#BC3FBC',
        cyan: '#11A8CD',
        white: '#E5E5E5',
        brightBlack: '#666666',
        brightRed: '#F14C4C',
        brightGreen: '#23D18B',
        brightYellow: '#F5F543',
        brightBlue: '#3B8EEA',
        brightMagenta: '#D670D6',
        brightCyan: '#29B8DB',
        brightWhite: '#E5E5E5',
        searchHitForeground: '#000000',
        searchHitBackground: '#FFD700',
        searchHitBackgroundCurrent: '#FFA500',
      );

  factory TerminalThemeConfig.fromMap(dynamic json) {
    if (json is! Map) return TerminalThemeConfig.defaults();
    final m = json is Map<String, dynamic>
        ? json
        : json.map((k, v) => MapEntry(k.toString(), v.toString()));
    final d = TerminalThemeConfig.defaults();
    String g(String key, String fallback) =>
        m[key] is String ? m[key] as String : fallback;
    return TerminalThemeConfig(
      background: g('background', d.background),
      foreground: g('foreground', d.foreground),
      cursor: g('cursor', d.cursor),
      selection: g('selection', d.selection),
      black: g('black', d.black),
      red: g('red', d.red),
      green: g('green', d.green),
      yellow: g('yellow', d.yellow),
      blue: g('blue', d.blue),
      magenta: g('magenta', d.magenta),
      cyan: g('cyan', d.cyan),
      white: g('white', d.white),
      brightBlack: g('bright_black', d.brightBlack),
      brightRed: g('bright_red', d.brightRed),
      brightGreen: g('bright_green', d.brightGreen),
      brightYellow: g('bright_yellow', d.brightYellow),
      brightBlue: g('bright_blue', d.brightBlue),
      brightMagenta: g('bright_magenta', d.brightMagenta),
      brightCyan: g('bright_cyan', d.brightCyan),
      brightWhite: g('bright_white', d.brightWhite),
      searchHitForeground: g('search_hit_foreground', d.searchHitForeground),
      searchHitBackground: g('search_hit_background', d.searchHitBackground),
      searchHitBackgroundCurrent:
          g('search_hit_background_current', d.searchHitBackgroundCurrent),
    );
  }

  Map<String, dynamic> toMap() => {
        'background': background,
        'foreground': foreground,
        'cursor': cursor,
        'selection': selection,
        'black': black,
        'red': red,
        'green': green,
        'yellow': yellow,
        'blue': blue,
        'magenta': magenta,
        'cyan': cyan,
        'white': white,
        'bright_black': brightBlack,
        'bright_red': brightRed,
        'bright_green': brightGreen,
        'bright_yellow': brightYellow,
        'bright_blue': brightBlue,
        'bright_magenta': brightMagenta,
        'bright_cyan': brightCyan,
        'bright_white': brightWhite,
        'search_hit_foreground': searchHitForeground,
        'search_hit_background': searchHitBackground,
        'search_hit_background_current': searchHitBackgroundCurrent,
      };

  final String background;
  final String foreground;
  final String cursor;
  final String selection;
  final String black;
  final String red;
  final String green;
  final String yellow;
  final String blue;
  final String magenta;
  final String cyan;
  final String white;
  final String brightBlack;
  final String brightRed;
  final String brightGreen;
  final String brightYellow;
  final String brightBlue;
  final String brightMagenta;
  final String brightCyan;
  final String brightWhite;
  final String searchHitForeground;
  final String searchHitBackground;
  final String searchHitBackgroundCurrent;
}

class WorkspaceConfig {
  WorkspaceConfig({
    required this.version,
    required this.configDir,
    this.startupSessionId,
    required this.sessions,
    required this.terminalTheme,
  });

  factory WorkspaceConfig.defaults({required String configDir}) {
    final defaultSession = WorkspaceSession(
      id: _newId('session'),
      name: 'Default',
      root: PaneLeaf.defaultLeaf(title: 'Pane 1'),
    );
    return WorkspaceConfig(
      version: 1,
      configDir: configDir,
      startupSessionId: defaultSession.id,
      sessions: <WorkspaceSession>[defaultSession],
      terminalTheme: TerminalThemeConfig.defaults(),
    );
  }

  factory WorkspaceConfig.fromYamlString(String yamlText) {
    final document = loadYaml(yamlText);
    final json = _map(document);
    final sessions = json['sessions'] == null
        ? <WorkspaceSession>[]
        : _list(json['sessions'])
            .map((item) => WorkspaceSession.fromMap(_map(item)))
            .toList();

    String? startupSessionId;
    final rawStartup = json['startup_session_id'];
    if (rawStartup != null && rawStartup.toString().isNotEmpty) {
      startupSessionId = rawStartup.toString();
    } else if (json.containsKey('selected_session')) {
      final idx = _int(json['selected_session'], fallback: 0);
      if (sessions.isNotEmpty && idx >= 0 && idx < sessions.length) {
        startupSessionId = sessions[idx].id;
      }
    }

    dynamic themeRaw;
    if (json['theme'] is Map) {
      themeRaw = _map(json['theme'])['terminal'];
    }
    final terminalTheme = TerminalThemeConfig.fromMap(themeRaw);

    return WorkspaceConfig(
      version: _int(json['version'], fallback: 1),
      configDir: _string(json['config_dir']),
      startupSessionId: startupSessionId,
      sessions: sessions.isEmpty
          ? <WorkspaceSession>[
              WorkspaceSession(
                id: _newId('session'),
                name: 'Default',
                root: PaneLeaf.defaultLeaf(title: 'Pane 1'),
              ),
            ]
          : sessions,
      terminalTheme: terminalTheme,
    );
  }

  final int version;
  final String configDir;
  final String? startupSessionId;
  final List<WorkspaceSession> sessions;
  final TerminalThemeConfig terminalTheme;

  WorkspaceSession get activeSession {
    if (startupSessionId != null) {
      final found = sessions.where((s) => s.id == startupSessionId).firstOrNull;
      if (found != null) return found;
    }
    return sessions.first;
  }

  WorkspaceConfig copyWith({
    int? version,
    String? configDir,
    String? startupSessionId,
    List<WorkspaceSession>? sessions,
    TerminalThemeConfig? terminalTheme,
  }) {
    return WorkspaceConfig(
      version: version ?? this.version,
      configDir: configDir ?? this.configDir,
      startupSessionId: startupSessionId ?? this.startupSessionId,
      sessions: sessions ?? this.sessions,
      terminalTheme: terminalTheme ?? this.terminalTheme,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'version': version,
      'config_dir': configDir,
      'sessions': sessions.map((session) => session.toMap()).toList(),
      'theme': <String, dynamic>{'terminal': terminalTheme.toMap()},
    };
    if (startupSessionId != null && startupSessionId!.isNotEmpty) {
      map['startup_session_id'] = startupSessionId;
    }
    return map;
  }

  String toYamlString() {
    final yaml = _yamlFromValue(toMap());
    return '${yaml.trimRight()}\n';
  }

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toMap());

  WorkspaceConfig updateActiveSession(WorkspaceSession Function(WorkspaceSession session) updater) {
    final active = activeSession;
    final index = sessions.indexWhere((s) => s.id == active.id);
    if (index < 0) return this;
    final nextSessions = sessions.toList();
    nextSessions[index] = updater(active);
    return copyWith(sessions: nextSessions);
  }
}
