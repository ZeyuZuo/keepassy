import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vault_models.dart';
import '../../repositories/vault_repository.dart';
import '../../settings/settings_service.dart';
import '../../widgets/field_line.dart';
import '../../widgets/status_chip.dart';
import '../settings/settings_dialog.dart';
import '../unlock/unlock_page.dart';

enum _RemoteConflictAction { keepLocal, reopenRemote }

enum _MoreAction {
  settings,
  remoteMetadata,
  changePassword,
  autoLock,
  reopenRemote,
}

double _pwStrength(String pw) {
  if (pw.isEmpty) return 0;
  double score = 0;
  if (pw.length >= 8) score += 1;
  if (pw.length >= 12) score += 1;
  if (pw.length >= 16) score += 1;
  if (RegExp(r'[a-z]').hasMatch(pw)) score += 0.5;
  if (RegExp(r'[A-Z]').hasMatch(pw)) score += 0.5;
  if (RegExp(r'[0-9]').hasMatch(pw)) score += 0.5;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(pw)) score += 0.5;
  return (score / 4).clamp(0.0, 1.0);
}

Color _pwColor(double v) {
  if (v < 0.3) return Colors.red;
  if (v < 0.6) return Colors.orange;
  return Colors.green;
}

class VaultPage extends StatefulWidget {
  const VaultPage({
    super.key,
    required this.repository,
    required this.initialVault,
    required this.masterPassword,
    this.keyfilePath,
    this.settingsService,
  });

  final VaultRepository repository;
  final OpenedVault initialVault;
  final String masterPassword;
  final String? keyfilePath;
  final SettingsService? settingsService;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  late GroupNode _groupTree;
  late GroupNode _selectedGroup;
  EntrySummary? _selectedEntry;
  EntryDetail? _detail;
  String _query = '';
  bool _loadingDetail = false;
  bool _passwordVisible = false;
  bool _editing = false;
  bool _editExpires = false;
  final _editExpiryDateController = TextEditingController();
  bool _dirty = false;
  bool _saving = false;
  String? _saveError;
  bool _conflict = false;
  bool _showHistory = false;
  List<HistorySummary>? _history;
  bool _loadingHistory = false;
  bool _searchAllGroups = false;
  int _sortMode = 0; // 0=title, 1=username, 2=modified
  Timer? _autoLockTimer;
  Timer? _inactivityTimer;
  Timer? _clipboardTimer;
  final Set<String> _selectedEntryIds = {};
  final Set<String> _visibleCustomFields = {};
  late int _autoLockMinutes;
  late String _saveMasterPassword;
  String? _saveKeyfilePath;

  // Edit form controllers
  final _editTitleController = TextEditingController();
  final _editUsernameController = TextEditingController();
  final _editPasswordController = TextEditingController();
  final _editUrlController = TextEditingController();
  final _editNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final svc = widget.settingsService;
    _autoLockMinutes = svc != null ? svc.settings.autoLockMinutes : 5;
    _saveMasterPassword = widget.masterPassword;
    _saveKeyfilePath = widget.keyfilePath;
    _groupTree = widget.initialVault.groupTree;
    _selectedGroup = _groupTree;
    if (_selectedGroup.entries.isNotEmpty) {
      _selectEntry(_selectedGroup.entries.first);
    }
    _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_autoLockMinutes > 0) {
      _inactivityTimer = Timer(Duration(minutes: _autoLockMinutes), _autoLock);
    }
  }

  void _autoLock() {
    if (!mounted) return;
    if (_dirty) {
      // If dirty, just reset the timer rather than auto-lock losing changes.
      _resetInactivityTimer();
      return;
    }
    widget.repository.close();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => UnlockPage(repository: widget.repository),
      ),
    );
  }

  void _onCopyToClipboard(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    _clipboardTimer?.cancel();
    final secs = widget.settingsService?.settings.clipboardClearSeconds ?? 30;
    if (secs > 0) {
      _clipboardTimer = Timer(Duration(seconds: secs), () {
        Clipboard.setData(const ClipboardData(text: ''));
      });
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copied to clipboard'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _inactivityTimer?.cancel();
    _clipboardTimer?.cancel();
    _editTitleController.dispose();
    _editUsernameController.dispose();
    _editPasswordController.dispose();
    _editUrlController.dispose();
    _editNotesController.dispose();
    _editExpiryDateController.dispose();
    super.dispose();
  }

  Future<void> _selectEntry(EntrySummary entry) async {
    _cancelEdit();
    setState(() {
      _selectedEntry = entry;
      _detail = null;
      _loadingDetail = true;
      _passwordVisible = false;
      _visibleCustomFields.clear();
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

  void _replaceVaultSnapshot(
    OpenedVault vault, {
    String? selectedGroupId,
    String? selectedEntryId,
  }) {
    _groupTree = vault.groupTree;
    _selectedGroup =
        _findGroupById(_groupTree, selectedGroupId ?? _selectedGroup.id) ??
        _groupTree;
    _selectedEntry = selectedEntryId == null
        ? null
        : _findEntryInGroup(_selectedGroup, selectedEntryId);
    if (_selectedEntry == null) {
      _detail = null;
      _editing = false;
      _showHistory = false;
      _history = null;
    }
    _selectedEntryIds.removeWhere(
      (id) => _findGroupContainingEntry(_groupTree, id) == null,
    );
  }

  GroupNode? _findGroupById(GroupNode root, String id) {
    for (final group in root.flatten()) {
      if (group.id == id) return group;
    }
    return null;
  }

  GroupNode? _findGroupContainingEntry(GroupNode root, String entryId) {
    for (final group in root.flatten()) {
      if (group.entries.any((entry) => entry.id == entryId)) {
        return group;
      }
    }
    return null;
  }

  EntrySummary? _findEntryInGroup(GroupNode group, String entryId) {
    for (final entry in group.entries) {
      if (entry.id == entryId) return entry;
    }
    return null;
  }

  bool _isGroupInRecycleBin(GroupNode group) {
    for (final candidate in _groupTree.flatten()) {
      if (candidate.isRecycleBin) {
        return _containsGroup(candidate, group.id);
      }
    }
    return false;
  }

  bool _containsGroup(GroupNode root, String groupId) {
    if (root.id == groupId) return true;
    return root.groups.any((child) => _containsGroup(child, groupId));
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
    _editExpires = detail.expires;
    _editExpiryDateController.text = detail.expiryTime ?? '';
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
      expires: _editExpires,
      expiryTime: _editExpires ? _editExpiryDateController.text.trim() : null,
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
        title: const Text('Move entry to recycle bin'),
        content: Text(
          'Move "${_detail?.displayTitle ?? entryId}" to Recycle Bin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final snapshot = await widget.repository.deleteEntry(entryId);
      if (!mounted) return;
      setState(() {
        _replaceVaultSnapshot(snapshot, selectedGroupId: _selectedGroup.id);
        _dirty = true;
      });
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> _restoreEntry() async {
    final entryId = _selectedEntry?.id;
    if (entryId == null) return;
    try {
      final snapshot = await widget.repository.restoreEntry(entryId);
      if (!mounted) return;
      final targetGroup = _findGroupContainingEntry(
        snapshot.groupTree,
        entryId,
      );
      setState(() {
        _replaceVaultSnapshot(
          snapshot,
          selectedGroupId: targetGroup?.id,
          selectedEntryId: entryId,
        );
        _dirty = true;
      });
      final restored = _selectedEntry;
      if (restored != null) {
        _selectEntry(restored);
      }
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> _permanentlyDeleteEntry() async {
    final entryId = _selectedEntry?.id;
    if (entryId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete entry'),
        content: Text(
          'Permanently delete "${_detail?.displayTitle ?? entryId}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final snapshot = await widget.repository.permanentlyDeleteEntry(entryId);
      if (!mounted) return;
      setState(() {
        _replaceVaultSnapshot(snapshot, selectedGroupId: _selectedGroup.id);
        _dirty = true;
      });
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> _emptyRecycleBin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty recycle bin'),
        content: const Text('Permanently delete all entries in Recycle Bin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Empty'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final snapshot = await widget.repository.emptyRecycleBin();
      if (!mounted) return;
      setState(() {
        _replaceVaultSnapshot(snapshot, selectedGroupId: _selectedGroup.id);
        _dirty = true;
        _selectedEntryIds.clear();
      });
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> _saveVault() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      await widget.repository.save(
        masterPassword: _saveMasterPassword,
        keyfilePath: _saveKeyfilePath,
      );
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
        _conflict = false;
      });
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = err.toString();
      });
      if (_isRemoteConflict(err)) {
        setState(() => _conflict = true);
        await _showRemoteConflictDialog(err.toString());
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $err')));
      }
    }
  }

  bool _isRemoteConflict(Object err) {
    final text = err.toString().toLowerCase();
    return text.contains('remote database has been modified') ||
        text.contains('conflict');
  }

  Future<void> _showRemoteConflictDialog(String message) async {
    final action = await showDialog<_RemoteConflictAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remote save conflict'),
        content: Text(
          '$message\n\nYour local edits are still open and unsaved.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_RemoteConflictAction.keepLocal),
            child: const Text('Keep local edits'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_RemoteConflictAction.reopenRemote),
            child: const Text('Reopen remote'),
          ),
        ],
      ),
    );

    if (action == _RemoteConflictAction.reopenRemote) {
      await _reopenRemote();
    }
  }

  Future<void> _showRemoteMetadata() async {
    final metadata = widget.initialVault.metadata;
    if (metadata == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remote metadata'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetadataLine(label: 'ETag', value: metadata.etag),
            _MetadataLine(label: 'Last-Modified', value: metadata.lastModified),
            _MetadataLine(
              label: 'Content-Length',
              value: metadata.contentLength?.toString(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPasswordGenerator(void Function(String) onAccept) {
    final lengthCtrl = TextEditingController(text: '20');
    bool lowercase = true, uppercase = true, digits = true, symbols = true;
    bool avoidAmbiguous = false;

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          String generated = _generatePassword(
            int.tryParse(lengthCtrl.text) ?? 20,
            lowercase: lowercase,
            uppercase: uppercase,
            digits: digits,
            symbols: symbols,
            avoidAmbiguous: avoidAmbiguous,
          );

          return AlertDialog(
            title: const Text('Password generator'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('Length:'),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: lengthCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(
                            () => generated = _generatePassword(
                              int.tryParse(lengthCtrl.text) ?? 20,
                              lowercase: lowercase,
                              uppercase: uppercase,
                              digits: digits,
                              symbols: symbols,
                              avoidAmbiguous: avoidAmbiguous,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  CheckboxListTile(
                    title: const Text('Lowercase (a–z)'),
                    value: lowercase,
                    onChanged: (v) => setState(() => lowercase = v ?? true),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Uppercase (A–Z)'),
                    value: uppercase,
                    onChanged: (v) => setState(() => uppercase = v ?? true),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Digits (0–9)'),
                    value: digits,
                    onChanged: (v) => setState(() => digits = v ?? true),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Symbols (!@#…)'),
                    value: symbols,
                    onChanged: (v) => setState(() => symbols = v ?? true),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Avoid ambiguous (Il1O0)'),
                    value: avoidAmbiguous,
                    onChanged: (v) =>
                        setState(() => avoidAmbiguous = v ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      generated,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onAccept(generated);
                },
                child: const Text('Use password'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _generatePassword(
    int length, {
    required bool lowercase,
    required bool uppercase,
    required bool digits,
    required bool symbols,
    required bool avoidAmbiguous,
  }) {
    const lower = 'abcdefghijklmnopqrstuvwxyz';
    const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const digit = '0123456789';
    const sym = '!@#\$%^&*()_+-=[]{}|;:,.<>?';
    const ambiguous = 'Il1O0';

    var pool = '';
    if (lowercase) pool += lower;
    if (uppercase) pool += upper;
    if (digits) pool += digit;
    if (symbols) pool += sym;
    if (pool.isEmpty) return '';

    if (avoidAmbiguous) {
      pool = pool.split('').where((c) => !ambiguous.contains(c)).join('');
    }

    final rand = Random.secure();
    return List.generate(length, (_) => pool[rand.nextInt(pool.length)]).join();
  }

  Future<void> _downloadAttachment(EntrySummary entry, String name) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save $name',
        fileName: name,
      );
      if (result == null) return;

      final bytes = await widget.repository.attachmentBytes(
        entryId: entry.id,
        name: name,
      );
      await File(result).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved $name')));
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $err')));
    }
  }

  Future<void> _addAttachment(EntrySummary entry) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        dialogTitle: 'Add attachment to ${entry.displayTitle}',
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;

      await widget.repository.upsertAttachment(
        entryId: entry.id,
        name: file.name,
        bytes: Uint8List.fromList(file.bytes!),
        protect: false,
      );
      if (!mounted) return;
      setState(() => _dirty = true);
      _selectEntry(entry);
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Add attachment failed: $err')));
    }
  }

  Future<void> _removeAttachment(EntrySummary entry, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove attachment'),
        content: Text('Remove "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.repository.removeAttachment(entryId: entry.id, name: name);
      if (!mounted) return;
      setState(() => _dirty = true);
      _selectEntry(entry);
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Remove failed: $err')));
    }
  }

  // --- Custom field helpers ---

  Future<void> _addCustomField() async {
    final keyCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    bool protect = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add custom field'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: 'Field name'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueCtrl,
                decoration: const InputDecoration(labelText: 'Value'),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                title: const Text('Protected'),
                value: protect,
                onChanged: (v) => setState(() => protect = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final key = keyCtrl.text.trim();
    final value = valueCtrl.text;
    keyCtrl.dispose();
    valueCtrl.dispose();
    if (key.isEmpty) return;

    final entryId = _selectedEntry?.id;
    if (entryId == null) return;

    try {
      final updated = await widget.repository.setCustomField(
        entryId: entryId,
        key: key,
        value: value,
        protect: protect,
      );
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _dirty = true;
        _editing = true;
      });
      _editTitleController.text = updated.title ?? '';
      _editUsernameController.text = updated.username ?? '';
      _editPasswordController.text = updated.password ?? '';
      _editUrlController.text = updated.url ?? '';
      _editNotesController.text = updated.notes ?? '';
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> _removeCustomField(String key) async {
    final entryId = _selectedEntry?.id;
    if (entryId == null) return;

    try {
      final updated = await widget.repository.deleteCustomField(
        entryId: entryId,
        key: key,
      );
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _dirty = true;
        _editing = true;
      });
      _editTitleController.text = updated.title ?? '';
      _editUsernameController.text = updated.username ?? '';
      _editPasswordController.text = updated.password ?? '';
      _editUrlController.text = updated.url ?? '';
      _editNotesController.text = updated.notes ?? '';
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> _toggleCustomFieldProtect(
    String key,
    String value,
    bool currentlyProtected,
  ) async {
    final entryId = _selectedEntry?.id;
    if (entryId == null) return;

    try {
      final updated = await widget.repository.setCustomField(
        entryId: entryId,
        key: key,
        value: value,
        protect: !currentlyProtected,
      );
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _dirty = true;
        _editing = true;
      });
      _editTitleController.text = updated.title ?? '';
      _editUsernameController.text = updated.username ?? '';
      _editPasswordController.text = updated.password ?? '';
      _editUrlController.text = updated.url ?? '';
      _editNotesController.text = updated.notes ?? '';
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> _loadHistory() async {
    final entryId = _selectedEntry?.id;
    if (entryId == null) return;

    setState(() {
      _loadingHistory = true;
      _showHistory = !_showHistory;
    });

    if (!_showHistory) {
      setState(() => _loadingHistory = false);
      return;
    }

    try {
      final history = await widget.repository.entryHistory(entryId);
      if (!mounted) return;
      setState(() {
        _history = history;
        _loadingHistory = false;
      });
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> _viewHistoryDetail(HistorySummary summary) async {
    final entryId = _selectedEntry?.id;
    if (entryId == null) return;

    try {
      final snapshot = await widget.repository.entryHistoryDetail(
        entryId: entryId,
        index: summary.index,
      );
      if (!mounted) return;
      setState(() {
        _detail = snapshot;
        _showHistory = false;
        _editing = false;
        _passwordVisible = false;
      });
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
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

  Future<void> _reopenRemote() async {
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
        final groups = _groupTree.flatten().toList();
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

  Future<void> _createGroupDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New group'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Group name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    final parent = _isGroupInRecycleBin(_selectedGroup)
        ? _groupTree
        : _selectedGroup;
    try {
      final group = await widget.repository.createGroup(
        parentId: parent.id,
        name: name,
      );
      if (!mounted) return;
      setState(() {
        _dirty = true;
        parent.groups.add(group);
        _selectedGroup = group;
        _selectedEntry = null;
        _detail = null;
      });
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _renameGroupDialog(GroupNode group) async {
    final ctrl = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Group name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty || name == group.name) return;
    try {
      await widget.repository.renameGroup(groupId: group.id, name: name);
      if (!mounted) return;
      setState(() {
        _dirty = true;
        for (final g in _groupTree.flatten()) {
          if (g.id == group.id) {
            g.name = name;
            break;
          }
        }
      });
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _deleteGroupDialog(GroupNode group) async {
    if (group.groups.isNotEmpty || group.entries.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Move "${group.name}" to recycle bin?'),
          content: Text(
            'This group contains ${group.totalEntryCount} entries and ${group.groups.length} subgroups.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Move'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      final snapshot = await widget.repository.deleteGroup(group.id);
      if (!mounted) return;
      setState(() {
        _replaceVaultSnapshot(snapshot, selectedGroupId: _groupTree.id);
        _dirty = true;
      });
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _restoreGroupDialog(GroupNode group) async {
    try {
      final snapshot = await widget.repository.restoreGroup(group.id);
      if (!mounted) return;
      setState(() {
        _replaceVaultSnapshot(snapshot, selectedGroupId: group.id);
        _dirty = true;
      });
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _permanentlyDeleteGroupDialog(GroupNode group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Permanently delete "${group.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final snapshot = await widget.repository.permanentlyDeleteGroup(group.id);
      if (!mounted) return;
      setState(() {
        _replaceVaultSnapshot(snapshot, selectedGroupId: _groupTree.id);
        _dirty = true;
      });
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _moveEntryDialog() async {
    final entry = _selectedEntry;
    if (entry == null) return;
    final groups = _groupTree
        .flatten()
        .where((group) => !_isGroupInRecycleBin(group))
        .toList();
    final target = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Move to group'),
        children: [
          for (final g in groups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g.id),
              child: Text(
                g.name,
                style: TextStyle(
                  fontWeight: g.id == _selectedGroup.id
                      ? FontWeight.bold
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
    if (target == null || target == _selectedGroup.id) return;
    try {
      await widget.repository.moveEntry(entry.id, target);
      if (!mounted) return;
      setState(() => _dirty = true);
      _refreshGroup(_selectedGroup.id);
      _refreshGroup(target);
      _selectedEntry = null;
      _detail = null;
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedEntryIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _selectedGroup.isRecycleBin
              ? 'Permanently delete selected entries'
              : 'Move selected entries to recycle bin',
        ),
        content: Text(
          _selectedGroup.isRecycleBin
              ? 'Permanently delete ${_selectedEntryIds.length} entries?'
              : 'Move ${_selectedEntryIds.length} entries to Recycle Bin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_selectedGroup.isRecycleBin ? 'Delete' : 'Move'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    OpenedVault? snapshot;
    for (final id in _selectedEntryIds.toList()) {
      try {
        snapshot = await widget.repository.deleteEntry(id);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      if (snapshot != null) {
        _replaceVaultSnapshot(snapshot, selectedGroupId: _selectedGroup.id);
      }
      _dirty = true;
      _selectedEntryIds.clear();
    });
  }

  Future<void> _changePasswordDialog() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change master password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Old password'),
              autofocus: true,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    final oldPw = oldCtrl.text;
    final newPw = newCtrl.text;
    oldCtrl.dispose();
    newCtrl.dispose();
    if (result != true || oldPw.isEmpty || newPw.isEmpty) return;
    try {
      await widget.repository.changePassword(
        oldPassword: oldPw,
        newPassword: newPw,
        keyfilePath: _saveKeyfilePath,
      );
      if (!mounted) return;
      _saveMasterPassword = newPw;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password changed')));
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _duplicateEntry() async {
    final detail = _detail;
    if (detail == null) return;
    try {
      await widget.repository.createEntry(
        CreateEntryRequest(
          groupId: _selectedGroup.id,
          title: '${detail.title ?? 'Untitled'} (copy)',
          username: detail.username,
          password: detail.password,
          url: detail.url,
          notes: detail.notes,
          customFields: detail.fields,
        ),
      );
      if (!mounted) return;
      setState(() => _dirty = true);
      _refreshGroup(_selectedGroup.id);
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  void _showCreateDialog() {
    final titleCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final customFields = <_FieldEntry>[];
    bool createExpires = false;
    final expiryDateCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: passwordCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                            ),
                            obscureText: true,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Generate password',
                          onPressed: () => _showPasswordGenerator((pw) {
                            passwordCtrl.text = pw;
                            setDialogState(() {});
                          }),
                          icon: const Icon(Icons.password_outlined),
                        ),
                      ],
                    ),
                    if (passwordCtrl.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: _pwStrength(passwordCtrl.text),
                                  color: _pwColor(
                                    _pwStrength(passwordCtrl.text),
                                  ),
                                  minHeight: 4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              [
                                'Weak',
                                'Fair',
                                'Good',
                                'Strong',
                              ][(_pwStrength(passwordCtrl.text) * 3.99)
                                  .toInt()],
                              style: TextStyle(
                                fontSize: 11,
                                color: _pwColor(_pwStrength(passwordCtrl.text)),
                              ),
                            ),
                          ],
                        ),
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
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: const Text('Entry expires'),
                      value: createExpires,
                      onChanged: (v) =>
                          setDialogState(() => createExpires = v ?? false),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (createExpires)
                      TextFormField(
                        controller: expiryDateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Expiry date (YYYY-MM-DD)',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          'Custom fields',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Add custom field',
                          onPressed: () {
                            setDialogState(
                              () => customFields.add(
                                _FieldEntry(
                                  keyCtrl: TextEditingController(),
                                  valueCtrl: TextEditingController(),
                                  protect: false,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < customFields.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          key: ValueKey(customFields[i]),
                          children: [
                            Expanded(
                              child: TextField(
                                controller: customFields[i].keyCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Field name',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: customFields[i].valueCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Value',
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: customFields[i].protect
                                  ? 'Protected'
                                  : 'Not protected',
                              onPressed: () {
                                setDialogState(
                                  () => customFields[i].protect =
                                      !customFields[i].protect,
                                );
                              },
                              icon: Icon(
                                customFields[i].protect
                                    ? Icons.lock
                                    : Icons.lock_open,
                                size: 18,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove field',
                              onPressed: () {
                                customFields[i].keyCtrl.dispose();
                                customFields[i].valueCtrl.dispose();
                                setDialogState(() => customFields.removeAt(i));
                              },
                              icon: Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
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
                final fields = <String, String>{};
                final protectedKeys = <String>[];
                for (final f in customFields) {
                  final key = f.keyCtrl.text.trim();
                  if (key.isNotEmpty) {
                    fields[key] = f.valueCtrl.text;
                    if (f.protect) protectedKeys.add(key);
                  }
                  f.keyCtrl.dispose();
                  f.valueCtrl.dispose();
                }
                _createEntry(
                  CreateEntryRequest(
                    groupId: _selectedGroup.id,
                    title: titleCtrl.text.trim(),
                    username: usernameCtrl.text.trim(),
                    password: passwordCtrl.text,
                    url: urlCtrl.text.trim(),
                    notes: notesCtrl.text.trim(),
                    customFields: fields,
                    protectedCustomFields: protectedKeys,
                    expires: createExpires,
                    expiryTime: createExpires
                        ? expiryDateCtrl.text.trim()
                        : null,
                  ),
                );
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchGroups = _searchAllGroups
        ? _groupTree.flatten().toList()
        : [_selectedGroup];
    final entries = searchGroups.expand((g) => g.entries).where((entry) {
      if (_query.isEmpty) return true;
      final haystack = [
        entry.title,
        entry.username,
        entry.url,
        entry.notes,
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(_query.toLowerCase());
    }).toList();
    switch (_sortMode) {
      case 0:
        entries.sort((a, b) => a.displayTitle.compareTo(b.displayTitle));
      case 1:
        entries.sort((a, b) => (a.username ?? '').compareTo(b.username ?? ''));
      case 2:
        entries.sort(
          (a, b) => (b.lastModified ?? '').compareTo(a.lastModified ?? ''),
        );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveVault,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): _lock,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _showCreateDialog,
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          shift: true,
        ): _copySelectedPassword,
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
      },
      child: Listener(
        onPointerDown: (_) => _resetInactivityTimer(),
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(
              children: [
                const Icon(Icons.lock_outline),
                const SizedBox(width: 10),
                const Text('KeePassY'),
                const SizedBox(width: 16),
                StatusChip(
                  dirty: _dirty,
                  saving: _saving,
                  error: _saveError,
                  conflict: _conflict,
                ),
                const SizedBox(width: 12),
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
              if (_selectedEntryIds.isNotEmpty)
                IconButton(
                  tooltip: 'Delete selected (${_selectedEntryIds.length})',
                  onPressed: _bulkDelete,
                  icon: Icon(
                    Icons.delete_sweep,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              _SaveButton(
                dirty: _dirty,
                saving: _saving,
                error: _saveError,
                conflict: _conflict,
                onPressed: _saveVault,
              ),
              PopupMenuButton<_MoreAction>(
                tooltip: 'More actions',
                icon: const Icon(Icons.more_vert),
                onSelected: (action) {
                  switch (action) {
                    case _MoreAction.settings:
                      showDialog<void>(
                        context: context,
                        builder: (_) => SettingsDialog(
                          settingsService: widget.settingsService!,
                        ),
                      );
                    case _MoreAction.remoteMetadata:
                      _showRemoteMetadata();
                    case _MoreAction.changePassword:
                      _changePasswordDialog();
                    case _MoreAction.autoLock:
                      _showAutoLockConfig();
                    case _MoreAction.reopenRemote:
                      _reopenRemote();
                  }
                },
                itemBuilder: (context) => [
                  if (widget.settingsService != null)
                    const PopupMenuItem<_MoreAction>(
                      value: _MoreAction.settings,
                      child: ListTile(
                        leading: Icon(Icons.settings_outlined),
                        title: Text('Settings'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (widget.initialVault.metadata != null)
                    const PopupMenuItem<_MoreAction>(
                      value: _MoreAction.remoteMetadata,
                      child: ListTile(
                        leading: Icon(Icons.cloud_done_outlined),
                        title: Text('Remote metadata'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem<_MoreAction>(
                    value: _MoreAction.changePassword,
                    child: ListTile(
                      leading: Icon(Icons.vpn_key_outlined),
                      title: Text('Change master password'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<_MoreAction>(
                    value: _MoreAction.autoLock,
                    child: ListTile(
                      leading: Icon(Icons.timer_outlined),
                      title: Text('Auto-lock settings'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (_conflict)
                    const PopupMenuItem<_MoreAction>(
                      value: _MoreAction.reopenRemote,
                      child: ListTile(
                        leading: Icon(Icons.refresh, color: Colors.red),
                        title: Text(
                          'Reopen remote',
                          style: TextStyle(color: Colors.red),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
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
                        root: _groupTree,
                        selectedGroup: _selectedGroup,
                        horizontal: true,
                        onSelected: _selectGroup,
                        onCreateGroup: _createGroupDialog,
                        onRenameGroup: _renameGroupDialog,
                        onDeleteGroup: _deleteGroupDialog,
                        onRestoreGroup: _restoreGroupDialog,
                        onPermanentDeleteGroup: _permanentlyDeleteGroupDialog,
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: _EntryList(
                        group: _selectedGroup,
                        entries: entries,
                        selectedEntry: _selectedEntry,
                        query: _query,
                        onQueryChanged: (value) =>
                            setState(() => _query = value),
                        onSelected: _selectEntry,
                        searchAllGroups: _searchAllGroups,
                        onSearchAllGroupsChanged: (v) =>
                            setState(() => _searchAllGroups = v),
                        selectedEntryIds: _selectedEntryIds,
                        onToggleSelect: (id) => setState(
                          () => _selectedEntryIds.contains(id)
                              ? _selectedEntryIds.remove(id)
                              : _selectedEntryIds.add(id),
                        ),
                        sortMode: _sortMode,
                        onSortModeChanged: (v) => setState(() => _sortMode = v),
                        onCreateEntry: _isGroupInRecycleBin(_selectedGroup)
                            ? null
                            : _showCreateDialog,
                        onEmptyRecycleBin:
                            _selectedGroup.isRecycleBin &&
                                _selectedGroup.totalEntryCount +
                                        _selectedGroup.groups.length >
                                    0
                            ? _emptyRecycleBin
                            : null,
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
                        onRestore: _restoreEntry,
                        onPermanentDelete: _permanentlyDeleteEntry,
                        inRecycleBin: _isGroupInRecycleBin(_selectedGroup),
                        onGeneratePassword: _showPasswordGenerator,
                        onDownloadAttachment: _downloadAttachment,
                        onAddAttachment: _addAttachment,
                        onRemoveAttachment: _removeAttachment,
                        onAddCustomField: _addCustomField,
                        onRemoveCustomField: _removeCustomField,
                        onToggleCustomFieldProtect: _toggleCustomFieldProtect,
                        onToggleHistory: _loadHistory,
                        onViewHistoryDetail: _viewHistoryDetail,
                        onMoveEntry: _moveEntryDialog,
                        onDuplicateEntry: _duplicateEntry,
                        editExpires: _editExpires,
                        onEditExpiresChanged: (v) =>
                            setState(() => _editExpires = v),
                        editExpiryDateCtrl: _editExpiryDateController,
                        showHistory: _showHistory,
                        history: _history,
                        loadingHistory: _loadingHistory,
                        selectedEntry: _selectedEntry,
                        visibleCustomFields: _visibleCustomFields,
                        clipboardClearSeconds:
                            widget
                                .settingsService
                                ?.settings
                                .clipboardClearSeconds ??
                            30,
                        onCopyToClipboard: _onCopyToClipboard,
                        onToggleCustomFieldVisibility: (key) {
                          setState(() {
                            if (_visibleCustomFields.contains(key)) {
                              _visibleCustomFields.remove(key);
                            } else {
                              _visibleCustomFields.add(key);
                            }
                          });
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
                      root: _groupTree,
                      selectedGroup: _selectedGroup,
                      onSelected: _selectGroup,
                      onCreateGroup: _createGroupDialog,
                      onRenameGroup: _renameGroupDialog,
                      onDeleteGroup: _deleteGroupDialog,
                      onRestoreGroup: _restoreGroupDialog,
                      onPermanentDeleteGroup: _permanentlyDeleteGroupDialog,
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
                      searchAllGroups: _searchAllGroups,
                      onSearchAllGroupsChanged: (v) =>
                          setState(() => _searchAllGroups = v),
                      selectedEntryIds: _selectedEntryIds,
                      onToggleSelect: (id) => setState(
                        () => _selectedEntryIds.contains(id)
                            ? _selectedEntryIds.remove(id)
                            : _selectedEntryIds.add(id),
                      ),
                      sortMode: _sortMode,
                      onSortModeChanged: (v) => setState(() => _sortMode = v),
                      onCreateEntry: _isGroupInRecycleBin(_selectedGroup)
                          ? null
                          : _showCreateDialog,
                      onEmptyRecycleBin:
                          _selectedGroup.isRecycleBin &&
                              _selectedGroup.totalEntryCount +
                                      _selectedGroup.groups.length >
                                  0
                          ? _emptyRecycleBin
                          : null,
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
                      onRestore: _restoreEntry,
                      onPermanentDelete: _permanentlyDeleteEntry,
                      inRecycleBin: _isGroupInRecycleBin(_selectedGroup),
                      onGeneratePassword: _showPasswordGenerator,
                      onDownloadAttachment: _downloadAttachment,
                      onAddAttachment: _addAttachment,
                      onRemoveAttachment: _removeAttachment,
                      onAddCustomField: _addCustomField,
                      onRemoveCustomField: _removeCustomField,
                      onToggleCustomFieldProtect: _toggleCustomFieldProtect,
                      onToggleHistory: _loadHistory,
                      onViewHistoryDetail: _viewHistoryDetail,
                      onMoveEntry: _moveEntryDialog,
                      onDuplicateEntry: _duplicateEntry,
                      editExpires: _editExpires,
                      onEditExpiresChanged: (v) =>
                          setState(() => _editExpires = v),
                      editExpiryDateCtrl: _editExpiryDateController,
                      showHistory: _showHistory,
                      history: _history,
                      loadingHistory: _loadingHistory,
                      selectedEntry: _selectedEntry,
                      visibleCustomFields: _visibleCustomFields,
                      onToggleCustomFieldVisibility: (key) {
                        setState(() {
                          if (_visibleCustomFields.contains(key)) {
                            _visibleCustomFields.remove(key);
                          } else {
                            _visibleCustomFields.add(key);
                          }
                        });
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _copySelectedPassword() {
    final pw = _detail?.password;
    if (pw != null && pw.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: pw));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password copied to clipboard'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _handleEscape() {
    if (_editing) {
      _cancelEdit();
    }
  }

  void _showAutoLockConfig() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auto-lock timer'),
        content: DropdownButtonFormField<int>(
          initialValue: _autoLockMinutes,
          decoration: const InputDecoration(labelText: 'Lock after inactivity'),
          items: const [
            DropdownMenuItem(value: 1, child: Text('1 minute')),
            DropdownMenuItem(value: 5, child: Text('5 minutes')),
            DropdownMenuItem(value: 15, child: Text('15 minutes')),
            DropdownMenuItem(value: 30, child: Text('30 minutes')),
            DropdownMenuItem(value: 0, child: Text('Never')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _autoLockMinutes = v);
            Navigator.pop(ctx);
            if (v == 0) {
              _inactivityTimer?.cancel();
            } else {
              _resetInactivityTimer();
            }
          },
        ),
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
    this.conflict = false,
  });

  final bool dirty;
  final bool saving;
  final VoidCallback onPressed;
  final String? error;
  final bool conflict;

  @override
  Widget build(BuildContext context) {
    final enabled = dirty || error != null || conflict;

    return IconButton(
      tooltip: conflict
          ? 'Save failed — remote conflict'
          : error != null
          ? 'Save failed: $error'
          : dirty
          ? 'Save vault (unsaved changes)'
          : 'Save vault',
      onPressed: enabled ? onPressed : null,
      icon: saving
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              conflict || error != null
                  ? Icons.error_outline
                  : dirty
                  ? Icons.save_as_outlined
                  : Icons.save_outlined,
            ),
    );
  }
}

class _MetadataLine extends StatelessWidget {
  const _MetadataLine({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              value?.isNotEmpty == true ? value! : 'Unavailable',
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupRail extends StatefulWidget {
  const _GroupRail({
    required this.root,
    required this.selectedGroup,
    required this.onSelected,
    this.horizontal = false,
    this.onCreateGroup,
    this.onRenameGroup,
    this.onDeleteGroup,
    this.onRestoreGroup,
    this.onPermanentDeleteGroup,
  });

  final GroupNode root;
  final GroupNode selectedGroup;
  final ValueChanged<GroupNode> onSelected;
  final bool horizontal;
  final VoidCallback? onCreateGroup;
  final void Function(GroupNode)? onRenameGroup;
  final void Function(GroupNode)? onDeleteGroup;
  final void Function(GroupNode)? onRestoreGroup;
  final void Function(GroupNode)? onPermanentDeleteGroup;

  @override
  State<_GroupRail> createState() => _GroupRailState();
}

class _GroupRailState extends State<_GroupRail> {
  final Set<String> _collapsedGroupIds = {};

  @override
  Widget build(BuildContext context) {
    final groups = _groupItems(widget.root).toList(growable: false);

    final header = !widget.horizontal
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
            child: Row(
              children: [
                Text(
                  'Groups',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (widget.onCreateGroup != null)
                  IconButton(
                    tooltip: 'New group',
                    onPressed: widget.onCreateGroup,
                    icon: const Icon(Icons.add, size: 18),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();

    if (widget.horizontal) {
      return Column(
        children: [
          header,
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              scrollDirection: Axis.horizontal,
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = groups[index];
                return SizedBox(
                  width: 180,
                  child: _GroupButton(
                    group: item.group,
                    depth: item.depth,
                    selected: item.group.id == widget.selectedGroup.id,
                    onSelected: widget.onSelected,
                    inRecycleBin: item.inRecycleBin,
                    canToggle: item.canToggle,
                    collapsed: item.collapsed,
                    onToggleCollapsed: item.canToggle
                        ? () => _toggleCollapsed(item.group)
                        : null,
                    onRename: widget.onRenameGroup,
                    onDelete: widget.onDeleteGroup,
                    onRestore: widget.onRestoreGroup,
                    onPermanentDelete: widget.onPermanentDeleteGroup,
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        header,
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final item = groups[index];
              return _GroupButton(
                group: item.group,
                depth: item.depth,
                selected: item.group.id == widget.selectedGroup.id,
                onSelected: widget.onSelected,
                inRecycleBin: item.inRecycleBin,
                canToggle: item.canToggle,
                collapsed: item.collapsed,
                onToggleCollapsed: item.canToggle
                    ? () => _toggleCollapsed(item.group)
                    : null,
                onRename: widget.onRenameGroup,
                onDelete: widget.onDeleteGroup,
                onRestore: widget.onRestoreGroup,
                onPermanentDelete: widget.onPermanentDeleteGroup,
              );
            },
          ),
        ),
      ],
    );
  }

  void _toggleCollapsed(GroupNode group) {
    setState(() {
      if (_collapsedGroupIds.contains(group.id)) {
        _collapsedGroupIds.remove(group.id);
      } else {
        _collapsedGroupIds.add(group.id);
      }
    });
  }

  Iterable<_GroupListItem> _groupItems(
    GroupNode group, [
    int depth = 0,
    bool inRecycleBin = false,
  ]) sync* {
    final currentInRecycleBin = inRecycleBin || group.isRecycleBin;
    final canToggle = group.groups.isNotEmpty;
    final collapsed = canToggle && _collapsedGroupIds.contains(group.id);
    yield _GroupListItem(
      group: group,
      depth: depth,
      inRecycleBin: currentInRecycleBin,
      canToggle: canToggle,
      collapsed: collapsed,
    );
    if (collapsed) {
      return;
    }
    for (final child in group.groups) {
      yield* _groupItems(child, depth + 1, currentInRecycleBin);
    }
  }
}

class _GroupListItem {
  const _GroupListItem({
    required this.group,
    required this.depth,
    required this.inRecycleBin,
    required this.canToggle,
    required this.collapsed,
  });

  final GroupNode group;
  final int depth;
  final bool inRecycleBin;
  final bool canToggle;
  final bool collapsed;
}

void _showGroupContextMenu(
  BuildContext context,
  Offset position,
  GroupNode group,
  bool inRecycleBin,
  void Function(GroupNode)? onRename,
  void Function(GroupNode)? onDelete,
  void Function(GroupNode)? onRestore,
  void Function(GroupNode)? onPermanentDelete,
) {
  showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: [
      if (!inRecycleBin && onRename != null)
        PopupMenuItem<String>(
          value: 'rename',
          child: const ListTile(
            leading: Icon(Icons.edit),
            title: Text('Rename'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (!inRecycleBin && onDelete != null)
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (inRecycleBin && onRestore != null)
        PopupMenuItem<String>(
          value: 'restore',
          child: const ListTile(
            leading: Icon(Icons.restore_from_trash_outlined),
            title: Text('Restore'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (inRecycleBin && onPermanentDelete != null)
        PopupMenuItem<String>(
          value: 'permanent-delete',
          child: ListTile(
            leading: Icon(
              Icons.delete_forever,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete permanently',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
    ],
  ).then((value) {
    if (value == 'rename') {
      onRename?.call(group);
    } else if (value == 'delete') {
      onDelete?.call(group);
    } else if (value == 'restore') {
      onRestore?.call(group);
    } else if (value == 'permanent-delete') {
      onPermanentDelete?.call(group);
    }
  });
}

class _GroupButton extends StatelessWidget {
  const _GroupButton({
    required this.group,
    required this.depth,
    required this.selected,
    required this.onSelected,
    required this.inRecycleBin,
    required this.canToggle,
    required this.collapsed,
    this.onToggleCollapsed,
    this.onRename,
    this.onDelete,
    this.onRestore,
    this.onPermanentDelete,
  });

  final GroupNode group;
  final int depth;
  final bool selected;
  final bool inRecycleBin;
  final bool canToggle;
  final bool collapsed;
  final ValueChanged<GroupNode> onSelected;
  final VoidCallback? onToggleCollapsed;
  final void Function(GroupNode)? onRename;
  final void Function(GroupNode)? onDelete;
  final void Function(GroupNode)? onRestore;
  final void Function(GroupNode)? onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entryLabel = group.entryCount == 1 ? 'entry' : 'entries';
    final isRecycledGroup = inRecycleBin && !group.isRecycleBin;
    final isRecycleRoot = group.isRecycleBin;
    final horizontalInset = 12.0 + (depth.clamp(0, 4) * 14.0);
    final recycleAccent = colorScheme.error;
    final recycleContainer = colorScheme.errorContainer.withValues(
      alpha: selected ? 0.55 : 0.18,
    );
    final backgroundColor = selected
        ? isRecycleRoot
              ? recycleContainer
              : colorScheme.primary.withValues(alpha: 0.11)
        : isRecycleRoot
        ? recycleContainer
        : Colors.transparent;
    final iconColor = selected
        ? isRecycleRoot
              ? colorScheme.onErrorContainer
              : colorScheme.primary
        : isRecycleRoot || isRecycledGroup
        ? recycleAccent
        : colorScheme.onSurfaceVariant;
    final titleColor = isRecycleRoot
        ? (selected ? colorScheme.onErrorContainer : recycleAccent)
        : null;
    final subtitle = isRecycleRoot
        ? '${group.totalEntryCount} ${group.totalEntryCount == 1 ? 'entry' : 'entries'}, '
              '${group.groups.length} ${group.groups.length == 1 ? 'group' : 'groups'}'
        : isRecycledGroup
        ? '${group.entryCount} $entryLabel in Recycle Bin'
        : '${group.entryCount} $entryLabel';

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelected(group),
        child: Padding(
          padding: EdgeInsets.fromLTRB(horizontalInset, 10, 12, 10),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 24,
                child: canToggle
                    ? IconButton(
                        tooltip: collapsed ? 'Expand group' : 'Collapse group',
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: onToggleCollapsed,
                        icon: Icon(
                          collapsed
                              ? Icons.keyboard_arrow_right
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: iconColor,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 4),
              Icon(
                group.isRecycleBin
                    ? Icons.delete_outline
                    : isRecycledGroup
                    ? Icons.folder_delete_outlined
                    : group.groups.isEmpty
                    ? Icons.folder_outlined
                    : Icons.folder_copy_outlined,
                color: iconColor,
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
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: isRecycleRoot
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isRecycleRoot
                            ? (selected
                                  ? colorScheme.onErrorContainer
                                  : recycleAccent)
                            : isRecycledGroup
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (group.id != 'root' &&
                  !group.isRecycleBin &&
                  ((inRecycleBin &&
                          (onRestore != null || onPermanentDelete != null)) ||
                      (!inRecycleBin && onRename != null && onDelete != null)))
                GestureDetector(
                  onTapDown: (details) {
                    _showGroupContextMenu(
                      context,
                      details.globalPosition,
                      group,
                      inRecycleBin,
                      onRename,
                      onDelete,
                      onRestore,
                      onPermanentDelete,
                    );
                  },
                  child: Icon(
                    Icons.more_vert,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
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
    this.searchAllGroups = false,
    this.onSearchAllGroupsChanged,
    this.selectedEntryIds = const {},
    this.onToggleSelect,
    this.sortMode = 0,
    this.onSortModeChanged,
    this.onCreateEntry,
    this.onEmptyRecycleBin,
  });

  final GroupNode group;
  final List<EntrySummary> entries;
  final EntrySummary? selectedEntry;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<EntrySummary> onSelected;
  final bool searchAllGroups;
  final ValueChanged<bool>? onSearchAllGroupsChanged;
  final Set<String> selectedEntryIds;
  final void Function(String)? onToggleSelect;
  final int sortMode;
  final ValueChanged<int>? onSortModeChanged;
  final VoidCallback? onCreateEntry;
  final VoidCallback? onEmptyRecycleBin;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      searchAllGroups ? 'All entries' : group.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onCreateEntry != null)
                    IconButton(
                      tooltip: 'Create entry',
                      onPressed: onCreateEntry,
                      icon: const Icon(Icons.add),
                    ),
                  if (onEmptyRecycleBin != null)
                    IconButton(
                      tooltip: 'Empty recycle bin',
                      onPressed: onEmptyRecycleBin,
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                ],
              ),
              if (selectedEntryIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text(
                        '${selectedEntryIds.length} selected',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onToggleSelect != null
                            ? () {
                                for (final id in selectedEntryIds.toList()) {
                                  onToggleSelect!(id);
                                }
                              }
                            : null,
                        child: Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: onQueryChanged,
                      decoration: const InputDecoration(
                        hintText: 'Search entries',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  if (onSearchAllGroupsChanged != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => onSearchAllGroupsChanged!(!searchAllGroups),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          color: searchAllGroups
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1)
                              : null,
                        ),
                        child: Text(
                          'All',
                          style: TextStyle(
                            fontSize: 12,
                            color: searchAllGroups
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (onSortModeChanged != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Row(
              children: [
                const Text('Sort: ', style: TextStyle(fontSize: 12)),
                DropdownButton<int>(
                  value: sortMode,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: 0,
                      child: Text('Title', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text('Username', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: 2,
                      child: Text('Modified', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  onChanged: (v) => onSortModeChanged!(v ?? 0),
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
                      isChecked: selectedEntryIds.contains(entry.id),
                      onToggle: onToggleSelect != null
                          ? () => onToggleSelect!(entry.id)
                          : null,
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
    this.isChecked = false,
    this.onToggle,
  });

  final EntrySummary entry;
  final bool selected;
  final ValueChanged<EntrySummary> onSelected;
  final bool isChecked;
  final VoidCallback? onToggle;

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
              if (onToggle != null)
                GestureDetector(
                  onTap: onToggle,
                  child: Icon(
                    isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: isChecked
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              if (onToggle != null) const SizedBox(width: 8),
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
    this.onRestore,
    this.onPermanentDelete,
    this.inRecycleBin = false,
    this.onGeneratePassword,
    this.onDownloadAttachment,
    this.onAddAttachment,
    this.onRemoveAttachment,
    this.onAddCustomField,
    this.onRemoveCustomField,
    this.onToggleCustomFieldProtect,
    this.onToggleHistory,
    this.onViewHistoryDetail,
    this.onMoveEntry,
    this.onDuplicateEntry,
    this.editExpires = false,
    this.onEditExpiresChanged,
    this.editExpiryDateCtrl,
    this.showHistory = false,
    this.history,
    this.loadingHistory = false,
    this.selectedEntry,
    this.visibleCustomFields = const {},
    this.onToggleCustomFieldVisibility,
    this.onCopyToClipboard,
    this.clipboardClearSeconds = 30,
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
  final VoidCallback? onRestore;
  final VoidCallback? onPermanentDelete;
  final bool inRecycleBin;
  final void Function(void Function(String))? onGeneratePassword;
  final void Function(EntrySummary, String)? onDownloadAttachment;
  final void Function(EntrySummary)? onAddAttachment;
  final void Function(EntrySummary, String)? onRemoveAttachment;
  final void Function()? onAddCustomField;
  final void Function(String)? onRemoveCustomField;
  final void Function(String, String, bool)? onToggleCustomFieldProtect;
  final VoidCallback? onToggleHistory;
  final void Function(HistorySummary)? onViewHistoryDetail;
  final VoidCallback? onMoveEntry;
  final VoidCallback? onDuplicateEntry;
  final bool editExpires;
  final ValueChanged<bool>? onEditExpiresChanged;
  final TextEditingController? editExpiryDateCtrl;
  final bool showHistory;
  final List<HistorySummary>? history;
  final bool loadingHistory;
  final EntrySummary? selectedEntry;
  final Set<String> visibleCustomFields;
  final void Function(String)? onToggleCustomFieldVisibility;
  final void Function(String, String)? onCopyToClipboard;
  final int clipboardClearSeconds;

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
            if (inRecycleBin) ...[
              if (onRestore != null)
                IconButton(
                  tooltip: 'Restore entry',
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore_from_trash_outlined),
                ),
              if (onPermanentDelete != null)
                IconButton(
                  tooltip: 'Delete permanently',
                  onPressed: onPermanentDelete,
                  icon: Icon(Icons.delete_forever, color: colorScheme.error),
                ),
            ] else ...[
              if (onMoveEntry != null)
                IconButton(
                  tooltip: 'Move to group',
                  onPressed: onMoveEntry,
                  icon: const Icon(Icons.drive_file_move_outlined),
                ),
              if (onDuplicateEntry != null)
                IconButton(
                  tooltip: 'Duplicate entry',
                  onPressed: onDuplicateEntry,
                  icon: const Icon(Icons.copy),
                ),
              if (detail.password != null && detail.password!.isNotEmpty)
                IconButton(
                  tooltip: 'Copy password',
                  onPressed: () =>
                      onCopyToClipboard?.call(detail.password!, 'Password'),
                  icon: const Icon(Icons.key),
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
        FieldLine(
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
            _buildFieldRow(
              context: context,
              fieldKey: item.key,
              value: item.value,
              isProtected: detail.protectedFields.contains(item.key),
            ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Text(
              'Attachments',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (!inRecycleBin &&
                onAddAttachment != null &&
                selectedEntry != null)
              IconButton(
                tooltip: 'Add attachment',
                onPressed: () => onAddAttachment!(selectedEntry!),
                icon: const Icon(Icons.add, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (detail.attachments.isEmpty)
          Text(
            'No attachments',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final attachment in detail.attachments)
            FieldLine(
              icon: attachment.protected
                  ? Icons.enhanced_encryption_outlined
                  : Icons.attach_file_outlined,
              label: attachment.name,
              value: '${attachment.size} bytes',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onDownloadAttachment != null && selectedEntry != null)
                    IconButton(
                      tooltip: 'Download ${attachment.name}',
                      onPressed: () => onDownloadAttachment!(
                        selectedEntry!,
                        attachment.name,
                      ),
                      icon: const Icon(Icons.download, size: 18),
                    ),
                  if (!inRecycleBin &&
                      onRemoveAttachment != null &&
                      selectedEntry != null)
                    IconButton(
                      tooltip: 'Remove ${attachment.name}',
                      onPressed: () =>
                          onRemoveAttachment!(selectedEntry!, attachment.name),
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
        const SizedBox(height: 18),
        Row(
          children: [
            Text(
              'History',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (onToggleHistory != null)
              IconButton(
                tooltip: showHistory ? 'Close history' : 'Entry history',
                onPressed: onToggleHistory,
                icon: Icon(
                  showHistory ? Icons.history_toggle_off : Icons.history,
                ),
              ),
          ],
        ),
        if (showHistory) ...[
          const SizedBox(height: 8),
          if (loadingHistory)
            const Center(child: CircularProgressIndicator())
          else if (history == null || history!.isEmpty)
            Text(
              'No history entries',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            )
          else
            for (final item in history!)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text(
                  item.title ?? 'Untitled snapshot',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  item.lastModified ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onViewHistoryDetail != null
                    ? () => onViewHistoryDetail!(item)
                    : null,
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: passwordCtrl,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
            ),
            if (onGeneratePassword != null)
              IconButton(
                tooltip: 'Generate password',
                onPressed: () =>
                    onGeneratePassword!((pw) => passwordCtrl.text = pw),
                icon: const Icon(Icons.password_outlined),
              ),
          ],
        ),
        StatefulBuilder(
          builder: (ctx, setSt) {
            final s = _pwStrength(passwordCtrl.text);
            if (s == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: s,
                        color: _pwColor(s),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ['Weak', 'Fair', 'Good', 'Strong'][(s * 3.99).toInt()],
                    style: TextStyle(fontSize: 11, color: _pwColor(s)),
                  ),
                ],
              ),
            );
          },
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
        if (onEditExpiresChanged != null)
          CheckboxListTile(
            title: const Text('Entry expires'),
            value: editExpires,
            onChanged: (v) => onEditExpiresChanged!(v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        if (editExpires && editExpiryDateCtrl != null)
          TextField(
            controller: editExpiryDateCtrl,
            decoration: const InputDecoration(
              labelText: 'Expiry date (YYYY-MM-DD)',
            ),
          ),
        // Custom fields
        if (detail != null) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                'Custom fields',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (onAddCustomField != null)
                IconButton(
                  tooltip: 'Add custom field',
                  onPressed: onAddCustomField,
                  icon: const Icon(Icons.add, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (detail!.fields.isEmpty)
            Text(
              'No custom fields',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final entry in detail!.readonlyFields.entries)
              Row(
                children: [
                  if (onToggleCustomFieldProtect != null)
                    IconButton(
                      tooltip: detail!.protectedFields.contains(entry.key)
                          ? 'Protected — click to unprotect'
                          : 'Not protected — click to protect',
                      onPressed: () => onToggleCustomFieldProtect!(
                        entry.key,
                        entry.value,
                        detail!.protectedFields.contains(entry.key),
                      ),
                      icon: Icon(
                        detail!.protectedFields.contains(entry.key)
                            ? Icons.lock
                            : Icons.lock_open,
                        size: 18,
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: entry.value),
                      decoration: InputDecoration(labelText: entry.key),
                      enabled: false,
                    ),
                  ),
                  if (entry.value.isNotEmpty)
                    IconButton(
                      tooltip: 'Copy ${entry.key}',
                      onPressed: () =>
                          onCopyToClipboard?.call(entry.value, entry.key),
                      icon: const Icon(Icons.copy, size: 18),
                    ),
                  if (onRemoveCustomField != null)
                    IconButton(
                      tooltip: 'Remove ${entry.key}',
                      onPressed: () => onRemoveCustomField!(entry.key),
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: onCancelEdit,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onSaveEdit,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Save changes'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFieldRow({
    required BuildContext context,
    required String fieldKey,
    required String value,
    required bool isProtected,
  }) {
    if (isProtected) {
      final visible = visibleCustomFields.contains(fieldKey);
      return FieldLine(
        icon: Icons.lock,
        label: fieldKey,
        value: visible ? value : '••••••••••••',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value.isNotEmpty)
              IconButton(
                tooltip: 'Copy $fieldKey',
                onPressed: () => onCopyToClipboard?.call(value, fieldKey),
                icon: const Icon(Icons.copy, size: 18),
              ),
            IconButton(
              tooltip: visible ? 'Hide $fieldKey' : 'Show $fieldKey',
              onPressed: () => onToggleCustomFieldVisibility?.call(fieldKey),
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
    return FieldLine(
      icon: Icons.tune_outlined,
      label: fieldKey,
      value: value,
      trailing: value.isNotEmpty
          ? IconButton(
              tooltip: 'Copy $fieldKey',
              onPressed: () => onCopyToClipboard?.call(value, fieldKey),
              icon: const Icon(Icons.copy, size: 18),
            )
          : null,
    );
  }

  Widget _buildCopyField({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return FieldLine(
      icon: icon,
      label: label,
      value: value,
      trailing: value.isNotEmpty
          ? IconButton(
              tooltip: 'Copy $label',
              onPressed: () => onCopyToClipboard?.call(value, label),
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
    return FieldLine(
      icon: Icons.password_outlined,
      label: 'Password',
      value: visible ? value : '••••••••••••',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value.isNotEmpty)
            IconButton(
              tooltip: 'Copy password',
              onPressed: () => onCopyToClipboard?.call(value, 'Password'),
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
}

class _FieldEntry {
  _FieldEntry({
    required this.keyCtrl,
    required this.valueCtrl,
    required this.protect,
  });

  final TextEditingController keyCtrl;
  final TextEditingController valueCtrl;
  bool protect;
}
