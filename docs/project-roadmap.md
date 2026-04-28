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
- WebDAV read and save foundation exists.
- Entry create, update, delete, save, keyfile, custom fields, attachments, and history support exist in core.
- Plain C ABI adapter exists for local session workflows and JSON responses.

Frontend:

- Flutter project exists under `keepassy_flutter`.
- Unlock and vault browsing surfaces are scaffolded.
- Dart DTOs and `VaultRepository` boundary exist.
- UI currently uses mock data.

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

- [ ] Confirm `keepass_ffi` exposes every read-only function needed by Flutter.
- [ ] Produce a Linux shared library artifact for `keepass_ffi`.
- [ ] Document development build command and output path.
- [ ] Add FFI smoke test or small C/Dart harness if practical.

Frontend tasks:

- [ ] Add native file picker for `.kdbx` and optional keyfile.
- [ ] Implement `FfiVaultRepository`.
- [ ] Map Rust FFI errors into user-safe frontend errors.
- [ ] Open local vault, read group tree, list entries, and show entry detail from real data.

Acceptance:

- [ ] Flutter opens a real local `.kdbx`.
- [ ] User can browse groups and details without mock data.
- [ ] Locking the vault closes the Rust session.

## Phase P2: Local Editing and Explicit Save

Goal: support the main password-manager workflow for local files.

Backend tasks:

- [ ] Ensure FFI exposes create, update, delete, save, custom field, and attachment operations needed by UI.
- [ ] Add missing FFI wrappers where core already has support.
- [ ] Keep save error messages specific enough for UI decisions.

Frontend tasks:

- [ ] Add create/edit/delete entry flows.
- [ ] Add dirty state and save status.
- [ ] Add unsaved-change prompts for lock and app close.
- [ ] Add copy actions and clipboard clear timer.

Acceptance:

- [ ] User can create, edit, delete, save, close, reopen, and verify changes.
- [ ] Failed save does not lose in-memory edits.
- [ ] Password values remain hidden outside explicit reveal/copy actions.

## Phase P3: Advanced Local Features

Goal: expose KeePass features that matter after the basic edit loop is stable.

Backend tasks:

- [ ] Close any FFI gaps for attachment removal and history detail.
- [ ] Keep large attachment bytes behind separate calls.
- [ ] Add tests for FFI JSON shape for advanced calls.

Frontend tasks:

- [ ] Add attachment list, export, add/replace, and remove flows.
- [ ] Add custom field management.
- [ ] Add history list and read-only history detail.
- [ ] Add password generator if it can stay frontend-owned without weakening backend rules.

Acceptance:

- [ ] Advanced features are reachable from entry detail without crowding the primary fields.
- [ ] Attachment bytes are loaded only when the user requests them.

## Pre-WebDAV Local Parity

Goal: close the most noticeable gaps vs. a standard desktop KeePass
client before introducing remote-sync complexity.

See `docs/todo.md` → Pre-WebDAV Local Feature Parity for the checklist.

Done when: global search, entry sort, auto-lock, move/duplicate
entries, group management, entry expiry, and password strength are all
usable against a real local KDBX.

## Phase P4: WebDAV End-to-End

Goal: support remote vault open and conflict-safe save.

Backend tasks:

- [ ] Expose WebDAV open through FFI.
- [ ] Expose WebDAV save conflict details through stable error mapping.
- [ ] Test ETag conflict handling against a local test server or mock server.

Frontend tasks:

- [ ] Add WebDAV open flow.
- [ ] Add remote metadata display.
- [ ] Add conflict UI for remote save failures.
- [ ] Add retry, reload, and cancel choices for remote conflicts.

Acceptance:

- [ ] User can open and save a WebDAV vault.
- [ ] Remote conflicts never silently overwrite server data.

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

Sprint goal: local read-only end-to-end.

1. Build `keepass_ffi` as a Linux `.so`.
2. Add `FfiVaultRepository` in Flutter.
3. Bind open, close, free string, group tree, entries, and entry detail.
4. Replace mock repository in the app entry behind a simple development switch.
5. Open a real `.kdbx` from Flutter and browse it.

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
