import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../models/vault_models.dart';
import 'vault_repository.dart';

final class _KeepassYFfiResult extends Struct {
  @Int32()
  external int status;

  external Pointer<Void> session;

  external Pointer<Utf8> json;
}

typedef _OpenLocalNative =
    _KeepassYFfiResult Function(
      Pointer<Utf8> path,
      Pointer<Utf8> masterPassword,
      Pointer<Utf8> keyfilePath,
    );
typedef _OpenLocalDart =
    _KeepassYFfiResult Function(
      Pointer<Utf8> path,
      Pointer<Utf8> masterPassword,
      Pointer<Utf8> keyfilePath,
    );

typedef _CreateLocalNative =
    _KeepassYFfiResult Function(
      Pointer<Utf8> requestJson,
      Pointer<Utf8> masterPassword,
    );
typedef _CreateLocalDart =
    _KeepassYFfiResult Function(
      Pointer<Utf8> requestJson,
      Pointer<Utf8> masterPassword,
    );

typedef _OpenWebDavNative =
    _KeepassYFfiResult Function(
      Pointer<Utf8> requestJson,
      Pointer<Utf8> masterPassword,
    );
typedef _OpenWebDavDart =
    _KeepassYFfiResult Function(
      Pointer<Utf8> requestJson,
      Pointer<Utf8> masterPassword,
    );

typedef _SessionCloseNative = Void Function(Pointer<Void> session);
typedef _SessionCloseDart = void Function(Pointer<Void> session);

typedef _StringFreeNative = Void Function(Pointer<Utf8> value);
typedef _StringFreeDart = void Function(Pointer<Utf8> value);

typedef _JsonWithIdNative =
    _KeepassYFfiResult Function(Pointer<Void> session, Pointer<Utf8> id);
typedef _JsonWithIdDart =
    _KeepassYFfiResult Function(Pointer<Void> session, Pointer<Utf8> id);

typedef _JsonWithRequestNative =
    _KeepassYFfiResult Function(
      Pointer<Void> session,
      Pointer<Utf8> requestJson,
    );
typedef _JsonWithRequestDart =
    _KeepassYFfiResult Function(
      Pointer<Void> session,
      Pointer<Utf8> requestJson,
    );

typedef _ChangePasswordNative =
    _KeepassYFfiResult Function(
      Pointer<Void> session,
      Pointer<Utf8> oldPassword,
      Pointer<Utf8> newPassword,
      Pointer<Utf8> keyfilePath,
    );
typedef _ChangePasswordDart =
    _KeepassYFfiResult Function(
      Pointer<Void> session,
      Pointer<Utf8> oldPassword,
      Pointer<Utf8> newPassword,
      Pointer<Utf8> keyfilePath,
    );

typedef _SaveNative =
    _KeepassYFfiResult Function(
      Pointer<Void> session,
      Pointer<Utf8> masterPassword,
      Pointer<Utf8> keyfilePath,
    );
typedef _SaveDart =
    _KeepassYFfiResult Function(
      Pointer<Void> session,
      Pointer<Utf8> masterPassword,
      Pointer<Utf8> keyfilePath,
    );

typedef _JsonWithTwoIdsNative =
    _KeepassYFfiResult Function(
      Pointer<Void> session,
      Pointer<Utf8> arg1,
      Pointer<Utf8> arg2,
    );
typedef _JsonWithTwoIdsDart =
    _KeepassYFfiResult Function(
      Pointer<Void> session,
      Pointer<Utf8> arg1,
      Pointer<Utf8> arg2,
    );

typedef _JsonWithIdAndIntNative =
    _KeepassYFfiResult Function(
      Pointer<Void> session,
      Pointer<Utf8> id,
      Int32 index,
    );
typedef _JsonWithIdAndIntDart =
    _KeepassYFfiResult Function(
      Pointer<Void> session,
      Pointer<Utf8> id,
      int index,
    );

typedef _IsDirtyNative = _KeepassYFfiResult Function(Pointer<Void> session);
typedef _IsDirtyDart = _KeepassYFfiResult Function(Pointer<Void> session);

typedef _NoArgNative = _KeepassYFfiResult Function();
typedef _NoArgDart = _KeepassYFfiResult Function();

class _LoadedLibrary {
  const _LoadedLibrary(this.library, this.path);

  final DynamicLibrary library;
  final String path;
}

_LoadedLibrary _loadLibraryWithPath() {
  final envLib = Platform.environment['KEEPASSY_FFI_LIB'];
  if (envLib != null && envLib.isNotEmpty) {
    return _LoadedLibrary(DynamicLibrary.open(envLib), envLib);
  }

  final libName = _platformLibraryName();
  final searched = <String>[];

  final executableDir = File(Platform.resolvedExecutable).parent.path;
  final directCandidates = [
    '$executableDir/lib/$libName',
    '$executableDir/$libName',
    '${Directory.current.path}/lib/$libName',
    '${Directory.current.path}/$libName',
  ];

  for (final candidate in directCandidates) {
    searched.add(candidate);
    if (File(candidate).existsSync()) {
      return _LoadedLibrary(DynamicLibrary.open(candidate), candidate);
    }
  }

  try {
    return _LoadedLibrary(DynamicLibrary.open(libName), libName);
  } catch (_) {
    searched.add(libName);
  }

  final cwd = Directory.current.path;
  for (final dir in [cwd, '$cwd/..']) {
    for (final profile in ['release', 'debug']) {
      final candidate = '$dir/keepass-rs/target/$profile/$libName';
      searched.add(candidate);
      if (File(candidate).existsSync()) {
        return _LoadedLibrary(DynamicLibrary.open(candidate), candidate);
      }
    }
  }

  throw VaultRepositoryException(
    'Cannot load keepass_ffi shared library. '
    'Build it first: cd keepass-rs && cargo build -p keepass_ffi --release\n'
    'Or set KEEPASSY_FFI_LIB to the full shared-library path.\n'
    'Searched: ${searched.join(', ')}',
  );
}

String _platformLibraryName() {
  if (Platform.isMacOS) return 'libkeepass_ffi.dylib';
  if (Platform.isWindows) return 'keepass_ffi.dll';
  return 'libkeepass_ffi.so';
}

class FfiVaultRepository implements VaultRepository {
  FfiVaultRepository({DynamicLibrary? library})
    : this._(
        library == null
            ? _loadLibraryWithPath()
            : _LoadedLibrary(library, 'injected'),
      );

  FfiVaultRepository._(this._loadedLibrary) : _lib = _loadedLibrary.library {
    _backendVersionJson = _lib.lookupFunction<_NoArgNative, _NoArgDart>(
      'keepassy_backend_version_json',
    );
    _openLocal = _lib.lookupFunction<_OpenLocalNative, _OpenLocalDart>(
      'keepassy_open_local',
    );
    _createLocal = _lib.lookupFunction<_CreateLocalNative, _CreateLocalDart>(
      'keepassy_create_local',
    );
    _openWebDav = _lib.lookupFunction<_OpenWebDavNative, _OpenWebDavDart>(
      'keepassy_open_webdav',
    );
    _sessionClose = _lib.lookupFunction<_SessionCloseNative, _SessionCloseDart>(
      'keepassy_session_close',
    );
    _stringFree = _lib.lookupFunction<_StringFreeNative, _StringFreeDart>(
      'keepassy_string_free',
    );
    _entriesJson = _lib.lookupFunction<_JsonWithIdNative, _JsonWithIdDart>(
      'keepassy_entries_json',
    );
    _entryDetailJson = _lib.lookupFunction<_JsonWithIdNative, _JsonWithIdDart>(
      'keepassy_entry_detail_json',
    );
    _createEntryJson = _lib
        .lookupFunction<_JsonWithRequestNative, _JsonWithRequestDart>(
          'keepassy_create_entry_json',
        );
    _updateEntryJson = _lib
        .lookupFunction<_JsonWithRequestNative, _JsonWithRequestDart>(
          'keepassy_update_entry_json',
        );
    _deleteEntryJson = _lib.lookupFunction<_JsonWithIdNative, _JsonWithIdDart>(
      'keepassy_delete_entry_json',
    );
    _restoreEntryJson = _lib.lookupFunction<_JsonWithIdNative, _JsonWithIdDart>(
      'keepassy_restore_entry_json',
    );
    _permanentlyDeleteEntryJson = _lib
        .lookupFunction<_JsonWithIdNative, _JsonWithIdDart>(
          'keepassy_permanently_delete_entry_json',
        );
    _emptyRecycleBinJson = _lib.lookupFunction<_IsDirtyNative, _IsDirtyDart>(
      'keepassy_empty_recycle_bin_json',
    );
    _isDirty = _lib.lookupFunction<_IsDirtyNative, _IsDirtyDart>(
      'keepassy_is_dirty',
    );
    _save = _lib.lookupFunction<_SaveNative, _SaveDart>('keepassy_save');
    _changePassword = _lib
        .lookupFunction<_ChangePasswordNative, _ChangePasswordDart>(
          'keepassy_change_password_json',
        );
    _setCustomFieldJson = _lib
        .lookupFunction<_JsonWithRequestNative, _JsonWithRequestDart>(
          'keepassy_set_custom_field_json',
        );
    _deleteCustomFieldJson = _lib
        .lookupFunction<_JsonWithTwoIdsNative, _JsonWithTwoIdsDart>(
          'keepassy_delete_custom_field_json',
        );
    _upsertAttachmentJson = _lib
        .lookupFunction<_JsonWithRequestNative, _JsonWithRequestDart>(
          'keepassy_upsert_attachment_json',
        );
    _removeAttachmentJson = _lib
        .lookupFunction<_JsonWithTwoIdsNative, _JsonWithTwoIdsDart>(
          'keepassy_remove_attachment_json',
        );
    _attachmentBytesJson = _lib
        .lookupFunction<_JsonWithTwoIdsNative, _JsonWithTwoIdsDart>(
          'keepassy_attachment_bytes_json',
        );
    _entryHistoryJson = _lib.lookupFunction<_JsonWithIdNative, _JsonWithIdDart>(
      'keepassy_entry_history_json',
    );
    _entryHistoryDetailJson = _lib
        .lookupFunction<_JsonWithIdAndIntNative, _JsonWithIdAndIntDart>(
          'keepassy_entry_history_detail_json',
        );
    _moveEntryJson = _lib
        .lookupFunction<_JsonWithRequestNative, _JsonWithRequestDart>(
          'keepassy_move_entry_json',
        );
    _createGroupJson = _lib
        .lookupFunction<_JsonWithRequestNative, _JsonWithRequestDart>(
          'keepassy_create_group_json',
        );
    _renameGroupJson = _lib
        .lookupFunction<_JsonWithRequestNative, _JsonWithRequestDart>(
          'keepassy_rename_group_json',
        );
    _deleteGroupJson = _lib.lookupFunction<_JsonWithIdNative, _JsonWithIdDart>(
      'keepassy_delete_group_json',
    );
    _restoreGroupJson = _lib.lookupFunction<_JsonWithIdNative, _JsonWithIdDart>(
      'keepassy_restore_group_json',
    );
    _permanentlyDeleteGroupJson = _lib
        .lookupFunction<_JsonWithIdNative, _JsonWithIdDart>(
          'keepassy_permanently_delete_group_json',
        );
  }

  final _LoadedLibrary _loadedLibrary;
  final DynamicLibrary _lib;
  Pointer<Void>? _session;

  late final _NoArgDart _backendVersionJson;
  late final _OpenLocalDart _openLocal;
  late final _CreateLocalDart _createLocal;
  late final _OpenWebDavDart _openWebDav;
  late final _SessionCloseDart _sessionClose;
  late final _StringFreeDart _stringFree;
  late final _JsonWithIdDart _entriesJson;
  late final _JsonWithIdDart _entryDetailJson;
  late final _JsonWithRequestDart _createEntryJson;
  late final _JsonWithRequestDart _updateEntryJson;
  late final _JsonWithIdDart _deleteEntryJson;
  late final _JsonWithIdDart _restoreEntryJson;
  late final _JsonWithIdDart _permanentlyDeleteEntryJson;
  late final _IsDirtyDart _emptyRecycleBinJson;
  late final _IsDirtyDart _isDirty;
  late final _SaveDart _save;
  late final _ChangePasswordDart _changePassword;
  late final _JsonWithRequestDart _setCustomFieldJson;
  late final _JsonWithTwoIdsDart _deleteCustomFieldJson;
  late final _JsonWithRequestDart _upsertAttachmentJson;
  late final _JsonWithTwoIdsDart _removeAttachmentJson;
  late final _JsonWithTwoIdsDart _attachmentBytesJson;
  late final _JsonWithIdDart _entryHistoryJson;
  late final _JsonWithIdAndIntDart _entryHistoryDetailJson;
  late final _JsonWithRequestDart _moveEntryJson;
  late final _JsonWithRequestDart _createGroupJson;
  late final _JsonWithRequestDart _renameGroupJson;
  late final _JsonWithIdDart _deleteGroupJson;
  late final _JsonWithIdDart _restoreGroupJson;
  late final _JsonWithIdDart _permanentlyDeleteGroupJson;

  BackendInfo backendInfo() {
    final json = _readJsonObject(_backendVersionJson());
    return BackendInfo(
      keepassCoreVersion: json['keepass_core'] as String? ?? 'unknown',
      keepassFfiVersion: json['keepass_ffi'] as String? ?? 'unknown',
      libraryPath: _loadedLibrary.path,
    );
  }

  @override
  Future<OpenedVault> openLocal({
    required String path,
    required String masterPassword,
    String? keyfilePath,
  }) async {
    if (path.trim().isEmpty) {
      throw const VaultRepositoryException('Vault file path is required.');
    }
    if (masterPassword.isEmpty &&
        (keyfilePath == null || keyfilePath.trim().isEmpty)) {
      throw const VaultRepositoryException(
        'Master password or keyfile is required.',
      );
    }

    final pathPtr = path.toNativeUtf8();
    final passwordPtr = masterPassword.toNativeUtf8();
    final keyfilePtr = (keyfilePath != null && keyfilePath.trim().isNotEmpty)
        ? keyfilePath.toNativeUtf8()
        : nullptr;

    try {
      final result = _openLocal(pathPtr, passwordPtr, keyfilePtr);
      final json = _readJsonObject(result);
      if (result.session != nullptr) {
        _session = result.session;
      }
      return OpenedVault.fromJson(json);
    } finally {
      calloc.free(pathPtr);
      calloc.free(passwordPtr);
      if (keyfilePtr != nullptr) {
        calloc.free(keyfilePtr);
      }
    }
  }

  @override
  Future<OpenedVault> createLocal({
    required String path,
    required String masterPassword,
    String? keyfilePath,
  }) async {
    if (path.trim().isEmpty) {
      throw const VaultRepositoryException('File path is required.');
    }
    if (masterPassword.isEmpty &&
        (keyfilePath == null || keyfilePath.trim().isEmpty)) {
      throw const VaultRepositoryException(
        'Master password or keyfile is required.',
      );
    }

    final request = <String, Object?>{
      'path': path.trim(),
      if (keyfilePath != null && keyfilePath.trim().isNotEmpty)
        'keyfile_path': keyfilePath.trim(),
    };
    final requestPtr = jsonEncode(request).toNativeUtf8();
    final passwordPtr = masterPassword.toNativeUtf8();

    try {
      final result = _createLocal(requestPtr, passwordPtr);
      final json = _readJsonObject(result);
      if (result.session != nullptr) {
        _session = result.session;
      }
      return OpenedVault.fromJson(json);
    } finally {
      calloc.free(requestPtr);
      calloc.free(passwordPtr);
    }
  }

  @override
  Future<OpenedVault> openWebDav({
    required String url,
    required String masterPassword,
    String? username,
    String? webDavPassword,
    String? keyfilePath,
  }) async {
    validateWebDavUrl(url);
    if (masterPassword.isEmpty &&
        (keyfilePath == null || keyfilePath.trim().isEmpty)) {
      throw const VaultRepositoryException(
        'Master password or keyfile is required.',
      );
    }

    final request = <String, Object?>{
      'url': url.trim(),
      if (username != null && username.trim().isNotEmpty)
        'username': username.trim(),
      if (webDavPassword != null && webDavPassword.isNotEmpty)
        'password': webDavPassword,
      if (keyfilePath != null && keyfilePath.trim().isNotEmpty)
        'keyfile_path': keyfilePath.trim(),
    };
    final requestPtr = jsonEncode(request).toNativeUtf8();
    final passwordPtr = masterPassword.toNativeUtf8();

    try {
      final result = _openWebDav(requestPtr, passwordPtr);
      final json = _readJsonObject(result);
      if (result.session != nullptr) {
        _session = result.session;
      }
      return OpenedVault.fromJson(json);
    } finally {
      calloc.free(requestPtr);
      calloc.free(passwordPtr);
    }
  }

  @override
  Future<List<EntrySummary>> entriesForGroup(String groupId) async {
    final session = _requireSession();
    final idPtr = groupId.toNativeUtf8();
    try {
      final result = _entriesJson(session, idPtr);
      final json = _readResult(result);
      return (json as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(EntrySummary.fromJson)
          .toList(growable: false);
    } finally {
      calloc.free(idPtr);
    }
  }

  @override
  Future<EntryDetail> entryDetail(String entryId) async {
    final session = _requireSession();
    final idPtr = entryId.toNativeUtf8();
    try {
      final result = _entryDetailJson(session, idPtr);
      final json = _readJsonObject(result);
      return EntryDetail.fromJson(json);
    } finally {
      calloc.free(idPtr);
    }
  }

  @override
  Future<EntryDetail> createEntry(CreateEntryRequest request) async {
    final session = _requireSession();
    final jsonPtr = jsonEncode(request.toJson()).toNativeUtf8();
    try {
      final result = _createEntryJson(session, jsonPtr);
      final json = _readJsonObject(result);
      return EntryDetail.fromJson(json);
    } finally {
      calloc.free(jsonPtr);
    }
  }

  @override
  Future<EntryDetail> updateEntry(UpdateEntryRequest request) async {
    final session = _requireSession();
    final jsonPtr = jsonEncode(request.toJson()).toNativeUtf8();
    try {
      final result = _updateEntryJson(session, jsonPtr);
      final json = _readJsonObject(result);
      return EntryDetail.fromJson(json);
    } finally {
      calloc.free(jsonPtr);
    }
  }

  @override
  Future<OpenedVault> deleteEntry(String entryId) async {
    final session = _requireSession();
    final idPtr = entryId.toNativeUtf8();
    try {
      final result = _deleteEntryJson(session, idPtr);
      final json = _readJsonObject(result);
      return OpenedVault.fromJson(json);
    } finally {
      calloc.free(idPtr);
    }
  }

  @override
  Future<OpenedVault> restoreEntry(String entryId) async {
    final session = _requireSession();
    final idPtr = entryId.toNativeUtf8();
    try {
      final result = _restoreEntryJson(session, idPtr);
      final json = _readJsonObject(result);
      return OpenedVault.fromJson(json);
    } finally {
      calloc.free(idPtr);
    }
  }

  @override
  Future<OpenedVault> permanentlyDeleteEntry(String entryId) async {
    final session = _requireSession();
    final idPtr = entryId.toNativeUtf8();
    try {
      final result = _permanentlyDeleteEntryJson(session, idPtr);
      final json = _readJsonObject(result);
      return OpenedVault.fromJson(json);
    } finally {
      calloc.free(idPtr);
    }
  }

  @override
  Future<OpenedVault> emptyRecycleBin() async {
    final session = _requireSession();
    final result = _emptyRecycleBinJson(session);
    final json = _readJsonObject(result);
    return OpenedVault.fromJson(json);
  }

  @override
  Future<bool> isDirty() async {
    final session = _requireSession();
    final result = _isDirty(session);
    final json = _readJsonObject(result);
    return (json['dirty'] as bool?) ?? false;
  }

  @override
  Future<void> save({
    required String masterPassword,
    String? keyfilePath,
  }) async {
    final session = _requireSession();
    final passwordPtr = masterPassword.toNativeUtf8();
    final keyfilePtr = (keyfilePath != null && keyfilePath.trim().isNotEmpty)
        ? keyfilePath.toNativeUtf8()
        : nullptr;

    try {
      final result = _save(session, passwordPtr, keyfilePtr);
      _readJsonObject(result);
    } finally {
      calloc.free(passwordPtr);
      if (keyfilePtr != nullptr) {
        calloc.free(keyfilePtr);
      }
    }
  }

  // --- P3: custom fields ---

  @override
  Future<EntryDetail> setCustomField({
    required String entryId,
    required String key,
    required String value,
    required bool protect,
  }) async {
    final session = _requireSession();
    final jsonPtr = jsonEncode({
      'entry_id': entryId,
      'key': key,
      'value': value,
      'protect': protect,
    }).toNativeUtf8();
    try {
      final result = _setCustomFieldJson(session, jsonPtr);
      final json = _readJsonObject(result);
      return EntryDetail.fromJson(json);
    } finally {
      calloc.free(jsonPtr);
    }
  }

  @override
  Future<EntryDetail> deleteCustomField({
    required String entryId,
    required String key,
  }) async {
    final session = _requireSession();
    final idPtr = entryId.toNativeUtf8();
    final keyPtr = key.toNativeUtf8();
    try {
      final result = _deleteCustomFieldJson(session, idPtr, keyPtr);
      final json = _readJsonObject(result);
      return EntryDetail.fromJson(json);
    } finally {
      calloc.free(idPtr);
      calloc.free(keyPtr);
    }
  }

  // --- P3: attachments ---

  @override
  Future<Uint8List> attachmentBytes({
    required String entryId,
    required String name,
  }) async {
    final session = _requireSession();
    final idPtr = entryId.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    try {
      final result = _attachmentBytesJson(session, idPtr, namePtr);
      final json = _readJsonObject(result);
      final bytesList = json['bytes'] as List<Object?>;
      return Uint8List.fromList(bytesList.cast<int>().toList(growable: false));
    } finally {
      calloc.free(idPtr);
      calloc.free(namePtr);
    }
  }

  @override
  Future<AttachmentSummary> upsertAttachment({
    required String entryId,
    required String name,
    required Uint8List bytes,
    required bool protect,
  }) async {
    final session = _requireSession();
    final jsonPtr = jsonEncode({
      'entry_id': entryId,
      'name': name,
      'bytes': bytes,
      'protect': protect,
    }).toNativeUtf8();
    try {
      final result = _upsertAttachmentJson(session, jsonPtr);
      final json = _readJsonObject(result);
      return AttachmentSummary.fromJson(json);
    } finally {
      calloc.free(jsonPtr);
    }
  }

  @override
  Future<void> removeAttachment({
    required String entryId,
    required String name,
  }) async {
    final session = _requireSession();
    final idPtr = entryId.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    try {
      final result = _removeAttachmentJson(session, idPtr, namePtr);
      _readResult(result);
    } finally {
      calloc.free(idPtr);
      calloc.free(namePtr);
    }
  }

  // --- P3: history ---

  @override
  Future<List<HistorySummary>> entryHistory(String entryId) async {
    final session = _requireSession();
    final idPtr = entryId.toNativeUtf8();
    try {
      final result = _entryHistoryJson(session, idPtr);
      final json = _readResult(result);
      return (json as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(HistorySummary.fromJson)
          .toList(growable: false);
    } finally {
      calloc.free(idPtr);
    }
  }

  @override
  Future<EntryDetail> entryHistoryDetail({
    required String entryId,
    required int index,
  }) async {
    final session = _requireSession();
    final idPtr = entryId.toNativeUtf8();
    try {
      final result = _entryHistoryDetailJson(session, idPtr, index);
      final json = _readJsonObject(result);
      return EntryDetail.fromJson(json);
    } finally {
      calloc.free(idPtr);
    }
  }

  // --- groups ---

  @override
  Future<GroupNode> createGroup({
    required String parentId,
    required String name,
  }) async {
    final session = _requireSession();
    final jsonPtr = jsonEncode(
      CreateGroupRequest(parentId: parentId, name: name).toJson(),
    ).toNativeUtf8();
    try {
      final result = _createGroupJson(session, jsonPtr);
      final json = _readJsonObject(result);
      return GroupNode.fromJson(json);
    } finally {
      calloc.free(jsonPtr);
    }
  }

  @override
  Future<GroupNode> renameGroup({
    required String groupId,
    required String name,
  }) async {
    final session = _requireSession();
    final jsonPtr = jsonEncode(
      RenameGroupRequest(groupId: groupId, name: name).toJson(),
    ).toNativeUtf8();
    try {
      final result = _renameGroupJson(session, jsonPtr);
      final json = _readJsonObject(result);
      return GroupNode.fromJson(json);
    } finally {
      calloc.free(jsonPtr);
    }
  }

  @override
  Future<OpenedVault> deleteGroup(String groupId) async {
    final session = _requireSession();
    final idPtr = groupId.toNativeUtf8();
    try {
      final result = _deleteGroupJson(session, idPtr);
      final json = _readJsonObject(result);
      return OpenedVault.fromJson(json);
    } finally {
      calloc.free(idPtr);
    }
  }

  @override
  Future<OpenedVault> restoreGroup(String groupId) async {
    final session = _requireSession();
    final idPtr = groupId.toNativeUtf8();
    try {
      final result = _restoreGroupJson(session, idPtr);
      final json = _readJsonObject(result);
      return OpenedVault.fromJson(json);
    } finally {
      calloc.free(idPtr);
    }
  }

  @override
  Future<OpenedVault> permanentlyDeleteGroup(String groupId) async {
    final session = _requireSession();
    final idPtr = groupId.toNativeUtf8();
    try {
      final result = _permanentlyDeleteGroupJson(session, idPtr);
      final json = _readJsonObject(result);
      return OpenedVault.fromJson(json);
    } finally {
      calloc.free(idPtr);
    }
  }

  @override
  Future<EntryDetail> moveEntry(String entryId, String targetGroupId) async {
    final session = _requireSession();
    final jsonPtr = jsonEncode(
      MoveEntryRequest(entryId: entryId, targetGroupId: targetGroupId).toJson(),
    ).toNativeUtf8();
    try {
      final result = _moveEntryJson(session, jsonPtr);
      final json = _readJsonObject(result);
      return EntryDetail.fromJson(json);
    } finally {
      calloc.free(jsonPtr);
    }
  }

  // --- database ---

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    String? keyfilePath,
  }) async {
    final session = _requireSession();
    final oldPtr = oldPassword.toNativeUtf8();
    final newPtr = newPassword.toNativeUtf8();
    final keyPtr = (keyfilePath != null && keyfilePath.trim().isNotEmpty)
        ? keyfilePath.toNativeUtf8()
        : nullptr;
    try {
      final result = _changePassword(session, oldPtr, newPtr, keyPtr);
      _readResult(result);
    } finally {
      calloc.free(oldPtr);
      calloc.free(newPtr);
      if (keyPtr != nullptr) calloc.free(keyPtr);
    }
  }

  @override
  Future<void> close() async {
    final session = _session;
    if (session != null) {
      _sessionClose(session);
      _session = null;
    }
  }

  Pointer<Void> _requireSession() {
    final session = _session;
    if (session == null) {
      throw const VaultRepositoryException('No open vault session.');
    }
    return session;
  }

  Map<String, Object?> _readJsonObject(_KeepassYFfiResult result) {
    final decoded = _readResult(result);
    return decoded as Map<String, Object?>;
  }

  dynamic _readResult(_KeepassYFfiResult result) {
    final jsonPtr = result.json;
    if (jsonPtr == nullptr) {
      throw const VaultRepositoryException('Null JSON response from FFI.');
    }
    final text = jsonPtr.toDartString();
    _stringFree(jsonPtr);

    final decoded = jsonDecode(text);
    if (result.status != 0) {
      final error = (decoded is Map) ? decoded['error'] as String? : null;
      throw VaultRepositoryException(error ?? 'Unknown FFI error.');
    }
    return decoded;
  }
}
