# Development Log

## 2026-04-25–26: Project bootstrap and Phase 1 completion

### Project initialized (Phase 0)

- Cargo workspace with `keepass_core` and `keepass_cli` crates.
- `StorageBackend` trait, `LocalFileStorage`, `WebDavStorage` with GET/PUT/HEAD.
- `VaultService` with `open_local`, `open_webdav`, `entries_for_group`, `entry_detail`.
- Serde-friendly DTOs: `OpenedVault`, `RemoteMetadata`, `GroupNode`, `EntrySummary`, `EntryDetail`.
- `VaultError` enum covering I/O, HTTP, URL parse, storage, database open, group/entry not found.
- CLI: `local tree`, `local entries`, `local show`, `webdav tree`.
- Opt-in integration test via `KEEPASS_RS_TEST_KDBX` / `KEEPASS_RS_TEST_PASSWORD`.
- Documentation: `README.md`, `docs/architecture.md`, `docs/roadmap.md`, `docs/todo.md`.

### Phase 1: Read-Only Local Database — done

All Phase 1 tasks completed.

#### 1.1 Stabilize Public DTOs

- All 5 public DTOs have rustdoc comments covering field meaning, ID format, and
  password-exclusion conventions.
- 5 serde shape tests:
  - `group_node_json_shape` — group tree JSON never contains `password`.
  - `entry_summary_excludes_password` — summary lacks `password` key.
  - `entry_detail_includes_password_and_notes` — detail includes password, notes, custom fields.
  - `opened_vault_skips_entry_details_in_json` — internal entry_details map is not serialized.
  - `remote_metadata_json_shape` — etag, last_modified, content_length shape.

#### 1.2 UUID-Based IDs

- Group and entry IDs now use KeePass native UUIDs (from `keepass::db::Group.uuid` and
  `keepass::db::Entry.uuid`) instead of path-based synthetic IDs (`root/group:0/entry:1`).
- `group_to_node` simplified — no longer carries parent-ID state.
- `find_group` compares UUID strings directly.
- CLI `--group` / `--entry` args accept UUIDs; `--group` no longer defaults to "root".
- Integration test assertion changed from `== "root"` to `!id.is_empty()`.

#### 1.3 Complete Entry Detail Mapping

- `EntryDetail.fields` now contains only custom/unknown fields. Standard fields
  (Title, UserName, Password, URL, Notes) are excluded from the map to avoid
  duplication — they already appear as dedicated struct fields.
- `KNOWN_FIELD_KEYS` constant drives the filter.
- 8 entry-mapping unit tests:
  - `maps_all_known_fields` — title, username, password, url, notes all mapped.
  - `known_fields_not_duplicated_in_fields_map` — no known keys in `fields`.
  - `custom_fields_stored_in_fields_map` — custom fields appear correctly.
  - `protected_password_is_readable` — `Value::Protected` password decrypted and readable.
  - `protected_custom_field_appears_in_fields` — protected custom fields readable.
  - `empty_fields_become_none` — empty KeePass string → `None`.
  - `empty_custom_field_is_filtered_out` — empty custom field omitted from map.
  - `missing_fields_become_none` — absent KeePass field → `None`.

#### 1.4 CLI Error Handling

- `main` no longer returns `Result`. Errors are caught, printed to stderr via
  `eprintln!("error: {err}")`, and exit code 1 is set.
- Error messages do not leak the master password. Wrong-password errors produce
  messages like `error: failed to open KeePass database: Incorrect key`.
- CLI has zero KeePass parsing or storage logic — all commands call only
  `VaultService` methods.

#### 1.5 Local Integration Tests

- `tests/open_kdbx.rs` expanded from 1 test to 3:
  - `opens_configured_kdbx_fixture` — (opt-in) opens a real kdbx via env vars.
  - `wrong_password_returns_clear_error` — (opt-in) a wrong password gives a
    credential-related error, not a panic or generic message.
  - `missing_file_returns_clear_error` — (always runs) nonexistent path gives
    `VaultError::Io` with a file-not-found message.
- README updated with integration test invocation instructions.

### Test summary

| Layer | Tests |
|-------|-------|
| DTO serde shapes | 5 |
| Entry mapping | 8 |
| VaultService | 2 |
| Storage | 2 |
| Integration (opt-in + always-on) | 3 |
| **Total** | **20** |

All pass with `cargo test --workspace`. Clippy strict (`-D warnings`) and
`cargo fmt --all --check` are clean.

### What's next

Phase 2: WebDAV Read and Save Foundation — `WebDavConfig` struct, remote metadata
completion, conflict detection, save preparation.

---

## 2026-04-27: Phase 2 and Phase 3 completion

### Phase 2: WebDAV Read and Save Foundation — done

#### 2.1 WebDavConfig

- New `WebDavConfig` struct bundling URL, optional credentials, timeout, and max
  download size.
- URL scheme validation — only `http` and `https` accepted; anything else errors
  at construction time.
- Custom `Debug` impl redacts credentials as `[redacted]`.
- Builder pattern: `with_credentials()`, `with_timeout()`, `with_max_size()`.
- `WebDavCredentials` also gained a custom `Debug` that redacts the password.
- `VaultService::open_webdav` now takes `WebDavConfig` instead of separate url
  + credentials parameters.

#### 2.2 Remote Metadata

- HEAD request failure gracefully degrades to `Ok(None)` instead of blocking
  the open flow (distinguishes connection errors from unsupported HEAD).
- ETag automatically cached in `WebDavStorage.last_etag` (an `Arc<Mutex<Option<String>>>`)
  for later conflict detection.

#### 2.3 Download Guards

- `reqwest::Client` configured with timeout from `WebDavConfig`.
- Size guard checks `Content-Length` header before downloading body, then
  checks actual byte count after download. Both paths return a clear
  `VaultError::Storage` message.

#### 2.4 Save Foundation

- `WebDavStorage::write` automatically sends `If-Match` header with the
  last known ETag.
- Server returns `412 Precondition Failed` → `VaultError::Conflict`.
- New `VaultError::Conflict` variant.

#### Storage tests added (6 new)

- `webdav_config_rejects_non_http_scheme`
- `webdav_config_accepts_http_and_https`
- `webdav_config_debug_redacts_credentials`
- `webdav_credentials_debug_redacts_password`
- `webdav_config_builder_pattern`
- `webdav_default_debug_redacts_password`

### Phase 3: Entry Mutation and Save — done

#### 3.1 VaultSession Model

New `VaultSession` struct holds the decrypted `Database`, `StorageBackend`,
cached group tree + entry details map, dirty flag, and source metadata.

`VaultService` is now a thin factory:
- `VaultService::open_local(...) -> VaultSession`
- `VaultService::open_webdav(...) -> VaultSession`

Read methods moved from `VaultService` to `VaultSession`:
- `group_tree()` — reference to the root `GroupNode`
- `entries_for_group(id)` — list `EntrySummary` for a group
- `entry_detail(id)` — full `EntryDetail` by UUID
- `snapshot()` — `OpenedVault` snapshot for Tauri/FFI
- `is_dirty()` — whether unsaved changes exist

`Debug` impl hides internal `Database` fields; only shows `source`, `dirty`, `metadata`.

#### 3.2 Entry Create

`CreateEntryRequest { group_id, title, username, password, url, notes, custom_fields }`

`VaultSession::create_entry(req)`:
- Validates target group exists
- Creates `keepass::db::Entry` with `Uuid::new_v4()`
- Pushes into group, rebuilds caches, marks dirty
- Returns the new `EntryDetail`

#### 3.3 Entry Update

`UpdateEntryRequest { entry_id, title, username, password, url, notes }`

Each field is `Option<String>`:
- `None` — leave unchanged
- `Some("")` — clear the field
- `Some(value)` — set to value

`VaultSession::update_entry(req)` traverses the group tree to find the entry
by UUID, applies changes, rebuilds caches, marks dirty.

#### 3.4 Entry Delete

`VaultSession::delete_entry(entry_id)` finds the parent group, removes the
entry, rebuilds caches, marks dirty. Returns `VaultError::EntryNotFound` if
the UUID doesn't match any entry.

#### 3.5 Save Database

- `keepass = { version = "=0.10.1", features = ["save_kdbx4"] }` enabled.
- `VaultSession::save(master_password)` re-derives the encryption key from the
  password, serializes the database via `Database::save()`, writes bytes through
  the `StorageBackend`, and clears the dirty flag.
- Save is never implicit — caller must provide the master password.
- KDBX4 writing carries a doc warning about experimental support in the keepass crate.

#### Mutation tests added (7 new)

- `create_entry_in_root` — entry created in root group, correct fields, dirty
- `create_entry_nonexistent_group` — returns `GroupNotFound`, not dirty
- `update_entry_changes_fields` — partial update preserves unspecified fields,
  clears empty-string fields
- `update_entry_nonexistent` — returns `EntryNotFound`, not dirty
- `delete_entry_removes_from_group` — entry removed, dirty
- `delete_entry_nonexistent` — returns `EntryNotFound`
- `save_writes_bytes` — save produces a file, dirty cleared
- `cache_rebuilds_after_mutation` — cached tree updates after create

### Test summary (after Phase 3)

| Layer | Tests |
|-------|-------|
| DTO serde shapes | 5 |
| Entry mapping | 8 |
| VaultSession read | 2 |
| VaultSession mutation + save | 8 |
| Storage (local + WebDAV) | 8 |
| Integration (opt-in + always-on) | 3 |
| **Total** | **33** |

All pass with `cargo test --workspace`. Clippy strict and `cargo fmt` clean.

### What's next

Phase 4: KeePass Advanced Features — keyfile support, attachments, custom field
editing, entry history.

---

## 2026-04-27 (later): Code review fixes

Issues found and resolved via code review:

### save password verification
- `VaultSession` now stores `original_bytes` (the raw encrypted database from open time).
- `save()` re-parses `original_bytes` with the provided password before writing. If the
  password is wrong, the save is rejected with `VaultError::DatabaseSave`, leaving the
  original file untouched and the session dirty.
- After a successful save, `original_bytes` is updated to the new encrypted data.
- Test `save_rejects_wrong_master_password_without_writing` covers this path.
- Test `save_writes_bytes` extended with round-trip verification (re-open saved file).

### WebDAV ETag refresh
- After a successful PUT, the response ETag is now captured via `store_etag()`.
- `check_write_status` extracted as a standalone function for testability.
- Tests added: `webdav_put_request_includes_if_match`, `webdav_store_etag_updates_cached_value`,
  `webdav_precondition_failed_status_maps_to_conflict`.

### WebDAV default timeout
- `WebDavStorage::new` now always sets a timeout, defaulting to 30 seconds when
  `config.timeout` is `None`. Previously only set when explicitly configured.

### No-op update detection
- `apply_update` returns `bool` — `true` only when the field value actually changed.
- `update_entry` only sets dirty and rebuilds cache when at least one field changed.
- Test `update_entry_noop_does_not_mark_dirty` covers unchanged updates.

### Request DTO serialization
- `CreateEntryRequest` and `UpdateEntryRequest` now derive `Serialize, Deserialize`.
- Round-trip JSON test `entry_request_dtos_are_json_serializable` added.

### Documentation fixes
- Fixed broken rustdoc links: `VaultService::entry_detail` → `VaultSession::entry_detail`
  in `dto.rs`.
- `docs/architecture.md` updated to reflect Phase 3 API: `VaultService` as factory,
  `VaultSession` as stateful handle, save verification mechanism.
- `docs/todo.md` checkboxes for Phase 1–3 marked as done.

### Verification
- `RUSTDOCFLAGS='-D warnings' cargo doc --workspace --no-deps` clean.
- `cargo test --workspace`: 39 tests pass.
- `cargo clippy --workspace --all-targets -- -D warnings` clean.
- `cargo fmt --all --check` clean.

---

## 2026-04-27: Phase 4 completion

### Phase 4: KeePass Advanced Features — done

#### 4.1 Keyfile Support

- Added password-plus-keyfile open paths:
  - `VaultService::open_local_with_keyfile(...)`
  - `VaultService::open_webdav_with_keyfile(...)`
- Added `VaultSession::save_with_keyfile(...)` so keyfile-protected databases can
  be saved without changing the credential model.
- Centralized key construction in core; CLI reads `--keyfile <path>` bytes and
  delegates unlock/save semantics to `keepass_core`.
- Password-only open/save APIs remain unchanged.

#### 4.2 Attachments

- Added DTOs:
  - `AttachmentSummary` for names, sizes, and protected status.
  - `AttachmentBytes` for explicit raw-byte reads.
  - `UpsertAttachmentRequest` for add/replace operations.
- `EntryDetail` includes attachment metadata only; raw bytes are intentionally
  excluded from normal detail JSON.
- Added `VaultSession` APIs:
  - `attachments_for_entry`
  - `attachment_bytes`
  - `upsert_attachment`
  - `remove_attachment`

#### 4.3 Custom Fields

- Added `SetCustomFieldRequest` and `VaultSession::{set_custom_field, delete_custom_field}`.
- Custom fields can be stored protected or unprotected.
- Standard KeePass field names (`Title`, `UserName`, `Password`, `URL`, `Notes`)
  are rejected as custom keys to prevent ambiguous writes.
- Save round-trip test now verifies custom fields survive serialization.

#### 4.4 History

- Inspected `keepass` crate history support (`Entry.history`, `History::get_entries`,
  `Entry::update_history`).
- Added `HistorySummary`.
- Added read-only history APIs:
  - `entry_history`
  - `entry_history_detail`
- Mutation paths now call `Entry::update_history()` when entry content actually changes.
- Restore-from-history is intentionally not implemented in Phase 4.

#### Tests added/updated

- `keyfile_open_and_save_round_trip`
- `attachment_metadata_and_bytes_are_separate`
- `custom_field_editing_rejects_known_field_conflicts`
- `history_api_lists_and_reads_snapshots`
- `entry_request_dtos_are_json_serializable` extended for new request DTOs.
- `save_writes_bytes` extended to verify custom fields and attachments survive save.

### Test summary (after Phase 4)

| Layer | Tests |
|-------|-------|
| DTO serde shapes and request DTOs | 6 |
| Entry mapping | 8 |
| VaultSession read | 2 |
| VaultSession mutation, save, keyfile, attachments, custom fields, history | 13 |
| Storage (local + WebDAV) | 11 |
| Integration (opt-in + always-on) | 3 |
| **Total** | **43** |

Verification commands:

- `cargo fmt --all --check`
- `cargo test --workspace`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `RUSTDOCFLAGS='-D warnings' cargo doc --workspace --no-deps`

---

## 2026-04-27: Phase 5 completion

### Phase 5: Desktop Adapters — done

The first desktop adapter is a plain FFI boundary rather than Tauri. This keeps
the repository usable without a frontend project and avoids adding Tauri or
Flutter dependencies to `keepass_core`.

#### 5.1 Adapter Boundary

- Added new workspace crate `crates/keepass_ffi`.
- `keepass_core` remains free of Tauri, Flutter, and FFI-specific types.
- FFI DTO conversion is explicit JSON serialization/deserialization of
  `keepass_core` request and response types.
- Error mapping is documented and implemented as:
  - `status == 0` for success.
  - non-zero `status` for error.
  - `json` body `{ "error": "..." }` for failures.

#### 5.2 Tauri Adapter Option

- Tauri-specific commands remain deferred until an actual Tauri frontend exists.
- Architecture docs keep the Tauri boundary guidance: command code should be thin
  and call `VaultService`/`VaultSession`, not parse `.kdbx` or own storage logic.

#### 5.3 Plain FFI Adapter

- Added opaque `KeepassYSession` handle.
- Added `KeepassYFfiResult` response struct with status, optional session handle,
  and owned JSON string.
- Added memory ownership functions:
  - `keepassy_string_free`
  - `keepassy_session_close`
- Added FFI wrappers for:
  - local open
  - snapshot/group tree/entries/detail reads
  - create/update entry
  - set custom field
  - upsert attachment and read attachment bytes
  - read entry history
  - explicit save
- Added `crates/keepass_ffi/README.md` documenting ownership and JSON boundaries.

#### Tests added

- `ffi_open_read_create_update_and_save` — opens a generated KDBX, creates and
  updates an entry through FFI JSON calls, saves, reopens, and verifies persisted state.
- `ffi_error_response_for_null_session` — verifies null session handles produce
  JSON error responses.

### Test summary (after Phase 5)

| Layer | Tests |
|-------|-------|
| Core unit tests | 40 |
| FFI smoke tests | 2 |
| Integration (opt-in + always-on) | 3 |
| **Total** | **45** |

Verification commands:

- `cargo fmt --all --check`
- `cargo test --workspace`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `RUSTDOCFLAGS='-D warnings' cargo doc --workspace --no-deps`

---

## 2026-04-27–28: P1 Frontend Integration

### P1: Local Read-Only End-to-End — done

Flutter now opens and browses a real local KeePass database through Rust FFI.

#### P1.1 Backend FFI verification

- `keepass_ffi` builds `libkeepass_ffi.so` (debug and release) with
  `crate-type = ["cdylib", "rlib"]`.
- All 14 symbols exported and verified via `nm -D`.
- Existing FFI smoke test (`ffi_open_read_create_update_and_save`) covers the
  full open-read-write-save-reopen cycle through the C ABI.

#### P1.2 FfiVaultRepository

- New `lib/src/repositories/ffi_vault_repository.dart` implements `VaultRepository`
  using `dart:ffi` and `package:ffi`.
- Bound 5 C functions: `keepassy_open_local`, `keepassy_session_close`,
  `keepassy_string_free`, `keepassy_entries_json`, `keepassy_entry_detail_json`.
- `_KeepassYFfiResult` struct maps the C struct layout.
- Memory ownership: every JSON string freed through `keepassy_string_free` in
  `_readResult`; session freed through `keepassy_session_close` in `close()`.
- Library loading: three-tier fallback — `KEEPASSY_FFI_LIB` env var, system
  library paths, relative dev path (`keepass-rs/target/debug/`).
- Error mapping: `status != 0` → `VaultRepositoryException` with Rust error
  message from `{"error": "..."}`.

#### P1.3 File picker UX

- Added `file_picker` dependency. Browse buttons next to KDBX path and keyfile
  path fields in `UnlockPage`.
- Manual path input retained alongside picker.

#### P1.4 Repository switch

- `KeepassYApp.defaultRepository()` tries `FfiVaultRepository` first, falls back
  to `MockVaultRepository` if the shared library cannot be loaded.
- `VaultPage` calls `entriesForGroup` and `entryDetail` through the repository
  interface — same code path for both FFI and mock data.
- Lock action calls `repository.close()`, which calls `keepassy_session_close`.

#### Verification

- `cargo fmt --all --check` — clean.
- `cargo clippy --workspace --all-targets -- -D warnings` — clean.
- `cargo test --workspace` — 45 tests pass.
- `dart format lib test` — 0 files changed.
- `flutter analyze` — no issues.
- `flutter test` — all tests pass.

### Next sprint

Phase P2: Local Editing and Explicit Save — bind mutation FFI functions in Dart,
add create/edit/delete entry UI, dirty state tracking, save button, and
unsaved-change prompts.

---

## 2026-04-28: P2 Local Editing and Explicit Save

### P2: Local Editing and Explicit Save — done

#### P2.1 Backend FFI mutation surface

New FFI wrappers added to `keepass_ffi`:
- `keepassy_delete_entry_json` — delete entry by UUID.
- `keepassy_delete_custom_field_json` — delete a custom field.
- `keepassy_remove_attachment_json` — remove an attachment.
- `keepassy_is_dirty` — query dirty state without a mutation.

All existing mutation wrappers (`create`, `update`, `set_custom_field`,
`upsert_attachment`, `save`) were already in place from Phase 5.

#### P2.2 Frontend editing model

- `CreateEntryRequest` and `UpdateEntryRequest` DTOs added to `vault_models.dart`
  with `toJson()` serialisation matching Rust serde field names.
- `VaultRepository` interface extended with `createEntry`, `updateEntry`,
  `deleteEntry`, `isDirty`, and `save`.
- `MockVaultRepository` updated with full mutation support for UI development.
- `FfiVaultRepository` extended with 5 new FFI bindings: `create_entry_json`,
  `update_entry_json`, `delete_entry_json`, `is_dirty`, `save`.
- `VaultPage` now supports:
  - **Create**: dialog with title/username/password/URL/notes fields.
  - **Edit**: inline edit mode in the detail pane.
  - **Delete**: confirmation dialog before removing entry.
  - **Save**: master-password re-prompt dialog before persisting to backend.
  - **Lock**: unsaved-changes prompt before discarding.

#### P2.3 Save and dirty state UX

- Dirty flag set locally after create/update/delete mutations.
- Save button states: clean (grey, disabled), dirty (primary colour, enabled),
  saving (spinner), failed (error icon with tooltip).
- Save re-prompts for master password (not stored in app state).
- Lock prompts to confirm before discarding unsaved changes.

#### P2.4 Clipboard

- Copy buttons on username, password, URL, and custom fields.
- 30-second clipboard auto-clear timer.
- Visual snackbar confirmation without revealing copied secret.

#### Verification

- `cargo fmt --all --check` — clean.
- `cargo clippy --workspace --all-targets -- -D warnings` — clean.
- `cargo test --workspace` — 45 tests pass.
- `dart format lib test` — clean.
- `flutter analyze` — no issues.
- `flutter test` — all tests pass.

### Next sprint

Phase P3: Advanced Local Features — attachment management UI, custom field
editing, entry history viewer, password generator.

---

## 2026-04-28: P3 Advanced Local Features

### P3: Advanced Local Features — done

#### P3.1 Attachments

- `VaultRepository` extended with `attachmentBytes`, `upsertAttachment`,
  `removeAttachment`.
- FFI bindings added for `keepassy_attachment_bytes_json`,
  `keepassy_upsert_attachment_json`, `keepassy_remove_attachment_json`.
- Attachment section in read mode shows download and remove buttons per
  attachment, plus an add-attachment button.
- `_downloadAttachment` uses `FilePicker.saveFile` + `repository.attachmentBytes`
  to save attachment content to a user-chosen path.
- `_addAttachment` uses `FilePicker.pickFiles` with `withData: true` to
  read file bytes and call `repository.upsertAttachment`.
- `_removeAttachment` shows confirmation dialog before calling
  `repository.removeAttachment`.

#### P3.2 Entry History

- Added `keepassy_entry_history_detail_json` FFI wrapper (was missing from
  Phase 5).
- `VaultRepository` extended with `entryHistory` and `entryHistoryDetail`.
- `HistorySummary` DTO added to `vault_models.dart`.
- FFI binding for `keepassy_entry_history_json`.

#### P3.3 Custom Fields

- `VaultRepository` extended with `setCustomField`, `deleteCustomField`.
- FFI bindings for `keepassy_set_custom_field_json`,
  `keepassy_delete_custom_field_json`.
- Edit mode shows custom fields section with add button and per-field
  remove buttons.
- Add-custom-field dialog with key, value, and protected toggle.

#### P3.4 Password Generator

- Pure frontend implementation in `_VaultPageState._showPasswordGenerator`.
- Configurable: length, lowercase, uppercase, digits, symbols, ambiguous
  character avoidance.
- `Random.secure()` for cryptographic randomness.
- Accessible from create-entry dialog and edit-mode password field.
- Preview pane with monospace display; explicit "Use password" accept button.

#### Verification

- `cargo fmt --all --check` — clean.
- `cargo clippy --workspace --all-targets -- -D warnings` — clean.
- `cargo test --workspace` — 45 tests pass.
- `dart format lib test` — clean.
- `flutter analyze` — no issues.
- `flutter test` — 2 tests pass.

### Next sprint

Pre-WebDAV local feature parity (see ../../docs/todo.md) — global search,
entry sort, auto-lock, move/duplicate entries, group management, entry
expiry, password strength indicator, database maintenance.

Phase P4: WebDAV End-to-End — remote vault open, save, and conflict UI.

---

## 2026-04-29: Pre-WebDAV parity review and UI fixes

### Pre-WebDAV Local Feature Parity — ready for P4

The local feature-parity sprint is complete enough to proceed to WebDAV:

- Global search across all groups.
- Entry sort controls.
- Auto-lock timer.
- Move entry and duplicate entry actions.
- Multi-select and bulk delete.
- Entry expiry fields.
- Password strength indicator.
- Group create, rename, and delete.
- Change master password.

Recycle Bin support is intentionally deferred to a dedicated future feature.
Reliable restore requires tracking each deleted entry's original group metadata
inside the KeePass database, which is a larger persistence and migration design
than the rest of the parity work.

### Follow-up UI fixes

- Added copy actions for custom fields in read and edit modes. Protected custom
  fields stay visually masked in read mode but can be copied like passwords.
- Fixed Save vault submit via Enter by moving the dialog text controllers into a
  dedicated dialog widget that owns and disposes them after route teardown.

### Next sprint

Phase P4: WebDAV End-to-End:

1. Add WebDAV open through the Rust FFI boundary.
2. Add Flutter WebDAV unlock flow through `VaultRepository`.
3. Add remote metadata display and conflict-safe save UX.

---

## 2026-04-29: P4 WebDAV End-to-End

### P4.1 Backend WebDAV FFI — done

- Added `keepassy_open_webdav`, taking a JSON request with URL, optional
  WebDAV username/password, optional keyfile path, and optional download size
  limit.
- The wrapper reuses `VaultService::open_webdav` /
  `open_webdav_with_keyfile`; WebDAV protocol behavior remains in
  `keepass_core`.
- Returned snapshots include remote metadata collected by core:
  ETag, Last-Modified, and Content-Length.
- Save continues to use the existing `keepassy_save` session path, so WebDAV
  saves use core's `If-Match` conflict detection.

### P4.2 Flutter WebDAV Open Flow — done

- `VaultRepository` now exposes `openWebDav`.
- `FfiVaultRepository` binds `keepassy_open_webdav`.
- Unlock UI has a local/WebDAV source selector, WebDAV URL, username,
  password, master password, and optional keyfile support.
- Flutter validates WebDAV URLs before calling the repository.

### P4.3 Sync and Conflict UX — done

- Vault app bar exposes remote metadata when available.
- Save conflicts show a dedicated dialog instead of a generic failure snackbar.
- Conflict dialog lets the user keep local edits or close the session and
  reopen the remote vault.
- Retrying save remains available through the normal Save action while local
  edits stay dirty.

### Tests

- Added FFI tests using a local mock HTTP/WebDAV server:
  - WebDAV open returns remote metadata.
  - WebDAV save succeeds and sends `If-Match`.
  - WebDAV `412 Precondition Failed` returns a conflict and does not silently
    overwrite.
- Added Flutter widget coverage for WebDAV unlock fields and Dart-side WebDAV
  URL validation.

### Manual verification

- WebDAV open flow tested successfully in the Flutter app.
- Remote metadata dialog tested successfully.
- WebDAV save and reopen verification tested successfully.
- Manual conflict testing was skipped because it depends on server-side ETag /
  `If-Match` behavior, but the FFI mock WebDAV tests cover successful save and
  `412 Precondition Failed` conflict handling.

### Next sprint

Phase P5: Desktop Release Quality — package the Linux build with the Rust shared
library, add startup checks, and run release smoke tests for local and WebDAV
workflows.

---

## 2026-04-30: P4.7 Create New KDBX

### Backend create-local support — done

- Added local database creation APIs in `keepass_core`:
  - `VaultService::create_local(...)`
  - `VaultService::create_local_with_keyfile(...)`
- Added `keepassy_create_local` in `keepass_ffi`, taking JSON with the target
  local path and optional keyfile path, plus a master password argument.
- Successful create returns an opened session snapshot so Flutter can navigate
  directly into the new vault.
- New database writes reject an existing target path and write through a temp
  file before renaming into place.

### Credential behavior — done

- Creation supports password-only, keyfile-only, and password-plus-keyfile
  vaults.
- `build_database_key` now treats empty password plus keyfile as true
  keyfile-only, instead of adding an empty-string password to the key.
- Empty password with no keyfile is rejected as an invalid request.

### Flutter flow — done

- Added `VaultRepository.createLocal` to the Dart repository boundary, with FFI
  and mock implementations.
- Added a create-vault dialog on the unlock surface.
- The vault path is now selected through the system save-location picker instead
  of relying on a free-form relative path field.
- The flow can select an existing keyfile or create a new random keyfile.
- Save/open validation now allows keyfile-only vaults where the database uses
  no master password.

### Tests

- Rust:
  - `ffi_create_local_and_reopen`
  - duplicate-path failure check in the create-local FFI test
  - `ffi_create_local_with_keyfile_only_and_reopen`
- Flutter:
  - Create dialog exposes save-location flow and keyfile controls.
  - Create flow requires a chosen save location.
  - Mock repository accepts keyfile-only create.

### Verification

- `/home/zzy/app/flutter/bin/flutter analyze`
- `/home/zzy/app/flutter/bin/flutter test`
- `cargo test -p keepass_core -p keepass_ffi`
- `cargo build -p keepass_ffi`

### Next sprint

Phase P4.8: Recycle Bin — implement KeePass-compatible recoverable delete,
restore, permanent delete, and empty-bin behavior.

---

## 2026-04-30: P4.8 Recycle Bin

### Backend recycle semantics — done

- Added KeePass-compatible Recycle Bin handling through
  `Meta.recyclebin_uuid`, `Meta.recyclebin_enabled`, and a root-level
  `Recycle Bin` group created on demand.
- Normal entry delete now moves entries into Recycle Bin instead of removing
  them from the database.
- Restore uses entry custom data key `keepassy.original_group_id` to return an
  entry to its original group when the group still exists, otherwise it falls
  back to root.
- Added explicit permanent delete and empty-bin APIs, recording removed entry
  UUIDs in KeePass deleted objects.
- Group deletion was later extended to use the same Recycle Bin path; see the
  2026-05-01 follow-up below.

### FFI and Flutter — done

- `keepassy_delete_entry_json` now returns an updated vault snapshot.
- Added FFI calls for restore, permanent delete, and empty Recycle Bin.
- Added Dart repository methods and mock behavior for recycle/restore flows.
- Added `GroupNode.isRecycleBin` so Flutter can render Recycle Bin distinctly
  and avoid treating it like a normal group.
- The vault UI now shows Recycle Bin with a trash icon, uses recoverable delete
  copy for normal entries, and exposes restore/permanent-delete actions inside
  Recycle Bin.
- Empty Recycle Bin is a separate confirmed action. Bulk delete remains
  recoverable outside Recycle Bin and becomes permanent inside Recycle Bin.

### Tests

- Rust:
  - delete moves entries to Recycle Bin and restore returns them.
  - permanent delete records a deleted object.
  - empty Recycle Bin removes recycled entries.
- Flutter:
  - mock repository delete-to-recycle and restore behavior.

### Verification

- `cargo fmt --all --check`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test --workspace`
- `/home/zzy/app/flutter/bin/flutter analyze`
- `/home/zzy/app/flutter/bin/flutter test`
- `cargo build -p keepass_ffi`

### Follow-up

- Manual desktop smoke test: delete, save, reopen, restore, save, reopen.
- Manual desktop smoke test: empty Recycle Bin, save, reopen, verify permanent
  removal.
- Next sprint: Phase P5 Desktop Release Quality.

---

## 2026-05-01: P4.8 Recycle Bin Follow-up

### UX fixes — done

- Save now reuses the master password and keyfile path supplied during
  unlock/create, so Save no longer opens a password prompt.
- After a successful password change, the in-memory save credential is updated
  to the new password.
- The Groups header and create-group button remain visible when Recycle Bin is
  selected. Creating a group while browsing Recycle Bin now creates it under the
  database root instead of inside Recycle Bin.

### Group recycle support — done

- Group delete now moves the group to Recycle Bin instead of hard-deleting.
- Recycled groups store their original parent group in group custom data under
  `keepassy.original_parent_group_id`.
- Recycled groups can be restored to their original parent when it still
  exists, otherwise root is used as the fallback.
- Recycled groups can be permanently deleted, and empty Recycle Bin now removes
  both recycled entries and recycled groups.
- FFI and Dart repository APIs were added for group restore and permanent
  group delete.

### Tests

- Rust core:
  - group delete moves to Recycle Bin and restores.
  - empty Recycle Bin removes recycled groups.
- FFI:
  - recycle/restore/permanent-delete flow covers both entries and groups.
- Flutter:
  - mock repository group recycle/restore behavior.

### Verification

- `cargo test --workspace`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `/home/zzy/app/flutter/bin/flutter analyze`
- `/home/zzy/app/flutter/bin/flutter test`
- `cargo build -p keepass_ffi`
