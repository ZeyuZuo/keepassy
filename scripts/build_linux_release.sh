#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="${ROOT_DIR}/keepass-rs"
FLUTTER_DIR="${ROOT_DIR}/keepassy_flutter"
BUNDLE_DIR="${FLUTTER_DIR}/build/linux/x64/release/bundle"
PACKAGE_DIR="${ROOT_DIR}/dist/linux/KeePassY"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

cargo build --manifest-path "${RUST_DIR}/Cargo.toml" -p keepass_ffi --release

(
  cd "${FLUTTER_DIR}"
  "${FLUTTER_BIN}" build linux --release
)

install -Dm755 \
  "${RUST_DIR}/target/release/libkeepass_ffi.so" \
  "${BUNDLE_DIR}/lib/libkeepass_ffi.so"

rm -rf "${PACKAGE_DIR}"
mkdir -p "${PACKAGE_DIR}"
cp -a "${BUNDLE_DIR}/." "${PACKAGE_DIR}/"

install -Dm644 \
  "${ROOT_DIR}/packaging/linux/com.keepassy.KeePassY.desktop" \
  "${PACKAGE_DIR}/share/applications/com.keepassy.KeePassY.desktop"
install -Dm644 \
  "${ROOT_DIR}/packaging/linux/com.keepassy.KeePassY.metainfo.xml" \
  "${PACKAGE_DIR}/share/metainfo/com.keepassy.KeePassY.metainfo.xml"
install -Dm644 \
  "${ROOT_DIR}/packaging/linux/icons/hicolor/scalable/apps/com.keepassy.KeePassY.svg" \
  "${PACKAGE_DIR}/share/icons/hicolor/scalable/apps/com.keepassy.KeePassY.svg"

test -x "${PACKAGE_DIR}/keepassy_flutter"
test -f "${PACKAGE_DIR}/lib/libkeepass_ffi.so"

echo "Linux release bundle: ${PACKAGE_DIR}"
