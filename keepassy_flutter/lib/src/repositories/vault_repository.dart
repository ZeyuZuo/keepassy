import '../models/vault_models.dart';

abstract class VaultRepository {
  Future<OpenedVault> openLocal({
    required String path,
    required String masterPassword,
    String? keyfilePath,
  });

  Future<List<EntrySummary>> entriesForGroup(String groupId);

  Future<EntryDetail> entryDetail(String entryId);

  Future<void> close();
}

class MockVaultRepository implements VaultRepository {
  OpenedVault? _vault;
  final Map<String, EntryDetail> _details = {};

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
  Future<void> close() async {
    _vault = null;
    _details.clear();
  }

  OpenedVault _requireVault() {
    final vault = _vault;
    if (vault == null) {
      throw const VaultRepositoryException('No open vault session.');
    }
    return vault;
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
