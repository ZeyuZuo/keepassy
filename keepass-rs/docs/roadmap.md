# Roadmap

Detailed step-by-step development tasks are tracked in [todo.md](todo.md).

## Phase 0: Initialization

- Cargo workspace with `keepass_core` and `keepass_cli`.
- Architecture and roadmap documentation.
- Storage abstraction for local files and WebDAV.
- CLI skeleton for local and WebDAV debugging.
- Formatting, clippy, and tests passing.

## Phase 1: Read-Only Local Database

- Open local `.kdbx`.
- Unlock with master password.
- Read group tree.
- Read entry list.
- Read entry details.
- Add optional integration test via `KEEPASS_RS_TEST_KDBX` and `KEEPASS_RS_TEST_PASSWORD`.

## Phase 2: WebDAV Read and Save Foundation

- Download `.kdbx` through WebDAV-compatible HTTP.
- Track ETag and Last-Modified metadata.
- Add `PUT` support for future save workflows.
- Add conflict checks before overwriting remote data.

## Phase 3: Entry Mutation and Save

- Add entry creation, update, and deletion.
- Track dirty state.
- Save `.kdbx` with clear backup guidance because KeePass crate KDBX4 writing is experimental.

## Phase 4: KeePass Advanced Features

- Keyfile support.
- Attachments.
- Custom fields.
- Entry history.
- Better handling of protected values.

## Phase 5: Desktop Adapters

- Add Tauri command adapter or Flutter FFI adapter.
- Keep UI code outside `keepass_core`.
- Reuse the same service API and DTOs.
