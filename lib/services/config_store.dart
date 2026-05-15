import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/workspace_config.dart';

class ConfigStore {
  ConfigStore(this.configDir);

  final String configDir;

  static String homeDirectory() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '.';
    }
    return Platform.environment['HOME'] ?? '.';
  }

  static String defaultConfigDir() {
    return path.join(homeDirectory(), 'resume-term', 'config');
  }

  static String configFilePath(String configDir) {
    return path.join(configDir, 'config.yaml');
  }

  Future<WorkspaceConfig> loadOrCreate() async {
    final directory = Directory(configDir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final file = File(configFilePath(configDir));
    if (!await file.exists()) {
      final config = WorkspaceConfig.defaults(configDir: configDir);
      await save(config);
      return config;
    }
    final text = await file.readAsString();
    return WorkspaceConfig.fromYamlString(text);
  }

  Future<void> save(WorkspaceConfig config) async {
    final directory = Directory(configDir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final file = File(configFilePath(configDir));
    await file.writeAsString(config.copyWith(configDir: configDir).toYamlString());
  }
}

