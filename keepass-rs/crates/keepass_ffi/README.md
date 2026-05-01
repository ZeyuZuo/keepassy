# keepass_ffi

Plain C ABI adapter over `keepass_core`.

The adapter is intended for future Flutter/plain-FFI or other desktop shells. It
does not parse `.kdbx` files or implement storage rules. All behavior delegates
to `keepass_core`.

## Ownership

- Functions return `KeepassYFfiResult`.
- `status == 0` means success; non-zero means error.
- `json` is always owned by the caller and must be released with
  `keepassy_string_free`.
- `session` is returned only by `keepassy_open_local` and must be released with
  `keepassy_session_close`.
- Null input pointers are accepted only where documented, such as optional
  keyfile paths.

## Data Shape

Cross-boundary data uses JSON encoded with the serde DTOs from `keepass_core`.
This keeps the FFI ABI small and stable while preserving explicit DTO conversion
outside the core crate.
