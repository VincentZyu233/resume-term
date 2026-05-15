import 'package:flutter/material.dart';

import '../models/workspace_config.dart';
import '../services/config_store.dart';
import '../services/shell_defaults.dart';

enum SplitAction { horizontal, vertical, auto }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TextEditingController _configDirController;
  late Future<void> _loader;
  WorkspaceConfig? _config;
  String? _selectedLeafId;
  String _status = 'Loading...';

  @override
  void initState() {
    super.initState();
    _configDirController = TextEditingController(text: ConfigStore.defaultConfigDir());
    _loader = _load();
  }

  @override
  void dispose() {
    _configDirController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _status = 'Loading config...';
    });
    final store = ConfigStore(_configDirController.text.trim());
    final config = await store.loadOrCreate();
    final firstLeaf = config.activeSession.firstLeaf();
    if (!mounted) return;
    setState(() {
      _config = config;
      _selectedLeafId = firstLeaf?.id;
      _status = 'Loaded ${ConfigStore.configFilePath(_configDirController.text.trim())}';
    });
  }

  Future<void> _save() async {
    final config = _config;
    if (config == null) return;
    final store = ConfigStore(_configDirController.text.trim());
    final next = config.copyWith(configDir: _configDirController.text.trim());
    await store.save(next);
    if (!mounted) return;
    setState(() {
      _config = next;
      _status = 'Saved ${ConfigStore.configFilePath(_configDirController.text.trim())}';
    });
  }

  void _applyConfigDir() {
    setState(() {
      _loader = _load();
    });
  }

  void _selectLeaf(String id) {
    setState(() {
      _selectedLeafId = id;
    });
  }

  void _updateLeaf(PaneLeaf updated) {
    final config = _config;
    if (config == null) return;
    final session = config.activeSession.replaceLeaf(updated.id, (_) => updated);
    final nextConfig = config.updateActiveSession((_) => session);
    setState(() {
      _config = nextConfig;
      _status = 'Pane updated';
    });
  }

  void _splitSelectedPane(SplitAction action, BoxConstraints constraints) {
    final config = _config;
    final selectedId = _selectedLeafId;
    if (config == null || selectedId == null) return;

    final actualDirection = switch (action) {
      SplitAction.horizontal => SplitDirection.horizontal,
      SplitAction.vertical => SplitDirection.vertical,
      SplitAction.auto => constraints.maxWidth > constraints.maxHeight
          ? SplitDirection.vertical
          : SplitDirection.horizontal,
    };

    final session = config.activeSession;
    final selectedLeaf = session.findLeaf(selectedId);
    if (selectedLeaf == null) return;

    final newLeaf = selectedLeaf.copyWith(
      id: 'leaf-${DateTime.now().microsecondsSinceEpoch}',
      title: '${selectedLeaf.title} (new)',
      command: '',
      args: const [],
    );
    final nextRoot = session.root.replaceLeaf(selectedId, (leaf) {
      return PaneSplit(
        id: 'split-${DateTime.now().microsecondsSinceEpoch}',
        direction: actualDirection,
        ratio: 0.5,
        first: leaf,
        second: newLeaf,
      );
    });
    if (nextRoot == null) return;
    final nextSession = session.copyWith(root: nextRoot);
    final nextConfig = config.updateActiveSession((_) => nextSession);
    setState(() {
      _config = nextConfig;
      _selectedLeafId = newLeaf.id;
      _status = 'Split ${actualDirection.name}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loader,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done || _config == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final config = _config!;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Resume-Term'),
            actions: [
              Builder(
                builder: (context) {
                  return PopupMenuButton<SplitAction>(
                    tooltip: 'Split',
                    onSelected: (action) {
                      final box = context.findRenderObject() as RenderBox?;
                      final size = box?.size ?? const Size(1200, 800);
                      _splitSelectedPane(action, BoxConstraints.tight(size));
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: SplitAction.horizontal,
                        child: Text('拆分视图 - 上下'),
                      ),
                      PopupMenuItem(
                        value: SplitAction.vertical,
                        child: Text('拆分视图 - 左右'),
                      ),
                      PopupMenuItem(
                        value: SplitAction.auto,
                        child: Text('拆分视图 - 自动'),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(Icons.call_split),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Save',
                onPressed: _save,
                icon: const Icon(Icons.save),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ToolbarRow(
                      configDirController: _configDirController,
                      status: _status,
                      onApplyDir: _applyConfigDir,
                      onReload: _load,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: WorkspaceTree(
                                  root: config.activeSession.root,
                                  selectedLeafId: _selectedLeafId,
                                  onSelectLeaf: _selectLeaf,
                                  onSplit: (action) => _splitSelectedPane(action, constraints),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: PaneInspector(
                              key: ValueKey<String?>(_selectedLeafId),
                              leaf: config.activeSession.findLeaf(_selectedLeafId ?? '') ??
                                  config.activeSession.firstLeaf() ??
                                  PaneLeaf.defaultLeaf(),
                              onSave: _updateLeaf,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Default shell order: ${ShellDefaults.shellPriority().join(' > ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ToolbarRow extends StatelessWidget {
  const _ToolbarRow({
    required this.configDirController,
    required this.status,
    required this.onApplyDir,
    required this.onReload,
  });

  final TextEditingController configDirController;
  final String status;
  final VoidCallback onApplyDir;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: configDirController,
            decoration: const InputDecoration(
              labelText: 'Config directory',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: onApplyDir,
          child: const Text('Apply dir'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () {
            onReload();
          },
          child: const Text('Reload'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            status,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class WorkspaceTree extends StatelessWidget {
  const WorkspaceTree({
    super.key,
    required this.root,
    required this.selectedLeafId,
    required this.onSelectLeaf,
    required this.onSplit,
  });

  final PaneNode root;
  final String? selectedLeafId;
  final ValueChanged<String> onSelectLeaf;
  final ValueChanged<SplitAction> onSplit;

  @override
  Widget build(BuildContext context) {
    return _PaneNodeView(
      node: root,
      selectedLeafId: selectedLeafId,
      onSelectLeaf: onSelectLeaf,
      onSplit: onSplit,
    );
  }
}

class _PaneNodeView extends StatelessWidget {
  const _PaneNodeView({
    required this.node,
    required this.selectedLeafId,
    required this.onSelectLeaf,
    required this.onSplit,
  });

  final PaneNode node;
  final String? selectedLeafId;
  final ValueChanged<String> onSelectLeaf;
  final ValueChanged<SplitAction> onSplit;

  @override
  Widget build(BuildContext context) {
    if (node is PaneLeaf) {
      final leaf = node as PaneLeaf;
      final selected = leaf.id == selectedLeafId;
      return GestureDetector(
        onTap: () => onSelectLeaf(leaf.id),
        child: Container(
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        leaf.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    PopupMenuButton<SplitAction>(
                      icon: const Icon(Icons.add_box_outlined),
                      onSelected: onSplit,
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: SplitAction.horizontal,
                          child: Text('拆分视图 - 上下'),
                        ),
                        PopupMenuItem(
                          value: SplitAction.vertical,
                          child: Text('拆分视图 - 左右'),
                        ),
                        PopupMenuItem(
                          value: SplitAction.auto,
                          child: Text('拆分视图 - 自动'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('shell: ${leaf.shell}'),
                Text('exe: ${leaf.executable}'),
                if (leaf.command.isNotEmpty) Text('cmd: ${leaf.command}'),
                if (leaf.workingDir.isNotEmpty) Text('dir: ${leaf.workingDir}'),
              ],
            ),
          ),
        ),
      );
    }

    final split = node as PaneSplit;
    final firstFlex = (split.ratio * 100).round().clamp(1, 99).toInt();
    final secondFlex = 100 - firstFlex;
    final children = [
      Expanded(
        flex: firstFlex,
        child: _PaneNodeView(
          node: split.first,
          selectedLeafId: selectedLeafId,
          onSelectLeaf: onSelectLeaf,
          onSplit: onSplit,
        ),
      ),
      Expanded(
        flex: secondFlex,
        child: _PaneNodeView(
          node: split.second,
          selectedLeafId: selectedLeafId,
          onSelectLeaf: onSelectLeaf,
          onSplit: onSplit,
        ),
      ),
    ];
    if (split.direction == SplitDirection.vertical) {
      return Row(children: children);
    }
    return Column(children: children);
  }
}

class PaneInspector extends StatefulWidget {
  const PaneInspector({
    super.key,
    required this.leaf,
    required this.onSave,
  });

  final PaneLeaf leaf;
  final ValueChanged<PaneLeaf> onSave;

  @override
  State<PaneInspector> createState() => _PaneInspectorState();
}

class _PaneInspectorState extends State<PaneInspector> {
  late final TextEditingController _titleController;
  late final TextEditingController _shellController;
  late final TextEditingController _exeController;
  late final TextEditingController _commandController;
  late final TextEditingController _dirController;
  late final TextEditingController _argsController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _shellController = TextEditingController();
    _exeController = TextEditingController();
    _commandController = TextEditingController();
    _dirController = TextEditingController();
    _argsController = TextEditingController();
    _sync(widget.leaf);
  }

  @override
  void didUpdateWidget(covariant PaneInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leaf.id != widget.leaf.id) {
      _sync(widget.leaf);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _shellController.dispose();
    _exeController.dispose();
    _commandController.dispose();
    _dirController.dispose();
    _argsController.dispose();
    super.dispose();
  }

  void _sync(PaneLeaf leaf) {
    _titleController.text = leaf.title;
    _shellController.text = leaf.shell;
    _exeController.text = leaf.executable;
    _commandController.text = leaf.command;
    _dirController.text = leaf.workingDir;
    _argsController.text = leaf.args.join(', ');
  }

  void _save() {
    final args = _argsController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    widget.onSave(
      widget.leaf.copyWith(
        title: _titleController.text.trim(),
        shell: _shellController.text.trim(),
        executable: _exeController.text.trim(),
        command: _commandController.text.trim(),
        workingDir: _dirController.text.trim(),
        args: args,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pane inspector', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _shellController,
              decoration: const InputDecoration(labelText: 'Shell'),
            ),
            TextField(
              controller: _exeController,
              decoration: const InputDecoration(labelText: 'Executable'),
            ),
            TextField(
              controller: _commandController,
              decoration: const InputDecoration(labelText: 'Command'),
            ),
            TextField(
              controller: _dirController,
              decoration: const InputDecoration(labelText: 'Working directory'),
            ),
            TextField(
              controller: _argsController,
              decoration: const InputDecoration(labelText: 'Args (comma separated)'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _save,
              child: const Text('Save pane'),
            ),
          ],
        ),
      ),
    );
  }
}
