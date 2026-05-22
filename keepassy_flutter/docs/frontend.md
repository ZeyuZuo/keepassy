# KeePassY Flutter Frontend

See `docs/roadmap.md` for the frontend implementation roadmap and
`../../docs/project-roadmap.md` for the full project plan.

## Product Direction

Visual thesis: a quiet desktop vault workbench with warm neutral surfaces, precise spacing, and a user-selectable Material 3 accent color.

Current Material 3 redesign reference:
`docs/assets/material3-redesign-reference.png`.

Content plan:

- Unlock: local `.kdbx` path, master password, optional keyfile, clear unlock status.
- Vault workspace: group tree, entry list, detail inspector, save/lock/create commands.
- Editing: entry create/update flows will use focused dialogs or right-side edit mode, not separate full-page forms.
- Sync: WebDAV metadata and conflict messages should appear near save/sync controls once the backend adapter exposes them.

Interaction thesis:

- Unlock is a short, direct flow with password visibility and keyfile expansion.
- The vault workspace is a stable three-pane desktop layout; compact widths stack panes without changing data ownership.
- Sensitive values are hidden by default and revealed only by direct action in the detail pane.

## Backend Boundary

- Flutter talks to a `VaultRepository` interface. Widgets must not call FFI directly.
- `keepass_core` remains the source of truth for KeePass parsing, validation, saving, WebDAV, history, and attachments.
- Dart models mirror Rust serde JSON names: `group_tree`, `last_modified`, `content_length`, and the entry fields from `keepass_core::dto`.
- The current `MockVaultRepository` is a UI scaffold. Replace it with an FFI implementation that wraps `keepass_ffi` and preserves the same interface.
- Entry summaries must not include passwords or notes. Fetch `EntryDetail` only for the selected entry.

## Page Design Rules

- Use a dense app surface, not a landing page, once a vault is open.
- Keep navigation left, entry lists center, sensitive details right on desktop.
- Use cards only where the frame is the interaction, such as the unlock form.
- Icon buttons need tooltips. Text buttons are for explicit commands only.
- Use Material icons before custom drawing.
- Preserve stable panel widths and list row heights so loading and selection do not shift layout.
- Avoid decorative gradients and oversized hero treatment in the operational workspace.

## Coding Rules

- Feature-first structure under `lib/src/features/<feature>`.
- Shared DTOs live in `lib/src/models`; backend access lives in `lib/src/repositories`.
- Keep widgets small enough that state ownership is obvious.
- Use immutable model classes and explicit JSON factories.
- Do not add a state-management package until state crosses multiple feature owners.
- Do not store master passwords in app-wide state. The native session owns the
  active save credentials after unlock.
- Prefer focused widget tests for route starts, repository behavior, and sensitive-value visibility.

## Next Integration Step

Build `FfiVaultRepository` with `dart:ffi`, map `KeepassYFfiResult` to repository exceptions, and ensure every returned JSON string is released through `keepassy_string_free`.
