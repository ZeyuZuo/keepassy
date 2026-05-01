import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/vault_models.dart';

class BackendInfo {
  const BackendInfo({
    required this.keepassCoreVersion,
    required this.keepassFfiVersion,
    required this.libraryPath,
  });

  final String keepassCoreVersion;
  final String keepassFfiVersion;
  final String libraryPath;
}

abstract class VaultRepository {
  Future<OpenedVault> openLocal({
    required String path,
    required String masterPassword,
    String? keyfilePath,
  });

  Future<OpenedVault> createLocal({
    required String path,
    required String masterPassword,
    String? keyfilePath,
  });

  Future<OpenedVault> openWebDav({
    required String url,
    required String masterPassword,
    String? username,
    String? webDavPassword,
    String? keyfilePath,
  });

  Future<List<EntrySummary>> entriesForGroup(String groupId);

  Future<EntryDetail> entryDetail(String entryId);

  Future<EntryDetail> createEntry(CreateEntryRequest request);

  Future<EntryDetail> updateEntry(UpdateEntryRequest request);

  Future<OpenedVault> deleteEntry(String entryId);

  Future<OpenedVault> restoreEntry(String entryId);

  Future<OpenedVault> permanentlyDeleteEntry(String entryId);

  Future<OpenedVault> emptyRecycleBin();

  Future<bool> isDirty();

  Future<void> save({required String masterPassword, String? keyfilePath});

  Future<void> close();

  // --- P3: custom fields ---

  Future<EntryDetail> setCustomField({
    required String entryId,
    required String key,
    required String value,
    required bool protect,
  });

  Future<EntryDetail> deleteCustomField({
    required String entryId,
    required String key,
  });

  // --- P3: attachments ---

  Future<Uint8List> attachmentBytes({
    required String entryId,
    required String name,
  });

  Future<AttachmentSummary> upsertAttachment({
    required String entryId,
    required String name,
    required Uint8List bytes,
    required bool protect,
  });

  Future<void> removeAttachment({
    required String entryId,
    required String name,
  });

  // --- P3: history ---

  Future<List<HistorySummary>> entryHistory(String entryId);

  Future<EntryDetail> entryHistoryDetail({
    required String entryId,
    required int index,
  });

  // --- groups ---
  Future<GroupNode> createGroup({
    required String parentId,
    required String name,
  });
  Future<GroupNode> renameGroup({
    required String groupId,
    required String name,
  });
  Future<OpenedVault> deleteGroup(String groupId);
  Future<OpenedVault> restoreGroup(String groupId);
  Future<OpenedVault> permanentlyDeleteGroup(String groupId);
  Future<EntryDetail> moveEntry(String entryId, String targetGroupId);
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    String? keyfilePath,
  });
}

class MockVaultRepository implements VaultRepository {
  OpenedVault? _vault;
  final Map<String, EntryDetail> _details = {};
  final Map<String, String> _recycledOriginalGroups = {};
  final Map<String, String> _recycledOriginalParentGroups = {};
  bool _dirty = false;

  @override
  Future<OpenedVault> openLocal({
    required String path,
    required String masterPassword,
    String? keyfilePath,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (path.trim().isEmpty) {
      throw const VaultRepositoryException('Vault file path is required.');
    }
    if (masterPassword.isEmpty &&
        (keyfilePath == null || keyfilePath.trim().isEmpty)) {
      throw const VaultRepositoryException(
        'Master password or keyfile is required.',
      );
    }

    final vault = _sampleVault(path);
    _vault = vault;
    _dirty = false;
    _details
      ..clear()
      ..addEntries(_sampleDetails.entries);
    _recycledOriginalGroups.clear();
    _recycledOriginalParentGroups.clear();
    return vault;
  }

  @override
  Future<OpenedVault> createLocal({
    required String path,
    required String masterPassword,
    String? keyfilePath,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (path.trim().isEmpty) {
      throw const VaultRepositoryException('File path is required.');
    }
    if (masterPassword.isEmpty &&
        (keyfilePath == null || keyfilePath.trim().isEmpty)) {
      throw const VaultRepositoryException(
        'Master password or keyfile is required.',
      );
    }
    final vault = _sampleVault(path.trim());
    _vault = vault;
    _dirty = false;
    _details
      ..clear()
      ..addEntries(_sampleDetails.entries);
    _recycledOriginalGroups.clear();
    _recycledOriginalParentGroups.clear();
    return vault;
  }

  @override
  Future<OpenedVault> openWebDav({
    required String url,
    required String masterPassword,
    String? username,
    String? webDavPassword,
    String? keyfilePath,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    validateWebDavUrl(url);
    if (masterPassword.isEmpty &&
        (keyfilePath == null || keyfilePath.trim().isEmpty)) {
      throw const VaultRepositoryException(
        'Master password or keyfile is required.',
      );
    }

    final vault = _sampleVault(url.trim()).copyWith(
      metadata: const RemoteMetadata(
        etag: '"mock-etag"',
        lastModified: 'Wed, 29 Apr 2026 00:00:00 GMT',
        contentLength: 4096,
      ),
    );
    _vault = vault;
    _dirty = false;
    _details
      ..clear()
      ..addEntries(_sampleDetails.entries);
    _recycledOriginalGroups.clear();
    _recycledOriginalParentGroups.clear();
    return vault;
  }

  @override
  Future<List<EntrySummary>> entriesForGroup(String groupId) async {
    final vault = _requireVault();
    final group = vault.groupTree.flatten().firstWhere(
      (group) => group.id == groupId,
      orElse: () => throw VaultRepositoryException('Group not found: $groupId'),
    );
    return group.entries;
  }

  @override
  Future<EntryDetail> entryDetail(String entryId) async {
    final detail = _details[entryId];
    if (detail == null) {
      throw VaultRepositoryException('Entry not found: $entryId');
    }
    return detail;
  }

  @override
  Future<EntryDetail> createEntry(CreateEntryRequest request) async {
    final vault = _requireVault();
    final id = 'entry-${Random().nextInt(99999)}';
    final detail = EntryDetail(
      id: id,
      title: request.title,
      username: request.username,
      password: request.password,
      url: request.url,
      notes: request.notes,
      fields: request.customFields,
    );
    _details[id] = detail;
    final summary = EntrySummary(
      id: id,
      title: request.title,
      username: request.username,
      url: request.url,
    );
    // Add to the target group (flattened search)
    final groups = vault.groupTree.flatten().toList();
    final target = groups.firstWhere(
      (g) => g.id == request.groupId,
      orElse: () =>
          throw const VaultRepositoryException('Target group not found.'),
    );
    target.entries.add(summary);
    _dirty = true;
    return detail;
  }

  @override
  Future<EntryDetail> updateEntry(UpdateEntryRequest request) async {
    final existing = _details[request.entryId];
    if (existing == null) {
      throw VaultRepositoryException('Entry not found: ${request.entryId}');
    }
    final updated = EntryDetail(
      id: existing.id,
      title: request.title ?? existing.title,
      username: request.username ?? existing.username,
      password: request.password ?? existing.password,
      url: request.url ?? existing.url,
      notes: request.notes ?? existing.notes,
      fields: existing.fields,
      attachments: existing.attachments,
    );
    _details[request.entryId] = updated;
    _replaceSummaryInTree(request.entryId, updated);
    _dirty = true;
    return updated;
  }

  @override
  Future<OpenedVault> deleteEntry(String entryId) async {
    final detail = _details[entryId];
    if (detail == null) {
      throw VaultRepositoryException('Entry not found: $entryId');
    }
    final vault = _requireVault();
    final source = vault.groupTree.flatten().firstWhere(
      (group) => group.entries.any((entry) => entry.id == entryId),
      orElse: () => throw VaultRepositoryException('Entry not found: $entryId'),
    );
    if (source.isRecycleBin) {
      return permanentlyDeleteEntry(entryId);
    }
    final idx = source.entries.indexWhere((entry) => entry.id == entryId);
    final summary = source.entries.removeAt(idx);
    final recycleBin = _ensureRecycleBin(vault);
    _recycledOriginalGroups[entryId] = source.id;
    recycleBin.entries.add(summary);
    _dirty = true;
    return vault;
  }

  @override
  Future<OpenedVault> restoreEntry(String entryId) async {
    final vault = _requireVault();
    final recycleBin = vault.groupTree.flatten().firstWhere(
      (group) => group.isRecycleBin,
      orElse: () => throw const VaultRepositoryException('Recycle bin missing'),
    );
    final idx = recycleBin.entries.indexWhere((entry) => entry.id == entryId);
    if (idx == -1) {
      throw VaultRepositoryException(
        'Entry not found in recycle bin: $entryId',
      );
    }
    final summary = recycleBin.entries.removeAt(idx);
    final originalGroupId = _recycledOriginalGroups.remove(entryId);
    final target = vault.groupTree.flatten().firstWhere(
      (group) => group.id == originalGroupId && !group.isRecycleBin,
      orElse: () => vault.groupTree,
    );
    target.entries.add(summary);
    _dirty = true;
    return vault;
  }

  @override
  Future<OpenedVault> permanentlyDeleteEntry(String entryId) async {
    final vault = _requireVault();
    var removed = false;
    for (final group in vault.groupTree.flatten()) {
      final before = group.entries.length;
      group.entries.removeWhere((entry) => entry.id == entryId);
      removed = removed || group.entries.length != before;
    }
    if (!removed && !_details.containsKey(entryId)) {
      throw VaultRepositoryException('Entry not found: $entryId');
    }
    _details.remove(entryId);
    _recycledOriginalGroups.remove(entryId);
    _dirty = true;
    return vault;
  }

  @override
  Future<OpenedVault> emptyRecycleBin() async {
    final vault = _requireVault();
    final recycleBin = vault.groupTree.flatten().where((g) => g.isRecycleBin);
    for (final group in recycleBin) {
      for (final entry in group.entries) {
        _details.remove(entry.id);
        _recycledOriginalGroups.remove(entry.id);
      }
      for (final recycledGroup in group.groups) {
        for (final nested in recycledGroup.flatten()) {
          _recycledOriginalParentGroups.remove(nested.id);
          for (final entry in nested.entries) {
            _details.remove(entry.id);
            _recycledOriginalGroups.remove(entry.id);
          }
        }
      }
      group.entries.clear();
      group.groups.clear();
    }
    _dirty = true;
    return vault;
  }

  @override
  Future<bool> isDirty() async => _dirty;

  @override
  Future<void> save({
    required String masterPassword,
    String? keyfilePath,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _dirty = false;
  }

  // --- P3: custom fields ---

  @override
  Future<EntryDetail> setCustomField({
    required String entryId,
    required String key,
    required String value,
    required bool protect,
  }) async {
    final existing = _details[entryId];
    if (existing == null) {
      throw VaultRepositoryException('Entry not found: $entryId');
    }
    final newFields = Map<String, String>.from(existing.fields);
    newFields[key] = value;
    final updated = EntryDetail(
      id: existing.id,
      title: existing.title,
      username: existing.username,
      password: existing.password,
      url: existing.url,
      notes: existing.notes,
      fields: newFields,
      attachments: existing.attachments,
    );
    _details[entryId] = updated;
    _dirty = true;
    return updated;
  }

  @override
  Future<EntryDetail> deleteCustomField({
    required String entryId,
    required String key,
  }) async {
    final existing = _details[entryId];
    if (existing == null) {
      throw VaultRepositoryException('Entry not found: $entryId');
    }
    final newFields = Map<String, String>.from(existing.fields);
    newFields.remove(key);
    final updated = EntryDetail(
      id: existing.id,
      title: existing.title,
      username: existing.username,
      password: existing.password,
      url: existing.url,
      notes: existing.notes,
      fields: newFields,
      attachments: existing.attachments,
    );
    _details[entryId] = updated;
    _dirty = true;
    return updated;
  }

  // --- P3: attachments ---

  @override
  Future<Uint8List> attachmentBytes({
    required String entryId,
    required String name,
  }) async {
    return Uint8List.fromList(utf8.encode('mock attachment content for $name'));
  }

  @override
  Future<AttachmentSummary> upsertAttachment({
    required String entryId,
    required String name,
    required Uint8List bytes,
    required bool protect,
  }) async {
    final existing = _details[entryId];
    if (existing == null) {
      throw VaultRepositoryException('Entry not found: $entryId');
    }
    final summary = AttachmentSummary(
      name: name,
      size: bytes.length,
      protected: protect,
    );
    final newAttachments = List<AttachmentSummary>.from(existing.attachments);
    final idx = newAttachments.indexWhere((a) => a.name == name);
    if (idx != -1) {
      newAttachments[idx] = summary;
    } else {
      newAttachments.add(summary);
    }
    final updated = EntryDetail(
      id: existing.id,
      title: existing.title,
      username: existing.username,
      password: existing.password,
      url: existing.url,
      notes: existing.notes,
      fields: existing.fields,
      attachments: newAttachments,
    );
    _details[entryId] = updated;
    _dirty = true;
    return summary;
  }

  @override
  Future<void> removeAttachment({
    required String entryId,
    required String name,
  }) async {
    final existing = _details[entryId];
    if (existing == null) {
      throw VaultRepositoryException('Entry not found: $entryId');
    }
    final newAttachments = existing.attachments
        .where((a) => a.name != name)
        .toList();
    final updated = EntryDetail(
      id: existing.id,
      title: existing.title,
      username: existing.username,
      password: existing.password,
      url: existing.url,
      notes: existing.notes,
      fields: existing.fields,
      attachments: newAttachments,
    );
    _details[entryId] = updated;
    _dirty = true;
  }

  // --- P3: history ---

  @override
  Future<List<HistorySummary>> entryHistory(String entryId) async {
    return const [
      HistorySummary(
        index: 0,
        title: 'Mock historical snapshot',
        username: 'mock-user',
        lastModified: '2026-04-28T12:00:00Z',
      ),
    ];
  }

  @override
  Future<EntryDetail> entryHistoryDetail({
    required String entryId,
    required int index,
  }) async {
    return _details[entryId] ??
        (throw VaultRepositoryException('Entry not found: $entryId'));
  }

  // --- groups ---
  @override
  Future<GroupNode> createGroup({
    required String parentId,
    required String name,
  }) async {
    final vault = _requireVault();
    final parent = vault.groupTree.flatten().firstWhere(
      (g) => g.id == parentId,
      orElse: () => throw VaultRepositoryException('Parent group not found'),
    );
    final id = 'group-${Random().nextInt(99999)}';
    final group = GroupNode(id: id, name: name, entries: [], groups: []);
    parent.groups.add(group);
    _dirty = true;
    return group;
  }

  @override
  Future<GroupNode> renameGroup({
    required String groupId,
    required String name,
  }) async {
    final vault = _requireVault();
    for (final g in vault.groupTree.flatten()) {
      if (g.id == groupId) {
        _dirty = true;
        return GroupNode(
          id: g.id,
          name: name,
          isRecycleBin: g.isRecycleBin,
          entries: g.entries,
          groups: g.groups,
        );
      }
    }
    throw VaultRepositoryException('Group not found: $groupId');
  }

  @override
  Future<OpenedVault> deleteGroup(String groupId) async {
    final vault = _requireVault();
    for (final g in vault.groupTree.flatten()) {
      final idx = g.groups.indexWhere((c) => c.id == groupId);
      if (idx != -1) {
        final group = g.groups.removeAt(idx);
        final recycleBin = _ensureRecycleBin(vault);
        _recycledOriginalParentGroups[groupId] = g.id;
        recycleBin.groups.add(group);
        _dirty = true;
        return vault;
      }
    }
    throw VaultRepositoryException('Cannot delete root group');
  }

  @override
  Future<OpenedVault> restoreGroup(String groupId) async {
    final vault = _requireVault();
    final recycleBin = vault.groupTree.flatten().firstWhere(
      (group) => group.isRecycleBin,
      orElse: () => throw const VaultRepositoryException('Recycle bin missing'),
    );
    final idx = recycleBin.groups.indexWhere((group) => group.id == groupId);
    if (idx == -1) {
      throw VaultRepositoryException(
        'Group not found in recycle bin: $groupId',
      );
    }
    final group = recycleBin.groups.removeAt(idx);
    final originalParentId = _recycledOriginalParentGroups.remove(groupId);
    final target = vault.groupTree.flatten().firstWhere(
      (candidate) =>
          candidate.id == originalParentId && !candidate.isRecycleBin,
      orElse: () => vault.groupTree,
    );
    target.groups.add(group);
    _dirty = true;
    return vault;
  }

  @override
  Future<OpenedVault> permanentlyDeleteGroup(String groupId) async {
    final vault = _requireVault();
    for (final g in vault.groupTree.flatten()) {
      final idx = g.groups.indexWhere((c) => c.id == groupId);
      if (idx != -1) {
        final removed = g.groups.removeAt(idx);
        for (final nested in removed.flatten()) {
          _recycledOriginalParentGroups.remove(nested.id);
          for (final entry in nested.entries) {
            _details.remove(entry.id);
            _recycledOriginalGroups.remove(entry.id);
          }
        }
        _dirty = true;
        return vault;
      }
    }
    throw VaultRepositoryException('Group not found: $groupId');
  }

  @override
  Future<EntryDetail> moveEntry(String entryId, String targetGroupId) async {
    final detail = _details[entryId];
    if (detail == null) {
      throw VaultRepositoryException('Entry not found: $entryId');
    }
    final vault = _requireVault();
    bool moved = false;
    for (final g in vault.groupTree.flatten()) {
      g.entries.removeWhere((e) {
        if (e.id == entryId) {
          moved = true;
          return true;
        }
        return false;
      });
    }
    final target = vault.groupTree.flatten().firstWhere(
      (g) => g.id == targetGroupId,
      orElse: () => throw VaultRepositoryException('Target group not found'),
    );
    target.entries.add(
      EntrySummary(
        id: detail.id,
        title: detail.title,
        username: detail.username,
        url: detail.url,
      ),
    );
    if (!moved) throw VaultRepositoryException('Entry not found in any group');
    _dirty = true;
    return detail;
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    String? keyfilePath,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<void> close() async {
    _vault = null;
    _details.clear();
    _recycledOriginalGroups.clear();
    _recycledOriginalParentGroups.clear();
    _dirty = false;
  }

  OpenedVault _requireVault() {
    final vault = _vault;
    if (vault == null) {
      throw const VaultRepositoryException('No open vault session.');
    }
    return vault;
  }

  void _replaceSummaryInTree(String entryId, EntryDetail detail) {
    final vault = _vault;
    if (vault == null) return;
    for (final group in vault.groupTree.flatten()) {
      final idx = group.entries.indexWhere((e) => e.id == entryId);
      if (idx != -1) {
        group.entries[idx] = EntrySummary(
          id: entryId,
          title: detail.title,
          username: detail.username,
          url: detail.url,
        );
        return;
      }
    }
  }

  GroupNode _ensureRecycleBin(OpenedVault vault) {
    final existing = vault.groupTree.flatten().where((g) => g.isRecycleBin);
    if (existing.isNotEmpty) {
      return existing.first;
    }
    final recycleBin = GroupNode(
      id: 'group-recycle-bin',
      name: 'Recycle Bin',
      isRecycleBin: true,
      entries: [],
      groups: [],
    );
    vault.groupTree.groups.add(recycleBin);
    return recycleBin;
  }
}

class VaultRepositoryException implements Exception {
  const VaultRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

void validateWebDavUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    throw const VaultRepositoryException('WebDAV URL is required.');
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw const VaultRepositoryException(
      'WebDAV URL must start with http:// or https://.',
    );
  }
}

OpenedVault _sampleVault(String source) {
  return OpenedVault(
    source: source,
    groupTree: GroupNode(
      id: 'root',
      name: 'Database',
      entries: [
        EntrySummary(
          id: 'entry-github',
          title: 'GitHub',
          username: 'zzy',
          url: 'https://github.com',
        ),
        EntrySummary(
          id: 'entry-router',
          title: 'Home router',
          username: 'admin',
          url: 'http://192.168.1.1',
        ),
      ],
      groups: [
        GroupNode(
          id: 'group-work',
          name: 'Work',
          entries: [
            EntrySummary(
              id: 'entry-cloudflare',
              title: 'Cloudflare',
              username: 'ops@keepassy.local',
              url: 'https://dash.cloudflare.com',
            ),
            EntrySummary(
              id: 'entry-webdav',
              title: 'WebDAV vault',
              username: 'vault-sync',
              url: 'https://example.com/remote.php/dav',
            ),
          ],
          groups: [],
        ),
        GroupNode(
          id: 'group-personal',
          name: 'Personal',
          entries: [
            EntrySummary(
              id: 'entry-email',
              title: 'Personal mail',
              username: 'me@example.com',
              url: 'https://mail.example.com',
            ),
          ],
          groups: [],
        ),
      ],
    ),
  );
}

final _sampleDetails = <String, EntryDetail>{
  'entry-github': EntryDetail(
    id: 'entry-github',
    title: 'GitHub',
    username: 'zzy',
    password: 'mock-password-not-persisted',
    url: 'https://github.com',
    notes: 'Use hardware key for second factor.',
    fields: {'RecoveryEmail': 'me@example.com'},
  ),
  'entry-router': EntryDetail(
    id: 'entry-router',
    title: 'Home router',
    username: 'admin',
    password: 'mock-password-not-persisted',
    url: 'http://192.168.1.1',
    notes: 'Local network only.',
  ),
  'entry-cloudflare': EntryDetail(
    id: 'entry-cloudflare',
    title: 'Cloudflare',
    username: 'ops@keepassy.local',
    password: 'mock-password-not-persisted',
    url: 'https://dash.cloudflare.com',
    notes: 'API tokens are stored as custom fields.',
    fields: {'AccountId': '9f11...', 'TokenScope': 'Workers deploy'},
    attachments: [
      AttachmentSummary(
        name: 'recovery-codes.txt',
        size: 2048,
        protected: true,
      ),
    ],
  ),
  'entry-webdav': EntryDetail(
    id: 'entry-webdav',
    title: 'WebDAV vault',
    username: 'vault-sync',
    password: 'mock-password-not-persisted',
    url: 'https://example.com/remote.php/dav',
    notes: 'Remote database source planned for the Rust backend.',
  ),
  'entry-email': EntryDetail(
    id: 'entry-email',
    title: 'Personal mail',
    username: 'me@example.com',
    password: 'mock-password-not-persisted',
    url: 'https://mail.example.com',
    notes: 'Recovery phone belongs in the provider profile, not notes.',
  ),
};
