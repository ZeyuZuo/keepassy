# KeePassY Flutter Frontend Roadmap

This roadmap tracks the Flutter desktop frontend. Backend parsing, validation,
storage, WebDAV, and save rules stay in `keepass-rs`; Flutter owns the product
surface, user workflow, platform integration, and adapter calls.

## Current State

Status: scaffold complete.

- Flutter project exists under `keepassy_flutter`.
- App shell, theme, unlock surface, and vault workspace are in place.
- Dart DTOs mirror the Rust serde JSON shape.
- `VaultRepository` defines the frontend/backend boundary.
- `MockVaultRepository` lets UI work continue before real FFI is connected.
- Frontend design and coding rules are documented in `docs/frontend.md`.

## Phase F0: Frontend Foundation

Goal: keep the project easy to extend before real backend integration.

- [x] Create Flutter project.
- [x] Define app theme and visual direction.
- [x] Define feature-first folder structure.
- [x] Add Dart DTOs for opened vault, groups, entries, metadata, and attachments.
- [x] Add `VaultRepository` interface.
- [x] Add mock repository for UI development.
- [x] Add first widget test.

Done when:

- [x] `dart format lib test` passes.
- [x] `flutter analyze` passes.
- [x] `flutter test` passes.

## Phase F1: Read-Only Local Vault UI

Goal: make local vault browsing feel complete before editing is introduced.

- [ ] Replace raw path typing with native file pickers for `.kdbx` and keyfile.
- [ ] Add unlock error states for missing file, wrong password, bad keyfile, and unsupported database.
- [ ] Improve group tree hierarchy with indentation and expand/collapse behavior.
- [ ] Add entry search across title, username, URL, and custom field labels once detail cache exists.
- [ ] Add entry detail loading, empty, error, and retry states.
- [ ] Add copy actions for username, password, URL, and custom fields.
- [ ] Hide sensitive values by default and reset visibility when selection changes.
- [ ] Add auto-lock affordance placeholder, even if the timer is implemented later.

Done when:

- [ ] A real or mock vault can be browsed without layout jumps.
- [ ] Passwords are never visible in list views.
- [ ] Widget tests cover unlock errors, entry selection, and password reveal.

## Phase F2: FFI Adapter Integration

Goal: replace mock data with the Rust `keepass_ffi` library without leaking FFI
details into widgets.

- [ ] Build `keepass_ffi` as a Linux shared library.
- [ ] Decide local library loading path for development and packaged builds.
- [ ] Add `FfiVaultRepository`.
- [ ] Bind `keepassy_open_local`.
- [ ] Bind `keepassy_session_close`.
- [ ] Bind `keepassy_string_free`.
- [ ] Bind `keepassy_group_tree_json`.
- [ ] Bind `keepassy_entries_json`.
- [ ] Bind `keepassy_entry_detail_json`.
- [ ] Convert `KeepassYFfiResult` into typed Dart results and exceptions.
- [ ] Ensure every returned JSON string is freed exactly once.
- [ ] Ensure session handles are closed on lock, app exit, and failed flows.

Done when:

- [ ] The app opens a real local `.kdbx` through FFI.
- [ ] Group and entry browsing use real backend data.
- [ ] FFI memory ownership is covered by focused repository tests where practical.

## Phase F3: Entry Editing and Save

Goal: support the core edit loop while making save explicit and understandable.

- [ ] Add create-entry dialog or side-panel edit mode.
- [ ] Add edit-entry mode for title, username, password, URL, and notes.
- [ ] Add custom field create/update flow.
- [ ] Add delete-entry confirmation flow.
- [ ] Track dirty state from backend responses or repository state.
- [ ] Add save button state: clean, dirty, saving, saved, failed.
- [ ] Prompt before lock/exit when there are unsaved changes.
- [ ] Keep save explicit; do not auto-save after mutations.

Done when:

- [ ] Create, edit, delete, save, close, and reopen works against a real local database.
- [ ] Failed saves do not clear dirty state.
- [ ] Tests cover edit form validation and unsaved-change prompts.

## Phase F4: Attachments, History, and Advanced KeePass Fields

Goal: expose advanced backend features without cluttering the common entry flow.

- [ ] Add attachment metadata list to entry detail.
- [ ] Add attachment export/download action.
- [ ] Add attachment add/replace action.
- [ ] Add attachment remove action after backend FFI exposes it.
- [ ] Add custom field protection toggle if backend semantics are available.
- [ ] Add read-only entry history list.
- [ ] Add history detail comparison view.

Done when:

- [ ] Attachments are handled through explicit user actions.
- [ ] Large attachment bytes are not loaded as part of normal entry detail.
- [ ] History is clearly read-only unless backend restore support is added.

## Phase F5: WebDAV and Sync UX

Goal: make remote vault use clear, conflict-aware, and safe.

- [ ] Add open-remote-vault flow for WebDAV URL and credentials.
- [ ] Keep WebDAV credentials scoped to the current action/session.
- [ ] Display remote metadata such as ETag and Last-Modified when available.
- [ ] Add conflict state for failed `If-Match` saves.
- [ ] Add retry and reload-from-remote actions.
- [ ] Add clear messaging for network timeout, auth failure, and remote overwrite conflicts.

Done when:

- [ ] Remote open and save work through the same repository interface.
- [ ] Conflict handling is visible and does not silently overwrite remote data.

## Phase F6: Desktop Product Hardening

Goal: turn the development UI into a reliable desktop application.

- [ ] Add app icon and desktop metadata.
- [ ] Add keyboard shortcuts for search, lock, save, copy password, and create entry.
- [ ] Add clipboard clear timer for sensitive copied values.
- [ ] Add configurable auto-lock timer.
- [ ] Add window size constraints and responsive layout checks.
- [ ] Add logging policy that never records secrets.
- [ ] Add release build documentation for Linux first.

Done when:

- [ ] The app can be run as a normal desktop application.
- [ ] Sensitive data handling has documented behavior.
- [ ] Release build smoke tests pass.

## Development Rhythm

- Keep UI work against `MockVaultRepository` until the workflow is clear.
- Move to `FfiVaultRepository` as soon as read-only local vault browsing is needed.
- Add tests at the repository boundary before adding broad state management.
- Only add a state-management package when local `StatefulWidget` ownership becomes hard to reason about.
- Run before closing frontend tasks:

```bash
/home/zzy/app/flutter/bin/dart format lib test
/home/zzy/app/flutter/bin/flutter analyze
/home/zzy/app/flutter/bin/flutter test
```
