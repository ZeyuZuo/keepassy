# keepass-rs Development TODO

This file turns the roadmap into implementation-sized tasks. Keep each item small enough to complete, test, and review independently.

Rules for every phase:

- Keep all reusable business logic in `keepass_core`.
- Keep `keepass_cli` as a thin debug and validation entrypoint.
- Do not add Tauri, Flutter, Dart, or UI framework dependencies to `keepass_core`.
- Run `cargo fmt --all --check`, `cargo test --workspace`, and `cargo clippy --workspace --all-targets -- -D warnings` before closing a phase.
- Do not commit real `.kdbx`, keyfile, password, or WebDAV credential fixtures.

## Phase 0: Project Initialization

Status: done.

- [x] Create Cargo workspace.
- [x] Create `crates/keepass_core`.
- [x] Create `crates/keepass_cli`.
- [x] Add root `README.md`.
- [x] Add `docs/architecture.md`.
- [x] Add `docs/roadmap.md`.
- [x] Add `.gitignore` for build output and secret database files.
- [x] Add `StorageBackend`.
- [x] Add `LocalFileStorage`.
- [x] Add `WebDavStorage` with GET, PUT, and HEAD metadata foundation.
- [x] Add `VaultService`.
- [x] Add serde-friendly DTOs.
- [x] Add CLI commands for local tree, local entries, local show, and WebDAV tree.
- [x] Add optional integration test controlled by `KEEPASS_RS_TEST_KDBX` and `KEEPASS_RS_TEST_PASSWORD`.

Done when:

- [x] `cargo fmt --all --check` passes.
- [x] `cargo test --workspace` passes.
- [x] `cargo clippy --workspace --all-targets -- -D warnings` passes.

## Phase 1: Read-Only Local Database

Goal: make local read-only KeePass browsing reliable enough for a desktop adapter to call later.

### 1.1 Stabilize Public DTOs

- [x] Review `GroupNode`, `EntrySummary`, `EntryDetail`, `OpenedVault`, and `RemoteMetadata`.
- [x] Decide which fields are part of the stable API for Phase 1.
- [x] Add Rustdoc comments for public DTO fields.
- [x] Make sure serialized JSON field names are UI-friendly and stable.
- [x] Keep passwords out of `GroupNode` and `EntrySummary`.

Done when:

- [x] DTOs have documented field meaning.
- [x] `serde_json` tests cover group tree, entry summary, and entry detail shapes.

### 1.2 Replace Path-Based IDs if Needed

- [x] Check whether KeePass UUIDs are always available and stable in `keepass = 0.10.1`.
- [x] Prefer UUID-based group and entry IDs if practical.
- [x] Keep path-based IDs only if UUIDs are not sufficient for all needed cases.
- [x] Document the ID format in `architecture.md`.
- [x] Add tests proving ID stability for nested groups and entries.

Done when:

- [x] `entries_for_group` and `entry_detail` work with the chosen ID format.
- [x] The ID format is documented and covered by tests.

### 1.3 Complete Entry Detail Mapping

- [x] Map title, username, password, URL, notes, and known fields.
- [x] Keep unknown custom fields in `EntryDetail.fields`.
- [x] Avoid duplicating known fields in a confusing way, or document the duplication policy.
- [x] Preserve empty vs missing values consistently.
- [x] Add tests for protected and unprotected KeePass values.

Done when:

- [x] Entry details expose all Phase 1 fields.
- [x] Tests cover known fields, custom fields, protected values, empty fields, and missing fields.

### 1.4 Add Local CLI Validation Flows

- [x] Keep `local tree --file <path>`.
- [x] Keep `local entries --file <path> --group <id>`.
- [x] Keep `local show --file <path> --entry <id>`.
- [x] Add `--json` only if a non-JSON format is introduced later.
- [x] Improve CLI error messages without leaking passwords.
- [x] Document example commands in `README.md`.

Done when:

- [x] CLI commands call only `VaultService`.
- [x] CLI has no KeePass parsing or storage business logic.

### 1.5 Local Integration Tests

- [x] Keep real database tests opt-in through environment variables.
- [x] Add a documented script or README section for running local integration tests.
- [x] Verify wrong password returns a clear error.
- [x] Verify missing file returns a clear error.
- [x] Verify a valid test database returns at least a root group.

Done when:

- [x] Integration tests are safe by default.
- [x] No private `.kdbx` fixture is required in the repository.

## Phase 2: WebDAV Read and Save Foundation

Goal: support remote `.kdbx` download/open now and prepare conflict-safe upload later.

### 2.1 WebDAV Configuration Model

- [x] Add a public `WebDavConfig` struct if URL plus credentials becomes too loose.
- [x] Support username/password credentials.
- [x] Keep credentials out of `Debug` output if a dedicated config type is added.
- [x] Validate URL scheme as `http` or `https`.
- [x] Document supported WebDAV assumptions.

Done when:

- [x] WebDAV construction fails early for invalid URLs.
- [x] Credentials are not accidentally printed in normal errors.

### 2.2 Remote Metadata

- [x] Read ETag from `HEAD`.
- [x] Read Last-Modified from `HEAD`.
- [x] Read Content-Length from `HEAD`.
- [x] Decide behavior when `HEAD` is unsupported by a server.
- [x] Add tests for metadata parsing.

Done when:

- [x] WebDAV open still works if metadata is unavailable, unless strict metadata is explicitly requested.
- [x] Metadata parsing behavior is documented.

### 2.3 Remote Download and Open

- [x] Ensure `open_webdav` downloads bytes and parses through the same core path as local files.
- [x] Add CLI flags for WebDAV username and password environment variables.
- [x] Add timeout configuration if needed.
- [x] Add size guard policy for unexpectedly large downloads.
- [x] Add tests for HTTP status mapping.

Done when:

- [x] WebDAV errors are mapped to `VaultError`.
- [x] Remote opening does not duplicate local parsing logic.

### 2.4 Save Foundation

- [x] Keep `StorageBackend::write` for local and WebDAV.
- [x] Add an explicit save API only after mutation support exists.
- [x] Add optional `If-Match` support for WebDAV PUT.
- [x] Track original ETag in opened remote vault metadata.
- [x] Document conflict behavior before exposing save to adapters.

Done when:

- [x] PUT support can be tested without requiring a real WebDAV server.
- [x] Conflict handling has a documented intended behavior.

## Phase 3: Entry Mutation and Save

Goal: allow modifying a database safely while keeping save behavior explicit.

### 3.1 Vault Session Model

- [x] Introduce a session or handle type if `OpenedVault` is insufficient for mutation.
- [x] Store decrypted database state in memory only where needed.
- [x] Track source metadata and dirty state.
- [x] Avoid serializing sensitive internal state.
- [x] Define when a session is closed or discarded.

Done when:

- [x] Read APIs and mutation APIs share one clear state model.
- [x] Sensitive data is not exposed through debug JSON.

### 3.2 Entry Create

- [x] Define `CreateEntryRequest`.
- [x] Support target group ID.
- [x] Support title, username, password, URL, notes, and custom fields.
- [x] Validate target group exists.
- [x] Return created entry summary or detail.

Done when:

- [x] Creating an entry marks the session dirty.
- [x] Tests cover valid create, missing group, and empty optional fields.

### 3.3 Entry Update

- [x] Define `UpdateEntryRequest`.
- [x] Support partial updates.
- [x] Preserve unspecified fields.
- [x] Support clearing optional fields intentionally.
- [x] Return updated entry detail.

Done when:

- [x] Updating an entry marks the session dirty only when data changes.
- [x] Tests cover update, clear field, missing entry, and custom fields.

### 3.4 Entry Delete

- [x] Define delete behavior for entries.
- [x] Decide whether to support soft delete metadata if the KeePass crate exposes it.
- [x] Return a clear result for deleted vs missing entries.
- [x] Mark session dirty after delete.

Done when:

- [x] Deleted entries no longer appear in group entry lists.
- [x] Tests cover delete and missing entry.

### 3.5 Save Database

- [x] Confirm `keepass = 0.10.1` save support and feature flags.
- [x] Gate save behind an explicit Cargo feature if needed.
- [x] Document KDBX4 writing risk and backup expectations.
- [x] Implement local save first.
- [x] Implement WebDAV save after conflict handling is tested.

Done when:

- [x] Save is never implicit.
- [x] Tests cover save failure and successful round-trip where supported.

## Phase 4: KeePass Advanced Features

Status: done.

Goal: add KeePass features without breaking the simple read/edit flow.

### 4.1 Keyfile Support

- [x] Extend unlock request to include optional keyfile bytes or path.
- [x] Keep keyfile handling in core, not CLI.
- [x] Add CLI flag for keyfile path.
- [x] Add tests for password-only and password-plus-keyfile paths.

Done when:

- [x] Existing password-only APIs still work.
- [x] Keyfile errors are distinct from wrong password where possible.

### 4.2 Attachments

- [x] Decide attachment DTO shape.
- [x] List attachment metadata without loading large data unnecessarily.
- [x] Add API to read attachment bytes.
- [x] Add API to add or replace attachment bytes.
- [x] Add API to remove attachments.

Done when:

- [x] Attachment metadata and bytes are separate API calls.
- [x] Large binary fields are not serialized into normal entry detail JSON.

### 4.3 Custom Fields

- [x] Preserve all custom fields in entry detail.
- [x] Allow create/update/delete of custom fields.
- [x] Define conflict behavior for known field names.
- [x] Add tests for protected custom fields if supported.

Done when:

- [x] Custom fields survive edit and save round-trips.

### 4.4 History

- [x] Inspect `keepass` crate history support.
- [x] Add DTOs for history summaries.
- [x] Add API to list entry history.
- [x] Add API to read one historical entry snapshot.
- [x] Decide whether restore-from-history belongs in Phase 4 or later.

Done when:

- [x] History APIs are read-only unless restore behavior is explicitly implemented.

## Phase 5: Desktop Adapters

Status: done via plain FFI adapter.

Goal: expose the core to a desktop UI without moving business logic into UI code.

### 5.1 Adapter Boundary

- [x] Decide whether the first adapter is Tauri or Flutter.
- [x] Keep adapter code outside `keepass_core`.
- [x] Keep DTO conversion explicit.
- [x] Avoid adapter-specific types in core APIs.
- [x] Document adapter error mapping.

Done when:

- [x] Core compiles without any Tauri or Flutter dependencies.

### 5.2 Tauri Adapter Option

Tauri-specific code is intentionally deferred until a Tauri frontend exists.
The Phase 5 adapter boundary is covered by `keepass_ffi`.

- [x] Add a Tauri command layer only when frontend work starts.
- [x] Commands call `VaultService` or session APIs.
- [x] Commands return serde DTOs or adapter-specific response wrappers.
- [x] Keep command functions thin.
- [x] Add command-level tests where practical.

Done when:

- [x] No KeePass parsing or WebDAV logic lives in Tauri command functions.

### 5.3 Flutter Adapter Option

- [x] Choose plain FFI or `flutter_rust_bridge`.
- [x] Add wrapper functions around core APIs.
- [x] Convert DTOs into bridge-safe types if required.
- [x] Define memory ownership and disposal rules.
- [x] Add a smoke test for generated bindings when the Flutter project exists.

Done when:

- [x] Flutter integration reuses core logic without forking behavior.

## Phase 6: Local Database Creation

Status: done.

Goal: let desktop clients create a new local KeePass database without using an
external KeePass app first.

- [x] Add `VaultService::create_local`.
- [x] Add `VaultService::create_local_with_keyfile`.
- [x] Support password-only, keyfile-only, and password-plus-keyfile databases.
- [x] Build database keys without adding an empty password when keyfile-only is
      requested.
- [x] Write new databases through a temp file and rename into place.
- [x] Reject duplicate target paths instead of overwriting an existing vault.
- [x] Expose `keepassy_create_local` through FFI.
- [x] Return an opened session snapshot after successful create.
- [x] Add FFI tests for create/reopen, duplicate target failure, and
      keyfile-only create/reopen.

Done when:

- [x] A Flutter client can create and immediately open a new local `.kdbx`.
- [x] Created vaults can be reopened with the selected credential strategy.

## Always-On Maintenance TODO

- [ ] Keep dependencies pinned or bounded deliberately.
- [ ] Review `keepass` crate release notes before upgrading.
- [ ] Keep public API changes documented.
- [ ] Add tests before broad refactors.
- [ ] Keep secret-handling behavior explicit in docs and errors.
- [ ] Re-run all verification commands before merging any phase.
