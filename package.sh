#!/usr/bin/env bash
# Builds ClawdCompanion (universal, see build.sh) and zips it for a GitHub
# release. Output: dist/ClawdCompanion-vX.Y.Z-macOS.zip
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DIST_DIR="dist"
OUT="$DIST_DIR/ClawdCompanion-v$VERSION-macOS.zip"

mkdir -p "$DIST_DIR"
rm -f "$OUT"

# ditto, not zip -- it preserves the resource fork / extended attributes a
# .app bundle needs, which a plain `zip` silently drops and `unzip` on the
# other end can't reconstruct.
ditto -c -k --sequesterRsrc --keepParent build/ClawdCompanion.app "$OUT"

echo "Packaged: $OUT ($(du -h "$OUT" | cut -f1))"
