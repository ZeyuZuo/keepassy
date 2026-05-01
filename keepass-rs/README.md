# keepass-rs

Rust backend core for a future KeePass desktop client.

This repository currently contains backend-only code. It does not create or depend on Tauri, Flutter, or any UI project.

## Goals

- Open local `.kdbx` files.
- Download and open remote `.kdbx` files through WebDAV-compatible HTTP endpoints.
- Unlock databases with a master password.
- Read the group tree, entry lists, and entry details.
- Keep the backend UI-independent, testable, and reusable.
- Prepare the public API for future Tauri commands or Flutter FFI wrappers.

## Workspace

- `crates/keepass_core`: business logic, storage abstraction, KeePass parsing, DTOs.
- `crates/keepass_cli`: debugging CLI that calls `keepass_core`.
- `crates/keepass_ffi`: plain C ABI adapter for future desktop shells.
- `docs/architecture.md`: layering and future desktop integration notes.
- `docs/roadmap.md`: staged implementation plan.

## CLI Examples

Use `KEEPASS_RS_PASSWORD` to avoid passing the master password as a command argument. If it is not set, the CLI prompts interactively.

```bash
cargo run -p keepass_cli -- local tree --file ./Database.kdbx
cargo run -p keepass_cli -- local entries --file ./Database.kdbx --group <UUID>
cargo run -p keepass_cli -- local show --file ./Database.kdbx --entry <UUID>
cargo run -p keepass_cli -- local tree --file ./Database.kdbx --keyfile ./Database.key
cargo run -p keepass_cli -- webdav tree --url https://example.com/remote.php/dav/files/user/db.kdbx
```

Group and entry identifiers are KeePass native UUIDs (e.g. `a1b2c3d4e5f6abcd7890ef1234567890`). Use `local tree` to discover UUIDs.
Add `--keyfile <path>` to local or WebDAV tree commands when the database requires password-plus-keyfile unlock.

## Development

```bash
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

### Integration tests

Integration tests are opt-in — they are skipped unless environment variables are provided. This keeps the test suite safe by default and avoids requiring a real `.kdbx` file in the repository.

```bash
KEEPASS_RS_TEST_KDBX=./my-test-vault.kdbx \
KEEPASS_RS_TEST_PASSWORD=my-password \
cargo test --workspace
```

When configured, the integration tests verify:

- The vault opens with the correct password.
- A wrong password returns a clear error message.
- A missing file returns a clear I/O error.

The missing-file test always runs; it does not need a database fixture.

The local `Database.kdbx` file is intentionally ignored and is not treated as a public fixture.

## Current Constraints

- No frontend code.
- No Tauri or Flutter project.
- CLI is only a validation and debugging entrypoint.
- Plain FFI adapter exists for desktop integration smoke testing; UI-specific
  bindings still belong outside `keepass_core`.
- Business logic must stay in `keepass_core`.
- Advanced entry features are exposed in core first: keyfiles, attachment metadata/bytes,
  custom field editing, and read-only history snapshots.
