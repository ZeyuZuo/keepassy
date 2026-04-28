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

DynamicLibrary _loadLibrary() {
  final envLib = Platform.environment['KEEPASSY_FFI_LIB'];
  if (envLib != null && envLib.isNotEmpty) {
    return DynamicLibrary.open(envLib);
  }

  const libNames = [
    'libkeepass_ffi.so',
    'libkeepass_ffi.dylib',
    'keepass_ffi.dll',
  ];

  for (final name in libNames) {
    try {
      return DynamicLibrary.open(name);
    } catch (_) {}
  }

  final cwd = Directory.current.path;
  for (final dir in [cwd, '$cwd/..']) {
    for (final name in libNames) {
      final candidate = '$dir/keepass-rs/target/debug/$name';
      if (File(candidate).existsSync()) {
        return DynamicLibrary.open(candidate);
      }
    }
  }

  throw VaultRepositoryException(
    'Cannot load keepass_ffi shared library. '
    'Build it first: cd keepass-rs && cargo build -p keepass_ffi\n'
    'Or set KEEPASSY_FFI_LIB to the full .so path.',
  );
}

class FfiVaultRepository implements VaultRepository {
  FfiVaultRepository({DynamicLibrary? library})
    : _lib = library ?? _loadLibrary() {
    _openLocal = _lib.lookupFunction<_OpenLocalNative, _OpenLocalDart>(
      'keepassy_open_local',
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
    _isDirty = _lib.lookupFunction<_IsDirtyNative, _IsDirtyDart>(
      'keepassy_is_dirty',
    );
    _save = _lib.lookupFunction<_SaveNative, _SaveDart>('keepassy_save');
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
  }

  final DynamicLibrary _lib;
  Pointer<Void>? _session;

  late final _OpenLocalDart _openLocal;
  late final _SessionCloseDart _sessionClose;
  late final _StringFreeDart _stringFree;
  late final _JsonWithIdDart _entriesJson;
  late final _JsonWithIdDart _entryDetailJson;
  late final _JsonWithRequestDart _createEntryJson;
  late final _JsonWithRequestDart _updateEntryJson;
  late final _JsonWithIdDart _deleteEntryJson;
  late final _IsDirtyDart _isDirty;
  late final _SaveDart _save;
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

  @override
  Future<OpenedVault> openLocal({
    required String path,
    required String masterPassword,
    String? keyfilePath,
  }) async {
    if (path.trim().isEmpty) {
      throw const VaultRepositoryException('Vault file path is required.');
    }
    if (masterPassword.isEmpty) {
      throw const VaultRepositoryException('Master password is required.');
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
  Future<void> deleteEntry(String entryId) async {
    final session = _requireSession();
    final idPtr = entryId.toNativeUtf8();
    try {
      final result = _deleteEntryJson(session, idPtr);
      _readResult(result);
    } finally {
      calloc.free(idPtr);
    }
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
  Future<void> deleteGroup(String groupId) async {
    final session = _requireSession();
    final idPtr = groupId.toNativeUtf8();
    try {
      final result = _deleteGroupJson(session, idPtr);
      _readResult(result);
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
