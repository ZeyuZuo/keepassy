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

Current sprint: Phase P4.8, Recycle Bin.

Local and WebDAV workflows are functionally complete enough for daily use, and
the first UX/UI refactor pass is complete. Settings and local `.kdbx` creation
are implemented. The next meaningful milestone is implementing Recycle Bin
semantics so normal deletes become recoverable.

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

Status: done.

### P1.1 Backend FFI Readiness

- [x] Confirm `keepass_ffi` crate type builds a Linux shared library.
- [x] If missing, set `crate-type = ["cdylib", "rlib"]` for `keepass_ffi`.
- [x] Build debug shared library:
  - `cargo build -p keepass_ffi`
- [x] Build release shared library:
  - `cargo build -p keepass_ffi --release`
- [x] Document expected `.so` output path.
- [x] Confirm these functions exist and are exported:
  - `keepassy_open_local`
  - `keepassy_session_close`
  - `keepassy_string_free`
  - `keepassy_snapshot_json`
  - `keepassy_group_tree_json`
  - `keepassy_entries_json`
  - `keepassy_entry_detail_json`
- [x] Add or update FFI tests for open, group tree, entries, detail, and close.
- [x] Verify FFI error JSON shape for invalid path and wrong password.
- [x] Verify returned JSON strings are always caller-owned.

Done when:

- [x] `libkeepass_ffi.so` can be built locally.
- [x] FFI read-only tests pass.
- [x] The exported function set is documented.

### P1.2 Frontend FFI Infrastructure

- [x] Add `lib/src/repositories/ffi/` or equivalent adapter folder.
- [x] Add Dart FFI type definitions for `KeepassYFfiResult`.
- [x] Bind `keepassy_open_local`.
- [x] Bind `keepassy_session_close`.
- [x] Bind `keepassy_string_free`.
- [x] Bind read-only JSON functions.
- [x] Add a small FFI result helper that:
  - checks `status`
  - decodes UTF-8 JSON
  - frees JSON through `keepassy_string_free`
  - maps errors into `VaultRepositoryException`
- [x] Add session handle wrapper that closes exactly once.
- [x] Add development library path resolution for Linux.
- [x] Add a clear error when the shared library cannot be loaded.

Done when:

- [x] A repository-level smoke test can load the library or fail with a clear
      setup error.
- [x] Widgets still depend only on `VaultRepository`.

### P1.3 Frontend Local File UX

- [x] Add file picker dependency after checking Flutter desktop compatibility.
- [x] Replace raw `.kdbx` path typing with a file picker.
- [x] Keep manual path input available if useful for development.
- [x] Add optional keyfile picker.
- [x] Validate empty path before calling repository.
- [x] Validate empty password before calling repository.
- [x] Show user-safe errors for:
  - file not found
  - wrong password
  - keyfile read failure
  - FFI library load failure
  - unsupported or corrupt database

Done when:

- [x] A user can select a local `.kdbx`, enter a password, and see a clear
      outcome.

### P1.4 Read-Only Vault Browsing

- [x] Replace app-level repository selection with a development switch:
  - mock repository for UI work
  - FFI repository for real data
- [x] Load real snapshot after unlock.
- [x] Render real group tree.
- [x] Render real entry summaries for selected group.
- [x] Load real entry detail on selection.
- [x] Keep password and notes out of summaries.
- [x] Reset password visibility when entry selection changes.
- [x] Add loading, empty, and error states for group and detail panes.
- [x] Close the session on lock.

Done when:

- [x] Flutter opens a real local `.kdbx` and browses groups and entry details.
- [x] Locking the vault closes the FFI session.

### P1.5 Tests and Checks

- [x] Backend: `cargo fmt --all --check`.
- [x] Backend: `cargo clippy --workspace --all-targets -- -D warnings`.
- [x] Backend: `cargo test --workspace`.
- [x] Frontend: `dart format lib test`.
- [x] Frontend: `flutter analyze`.
- [x] Frontend: `flutter test`.
- [x] Add widget tests for unlock validation.
- [x] Add widget tests for entry selection and password reveal.
- [x] Add repository tests for FFI error mapping where practical.

Acceptance:

- [x] Real local vault opens from Flutter.
- [x] Browsing uses real backend data, not mock data.
- [x] User-facing errors are understandable and do not leak secrets.
- [x] FFI memory ownership rules are enforced in code review and tests.

## Phase P2: Local Editing and Explicit Save

Goal: user can modify a local vault, save explicitly, close it, and verify
changes after reopening.

Status: done.

### P2.1 Backend FFI Mutation Surface

- [x] Confirm FFI exposes:
  - `keepassy_create_entry_json`
  - `keepassy_update_entry_json`
  - `keepassy_set_custom_field_json`
  - `keepassy_upsert_attachment_json`
  - `keepassy_save`
- [x] Add FFI wrapper for delete entry if missing.
- [x] Add FFI wrapper for dirty state if needed by UI.
- [x] Add FFI tests for create, update, delete, save, and reopen.
- [x] Add specific error mapping for save failure and conflict.

Done when:

- [x] All core local edit operations needed by the UI are callable through FFI.

### P2.2 Frontend Editing Model

- [x] Decide edit surface:
  - focused dialog for create
  - detail-pane edit mode for update
- [x] Add form models for create and update.
- [x] Validate required fields client-side before repository calls.
- [x] Keep optional field clearing explicit.
- [x] Add password visibility and generate/copy controls in edit mode.
- [x] Add custom field add/edit/remove UI.
- [x] Add delete confirmation.

Done when:

- [x] Create, update, and delete flows are usable against mock data first.

### P2.3 Save and Dirty State UX

- [x] Add dirty state to repository contract or session model.
- [x] Mark UI dirty after create, update, delete, custom field, or attachment mutation.
- [x] Add save button states:
  - clean
  - dirty
  - saving
  - saved
  - failed
- [x] Prompt before lock when dirty.
- [ ] Prompt before app/window close when dirty.
- [x] Keep failed saves dirty.
- [x] Show backup guidance for local saves if backend docs require it.

Done when:

- [x] User cannot accidentally discard unsaved local changes without warning during in-app lock.

### P2.4 Clipboard and Sensitive Actions

- [x] Add copy username.
- [x] Add copy password.
- [x] Add copy URL.
- [x] Add copy custom field.
- [x] Add clipboard clear timer.
- [x] Add visual confirmation without revealing copied secret.
- [x] Never log copied values.

Done when:

- [x] Copy actions are explicit, discoverable, and do not expose values in logs.

### P2.5 End-to-End Validation

- [x] Create entry in Flutter.
- [x] Edit entry in Flutter.
- [x] Delete entry in Flutter.
- [x] Save local vault.
- [x] Lock vault.
- [x] Reopen vault.
- [x] Verify persisted changes.

Acceptance:

- [x] Local editing round trip works on a real `.kdbx`.
- [x] Failed save preserves in-memory changes.
- [x] Tests cover form validation, dirty prompts, and save failure UI.

## Phase P3: Advanced Local Features

Goal: expose useful KeePass features after the common edit/save loop is stable.

Status: done.

### P3.1 Attachments

- [x] Confirm backend core and FFI support attachment metadata.
- [x] Confirm backend core and FFI support reading attachment bytes.
- [x] Add FFI wrapper for attachment removal if missing.
- [x] Add attachment metadata list in entry detail.
- [x] Add export attachment flow.
- [x] Add add or replace attachment flow.
- [x] Add remove attachment flow.
- [x] Keep attachment bytes out of normal entry detail loading.

Done when:

- [x] Attachment bytes are loaded only through explicit user actions.

### P3.2 Entry History

- [x] Confirm FFI exposes entry history list.
- [x] Add FFI wrapper for history detail if missing.
- [x] Add history tab or section in entry detail.
- [x] Add read-only history detail view.
- [x] Add comparison affordance if it remains simple.
- [x] Do not add restore until backend explicitly supports it.

Done when:

- [x] History is visible and clearly read-only.

### P3.3 Custom and Protected Fields

- [x] Display custom fields separately from standard fields.
- [x] Add protected/unprotected field indicator if backend exposes it.
- [x] Add custom field protect toggle if backend supports it.
- [x] Reject standard KeePass field names in UI before repository call.

Done when:

- [x] Custom field behavior matches backend validation and error messages.

### P3.4 Password Generator

- [x] Decide whether password generation is frontend-owned.
- [x] Add generator policy options:
  - length
  - lowercase
  - uppercase
  - digits
  - symbols
  - ambiguous character avoidance
- [x] Add generated password preview with explicit accept action.
- [x] Add tests for generator constraints.

Done when:

- [x] Generator can fill create/edit password fields without changing backend
      business rules.

Acceptance:

- [x] Advanced features do not crowd the primary entry detail workflow.
- [x] Tests cover attachment and history error states.

## Phase P4: WebDAV End-to-End

Goal: open and save remote vaults with visible conflict handling.

### P4.1 Backend WebDAV FFI

- [x] Add `keepassy_open_webdav` or equivalent FFI wrapper.
- [x] Define JSON request shape for WebDAV URL and credentials.
- [x] Support optional keyfile path or bytes consistently with local open.
- [x] Ensure credentials do not appear in debug output or errors.
- [x] Expose remote metadata in snapshot.
- [x] Expose conflict errors distinctly enough for UI.
- [x] Add FFI tests with mocked HTTP/WebDAV server where practical.

Done when:

- [x] Flutter can call WebDAV open without adding WebDAV logic to Dart.

### P4.2 Frontend Remote Open Flow

- [x] Add source selector:
  - local file
  - WebDAV
- [x] Add WebDAV URL field.
- [x] Add WebDAV username field.
- [x] Add WebDAV password field.
- [x] Add optional keyfile picker for remote vault.
- [x] Validate URL format before repository call.
- [x] Keep credentials scoped to the unlock action/session.

Done when:

- [x] Remote unlock UI is clear and separate from local file selection.

### P4.3 Sync and Conflict UX

- [x] Display remote metadata when available:
  - ETag
  - Last-Modified
  - Content-Length
- [x] Add save conflict state.
- [x] Add reload from remote action.
- [x] Add retry save action.
- [x] Add cancel/keep local edits action.
- [x] Never silently overwrite remote conflicts.

Done when:

- [x] Users understand whether a save succeeded, failed, or conflicted.

Acceptance:

- [x] User can open and save a WebDAV vault.
- [x] ETag conflict does not overwrite server data.
- [x] Network, auth, and conflict failures have separate user messages.

## Phase P4.5: Frontend UX/UI Refactor

Goal: keep the current functionality intact while making the app more
beautiful, predictable, and efficient to use before release packaging starts.

Status: done.

Design direction:

- Build a calm, professional desktop workspace rather than a marketing-style
  page.
- Prefer clear regions, dividers, toolbars, menus, and status surfaces over
  stacked cards.
- Keep information dense but readable.
- Use one primary accent for selection and primary actions.
- Use red only for destructive or conflict states.
- Keep all widgets behind `VaultRepository`; this phase must not move business
  logic into Flutter widgets.

### P4.5.1 Unlock Flow Redesign

- [x] Keep the Local file / WebDAV source selector.
- [x] Separate source credentials from database credentials:
  - Local file path or WebDAV URL/auth fields.
  - Master password.
  - Optional keyfile.
- [x] Make WebDAV password visually distinct from master password.
- [x] Keep manual local file path input and file picker.
- [x] Keep optional keyfile picker for both local and WebDAV.
- [x] Improve empty field and invalid URL validation messages.
- [x] Keep `Unlock` as the single primary action.
- [x] Avoid product-marketing copy; use concise operational labels.
- [x] Add or update widget tests for source switching and validation.

Done when:

- [x] A user can tell whether they are entering server credentials or KDBX
      credentials without reading documentation.

### P4.5.2 Vault App Bar and Global Actions

- [x] Reduce the top app bar to global vault context and high-priority actions:
  - vault source
  - saved/dirty/saving/error/conflict status
  - Save
  - Lock
  - More menu
- [x] Move low-frequency global actions into the More menu:
  - Change master password
  - Auto-lock settings
  - Remote metadata
  - Vault/source info if useful
- [x] Keep Save disabled or visually quiet when clean.
- [x] Make unsaved changes visibly persistent until saved or discarded.
- [x] Show remote conflict as a persistent state, not only a one-time dialog.
- [x] Keep Lock visible and predictable.

Done when:

- [x] The app bar no longer mixes current-entry actions with whole-vault
      actions.

### P4.5.3 Three-Pane Workspace Layout

- [x] Preserve the left groups / middle entries / right detail model.
- [x] Clarify each pane's responsibility:
  - Groups: group tree and group management.
  - Entries: search, sort, multi-select, and entry list.
  - Detail: selected entry viewing and editing.
- [x] Move group actions close to the group tree instead of the global app bar.
- [x] Move entry-list actions close to the entry list:
  - create entry
  - sort
  - search scope
  - bulk delete
- [x] Keep multi-select state visually obvious.
- [x] Verify compact/narrow layout still preserves all workflows.

Done when:

- [x] A user can infer which object each button affects from its location.

### P4.5.4 Entry Detail and Edit Mode

- [x] Put selected-entry actions in the detail header:
  - Edit
  - Copy password
  - Move
  - Duplicate
  - Delete
  - History
- [x] Keep destructive actions visually secondary until confirmation.
- [x] Reorder detail sections:
  - header and identity
  - standard fields
  - custom fields
  - attachments
  - history
- [x] Preserve copy controls for username, password, URL, and custom fields.
- [x] Keep protected fields visually masked but copyable where current behavior
      allows it.
- [x] In edit mode, keep the same section order and replace values with inputs
      rather than visually rebuilding the whole page.
- [x] Keep `Cancel` and `Save changes` fixed near the edit context.
- [x] Preserve create, edit, delete, move, duplicate, expiry, notes, custom
      fields, attachments, and history behavior.

Done when:

- [x] Entry operations feel attached to the selected entry, not to the whole
      application.

### P4.5.5 Save, Conflict, and Error States

- [x] Define one visual state model:
  - Saved
  - Unsaved changes
  - Saving
  - Save failed
  - Remote conflict
- [x] Keep failed saves dirty.
- [x] Keep conflict local edits open unless the user explicitly reopens remote.
- [x] Make retry save available through the normal Save action.
- [x] Keep `Reopen remote` available from conflict UI.
- [x] Keep `Keep local edits` available from conflict UI.
- [x] Ensure errors do not expose master password, keyfile contents, or WebDAV
      password.

Done when:

- [x] Users can understand whether changes are saved, unsaved, failed, or
      conflicted at a glance.

### P4.5.6 Visual System Cleanup

- [x] Create or consolidate shared spacing, radius, and border conventions.
- [x] Use restrained pane backgrounds and dividers.
- [x] Avoid nested cards and card-heavy layouts.
- [x] Standardize icon button sizes and tooltip language.
- [x] Standardize section headings and field rows.
- [x] Standardize empty, loading, and error states.
- [x] Make text fit at narrow and wide desktop widths.
- [x] Ensure button labels do not overflow.
- [x] Keep the palette from becoming one-note or overly decorative.
- [x] Verify both light and dark modes if the theme supports them.

Done when:

- [x] The app feels like one design system instead of separate feature patches.

### P4.5.7 Keyboard and Interaction Polish

- [x] Keep or add shortcuts for:
  - search
  - save
  - lock
  - create entry
  - copy password
- [x] Ensure Enter submits only the intended local form.
- [x] Ensure Escape closes dialogs or cancels edit mode where appropriate.
- [x] Ensure focus order follows the visible workflow.
- [ ] Add minimum window size if the platform shell supports it.

Done when:

- [x] Common workflows can be completed without mouse-only navigation.

### P4.5.8 Refactor Boundaries

- [x] Extract reusable UI pieces only when duplication is real:
  - status indicator
  - field row
  - pane header
  - action toolbar
  - confirm dialog helpers
- [x] Keep `VaultPage` readable by moving purely visual subwidgets out where
      useful.
- [x] Do not change repository method semantics.
- [x] Do not change Rust FFI or core behavior unless a UI bug exposes a real
      contract gap.
- [x] Do not remove mock repository coverage.

Done when:

- [x] The UI code is easier to modify without touching backend or repository
      logic.

### P4.5.9 Verification

- [x] `dart format lib test` clean.
- [x] `flutter analyze` clean.
- [x] `flutter test` pass.
- [x] Manual local smoke test:
  - open local KDBX
  - browse entry
  - edit and save
  - lock and reopen
  - verify changes
- [x] Manual WebDAV smoke test:
  - open WebDAV KDBX
  - inspect metadata
  - edit and save
  - reopen and verify changes
- [x] Manual dirty/discard test:
  - edit without saving
  - lock
  - confirm discard prompt is clear
- [ ] Manual conflict UX review if a server with ETag conflict support is
      available; otherwise rely on existing FFI mock WebDAV conflict tests.

Acceptance:

- [x] All existing features remain reachable.
- [x] Global actions, group actions, entry-list actions, and selected-entry
      actions are visually separated.
- [x] Local and WebDAV unlock flows are clear.
- [x] Saved, dirty, failed, and conflict states are obvious.
- [x] The app is visually calmer and more consistent without reducing
      information density.
- [x] No backend, FFI, or repository contract regressions.

## Phase P4.6: Settings Foundation

Status: mostly done.

Goal: add practical settings before adding more vault workflows, so user
preferences and operational controls have a stable home.

### P4.6.1 Settings Surface

- [x] Add a Settings dialog or page reachable from the vault More menu and
      unlock surface if useful.
- [x] Split settings into clear sections:
  - App
  - Security
- [x] Keep backend / FFI internals out of the normal settings surface.
- [x] Keep settings UI behind Flutter; do not move KeePass logic into widgets.
- [x] Persist app-level settings locally without storing secrets.
- [x] Keep vault-specific facts read-only unless backend support exists.

Done when:

- [x] Users have one obvious place to change app behavior.

### P4.6.2 App Settings

- [x] Theme mode:
  - system
  - light
  - dark
- [ ] Compact layout toggle or density choice if it remains visually useful.
- [x] Default unlock source:
  - local file
  - WebDAV
- [x] Remember last non-secret local path / WebDAV URL if enabled.
- [x] Do not remember master password, keyfile contents, or WebDAV password.

Done when:

- [x] App preferences persist across restarts without leaking credentials.

### P4.6.3 Security Settings

- [x] Configurable auto-lock timeout.
- [x] Configurable clipboard clear timeout.
- [ ] Option to clear clipboard immediately on lock.
- [ ] Option to hide or show protected custom fields by default if useful.
- [ ] Document what sensitive data remains in memory during an open session.

Done when:

- [x] Core security-sensitive behavior is explicit and user-configurable.

### P4.6.4 Vault and Backend Status

- [x] Show current vault source.
- [x] Show whether the vault is local or WebDAV.
- [x] Show remote metadata when present:
  - ETag
  - Last-Modified
  - Content-Length
- [x] Do not expose FFI library details in normal user settings.
- [ ] Add diagnostics-only FFI load path if needed for support.
- [ ] Show backend/FFI version if added.
- [ ] Add startup check for missing or incompatible FFI library.

Done when:

- [x] A user can understand what vault source and sync state are active.
- [ ] Startup diagnostics explain why loading failed.

### P4.6.5 Verification

- [x] `dart format lib test` clean.
- [x] `flutter analyze` clean.
- [x] `flutter test` pass.
- [ ] Manual check: settings persist after restart.
- [ ] Manual check: no secrets are written to settings storage.

Acceptance:

- [x] Settings cover the main app/security knobs needed for daily use.
- [x] Settings do not store secrets.
- [x] Existing local and WebDAV workflows keep working.

## Phase P4.7: Create New KDBX

Status: done.

Goal: let KeePassY create a brand-new KeePass database instead of only opening
existing files.

### P4.7.1 Backend Create Database API

- [x] Add core API to create an empty KeePass database.
- [x] Support master password.
- [x] Support optional keyfile.
- [x] Support keyfile-only vault creation.
- [x] Decide default database name / root group name.
- [x] Save the new database atomically to a local path.
- [x] Avoid leaving partial/corrupt files on failure.
- [x] Avoid overwriting an existing vault file.
- [x] Add Rust tests for create, reopen, duplicate-path failure, and
      keyfile-only behavior.

Done when:

- [x] Core can create a new KDBX and reopen it with the chosen credentials.

### P4.7.2 FFI and Repository

- [x] Add FFI wrapper for create-local-database.
- [x] Define request JSON:
  - path
  - master password
  - optional keyfile path
- [x] Return an opened session snapshot after create.
- [x] Add Dart repository method for create local vault.
- [x] Add mock repository implementation.
- [x] Add FFI tests for success and invalid request errors.

Done when:

- [x] Flutter can create and immediately open a new local KDBX through
      `VaultRepository`.

### P4.7.3 Frontend Create Flow

- [x] Add `Create vault` action on unlock surface.
- [x] Let user choose save path with file picker.
- [x] Avoid free-form relative path entry for the vault file.
- [x] Validate extension or clearly explain `.kdbx`.
- [x] Ask for master password and confirmation when password is used.
- [x] Allow password-only, keyfile-only, or password-plus-keyfile creation.
- [x] Show password strength for the new master password.
- [x] Support selecting an existing keyfile.
- [x] Support creating a new random keyfile.
- [x] Create vault and navigate into the empty vault.
- [x] Show clear errors for invalid path, existing file, password mismatch, and
      write failure.

Done when:

- [x] A first-time user can create a database without using another KeePass
      app.

### P4.7.4 Verification

- [x] `cargo fmt` clean.
- [x] `cargo test -p keepass_core -p keepass_ffi` pass.
- [x] `dart format lib test` clean.
- [x] `flutter analyze` clean.
- [x] `flutter test` pass.
- [x] `cargo build -p keepass_ffi` pass.
- [ ] Manual test: create local vault, add entry, save, lock, reopen, verify.
- [ ] Manual test: password mismatch blocks create.
- [ ] Manual test: keyfile-only create, save, lock, reopen.
- [ ] Manual test: failed write gives a clear error.

Acceptance:

- [x] KeePassY can create a usable local `.kdbx`.
- [x] Created vaults can be reopened by KeePassY.
- [ ] External KeePass app compatibility smoke test before release.
- [x] Failed creates do not silently produce corrupt databases.

## Phase P4.8: Recycle Bin

Goal: replace destructive entry deletion with KeePass-compatible Recycle Bin
semantics and restore support.

### P4.8.1 Backend Recycle Bin Model

- [ ] Inspect KeePass database fields for Recycle Bin group support.
- [ ] Decide how to create or identify the Recycle Bin group.
- [ ] Define original-location metadata strategy for restore:
  - custom data on entry
  - custom field
  - database-level metadata
  - other KeePass-compatible option
- [ ] Ensure metadata does not collide with user fields.
- [ ] Add API to move entry to Recycle Bin.
- [ ] Add API to restore entry to original group or fallback group.
- [ ] Add API to permanently delete recycled entry.
- [ ] Add API to empty Recycle Bin.
- [ ] Decide whether group deletion enters Recycle Bin or remains hard-delete
      for the first version.

Done when:

- [ ] Entry deletion is recoverable and original group restore is reliable.

### P4.8.2 FFI and Repository

- [ ] Add FFI wrappers for recycle, restore, permanent delete, and empty bin.
- [ ] Add Dart repository methods.
- [ ] Update mock repository behavior.
- [ ] Ensure save/dirty semantics match other mutations.
- [ ] Add tests for restore and empty-bin behavior.

Done when:

- [ ] Flutter can manage recycled entries without bypassing Rust core logic.

### P4.8.3 Frontend Recycle Bin UX

- [ ] Show Recycle Bin in the group tree with a recognizable icon.
- [ ] Rename destructive entry delete to move to Recycle Bin where applicable.
- [ ] Add restore action for entries in Recycle Bin.
- [ ] Add permanent delete action for entries in Recycle Bin.
- [ ] Add empty Recycle Bin action with strong confirmation.
- [ ] Keep bulk delete recoverable by moving selected entries to Recycle Bin.
- [ ] Clearly distinguish recoverable delete from permanent delete.

Done when:

- [ ] Users can recover accidentally deleted entries.

### P4.8.4 Verification

- [ ] `cargo fmt --all --check`.
- [ ] `cargo clippy --workspace --all-targets -- -D warnings`.
- [ ] `cargo test --workspace`.
- [ ] `dart format lib test` clean.
- [ ] `flutter analyze` clean.
- [ ] `flutter test` pass.
- [ ] Manual test: delete entry, save, reopen, restore, save, reopen, verify.
- [ ] Manual test: empty Recycle Bin, save, reopen, verify permanent removal.

Acceptance:

- [ ] Normal delete no longer hard-deletes entries.
- [ ] Restore returns entries to their original group when possible.
- [ ] Permanent deletion is explicit and confirmed.
- [ ] Recycle Bin behavior is documented.

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
