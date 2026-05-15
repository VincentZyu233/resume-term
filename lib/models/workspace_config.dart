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
  WorkspaceSession({required this.name, required this.root});

  factory WorkspaceSession.fromMap(Map<String, dynamic> json) {
    return WorkspaceSession(
      name: _string(json['name'], fallback: 'Session'),
      root: paneNodeFromMap(_map(json['root'])),
    );
  }

  final String name;
  final PaneNode root;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': name,
        'root': root.toMap(),
      };

  WorkspaceSession copyWith({String? name, PaneNode? root}) {
    return WorkspaceSession(name: name ?? this.name, root: root ?? this.root);
  }

  PaneLeaf? firstLeaf() => root.firstLeaf();

  PaneLeaf? findLeaf(String id) => root.findLeaf(id);

  WorkspaceSession replaceLeaf(String targetId, PaneNode Function(PaneLeaf leaf) replacer) {
    final nextRoot = root.replaceLeaf(targetId, replacer);
    if (nextRoot == null) return this;
    return copyWith(root: nextRoot);
  }
}

class WorkspaceConfig {
  WorkspaceConfig({
    required this.version,
    required this.configDir,
    required this.selectedSession,
    required this.sessions,
  });

  factory WorkspaceConfig.defaults({required String configDir}) {
    return WorkspaceConfig(
      version: 1,
      configDir: configDir,
      selectedSession: 0,
      sessions: <WorkspaceSession>[
        WorkspaceSession(
          name: 'Default',
          root: PaneLeaf.defaultLeaf(title: 'Pane 1'),
        ),
      ],
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
    return WorkspaceConfig(
      version: _int(json['version'], fallback: 1),
      configDir: _string(json['config_dir']),
      selectedSession: _int(json['selected_session'], fallback: 0),
      sessions: sessions.isEmpty
          ? <WorkspaceSession>[
              WorkspaceSession(
                name: 'Default',
                root: PaneLeaf.defaultLeaf(title: 'Pane 1'),
              ),
            ]
          : sessions,
    );
  }

  final int version;
  final String configDir;
  final int selectedSession;
  final List<WorkspaceSession> sessions;

  WorkspaceSession get activeSession {
    final index = selectedSession.clamp(0, sessions.length - 1).toInt();
    return sessions[index];
  }

  WorkspaceConfig copyWith({
    int? version,
    String? configDir,
    int? selectedSession,
    List<WorkspaceSession>? sessions,
  }) {
    return WorkspaceConfig(
      version: version ?? this.version,
      configDir: configDir ?? this.configDir,
      selectedSession: selectedSession ?? this.selectedSession,
      sessions: sessions ?? this.sessions,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'version': version,
        'config_dir': configDir,
        'selected_session': selectedSession,
        'sessions': sessions.map((session) => session.toMap()).toList(),
      };

  String toYamlString() {
    final yaml = _yamlFromValue(toMap());
    return '${yaml.trimRight()}\n';
  }

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toMap());

  WorkspaceConfig updateActiveSession(WorkspaceSession Function(WorkspaceSession session) updater) {
    final index = selectedSession.clamp(0, sessions.length - 1).toInt();
    final nextSessions = sessions.toList();
    nextSessions[index] = updater(activeSession);
    return copyWith(sessions: nextSessions);
  }
}
