import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vault_models.dart';
import '../../repositories/vault_repository.dart';
import '../unlock/unlock_page.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({
    super.key,
    required this.repository,
    required this.initialVault,
    this.keyfilePath,
  });

  final VaultRepository repository;
  final OpenedVault initialVault;
  final String? keyfilePath;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  late GroupNode _selectedGroup = widget.initialVault.groupTree;
  EntrySummary? _selectedEntry;
  EntryDetail? _detail;
  String _query = '';
  bool _loadingDetail = false;
  bool _passwordVisible = false;
  bool _editing = false;
  bool _dirty = false;
  bool _saving = false;
  String? _saveError;

  // Edit form controllers
  final _editTitleController = TextEditingController();
  final _editUsernameController = TextEditingController();
  final _editPasswordController = TextEditingController();
  final _editUrlController = TextEditingController();
  final _editNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_selectedGroup.entries.isNotEmpty) {
      _selectEntry(_selectedGroup.entries.first);
    }
  }

  @override
  void dispose() {
    _editTitleController.dispose();
    _editUsernameController.dispose();
    _editPasswordController.dispose();
    _editUrlController.dispose();
    _editNotesController.dispose();
    super.dispose();
  }

  Future<void> _selectEntry(EntrySummary entry) async {
    _cancelEdit();
    setState(() {
      _selectedEntry = entry;
      _detail = null;
      _loadingDetail = true;
      _passwordVisible = false;
    });
    try {
      final detail = await widget.repository.entryDetail(entry.id);
      if (!mounted) return;
      setState(() => _detail = detail);
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  void _selectGroup(GroupNode group) {
    _cancelEdit();
    setState(() {
      _selectedGroup = group;
      _selectedEntry = null;
      _detail = null;
      _query = '';
    });
    if (group.entries.isNotEmpty) {
      _selectEntry(group.entries.first);
    }
  }

  Future<void> _createEntry(CreateEntryRequest request) async {
    try {
      final detail = await widget.repository.createEntry(request);
      if (!mounted) return;
      setState(() => _dirty = true);
      // Refresh the vault tree by re-fetching the group
      _refreshGroup(_selectedGroup.id);
      _selectEntry(
        EntrySummary(
          id: detail.id,
          title: detail.title,
          username: detail.username,
          url: detail.url,
        ),
      );
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  void _startEdit() {
    final detail = _detail;
    if (detail == null) return;
    _editTitleController.text = detail.title ?? '';
    _editUsernameController.text = detail.username ?? '';
    _editPasswordController.text = detail.password ?? '';
    _editUrlController.text = detail.url ?? '';
    _editNotesController.text = detail.notes ?? '';
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    setState(() => _editing = false);
    _editTitleController.clear();
    _editUsernameController.clear();
    _editPasswordController.clear();
    _editUrlController.clear();
    _editNotesController.clear();
  }

  Future<void> _saveEdit() async {
    final entryId = _selectedEntry?.id;
    if (entryId == null) return;

    final request = UpdateEntryRequest(
      entryId: entryId,
      title: _editTitleController.text.trim().isEmpty
          ? ''
          : _editTitleController.text.trim(),
      username: _editUsernameController.text.trim().isEmpty
          ? ''
          : _editUsernameController.text.trim(),
      password: _editPasswordController.text,
      url: _editUrlController.text.trim().isEmpty
          ? ''
          : _editUrlController.text.trim(),
      notes: _editNotesController.text.trim().isEmpty
          ? ''
          : _editNotesController.text.trim(),
    );

    try {
      final updated = await widget.repository.updateEntry(request);
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _dirty = true;
        _editing = false;
      });
      _refreshGroup(_selectedGroup.id);
      _selectEntry(
        EntrySummary(
          id: updated.id,
          title: updated.title,
          username: updated.username,
          url: updated.url,
        ),
      );
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> _deleteEntry() async {
    final entryId = _selectedEntry?.id;
    if (entryId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry'),
        content: Text('Delete "${_detail?.displayTitle ?? entryId}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.repository.deleteEntry(entryId);
      if (!mounted) return;
      setState(() {
        _dirty = true;
        _selectedEntry = null;
        _detail = null;
        _editing = false;
      });
      _refreshGroup(_selectedGroup.id);
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> _saveVault() async {
    final passwordCtrl = TextEditingController();
    final keyfileCtrl = TextEditingController();
    final hasKeyfile = widget.keyfilePath != null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save vault'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Master password'),
                autofocus: true,
                onSubmitted: (_) => Navigator.of(context).pop(true),
              ),
              if (hasKeyfile) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: keyfileCtrl,
                  decoration: InputDecoration(
                    labelText: 'Keyfile path',
                    hintText: widget.keyfilePath,
                    prefixIcon: const Icon(Icons.insert_drive_file_outlined),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final password = passwordCtrl.text;
    final keyfilePath = hasKeyfile
        ? (keyfileCtrl.text.trim().isNotEmpty
              ? keyfileCtrl.text.trim()
              : widget.keyfilePath)
        : null;
    passwordCtrl.dispose();
    keyfileCtrl.dispose();

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      await widget.repository.save(
        masterPassword: password,
        keyfilePath: keyfilePath,
      );
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = err.toString();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $err')));
    }
  }

  Future<void> _lock() async {
    if (_dirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text(
            'You have unsaved changes. Locking will discard them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard and lock'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await widget.repository.close();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => UnlockPage(repository: widget.repository),
      ),
    );
  }

  void _refreshGroup(String groupId) {
    widget.repository.entriesForGroup(groupId).then((entries) {
      if (!mounted) return;
      setState(() {
        final groups = widget.initialVault.groupTree.flatten().toList();
        final group = groups.firstWhere(
          (g) => g.id == groupId,
          orElse: () => _selectedGroup,
        );
        group.entries
          ..clear()
          ..addAll(entries);
      });
    });
  }

  void _showCreateDialog() {
    final titleCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New entry'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title'),
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Title is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(labelText: 'Username'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordCtrl,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(labelText: 'URL'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop();
              _createEntry(
                CreateEntryRequest(
                  groupId: _selectedGroup.id,
                  title: titleCtrl.text.trim(),
                  username: usernameCtrl.text.trim(),
                  password: passwordCtrl.text,
                  url: urlCtrl.text.trim(),
                  notes: notesCtrl.text.trim(),
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _selectedGroup.entries
        .where((entry) {
          final haystack = [
            entry.title,
            entry.username,
            entry.url,
          ].whereType<String>().join(' ').toLowerCase();
          return haystack.contains(_query.toLowerCase());
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const Icon(Icons.lock_outline),
            const SizedBox(width: 10),
            const Text('KeePassY'),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                widget.initialVault.source,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Create entry',
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add),
          ),
          _SaveButton(
            dirty: _dirty,
            saving: _saving,
            error: _saveError,
            onPressed: _saveVault,
          ),
          IconButton(
            tooltip: 'Lock vault',
            onPressed: _lock,
            icon: const Icon(Icons.lock_outline),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 920;
          if (compact) {
            return Column(
              children: [
                SizedBox(
                  height: 168,
                  child: _GroupRail(
                    root: widget.initialVault.groupTree,
                    selectedGroup: _selectedGroup,
                    horizontal: true,
                    onSelected: _selectGroup,
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _EntryList(
                    group: _selectedGroup,
                    entries: entries,
                    selectedEntry: _selectedEntry,
                    query: _query,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onSelected: _selectEntry,
                  ),
                ),
                const Divider(),
                SizedBox(
                  height: 340,
                  child: _DetailPane(
                    detail: _detail,
                    loading: _loadingDetail,
                    passwordVisible: _passwordVisible,
                    editing: _editing,
                    titleCtrl: _editTitleController,
                    usernameCtrl: _editUsernameController,
                    passwordCtrl: _editPasswordController,
                    urlCtrl: _editUrlController,
                    notesCtrl: _editNotesController,
                    onPasswordVisibilityChanged: () {
                      setState(() => _passwordVisible = !_passwordVisible);
                    },
                    onEdit: _startEdit,
                    onSaveEdit: _saveEdit,
                    onCancelEdit: _cancelEdit,
                    onDelete: _deleteEntry,
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              SizedBox(
                width: 264,
                child: _GroupRail(
                  root: widget.initialVault.groupTree,
                  selectedGroup: _selectedGroup,
                  onSelected: _selectGroup,
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 380,
                child: _EntryList(
                  group: _selectedGroup,
                  entries: entries,
                  selectedEntry: _selectedEntry,
                  query: _query,
                  onQueryChanged: (value) => setState(() => _query = value),
                  onSelected: _selectEntry,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _DetailPane(
                  detail: _detail,
                  loading: _loadingDetail,
                  passwordVisible: _passwordVisible,
                  editing: _editing,
                  titleCtrl: _editTitleController,
                  usernameCtrl: _editUsernameController,
                  passwordCtrl: _editPasswordController,
                  urlCtrl: _editUrlController,
                  notesCtrl: _editNotesController,
                  onPasswordVisibilityChanged: () {
                    setState(() => _passwordVisible = !_passwordVisible);
                  },
                  onEdit: _startEdit,
                  onSaveEdit: _saveEdit,
                  onCancelEdit: _cancelEdit,
                  onDelete: _deleteEntry,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.dirty,
    required this.saving,
    required this.onPressed,
    this.error,
  });

  final bool dirty;
  final bool saving;
  final VoidCallback onPressed;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final tooltip = error != null
        ? 'Save failed: $error'
        : dirty
        ? 'Save vault (unsaved changes)'
        : 'Save vault';

    final enabled = dirty || error != null;

    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: Icon(
        error != null
            ? Icons.error_outline
            : dirty
            ? Icons.save_as_outlined
            : Icons.save_outlined,
        color: error != null
            ? Theme.of(context).colorScheme.error
            : dirty
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
    );
  }
}

class _GroupRail extends StatelessWidget {
  const _GroupRail({
    required this.root,
    required this.selectedGroup,
    required this.onSelected,
    this.horizontal = false,
  });

  final GroupNode root;
  final GroupNode selectedGroup;
  final ValueChanged<GroupNode> onSelected;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final groups = root.flatten().toList(growable: false);

    if (horizontal) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 180,
            child: _GroupButton(
              group: groups[index],
              selected: groups[index].id == selectedGroup.id,
              onSelected: onSelected,
            ),
          );
        },
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        return _GroupButton(
          group: groups[index],
          selected: groups[index].id == selectedGroup.id,
          onSelected: onSelected,
        );
      },
    );
  }
}

class _GroupButton extends StatelessWidget {
  const _GroupButton({
    required this.group,
    required this.selected,
    required this.onSelected,
  });

  final GroupNode group;
  final bool selected;
  final ValueChanged<GroupNode> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entryLabel = group.entryCount == 1 ? 'entry' : 'entries';

    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.11)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelected(group),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                group.groups.isEmpty
                    ? Icons.folder_outlined
                    : Icons.folder_copy_outlined,
                color: selected ? colorScheme.primary : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${group.entryCount} $entryLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.group,
    required this.entries,
    required this.selectedEntry,
    required this.query,
    required this.onQueryChanged,
    required this.onSelected,
  });

  final GroupNode group;
  final List<EntrySummary> entries;
  final EntrySummary? selectedEntry;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<EntrySummary> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                group.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  hintText: 'Search entries',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No matching entries'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _EntryRow(
                      entry: entry,
                      selected: entry.id == selectedEntry?.id,
                      onSelected: onSelected,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.selected,
    required this.onSelected,
  });

  final EntrySummary entry;
  final bool selected;
  final ValueChanged<EntrySummary> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colorScheme.surfaceContainerLow : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelected(entry),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: selected
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerLow,
                foregroundColor: selected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                child: Text(entry.displayTitle.characters.first.toUpperCase()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayTitle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.username ?? entry.url ?? 'No username',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailPane extends StatelessWidget {
  const _DetailPane({
    required this.detail,
    required this.loading,
    required this.passwordVisible,
    required this.editing,
    required this.titleCtrl,
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.urlCtrl,
    required this.notesCtrl,
    required this.onPasswordVisibilityChanged,
    required this.onEdit,
    required this.onSaveEdit,
    required this.onCancelEdit,
    required this.onDelete,
  });

  final EntryDetail? detail;
  final bool loading;
  final bool passwordVisible;
  final bool editing;
  final TextEditingController titleCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController urlCtrl;
  final TextEditingController notesCtrl;
  final VoidCallback onPasswordVisibilityChanged;
  final VoidCallback onEdit;
  final VoidCallback onSaveEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (detail == null) {
      return const Center(child: Text('Select an entry'));
    }

    if (editing) {
      return _buildEditMode(context);
    }
    return _buildReadMode(context);
  }

  Widget _buildReadMode(BuildContext context) {
    final detail = this.detail!;
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                detail.displayTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Edit entry',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete entry',
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, color: colorScheme.error),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildCopyField(
          context: context,
          icon: Icons.person_outline,
          label: 'Username',
          value: detail.username ?? '',
        ),
        _buildPasswordField(
          context: context,
          visible: passwordVisible,
          value: detail.password ?? '',
          onToggle: onPasswordVisibilityChanged,
        ),
        _buildCopyField(
          context: context,
          icon: Icons.link_outlined,
          label: 'URL',
          value: detail.url ?? '',
        ),
        _FieldLine(
          icon: Icons.notes_outlined,
          label: 'Notes',
          value: detail.notes ?? '',
        ),
        if (detail.fields.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'Custom fields',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final item in detail.readonlyFields.entries)
            _buildCopyField(
              context: context,
              icon: Icons.tune_outlined,
              label: item.key,
              value: item.value,
            ),
        ],
        if (detail.attachments.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'Attachments',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final attachment in detail.attachments)
            _FieldLine(
              icon: attachment.protected
                  ? Icons.enhanced_encryption_outlined
                  : Icons.attach_file_outlined,
              label: attachment.name,
              value: '${attachment.size} bytes',
            ),
        ],
      ],
    );
  }

  Widget _buildEditMode(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Edit entry',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Save changes',
              onPressed: onSaveEdit,
              icon: const Icon(Icons.check),
            ),
            IconButton(
              tooltip: 'Cancel editing',
              onPressed: onCancelEdit,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: usernameCtrl,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: passwordCtrl,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: urlCtrl,
          decoration: const InputDecoration(labelText: 'URL'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: notesCtrl,
          decoration: const InputDecoration(labelText: 'Notes'),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildCopyField({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return _FieldLine(
      icon: icon,
      label: label,
      value: value,
      trailing: value.isNotEmpty
          ? IconButton(
              tooltip: 'Copy $label',
              onPressed: () => _copyToClipboard(context, value, label),
              icon: const Icon(Icons.copy, size: 18),
            )
          : null,
    );
  }

  Widget _buildPasswordField({
    required BuildContext context,
    required bool visible,
    required String value,
    required VoidCallback onToggle,
  }) {
    return _FieldLine(
      icon: Icons.password_outlined,
      label: 'Password',
      value: visible ? value : '••••••••••••',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value.isNotEmpty)
            IconButton(
              tooltip: 'Copy password',
              onPressed: () => _copyToClipboard(context, value, 'Password'),
              icon: const Icon(Icons.copy, size: 18),
            ),
          IconButton(
            tooltip: visible ? 'Hide password' : 'Show password',
            onPressed: onToggle,
            icon: Icon(
              visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
    );
  }

  static Timer? _clipboardTimer;

  static void _copyToClipboard(
    BuildContext context,
    String value,
    String label,
  ) {
    Clipboard.setData(ClipboardData(text: value));
    _clipboardTimer?.cancel();
    _clipboardTimer = Timer(const Duration(seconds: 30), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copied to clipboard'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

class _FieldLine extends StatelessWidget {
  const _FieldLine({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? 'Not set' : value,
              style: TextStyle(
                color: value.isEmpty
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurface,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
