# KeePassY Project Roadmap

Detailed execution tasks are tracked in `docs/todo.md`.

KeePassY is a Flutter desktop KeePass client backed by a Rust core. The Rust
workspace owns KeePass data, storage, validation, WebDAV, and FFI. Flutter owns
the desktop product surface and calls Rust through a repository adapter.

## Architecture Direction

Dependency direction:

```text
Flutter UI -> Dart repository -> Rust FFI adapter -> keepass_core -> storage/KeePass crate
```

Rules:

- `keepass_core` stays UI-independent.
- `keepass_ffi` stays a thin adapter over `keepass_core`.
- Flutter widgets depend on `VaultRepository`, not `dart:ffi`.
- Cross-language data uses explicit JSON DTOs until there is a strong reason to introduce generated bridge types.
- Save remains explicit. Mutations mark state dirty but do not persist automatically.

## Current State

Backend:

- Rust workspace exists under `keepass-rs`.
- Local `.kdbx` open, tree, entries, and details are implemented.
- WebDAV open/save and conflict detection are implemented.
- Entry create, update, delete, move, duplicate support, save, keyfile, custom
  fields, attachments, history, expiry, groups, and change-password support
  exist in core/FFI as needed by Flutter.
- Plain C ABI adapter exists for local and WebDAV session workflows and JSON
  responses.

Frontend:

- Flutter project exists under `keepassy_flutter`.
- Unlock supports local file and WebDAV sources.
- Vault browsing, editing, attachments, custom fields, history, group
  management, save/dirty state, auto-lock, clipboard clearing, and WebDAV
  conflict UX are implemented through `VaultRepository`.
- First UX/UI refactor pass is complete: clearer unlock flow, simplified vault
  app bar, three-pane workspace, detail-pane actions, status chip, and keyboard
  shortcuts.

## Phase P0: Repository and Documentation Baseline

Goal: make project structure and responsibilities obvious.

- [x] Keep backend in `keepass-rs`.
- [x] Keep frontend in `keepassy_flutter`.
- [x] Document backend architecture.
- [x] Document frontend design and coding rules.
- [x] Add frontend roadmap.
- [x] Add project roadmap.

Done when:

- [x] A new contributor can identify where backend, frontend, and adapter work belongs.

## Phase P1: Local Read-Only End-to-End

Goal: open and browse a real local KeePass database from Flutter.

Backend tasks:

- [x] Confirm `keepass_ffi` exposes every read-only function needed by Flutter.
- [x] Produce a Linux shared library artifact for `keepass_ffi`.
- [x] Document development build command and output path.
- [x] Add FFI smoke test or small C/Dart harness if practical.

Frontend tasks:

- [x] Add native file picker for `.kdbx` and optional keyfile.
- [x] Implement `FfiVaultRepository`.
- [x] Map Rust FFI errors into user-safe frontend errors.
- [x] Open local vault, read group tree, list entries, and show entry detail from real data.

Acceptance:

- [x] Flutter opens a real local `.kdbx`.
- [x] User can browse groups and details without mock data.
- [x] Locking the vault closes the Rust session.

## Phase P2: Local Editing and Explicit Save

Goal: support the main password-manager workflow for local files.

Backend tasks:

- [x] Ensure FFI exposes create, update, delete, save, custom field, and attachment operations needed by UI.
- [x] Add missing FFI wrappers where core already has support.
- [x] Keep save error messages specific enough for UI decisions.

Frontend tasks:

- [x] Add create/edit/delete entry flows.
- [x] Add dirty state and save status.
- [x] Add unsaved-change prompts for lock.
- [ ] Add unsaved-change prompts for app close.
- [x] Add copy actions and clipboard clear timer.

Acceptance:

- [x] User can create, edit, delete, save, close, reopen, and verify changes.
- [x] Failed save does not lose in-memory edits.
- [x] Password values remain hidden outside explicit reveal/copy actions.

## Phase P3: Advanced Local Features

Goal: expose KeePass features that matter after the basic edit loop is stable.

Backend tasks:

- [x] Close any FFI gaps for attachment removal and history detail.
- [x] Keep large attachment bytes behind separate calls.
- [x] Add tests for FFI JSON shape for advanced calls.

Frontend tasks:

- [x] Add attachment list, export, add/replace, and remove flows.
- [x] Add custom field management.
- [x] Add history list and read-only history detail.
- [x] Add password generator if it can stay frontend-owned without weakening backend rules.

Acceptance:

- [x] Advanced features are reachable from entry detail without crowding the primary fields.
- [x] Attachment bytes are loaded only when the user requests them.

## Pre-WebDAV Local Parity

Goal: close the most noticeable gaps vs. a standard desktop KeePass
client before introducing remote-sync complexity.

See `docs/todo.md` → Pre-WebDAV Local Feature Parity for the checklist.

Done when: global search, entry sort, auto-lock, move/duplicate
entries, group management, entry expiry, and password strength are all
usable against a real local KDBX.

Status: done except Recycle Bin support, which is deferred to a dedicated
future feature because it requires persistent original-group tracking inside
the KeePass database.

## Phase P4: WebDAV End-to-End

Goal: support remote vault open and conflict-safe save.

Backend tasks:

- [x] Expose WebDAV open through FFI.
- [x] Expose WebDAV save conflict details through stable error mapping.
- [x] Test ETag conflict handling against a local test server or mock server.

Frontend tasks:

- [x] Add WebDAV open flow.
- [x] Add remote metadata display.
- [x] Add conflict UI for remote save failures.
- [x] Add retry, reload, and cancel choices for remote conflicts.

Acceptance:

- [x] User can open and save a WebDAV vault.
- [x] Remote conflicts never silently overwrite server data.

## Phase P4.5: Frontend UX/UI Refactor

Goal: preserve the complete local and WebDAV feature set while improving the
Flutter app's visual hierarchy, button placement, and day-to-day interaction
logic before release packaging.

Frontend tasks:

- [x] Redesign the unlock flow so Local file and WebDAV are clear source modes.
- [x] Reduce the vault app bar to global actions and move low-frequency actions
      into menus.
- [x] Clarify the three-pane workspace: groups, entries, detail.
- [x] Move selected-entry actions into the detail header.
- [x] Make saved, dirty, failed, and conflict states persistent and easy to
      understand.
- [x] Consolidate shared visual components, spacing, and icon button rules.
- [x] Preserve all current repository, FFI, local, and WebDAV behavior.

Acceptance:

- [x] All existing features remain reachable.
- [x] Button placement matches the object being acted on.
- [x] Local and WebDAV unlock flows are visually distinct.
- [x] The app feels calmer and more consistent without losing information
      density.

## Phase P4.6: Settings Foundation

Status: mostly done.

Goal: add practical app, security, vault, and backend settings before adding
more workflows.

- [x] Add a Settings surface reachable from the app.
- [x] Persist non-secret app preferences.
- [x] Add theme, default source, auto-lock, and clipboard timeout
      controls.
- [ ] Add density controls.
- [x] Show vault source and WebDAV metadata where relevant.
- [x] Keep backend/FFI internals out of the normal user settings surface.
- [ ] Add startup checks for missing or incompatible FFI library.

Acceptance:

- [x] Main app/security preferences persist without storing secrets.
- [x] Users can inspect active vault and sync status.
- [ ] Startup diagnostics cover missing or incompatible FFI libraries.

## Phase P4.7: Create New KDBX

Status: done.

Goal: let KeePassY create a new local KeePass database and immediately open it.

- [x] Add Rust core API to create and save an empty database.
- [x] Expose create-local-vault through FFI and `VaultRepository`.
- [x] Add Flutter create-vault flow with save-location picker, password
      confirmation, strength feedback, and optional keyfile.
- [x] Support password-only, keyfile-only, and password-plus-keyfile creation.
- [x] Support creating a new random keyfile from the create flow.
- [x] Ensure failed creates do not leave corrupt files or overwrite existing
      vault files.

Acceptance:

- [x] A new `.kdbx` can be created and immediately opened.
- [x] Created `.kdbx` files can be reopened by KeePassY with the chosen
      credentials.
- [ ] Run an external KeePass compatibility smoke test before release.

## Phase P4.8: Recycle Bin

Goal: make delete recoverable through KeePass-compatible Recycle Bin semantics.

- [ ] Identify or create the Recycle Bin group.
- [ ] Track original entry group metadata for reliable restore.
- [ ] Move normal deletes to Recycle Bin instead of hard-deleting.
- [ ] Add restore, permanent delete, and empty-bin actions.
- [ ] Add backend, FFI, repository, and UI tests.

Acceptance:

- [ ] Accidentally deleted entries can be restored to their original group when
      possible.
- [ ] Permanent deletion is explicit and confirmed.

## Phase P5: Desktop Release Quality

Goal: make KeePassY practical to run outside development.

Backend tasks:

- [ ] Define release artifact layout for Rust shared library.
- [ ] Add version reporting for backend and FFI.
- [ ] Audit error messages for secret leakage.

Frontend tasks:

- [ ] Package Linux desktop build with the Rust shared library.
- [ ] Add app icon, desktop metadata, and startup checks.
- [ ] Add auto-lock, clipboard timeout, and keyboard shortcuts.
- [ ] Add app-level error boundary and recovery options.

Acceptance:

- [ ] A release build can be installed and launched on Linux.
- [ ] App startup verifies the bundled FFI library is loadable.
- [ ] Basic local workflows pass release smoke testing.

## Phase P6: Cross-Platform Expansion

Goal: expand only after Linux local and WebDAV workflows are reliable.

- [ ] Decide target order for Windows and macOS.
- [ ] Add platform-specific FFI library loading.
- [ ] Add packaging steps for each target platform.
- [ ] Verify file picker, clipboard, auto-lock, and window behavior per platform.

Acceptance:

- [ ] Each supported platform has documented build and smoke-test steps.

## Recommended Next Sprint

Sprint goal: Recycle Bin.

1. Identify or create the KeePass-compatible Recycle Bin group.
2. Move normal deletes to Recycle Bin instead of hard-deleting.
3. Track enough original group metadata to make restore reliable.
4. Add restore, permanent delete, and empty-bin actions.
5. Run local create/open/save/reopen smoke tests, including keyfile-only vaults.

Run backend checks:

```bash
cd /home/zzy/Desktop/code/KeepassY/keepass-rs
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

Run frontend checks:

```bash
cd /home/zzy/Desktop/code/KeepassY/keepassy_flutter
/home/zzy/app/flutter/bin/dart format lib test
/home/zzy/app/flutter/bin/flutter analyze
/home/zzy/app/flutter/bin/flutter test
```
