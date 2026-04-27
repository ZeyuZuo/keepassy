import 'package:flutter/material.dart';

import '../../models/vault_models.dart';
import '../../repositories/vault_repository.dart';
import '../unlock/unlock_page.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({
    super.key,
    required this.repository,
    required this.initialVault,
  });

  final VaultRepository repository;
  final OpenedVault initialVault;

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

  @override
  void initState() {
    super.initState();
    if (_selectedGroup.entries.isNotEmpty) {
      _selectEntry(_selectedGroup.entries.first);
    }
  }

  Future<void> _selectEntry(EntrySummary entry) async {
    setState(() {
      _selectedEntry = entry;
      _detail = null;
      _loadingDetail = true;
      _passwordVisible = false;
    });
    try {
      final detail = await widget.repository.entryDetail(entry.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDetail = false;
        });
      }
    }
  }

  void _selectGroup(GroupNode group) {
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

  Future<void> _lock() async {
    await widget.repository.close();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => UnlockPage(repository: widget.repository),
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
            onPressed: () {},
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Save vault',
            onPressed: () {},
            icon: const Icon(Icons.save_outlined),
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
                    onPasswordVisibilityChanged: () {
                      setState(() => _passwordVisible = !_passwordVisible);
                    },
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
                  onPasswordVisibilityChanged: () {
                    setState(() => _passwordVisible = !_passwordVisible);
                  },
                ),
              ),
            ],
          );
        },
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
                      '${group.entryCount} entries',
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
    required this.onPasswordVisibilityChanged,
  });

  final EntryDetail? detail;
  final bool loading;
  final bool passwordVisible;
  final VoidCallback onPasswordVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (detail == null) {
      return const Center(child: Text('Select an entry'));
    }

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
              onPressed: () {},
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _FieldLine(
          icon: Icons.person_outline,
          label: 'Username',
          value: detail.username ?? '',
        ),
        _FieldLine(
          icon: Icons.password_outlined,
          label: 'Password',
          value: passwordVisible ? detail.password ?? '' : '••••••••••••',
          trailing: IconButton(
            tooltip: passwordVisible ? 'Hide password' : 'Show password',
            onPressed: onPasswordVisibilityChanged,
            icon: Icon(
              passwordVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
        _FieldLine(
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
            _FieldLine(
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
