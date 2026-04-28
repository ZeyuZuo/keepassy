import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

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
  for (final name in libNames) {
    final candidate = '$cwd/keepass-rs/target/debug/$name';
    if (File(candidate).existsSync()) {
      return DynamicLibrary.open(candidate);
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
