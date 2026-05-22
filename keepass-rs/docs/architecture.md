# Architecture

`keepass-rs` is a backend-only Rust workspace for KeePass client capabilities.

## Layers

Dependency direction is fixed:

```text
CLI / FFI / future adapters -> application service -> domain DTOs -> infrastructure adapters
```

- `keepass_core` owns all reusable backend behavior.
- `keepass_cli` is a thin debug wrapper over `keepass_core`.
- `keepass_ffi` is a thin plain C ABI wrapper over `keepass_core`.
- Future Tauri or Flutter integration should add adapter code outside the core business logic.

## Core API

`VaultService` is a thin factory that exposes async operations for:

- opening local `.kdbx` files;
- downloading and opening WebDAV `.kdbx` files.

Opening a vault returns a `VaultSession`. The session owns the decrypted in-memory database state and exposes operations for:

- reading a group tree;
- reading entry summaries for a group;
- reading entry details.
- creating, updating, and deleting entries;
- explicitly saving the database back through its storage backend.

The public return and request types are serde-friendly DTOs such as `GroupNode`, `EntrySummary`, `EntryDetail`, `CreateEntryRequest`, and `UpdateEntryRequest`. These types are designed to be serialized through Tauri IPC or converted into FFI-safe models later.

## Storage

Storage is abstracted behind `StorageBackend`.

- `LocalFileStorage` reads and writes bytes from the local filesystem.
- `WebDavStorage` uses `reqwest` and standard HTTP/WebDAV methods for `GET`, `PUT`, and metadata.

The KeePass parser receives bytes and does not know whether the source was local or remote. A session keeps the original encrypted bytes and the active save credentials in native memory so the Flutter UI does not need to retain the master password after unlock. Explicit save calls can still provide credentials for tests or non-UI callers.

## FFI Adapter

`keepass_ffi` exposes an opaque session handle plus JSON request/response functions for desktop shells that need a stable C ABI. It does not parse KeePass data, perform storage logic, or define business rules. All cross-boundary DTO conversion is explicit JSON serialization of `keepass_core` request and response types.

Memory ownership is adapter-owned:

- JSON strings returned by FFI must be released with `keepassy_string_free`.
- Session handles returned by `keepassy_open_local` must be released with `keepassy_session_close`.
- FFI errors use non-zero status plus JSON `{ "error": "..." }`.

## Future Tauri Integration

Tauri should call `keepass_core` from command functions:

```rust
#[tauri::command]
async fn read_tree(path: String, password: String) -> Result<GroupNode, String> {
    let service = keepass_core::VaultService::default();
    service.open_local(path, password).await
        .map(|vault| vault.group_tree().clone())
        .map_err(|err| err.to_string())
}
```

Tauri command code should stay an adapter. It should not parse `.kdbx`, perform storage logic, or own domain rules.

## Future Flutter Integration

Flutter can integrate through the current plain FFI crate or a later `flutter_rust_bridge` adapter.

The recommended path is to expose wrapper functions that call `keepass_core` and map DTOs into generated bridge types. If FFI-safe structs require different memory layout, keep those wrappers separate from the core crate.

## Save and Edit

Entry editing and saving live in `keepass_core`. Saving is explicit and never happens as a side effect of mutation. WebDAV saves use `If-Match` with the last known ETag when available so remote conflicts surface as `VaultError::Conflict`.

Password-plus-keyfile unlock is supported by passing keyfile bytes into core APIs; CLI only reads the keyfile and delegates unlock to core. Attachments expose metadata in `EntryDetail`, while raw attachment bytes are returned by a separate API so large binaries are not serialized in normal detail responses. Custom field editing rejects standard KeePass field names (`Title`, `UserName`, `Password`, `URL`, `Notes`) to avoid ambiguous writes. Entry history is read-only in Phase 4.

Keyfile paths, UI prompts, and adapter-specific error mapping should stay outside `keepass_core`.
