# Clawd Companion

A tiny desktop mascot that lives on your Dock and reacts to what [Claude Code](https://claude.com/claude-code) is actually doing — walking over to the app it's working with, jumping for attention when you wander off, and dozing off when nothing's happening.

Clawd is a borderless, always-on-top `NSPanel` rendered with SwiftUI. A Claude Code hook writes a small JSON file every time a tool runs; the app watches that file and turns it into mood, movement, and a state machine that decides whether he's walking, jumping, sleeping, or doing something mood-specific in place.

## How he decides what to do

```
Claude Code tool call
        │
        ▼
 ~/.claude/hooks/clawd-companion.sh   (PreToolUse / Stop / SessionStart hooks)
        │  writes
        ▼
 ~/.claude/creature/state.json        { "state": "typing", "target": "finder" }
        │  watched via kqueue
        ▼
 CompanionState.displayState          walking | jumping | sleeping | active(mood)
        │
        ▼
 CompanionView + DockWalker           renders the sprite, animates position
```

`displayState` is the single source of truth for what's on screen. Roughly:

- **Any real activity** (a mood other than idle) always wins — typing, thinking, etc. play in place regardless of anything else.
- **Idle + VS Code unfocused** → jump for attention.
- **Idle + focused + mid-transit** (walking to a target, walking home, or idly wandering) → keep walking until he actually arrives. Sleep never interrupts a walk in progress.
- **Idle + focused + arrived + been idle 45s+** → sleeping.
- Otherwise → idle wander around the Dock.

## Stages & animations

Every GIF below is a real capture of the running app.

### Idle wander

Between tool calls, Clawd ambles between random Dock icons and blinks occasionally.

![Idle wander](docs/gifs/idle_walking.gif)

### Typing / Working

`Bash`, and other tool calls that imply active work, drive a quick alternating-leg animation in place.

![Typing / working](docs/gifs/typing_working.gif)

### Thinking

A slow, gentle pulse while Claude is reasoning.

![Thinking](docs/gifs/thinking.gif)

### Inspecting

Eyes dart left and right with a slight lean — shown for tools that "look at" something (`Read`, `Grep`, `Glob`).

![Inspecting](docs/gifs/inspecting.gif)

### Celebrating

Triggered by the `Stop` hook when Claude finishes responding — a happy hop with a scale pulse.

![Celebrating](docs/gifs/celebrating.gif)

### Waving

Plays once at the start of a session (`SessionStart`) — a side-to-side lean like a wave.

![Waving](docs/gifs/waving.gif)

### Jumping (need your attention)

If VS Code loses focus while Claude is otherwise idle, Clawd hops in place near the Dock to nag you back.

![Jumping](docs/gifs/jumping.gif)

### Sleeping

After ~45 uninterrupted idle seconds *and* having actually arrived wherever he was headed, Clawd's eyes close, he settles into a slow breathing bob, and a few "Z"s float up and fade away.

![Sleeping](docs/gifs/sleeping.gif)

### Walking to a target app

File tools walk him to Finder, browser tools walk him to Chrome/Safari, shell tools walk him to Terminal (if it's running) — all based on which Dock icon the current tool call relates to.

![Walking to a target](docs/gifs/target_walk.gif)

### Coming home

When VS Code regains focus after being away, Clawd stops whatever he's doing and walks back to sit above the VS Code Dock icon — arriving already sleepy, since the time away counts against the idle clock.

![Coming home](docs/gifs/home_arrival.gif)

### Hover fade

Hovering the mouse over him fades him to 20% opacity so he never blocks something you're trying to click in the Dock. He isn't draggable — his position is entirely driven by Dock state, not the mouse.

![Hover fade](docs/gifs/hover_fade.gif)

## Also worth knowing

- **Full-screen apps**: Clawd hides completely while any other app is in real macOS fullscreen, and briefly peeks up from the bottom edge of the screen to signal a completed response before sinking back out of view.
- **Sizing**: he's sized relative to your actual Dock's measured tile size (not a fixed constant), so he scales sensibly across displays and Dock size settings.
- **Signing**: `build.sh` signs with a stable local "Apple Development" identity rather than an ad-hoc signature, so the Accessibility permission grant survives rebuilds.

## Setup

1. `./build.sh` — builds and code-signs `build/ClawdCompanion.app`.
2. Grant Accessibility permission when prompted (needed to read Dock icon positions and walk to them precisely).
3. Wire up the hooks in `~/.claude/settings.json` to call `~/.claude/hooks/clawd-companion.sh` on `SessionStart`, `PreToolUse`, and `Stop`.
4. Launch the app — `open build/ClawdCompanion.app`.
