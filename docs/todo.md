# KeePassY Project TODO

This TODO is the project execution checklist. It follows
`docs/project-roadmap.md` and includes backend, frontend, integration, testing,
and release work in one place.

Use this file as the primary development tracker. Keep backend-only detail in
`keepass-rs/docs/todo.md` when it needs lower-level Rust implementation notes,
and keep frontend design rules in `keepassy_flutter/docs/frontend.md`.

## Working Rules

- Follow the main project phases in order unless a task is clearly independent.
- Keep business logic in `keepass_core`.
- Keep `keepass_ffi` as a thin C ABI adapter over `keepass_core`.
- Keep Flutter widgets behind `VaultRepository`; widgets must not call FFI.
- Keep save explicit; mutations mark state dirty but do not auto-save.
- Do not commit real `.kdbx`, keyfile, password, or WebDAV credential fixtures.
- Treat memory ownership across FFI as a release blocker.

## Current Priority

Current sprint: Phase P4, WebDAV end-to-end.

Pre-WebDAV local feature parity is complete enough to proceed: global search,
entry sort, auto-lock, move/duplicate entries, bulk delete, group management,
entry expiry, password strength, and change-master-password are implemented.
Recycle Bin support is intentionally deferred because tracking original entry
group metadata inside the KeePass database should be handled as a separate
feature.

The next meaningful milestone is opening and saving a WebDAV-hosted `.kdbx`
from Flutter through Rust FFI, with clear remote metadata and conflict handling.

## Phase P0: Baseline and Documentation

Status: mostly done.

### Backend

- [x] Create Rust workspace under `keepass-rs`.
- [x] Keep reusable behavior in `keepass_core`.
- [x] Add CLI validation entrypoint.
- [x] Add FFI crate.
- [x] Document backend architecture.
- [x] Track backend implementation details in `keepass-rs/docs/todo.md`.

### Frontend

- [x] Create Flutter project under `keepassy_flutter`.
- [x] Add app shell, theme, unlock page, and vault workspace.
- [x] Add Dart DTOs that mirror Rust serde JSON.
- [x] Add `VaultRepository`.
- [x] Add `MockVaultRepository`.
- [x] Document frontend design and coding rules.
- [x] Add frontend roadmap.

### Project

- [x] Add overall project roadmap.
- [x] Add overall project TODO.
- [ ] Add a root README or update existing top-level docs to point at:
  - `docs/project-roadmap.md`
  - `docs/todo.md`
  - `keepass-rs/README.md`
  - `keepassy_flutter/docs/frontend.md`

Done when:

- [ ] A developer can start from the repository root and find the roadmap, TODO,
      backend docs, and frontend docs without guessing.

## Phase P1: Local Read-Only End-to-End

Goal: Flutter opens and browses a real local KeePass database through Rust FFI.

### P1.1 Backend FFI Readiness

- [ ] Confirm `keepass_ffi` crate type builds a Linux shared library.
- [ ] If missing, set `crate-type = ["cdylib", "rlib"]` for `keepass_ffi`.
- [ ] Build debug shared library:
  - `cargo build -p keepass_ffi`
- [ ] Build release shared library:
  - `cargo build -p keepass_ffi --release`
- [ ] Document expected `.so` output path.
- [ ] Confirm these functions exist and are exported:
  - `keepassy_open_local`
  - `keepassy_session_close`
  - `keepassy_string_free`
  - `keepassy_snapshot_json`
  - `keepassy_group_tree_json`
  - `keepassy_entries_json`
  - `keepassy_entry_detail_json`
- [ ] Add or update FFI tests for open, group tree, entries, detail, and close.
- [ ] Verify FFI error JSON shape for invalid path and wrong password.
- [ ] Verify returned JSON strings are always caller-owned.

Done when:

- [ ] `libkeepass_ffi.so` can be built locally.
- [ ] FFI read-only tests pass.
- [ ] The exported function set is documented.

### P1.2 Frontend FFI Infrastructure

- [ ] Add `lib/src/repositories/ffi/` or equivalent adapter folder.
- [ ] Add Dart FFI type definitions for `KeepassYFfiResult`.
- [ ] Bind `keepassy_open_local`.
- [ ] Bind `keepassy_session_close`.
- [ ] Bind `keepassy_string_free`.
- [ ] Bind read-only JSON functions.
- [ ] Add a small FFI result helper that:
  - checks `status`
  - decodes UTF-8 JSON
  - frees JSON through `keepassy_string_free`
  - maps errors into `VaultRepositoryException`
- [ ] Add session handle wrapper that closes exactly once.
- [ ] Add development library path resolution for Linux.
- [ ] Add a clear error when the shared library cannot be loaded.

Done when:

- [ ] A repository-level smoke test can load the library or fail with a clear
      setup error.
- [ ] Widgets still depend only on `VaultRepository`.

### P1.3 Frontend Local File UX

- [ ] Add file picker dependency after checking Flutter desktop compatibility.
- [ ] Replace raw `.kdbx` path typing with a file picker.
- [ ] Keep manual path input available if useful for development.
- [ ] Add optional keyfile picker.
- [ ] Validate empty path before calling repository.
- [ ] Validate empty password before calling repository.
- [ ] Show user-safe errors for:
  - file not found
  - wrong password
  - keyfile read failure
  - FFI library load failure
  - unsupported or corrupt database

Done when:

- [ ] A user can select a local `.kdbx`, enter a password, and see a clear
      outcome.

### P1.4 Read-Only Vault Browsing

- [ ] Replace app-level repository selection with a development switch:
  - mock repository for UI work
  - FFI repository for real data
- [ ] Load real snapshot after unlock.
- [ ] Render real group tree.
- [ ] Render real entry summaries for selected group.
- [ ] Load real entry detail on selection.
- [ ] Keep password and notes out of summaries.
- [ ] Reset password visibility when entry selection changes.
- [ ] Add loading, empty, and error states for group and detail panes.
- [ ] Close the session on lock.

Done when:

- [ ] Flutter opens a real local `.kdbx` and browses groups and entry details.
- [ ] Locking the vault closes the FFI session.

### P1.5 Tests and Checks

- [ ] Backend: `cargo fmt --all --check`.
- [ ] Backend: `cargo clippy --workspace --all-targets -- -D warnings`.
- [ ] Backend: `cargo test --workspace`.
- [ ] Frontend: `dart format lib test`.
- [ ] Frontend: `flutter analyze`.
- [ ] Frontend: `flutter test`.
- [ ] Add widget tests for unlock validation.
- [ ] Add widget tests for entry selection and password reveal.
- [ ] Add repository tests for FFI error mapping where practical.

Acceptance:

- [ ] Real local vault opens from Flutter.
- [ ] Browsing uses real backend data, not mock data.
- [ ] User-facing errors are understandable and do not leak secrets.
- [ ] FFI memory ownership rules are enforced in code review and tests.

## Phase P2: Local Editing and Explicit Save

Goal: user can modify a local vault, save explicitly, close it, and verify
changes after reopening.

### P2.1 Backend FFI Mutation Surface

- [ ] Confirm FFI exposes:
  - `keepassy_create_entry_json`
  - `keepassy_update_entry_json`
  - `keepassy_set_custom_field_json`
  - `keepassy_upsert_attachment_json`
  - `keepassy_save`
- [ ] Add FFI wrapper for delete entry if missing.
- [ ] Add FFI wrapper for dirty state if needed by UI.
- [ ] Add FFI tests for create, update, delete, save, and reopen.
- [ ] Add specific error mapping for save failure and conflict.

Done when:

- [ ] All core local edit operations needed by the UI are callable through FFI.

### P2.2 Frontend Editing Model

- [ ] Decide edit surface:
  - focused dialog for create
  - detail-pane edit mode for update
- [ ] Add form models for create and update.
- [ ] Validate required fields client-side before repository calls.
- [ ] Keep optional field clearing explicit.
- [ ] Add password visibility and generate/copy controls in edit mode.
- [ ] Add custom field add/edit/remove UI.
- [ ] Add delete confirmation.

Done when:

- [ ] Create, update, and delete flows are usable against mock data first.

### P2.3 Save and Dirty State UX

- [ ] Add dirty state to repository contract or session model.
- [ ] Mark UI dirty after create, update, delete, custom field, or attachment mutation.
- [ ] Add save button states:
  - clean
  - dirty
  - saving
  - saved
  - failed
- [ ] Prompt before lock when dirty.
- [ ] Prompt before app/window close when dirty.
- [ ] Keep failed saves dirty.
- [ ] Show backup guidance for local saves if backend docs require it.

Done when:

- [ ] User cannot accidentally discard unsaved local changes without warning.

### P2.4 Clipboard and Sensitive Actions

- [ ] Add copy username.
- [ ] Add copy password.
- [ ] Add copy URL.
- [ ] Add copy custom field.
- [ ] Add clipboard clear timer.
- [ ] Add visual confirmation without revealing copied secret.
- [ ] Never log copied values.

Done when:

- [ ] Copy actions are explicit, discoverable, and do not expose values in logs.

### P2.5 End-to-End Validation

- [ ] Create entry in Flutter.
- [ ] Edit entry in Flutter.
- [ ] Delete entry in Flutter.
- [ ] Save local vault.
- [ ] Lock vault.
- [ ] Reopen vault.
- [ ] Verify persisted changes.

Acceptance:

- [ ] Local editing round trip works on a real `.kdbx`.
- [ ] Failed save preserves in-memory changes.
- [ ] Tests cover form validation, dirty prompts, and save failure UI.

## Phase P3: Advanced Local Features

Goal: expose useful KeePass features after the common edit/save loop is stable.

### P3.1 Attachments

- [ ] Confirm backend core and FFI support attachment metadata.
- [ ] Confirm backend core and FFI support reading attachment bytes.
- [ ] Add FFI wrapper for attachment removal if missing.
- [ ] Add attachment metadata list in entry detail.
- [ ] Add export attachment flow.
- [ ] Add add or replace attachment flow.
- [ ] Add remove attachment flow.
- [ ] Keep attachment bytes out of normal entry detail loading.

Done when:

- [ ] Attachment bytes are loaded only through explicit user actions.

### P3.2 Entry History

- [ ] Confirm FFI exposes entry history list.
- [ ] Add FFI wrapper for history detail if missing.
- [ ] Add history tab or section in entry detail.
- [ ] Add read-only history detail view.
- [ ] Add comparison affordance if it remains simple.
- [ ] Do not add restore until backend explicitly supports it.

Done when:

- [ ] History is visible and clearly read-only.

### P3.3 Custom and Protected Fields

- [ ] Display custom fields separately from standard fields.
- [ ] Add protected/unprotected field indicator if backend exposes it.
- [ ] Add custom field protect toggle if backend supports it.
- [ ] Reject standard KeePass field names in UI before repository call.

Done when:

- [ ] Custom field behavior matches backend validation and error messages.

### P3.4 Password Generator

- [ ] Decide whether password generation is frontend-owned.
- [ ] Add generator policy options:
  - length
  - lowercase
  - uppercase
  - digits
  - symbols
  - ambiguous character avoidance
- [ ] Add generated password preview with explicit accept action.
- [ ] Add tests for generator constraints.

Done when:

- [ ] Generator can fill create/edit password fields without changing backend
      business rules.

Acceptance:

- [ ] Advanced features do not crowd the primary entry detail workflow.
- [ ] Tests cover attachment and history error states.

## Phase P4: WebDAV End-to-End

Goal: open and save remote vaults with visible conflict handling.

### P4.1 Backend WebDAV FFI

- [ ] Add `keepassy_open_webdav` or equivalent FFI wrapper.
- [ ] Define JSON request shape for WebDAV URL and credentials.
- [ ] Support optional keyfile path or bytes consistently with local open.
- [ ] Ensure credentials do not appear in debug output or errors.
- [ ] Expose remote metadata in snapshot.
- [ ] Expose conflict errors distinctly enough for UI.
- [ ] Add FFI tests with mocked HTTP/WebDAV server where practical.

Done when:

- [ ] Flutter can call WebDAV open without adding WebDAV logic to Dart.

### P4.2 Frontend Remote Open Flow

- [ ] Add source selector:
  - local file
  - WebDAV
- [ ] Add WebDAV URL field.
- [ ] Add WebDAV username field.
- [ ] Add WebDAV password field.
- [ ] Add optional keyfile picker for remote vault.
- [ ] Validate URL format before repository call.
- [ ] Keep credentials scoped to the unlock action/session.

Done when:

- [ ] Remote unlock UI is clear and separate from local file selection.

### P4.3 Sync and Conflict UX

- [ ] Display remote metadata when available:
  - ETag
  - Last-Modified
  - Content-Length
- [ ] Add save conflict state.
- [ ] Add reload from remote action.
- [ ] Add retry save action.
- [ ] Add cancel/keep local edits action.
- [ ] Never silently overwrite remote conflicts.

Done when:

- [ ] Users understand whether a save succeeded, failed, or conflicted.

Acceptance:

- [ ] User can open and save a WebDAV vault.
- [ ] ETag conflict does not overwrite server data.
- [ ] Network, auth, and conflict failures have separate user messages.

## Phase P5: Desktop Release Quality

Goal: ship a practical Linux desktop build.

### P5.1 Packaging

- [ ] Decide release artifact layout.
- [ ] Bundle `libkeepass_ffi.so` with Flutter Linux build.
- [ ] Verify runtime library loading from bundled path.
- [ ] Add app icon.
- [ ] Add desktop metadata.
- [ ] Add release build command documentation.
- [ ] Add startup check for missing or incompatible FFI library.

Done when:

- [ ] A clean Linux machine can launch the packaged app with the bundled library.

### P5.2 Security and Session Hardening

- [ ] Add auto-lock timer.
- [ ] Add lock on suspend or window inactivity if feasible.
- [ ] Clear clipboard after timeout.
- [ ] Clear sensitive UI state on lock.
- [ ] Audit logs for secret leakage.
- [ ] Avoid storing master password in app-wide state.
- [ ] Document what remains in process memory during an open session.

Done when:

- [ ] Sensitive handling rules are implemented and documented.

### P5.3 Desktop Interaction Polish

- [ ] Add keyboard shortcut for search.
- [ ] Add keyboard shortcut for save.
- [ ] Add keyboard shortcut for lock.
- [ ] Add keyboard shortcut for create entry.
- [ ] Add keyboard shortcut for copy password.
- [ ] Add menu actions if needed for Linux desktop conventions.
- [ ] Add minimum window size.
- [ ] Verify responsive layout at narrow and wide desktop widths.

Done when:

- [ ] Common workflows are fast without mouse-only navigation.

### P5.4 Release Smoke Tests

- [ ] Build Rust release library.
- [ ] Build Flutter Linux release.
- [ ] Launch packaged app.
- [ ] Open local vault.
- [ ] Browse entry detail.
- [ ] Edit, save, lock, reopen, verify.
- [ ] Test wrong password.
- [ ] Test missing FFI library.

Acceptance:

- [ ] Linux release build passes smoke test.
- [ ] Startup and runtime failures are recoverable and understandable.

## Phase P6: Cross-Platform Expansion

Goal: add Windows and macOS only after Linux workflows are reliable.

### P6.1 Platform Plan

- [ ] Decide platform order: Windows first or macOS first.
- [ ] Define shared library names per platform:
  - Linux: `.so`
  - Windows: `.dll`
  - macOS: `.dylib`
- [ ] Define artifact locations per Flutter platform build.
- [ ] Document toolchain requirements.

### P6.2 Platform Implementations

- [ ] Add platform-specific FFI loading.
- [ ] Verify file picker behavior per platform.
- [ ] Verify clipboard behavior per platform.
- [ ] Verify auto-lock behavior per platform.
- [ ] Verify window close and unsaved-change behavior per platform.

### P6.3 Platform Release Checks

- [ ] Add Windows build instructions.
- [ ] Add macOS build instructions.
- [ ] Add smoke test checklist for each supported platform.
- [ ] Document unsupported platform behavior.

Acceptance:

- [ ] Each supported platform has build steps, bundled FFI artifact, and smoke
      test coverage.

## Recurring Quality Gates

Run backend checks before closing backend or FFI work:

```bash
cd /home/zzy/Desktop/code/KeepassY/keepass-rs
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

Run frontend checks before closing Flutter work:

```bash
cd /home/zzy/Desktop/code/KeepassY/keepassy_flutter
/home/zzy/app/flutter/bin/dart format lib test
/home/zzy/app/flutter/bin/flutter analyze
/home/zzy/app/flutter/bin/flutter test
```

Run end-to-end checks before closing an integrated milestone:

- [ ] Build Rust shared library.
- [ ] Run Flutter app against real FFI.
- [ ] Open a test `.kdbx`.
- [ ] Lock and reopen.
- [ ] Confirm no secrets were printed to logs.

## Pre-WebDAV Local Feature Parity

Goal: make KeePassY's local experience solid before opening the WebDAV
sync work. These are the most conspicuous gaps vs. a standard
desktop KeePass client (KeePassXC/KeePass 2) that can be closed with
moderate effort.

Status: done except Recycle Bin support, which is deferred to a dedicated
future feature because it needs persistent original-group tracking in the
KeePass database.

### Group A — User-facing experience blockers

- [x] **Global search across all groups.** Current search only filters
  entries within the selected group. Need a vault-wide search that can
  find entries by title/username/URL/notes across the entire group tree.
- [x] **Entry sort.** Entry list currently follows the database's raw
  order. Add sort controls (by title, username, modification time)
  so the user can find entries predictably.
- [x] **Auto-lock timer.** The vault should lock after a configurable
  period of user inactivity. This is a security baseline for any
  password manager.

### Group B — Entry operations that feel missing

- [x] **Move entry to another group.** The user can only create an
  entry in one group and can never move it. Need a "move to group"
  action in the entry context or detail pane.
- [x] **Duplicate / clone entry.** Quick way to create a variation of
  an existing entry.
- [x] **Multi-select and bulk delete.** Select several entries in the
  list and delete them at once.

### Group C — KeePass-native fields not yet exposed

- [x] **Entry expiry.** KeePass entries have an `expires` flag and
  expiry date. Expose this in the edit/create UI.
- [x] **Password strength indicator.** Show a strength bar when
  creating/editing/generating a password.
- [x] **Group management.** Create, rename, and delete groups. The
  group tree is currently read-only from the UI side.

### Group D — Database maintenance

- [x] **Change master password.** User cannot change the database
  encryption password from within KeePassY.
- [ ] **Recycle Bin support — deferred.** KeePass has a built-in Recycle Bin
  group. Deletion should move entries there instead of hard-deleting,
  and the UI should offer restore/empty-bin actions. This remains parked
  because reliable restore needs original-group metadata tracked in the
  KeePass database.

### Verification (per group)

- [ ] `flutter analyze` clean, `flutter test` pass.
- [ ] `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace` pass.
- [ ] End-to-end: open a real KDBX, exercise the new feature, save, reopen, verify.

---

## Backlog Parking Lot

Do not start these until the corresponding phase is stable:

- [ ] Import/export helpers.
- [ ] Browser extension integration.
- [ ] Mobile UI.
- [ ] Cloud-provider-specific sync beyond WebDAV.
- [ ] Tauri adapter.
- [ ] Generated bridge migration from JSON FFI.
- [ ] Multi-vault tabs.
- [ ] Full text index with encrypted local cache.
- [ ] TOTP generator (custom-field based).
- [ ] Auto-type / global hotkey for credential fill.
- [ ] Entry icon / favicon download.
- [ ] Entry templates.
- [ ] Entry field references (`{REF:…}`).
