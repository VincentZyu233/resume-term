import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/workspace_config.dart';
import '../services/config_store.dart';
import '../services/shell_defaults.dart';
import '../widgets/terminal_pane.dart';

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
  bool _showTopTools = true;
  bool _showWorkspacePanel = true;
  bool _showInspectorPanel = true;
  Timer? _autoCollapseTimer;

  @override
  void initState() {
    super.initState();
    _configDirController = TextEditingController(text: ConfigStore.defaultConfigDir());
    _loader = _load();
    _autoCollapseTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _showTopTools = false;
        _showWorkspacePanel = false;
        _showInspectorPanel = false;
      });
    });
  }

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
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

  Future<void> _setStartupLayout(String sessionId) async {
    final config = _config;
    if (config == null) return;
    final store = ConfigStore(_configDirController.text.trim());
    final next = config.copyWith(
      configDir: _configDirController.text.trim(),
      startupSessionId: sessionId,
    );
    await store.save(next);
    if (!mounted) return;
    setState(() {
      _config = next;
      _status = 'Startup layout set';
    });
  }

  void _applyConfigDir() {
    setState(() {
      _loader = _load();
    });
  }

  Future<void> _pickConfigDirectory() async {
    try {
      final selectedDir = await getDirectoryPath(
        initialDirectory: _configDirController.text.trim().isEmpty
            ? ConfigStore.defaultConfigDir()
            : _configDirController.text.trim(),
        confirmButtonText: 'Use this folder',
      );
      if (selectedDir == null || !mounted) return;
      setState(() {
        _configDirController.text = selectedDir;
        _status = 'Selected config directory';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Directory picker failed: $error';
      });
    }
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

  void _splitSelectedPane(SplitAction action, BoxConstraints constraints, {String? targetLeafId}) {
    final config = _config;
    final selectedId = targetLeafId ?? _selectedLeafId;
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

    int countLeaves(PaneNode n) {
      if (n is PaneLeaf) return 1;
      if (n is PaneSplit) return countLeaves(n.first) + countLeaves(n.second);
      return 0;
    }
    final paneNumber = countLeaves(session.root) + 1;
    final newLeaf = selectedLeaf.copyWith(
      id: 'leaf-${DateTime.now().microsecondsSinceEpoch}',
      title: 'Pane $paneNumber',
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
            toolbarHeight: 40,
            title: const Text('Resume-Term'),
            actions: [
              IconButton(
                tooltip: _showTopTools ? 'Hide tools' : 'Show tools',
                onPressed: () {
                  setState(() {
                    _showTopTools = !_showTopTools;
                  });
                },
                icon: Icon(_showTopTools ? Icons.unfold_less : Icons.unfold_more),
              ),
              IconButton(
                tooltip: _showWorkspacePanel ? 'Hide workspace panel' : 'Show workspace panel',
                onPressed: () {
                  setState(() {
                    _showWorkspacePanel = !_showWorkspacePanel;
                  });
                },
                icon: Icon(_showWorkspacePanel ? Icons.chevron_left : Icons.chevron_right),
              ),
              IconButton(
                tooltip: _showInspectorPanel ? 'Hide inspector panel' : 'Show inspector panel',
                onPressed: () {
                  setState(() {
                    _showInspectorPanel = !_showInspectorPanel;
                  });
                },
                icon: Icon(_showInspectorPanel ? Icons.chevron_right : Icons.chevron_left),
              ),
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
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 220),
                      firstChild: _ToolbarRow(
                        configDirController: _configDirController,
                        status: _status,
                        onApplyDir: _applyConfigDir,
                        onReload: _load,
                        onPickDirectory: _pickConfigDirectory,
                    ),
                    secondChild: _CollapsedStrip(
                        text: _status,
                        icon: Icons.tune,
                        onExpand: () {
                          setState(() {
                            _showTopTools = true;
                          });
                        },
                      ),
                      crossFadeState: _showTopTools
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: _showWorkspacePanel ? 200 : 52,
                            child: _showWorkspacePanel
                                ? Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: WorkspaceSummary(
                                        session: config.activeSession,
                                        selectedLeafId: _selectedLeafId,
                                        onSelectLeaf: _selectLeaf,
                                        isStartup: config.activeSession.id == config.startupSessionId,
                                        onSetStartup: _setStartupLayout,
                                        onCollapse: () => setState(() => _showWorkspacePanel = false),
                                      ),
                                    ),
                                  )
                                : _SideCollapsedButton(
                                    icon: Icons.account_tree_outlined,
                                    tooltip: 'Show workspace panel',
                                    onTap: () {
                                      setState(() {
                                        _showWorkspacePanel = true;
                                      });
                                    },
                                  ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 8,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child:                 WorkspaceTree(
                                  root: config.activeSession.root,
                                  selectedLeafId: _selectedLeafId,
                                  onSelectLeaf: _selectLeaf,
                                  onSplit: (action, leafId) => _splitSelectedPane(action, constraints, targetLeafId: leafId),
                                  terminalThemeConfig: config.terminalTheme,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: _showInspectorPanel ? 240 : 52,
                            child: _showInspectorPanel
                                ? PaneInspector(
                                    key: ValueKey<String?>(_selectedLeafId),
                                    leaf: config.activeSession.findLeaf(_selectedLeafId ?? '') ??
                                        config.activeSession.firstLeaf() ??
                                        PaneLeaf.defaultLeaf(),
                                    onSave: _updateLeaf,
                                    onCollapse: () => setState(() => _showInspectorPanel = false),
                                  )
                                : _SideCollapsedButton(
                                    icon: Icons.tune,
                                    tooltip: 'Show inspector panel',
                                    onTap: () {
                                      setState(() {
                                        _showInspectorPanel = true;
                                      });
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
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
    required this.onPickDirectory,
  });

  final TextEditingController configDirController;
  final String status;
  final VoidCallback onApplyDir;
  final Future<void> Function() onReload;
  final Future<void> Function() onPickDirectory;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: configDirController,
            decoration: InputDecoration(
              labelText: 'Config directory',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Clear path',
                    onPressed: () {
                      configDirController.clear();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                  IconButton(
                    tooltip: 'Browse directory',
                    onPressed: () {
                      onPickDirectory();
                    },
                    icon: const Icon(Icons.folder_open_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton(
          onPressed: onApplyDir,
          child: const Text('Apply dir'),
        ),
        const SizedBox(width: 4),
        OutlinedButton(
          onPressed: () {
            onReload();
          },
          child: const Text('Reload'),
        ),
        const SizedBox(width: 6),
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

class _CollapsedStrip extends StatelessWidget {
  const _CollapsedStrip({
    required this.text,
    required this.icon,
    required this.onExpand,
  });

  final String text;
  final IconData icon;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onExpand,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.expand_more),
          ],
        ),
      ),
    );
  }
}

class _SideCollapsedButton extends StatelessWidget {
  const _SideCollapsedButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(
        child: Tooltip(
          message: tooltip,
          child: IconButton(
            onPressed: onTap,
            icon: Icon(icon),
          ),
        ),
      ),
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
    required this.terminalThemeConfig,
  });

  final PaneNode root;
  final String? selectedLeafId;
  final ValueChanged<String> onSelectLeaf;
  final void Function(SplitAction action, String leafId) onSplit;
  final TerminalThemeConfig terminalThemeConfig;

  @override
  Widget build(BuildContext context) {
    return _PaneNodeView(
      node: root,
      selectedLeafId: selectedLeafId,
      onSelectLeaf: onSelectLeaf,
      onSplit: onSplit,
      terminalThemeConfig: terminalThemeConfig,
    );
  }
}

class WorkspaceSummary extends StatelessWidget {
  const WorkspaceSummary({
    super.key,
    required this.session,
    required this.selectedLeafId,
    required this.onSelectLeaf,
    required this.isStartup,
    required this.onSetStartup,
    required this.onCollapse,
  });

  final WorkspaceSession session;
  final String? selectedLeafId;
  final ValueChanged<String> onSelectLeaf;
  final bool isStartup;
  final ValueChanged<String> onSetStartup;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final leaves = <PaneLeaf>[];

    void collect(PaneNode node) {
      if (node is PaneLeaf) {
        leaves.add(node);
        return;
      }
      final split = node as PaneSplit;
      collect(split.first);
      collect(split.second);
    }

    collect(session.root);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(session.name, style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              icon: Icon(isStartup ? Icons.star : Icons.star_border),
              color: isStartup ? Colors.amber : null,
              tooltip: isStartup ? 'Startup layout' : 'Set as startup layout',
              onPressed: () => onSetStartup(session.id),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('${leaves.length} pane(s)', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.separated(
            itemCount: leaves.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final leaf = leaves[index];
              final selected = leaf.id == selectedLeafId;
              return InkWell(
                onTap: () => onSelectLeaf(leaf.id),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        leaf.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        leaf.command.isEmpty ? leaf.executable : leaf.command,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 28,
          child: TextButton.icon(
            onPressed: onCollapse,
            icon: const Icon(Icons.chevron_left, size: 14),
            label: const Text('收起', style: TextStyle(fontSize: 11)),
          ),
        ),
      ],
    );
  }
}

class _PaneNodeView extends StatelessWidget {
  const _PaneNodeView({
    required this.node,
    required this.selectedLeafId,
    required this.onSelectLeaf,
    required this.onSplit,
    required this.terminalThemeConfig,
  });

  final PaneNode node;
  final String? selectedLeafId;
  final ValueChanged<String> onSelectLeaf;
  final void Function(SplitAction action, String leafId) onSplit;
  final TerminalThemeConfig terminalThemeConfig;

  @override
  Widget build(BuildContext context) {
    if (node is PaneLeaf) {
      final leaf = node as PaneLeaf;
      final selected = leaf.id == selectedLeafId;
      return GestureDetector(
        onTap: () => onSelectLeaf(leaf.id),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Column(
              children: [
                Container(
                  height: 24,
                  color: Colors.black26,
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          leaf.title,
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ),
                      PopupMenuButton<SplitAction>(
                        icon: const Icon(Icons.add_box_outlined, size: 16, color: Colors.white54),
                        onSelected: (action) => onSplit(action, leaf.id),
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: SplitAction.horizontal, child: Text('拆分视图 - 上下')),
                          PopupMenuItem(value: SplitAction.vertical, child: Text('拆分视图 - 左右')),
                          PopupMenuItem(value: SplitAction.auto, child: Text('拆分视图 - 自动')),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TerminalPane(leafId: leaf.id, config: leaf, themeConfig: terminalThemeConfig),
                ),
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
          terminalThemeConfig: terminalThemeConfig,
        ),
      ),
      Expanded(
        flex: secondFlex,
        child: _PaneNodeView(
          node: split.second,
          selectedLeafId: selectedLeafId,
          onSelectLeaf: onSelectLeaf,
          onSplit: onSplit,
          terminalThemeConfig: terminalThemeConfig,
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
    required this.onCollapse,
  });

  final PaneLeaf leaf;
  final ValueChanged<PaneLeaf> onSave;
  final VoidCallback onCollapse;

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
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pane inspector', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
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
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _save,
              child: const Text('Save pane'),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 28,
              child: TextButton.icon(
                onPressed: widget.onCollapse,
                icon: const Icon(Icons.chevron_right, size: 14),
                label: const Text('收起', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
