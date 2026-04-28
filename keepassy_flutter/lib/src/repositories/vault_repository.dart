import 'dart:math';

import '../models/vault_models.dart';

abstract class VaultRepository {
  Future<OpenedVault> openLocal({
    required String path,
    required String masterPassword,
    String? keyfilePath,
  });

  Future<List<EntrySummary>> entriesForGroup(String groupId);

  Future<EntryDetail> entryDetail(String entryId);

  Future<EntryDetail> createEntry(CreateEntryRequest request);

  Future<EntryDetail> updateEntry(UpdateEntryRequest request);

  Future<void> deleteEntry(String entryId);

  Future<bool> isDirty();

  Future<void> save({required String masterPassword, String? keyfilePath});

  Future<void> close();
}

class MockVaultRepository implements VaultRepository {
  OpenedVault? _vault;
  final Map<String, EntryDetail> _details = {};
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
    if (masterPassword.isEmpty) {
      throw const VaultRepositoryException('Master password is required.');
    }

    final vault = _sampleVault(path);
    _vault = vault;
    _dirty = false;
    _details
      ..clear()
      ..addEntries(_sampleDetails.entries);
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
  Future<void> deleteEntry(String entryId) async {
    if (!_details.containsKey(entryId)) {
      throw VaultRepositoryException('Entry not found: $entryId');
    }
    _details.remove(entryId);
    final vault = _requireVault();
    for (final group in vault.groupTree.flatten()) {
      group.entries.removeWhere((e) => e.id == entryId);
    }
    _dirty = true;
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

  @override
  Future<void> close() async {
    _vault = null;
    _details.clear();
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
}

class VaultRepositoryException implements Exception {
  const VaultRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

OpenedVault _sampleVault(String source) {
  return OpenedVault(
    source: source,
    groupTree: const GroupNode(
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

const _sampleDetails = <String, EntryDetail>{
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
