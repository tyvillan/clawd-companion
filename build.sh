#!/usr/bin/env bash
# Builds ClawdCompanion and packages it into a minimal .app bundle.
# A bare loose Mach-O executable gets silently reaped by RunningBoardServices
# shortly after launch on modern macOS -- it needs a real bundle for the
# system to treat it as a legitimate long-lived UI-agent process.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP_DIR="build/ClawdCompanion.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp .build/release/ClawdCompanion "$APP_DIR/Contents/MacOS/ClawdCompanion"
cp Info.plist "$APP_DIR/Contents/Info.plist"

# Sign with a real local identity, not ad-hoc (-s -). An ad-hoc signature's
# identifier is derived from the binary's content hash, which changes every
# rebuild, so TCC (Accessibility permission) can't recognize it as "the same
# app" build-to-build. Signing with a stable certificate keeps the identity
# consistent across rebuilds as long as CFBundleIdentifier + the cert don't
# change, so the Accessibility grant should persist.
SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [ -n "$SIGNING_IDENTITY" ]; then
  codesign --force --options runtime -s "$SIGNING_IDENTITY" "$APP_DIR"
  echo "Signed with: $SIGNING_IDENTITY"
else
  echo "No local signing identity found -- signing ad-hoc (Accessibility grant may not survive the next rebuild)"
  codesign --force -s - "$APP_DIR"
fi

echo "Built: $APP_DIR"
