# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ClawdCompanion is a macOS menu-bar/Dock mascot app (Swift/SwiftUI, `LSUIElement` accessory app — no Dock icon or app switcher entry of its own) that watches Claude Code activity and animates a small pixel-sprite companion in response. See `README.md` for the full behavior spec (state machine, every animation with a captured GIF, settings) — it's kept current and is the best source of truth for *what the app does*. This file is about how to work in the codebase.

This repo is one of several independent projects living side by side under iCloud Drive's `Projects/` folder — see `../CLAUDE.md` for iCloud sync caveats (evicted `.icloud` placeholder files, avoiding concurrent heavy builds across projects).

## Architecture

A Claude Code hook script (tracked in this repo at `hooks/clawd-companion.sh`, copied — not symlinked — to `~/.claude/hooks/clawd-companion.sh` per the README's Setup section, since a hook firing on every tool call shouldn't depend on this iCloud-synced repo being reachable at that instant) writes one JSON file per session to `~/.claude/creature/sessions/<session_id>.json` on `SessionStart`/`PreToolUse`/`Stop`/`Notification` hook events. That file's existence *is* the session's lifetime — `SessionStart` creates it, `SessionEnd` removes it. If you edit the hook, remember to copy it back to `~/.claude/hooks/` afterward — the two can drift out of sync otherwise (this happened once already: a fix landed only in the live copy and had to be backported here).

Pipeline: hook writes JSON → `SessionRegistry` (kqueue watch + 2s safety rescan on the sessions directory, since directory vnode events can coalesce multiple sessions ending at once) discovers/retires per-session companions, and also prunes any session file whose recorded PID is dead (crashed/killed sessions never get a clean `SessionEnd`) → `StateFileWatcher` watches one session's file → `CompanionState.displayState` derives what's actually on screen (walking / jumping / sleeping / active-mood) from mood + focus + idle timers → `CompanionView` + `DockWalker` render and animate it.

Source layout (`Sources/ClawdCompanion/`):
- `main.swift` — entry point.
- `AppDelegate.swift` — machine-wide state shared across all companions: VS Code focus, fullscreen, Settings window, menu bar item. Spawns/despawns `SessionCompanion` per session.
- `SessionRegistry.swift` — discovers session files, assigns color slots, prunes dead sessions.
- `SessionCompanion.swift` — one companion's lifecycle, wired to its own session file.
- `SessionPalette.swift` — per-session color tinting (slot 0 stays original orange).
- `StateFileWatcher.swift` — reads/decodes a session's JSON into `CompanionState`.
- `CompanionState.swift` — mood/state model and the `displayState` decision logic.
- `CompanionView.swift` — SwiftUI rendering: sprite grid drawing, all animations (walk, jump, sleep Z's, hammer, blueprint, attention flash, etc.).
- `MascotSprite.swift` — the pixel-grid sprite definition and body-color source (also feeds `tools/make_icon.py`).
- `DockWalker.swift` — resolves Dock icon positions via the Accessibility API and drives walk animations/targets.
- `FocusWatcher.swift`, `FullScreenWatcher.swift`, `HoverWatcher.swift` — polling-based observers (frontmost app, fullscreen state, mouse-over-companion) used because this is an `LSUIElement` accessory app, so several normal AppKit/SwiftUI event paths (e.g. `.onHover`) don't fire.
- `CompletionAlerter.swift` — system notification/sound alerts; owns notification-permission request/state.
- `Settings.swift` / `SettingsView.swift` — `UserDefaults`-backed settings model and its UI, under the `com.tyvillan.clawdcompanion` domain.
- `StatusItemController.swift` — menu bar glyph, right-click menu, `--settings` launch arg handling.

## Build & package

```
./build.sh      # swift build -c release, universal (arm64+x86_64), stages a real .app bundle, codesigns locally
./package.sh    # runs build.sh, then ditto-zips build/ClawdCompanion.app into dist/ClawdCompanion-v<version>-macOS.zip
```

- `build.sh` signs with a stable local "Apple Development" identity (falls back to ad-hoc `-s -` with a warning if none is found) rather than an ad-hoc signature on every build — a changing signature invalidates the Accessibility permission grant, forcing it to be re-granted after every rebuild.
- Because this repo lives on iCloud Drive, Finder/Spotlight can re-stamp AppleDouble/resource-fork attributes on freshly-copied files within moments of `build.sh`'s `cp`, and `codesign` refuses to sign a bundle containing those. `build.sh` already retries `xattr -cr` + `codesign` a few times to absorb this race — if a build fails signing, retry before assuming something's actually broken.
- No test suite exists (no `Tests/` target, no XCTest). Verification in this codebase's history has consistently been manual/live: build, launch, and observe the real Dock behavior (screenshots, or a temporary forced-state override added and reverted before committing) rather than unit tests. Follow that pattern — there's no `swift test` to run here.
- `Info.plist`'s `CFBundleShortVersionString`/`CFBundleVersion` get bumped as part of most substantive commits (see git history) — treat a meaningful behavior change as a cue to bump the version too, matching existing convention.

## Requirements

macOS 14 (Sonoma)+, Xcode Command Line Tools (`xcode-select --install`). Accessibility permission is required at runtime (Dock icon geometry) — grant it when prompted after building/launching.

## Icon regeneration

`Resources/AppIcon.icns` is a checked-in build artifact rendered by `tools/make_icon.py` from `MascotSprite.swift`'s own grid/body color. Rerun it if either changes, so the icon can't drift from the sprite it's derived from.
