#!/usr/bin/env bash
# Renders the README's animated GIFs offscreen from the real CompanionView
# (no screen recording): compiles the app's sources with tools/render_gifs.swift
# as the entry point, writes PNG frames, then assembles tight-cropped GIFs
# with tools/make_gifs.py. Usage: tools/render_gifs.sh [scene ...]
# Scenes: hammer canvas agents (default: all)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
SRCS=$(ls Sources/ClawdCompanion/*.swift | grep -v main.swift)
swiftc -O -parse-as-library $SRCS tools/render_gifs.swift -o "$OUT/render" 2>&1 | grep -E "error" || true
"$OUT/render" "$OUT/frames" "$@"
python3 -I tools/make_gifs.py "$OUT/frames" docs/gifs
rm -rf "$OUT"
