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

# This project lives on iCloud Drive: Finder/Spotlight sometimes re-stamps
# AppleDouble/resource-fork extended attributes on freshly-created files
# within moments of the cp above (a real race, not just a one-time cleanup),
# and codesign refuses to sign a bundle containing those ("resource fork,
# Finder information, or similar detritus not allowed"). Retry the
# strip+sign a few times to absorb that race rather than failing on it.
SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
SIGN_OK=0
for attempt in 1 2 3 4 5; do
  xattr -cr "$APP_DIR"
  if [ -n "$SIGNING_IDENTITY" ]; then
    if codesign --force --options runtime -s "$SIGNING_IDENTITY" "$APP_DIR" 2>/tmp/clawd-codesign-err; then
      echo "Signed with: $SIGNING_IDENTITY (attempt $attempt)"
      SIGN_OK=1
      break
    fi
  else
    if codesign --force -s - "$APP_DIR" 2>/tmp/clawd-codesign-err; then
      echo "No local signing identity found -- signed ad-hoc (Accessibility grant may not survive the next rebuild)"
      SIGN_OK=1
      break
    fi
  fi
  sleep 0.3
done
if [ "$SIGN_OK" -ne 1 ]; then
  cat /tmp/clawd-codesign-err >&2
  echo "codesign failed after retries" >&2
  exit 1
fi
rm -f /tmp/clawd-codesign-err

echo "Built: $APP_DIR"
