# Linux Release Build

KeePassY's Linux bundle contains the Flutter desktop app plus the Rust FFI
shared library.

## Build

From the repository root:

```bash
scripts/build_linux_release.sh
```

The script:

1. builds `keepass_ffi` in release mode,
2. builds the Flutter Linux release bundle,
3. copies `libkeepass_ffi.so` into the bundle `lib/` directory,
4. copies desktop metadata and the application icon, and
5. writes the assembled bundle to `dist/linux/KeePassY`.

## Runtime Layout

```text
dist/linux/KeePassY/
  keepassy_flutter
  lib/
    libapp.so
    libflutter_linux_gtk.so
    libkeepass_ffi.so
  data/
  share/
```

At startup, Flutter loads `libkeepass_ffi.so` from the bundle `lib/` directory.
For development overrides, set `KEEPASSY_FFI_LIB` to a full shared-library path.

## Smoke Test

Run:

```bash
dist/linux/KeePassY/keepassy_flutter
```

Then verify:

- local `.kdbx` open succeeds,
- wrong password shows a clear error,
- edit/save/lock/reopen keeps changes,
- missing `lib/libkeepass_ffi.so` shows the startup failure page, and
- no error text includes passwords, keyfile contents, or WebDAV credentials.
