#!/usr/bin/env bash
# Claude Code hook dispatcher for the Clawd desktop companion. Registered on
# SessionStart/SessionEnd/UserPromptSubmit/PreToolUse/Stop/Notification/
# SubagentStart/SubagentStop.
# Launches/quits the companion app based on how many Claude Code sessions are
# currently open —
# tracked as one marker file per session_id (not a raw counter), so a
# duplicate or missed event can't drift the count out of sync — and pushes
# mood changes by writing a small state file the app watches for.
set -euo pipefail

CREATURE_DIR="$HOME/.claude/creature"
SESSIONS_DIR="$CREATURE_DIR/sessions"
PROJECT_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Projects/clawd-companion"
APP_BUNDLE="$PROJECT_DIR/build/ClawdCompanion.app"
APP_BIN="$APP_BUNDLE/Contents/MacOS/ClawdCompanion"
LOG_FILE="$CREATURE_DIR/companion.log"

mkdir -p "$SESSIONS_DIR"

PAYLOAD="$(cat)"

PARSED="$(printf '%s' "$PAYLOAD" | node -e '
  let d = "";
  process.stdin.on("data", c => d += c);
  process.stdin.on("end", () => {
    let p;
    try { p = JSON.parse(d); } catch { p = {}; }
    console.log(p.hook_event_name || "");
    console.log(p.session_id || "");
    console.log(p.tool_name || "");
    console.log(p.permission_mode || "");
    console.log(p.notification_type || "");
    console.log(p.agent_id || "");
  });
' 2>>"$LOG_FILE")"

EVENT="$(printf '%s\n' "$PARSED" | sed -n '1p')"
SESSION_ID="$(printf '%s\n' "$PARSED" | sed -n '2p')"
TOOL_NAME="$(printf '%s\n' "$PARSED" | sed -n '3p')"
PERMISSION_MODE="$(printf '%s\n' "$PARSED" | sed -n '4p')"
NOTIFICATION_TYPE="$(printf '%s\n' "$PARSED" | sed -n '5p')"
AGENT_ID="$(printf '%s\n' "$PARSED" | sed -n '6p')"
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"

# The hook script's own parent process is the actual long-lived `claude` CLI
# process for this session (confirmed via ps: PreToolUse's $PPID resolves
# straight to the `claude --resume=<session_id> ...` process, not some
# intermediate shell) -- recorded so the app can tell a session file left
# behind by a crash/force-quit (SessionEnd never fires) from one still
# genuinely in progress, instead of trusting the file's mere existence
# forever.
SESSION_PID="$PPID"

# permission_mode is a common field on every hook event (not tied to a
# specific tool), so this reflects whether we're *currently* in plan mode
# regardless of which tool (if any) is running -- plan mode spans many tool
# calls between EnterPlanMode and ExitPlanMode, not just one.
PLANNING="false"
[ "$PERMISSION_MODE" = "plan" ] && PLANNING="true"

# Subagents currently running for this session, tracked as one marker file
# per agent_id (written on SubagentStart, removed on SubagentStop) for the
# same drift-proofing reason sessions are. Markers older than two hours are
# pruned on every count, so an agent that was killed without a SubagentStop
# can't leave the orbiting helpers spinning forever.
AGENTS_DIR="$CREATURE_DIR/agents/$SESSION_ID"
count_agents() {
  [ -d "$AGENTS_DIR" ] || { echo 0; return; }
  find "$AGENTS_DIR" -type f -mmin +120 -delete 2>/dev/null || true
  find "$AGENTS_DIR" -type f 2>/dev/null | wc -l | tr -d ' '
}
AGENT_COUNT="$(count_agents)"

# Maps a tool name to the mood it should show while that tool runs.
mood_for_tool() {
  case "$1" in
    Artifact) echo "creating" ;;
    Edit|Write|NotebookEdit) echo "typing" ;;
    Read|Grep|Glob|WebFetch|WebSearch) echo "inspecting" ;;
    *) echo "working" ;;
  esac
}

# Maps a tool name to which dock app Clawd should walk to while it runs.
# Unmapped tools clear the target so Clawd resumes idle-wandering.
target_for_tool() {
  case "$1" in
    Bash) echo "terminal" ;;
    Read|Grep|Glob|Write|Edit|NotebookEdit) echo "finder" ;;
    WebFetch|WebSearch) echo "browser" ;;
    *) echo "" ;;
  esac
}

# One state file per session, named for its session_id. The file's
# existence is what tells the app this session is live -- it spawns a
# color-tinted companion per file and despawns when the file goes away -- and
# its contents are that session's own mood, so concurrent sessions animate
# independently instead of clobbering one shared state file.
#
# Written to a temp file and moved into place: the app watches this
# directory, and a partially-written file would otherwise be read as
# malformed JSON and dropped.
write_state() {
  local tmp="$SESSIONS_DIR/.$SESSION_ID.tmp"
  printf '{"state":"%s","target":"%s","planning":%s,"agents":%s,"pid":%s}' "$1" "${2:-}" "$PLANNING" "$AGENT_COUNT" "$SESSION_PID" > "$tmp"
  mv -f "$tmp" "$SESSIONS_DIR/$SESSION_ID.json"
}

# Rewrites the state file after the agent count changed, keeping whatever
# the session was already doing. Every write bumps the app's mood event, and
# celebrating/needsAttention/waving trigger alerts or a re-flash, so those
# are never replayed from here -- they become "delegating" (or idle once the
# last agent is gone) instead.
refresh_for_agent_change() {
  local file="$SESSIONS_DIR/$SESSION_ID.json" cur="idle" tgt=""
  if [ -f "$file" ]; then
    cur="$(sed -n 's/.*"state":"\([^"]*\)".*/\1/p' "$file")"
    tgt="$(sed -n 's/.*"target":"\([^"]*\)".*/\1/p' "$file")"
  fi
  case "$cur" in
    celebrating|needsAttention|waving|idle|delegating|"")
      if [ "$AGENT_COUNT" -gt 0 ]; then cur="delegating"; else cur="idle"; fi
      tgt=""
      ;;
  esac
  write_state "$cur" "$tgt"
}

launch_app_if_needed() {
  if [ -x "$APP_BIN" ] && ! pgrep -f "$APP_BIN" >/dev/null 2>&1; then
    open -g "$APP_BUNDLE" >>"$LOG_FILE" 2>&1
  fi
}

case "$EVENT" in
  SessionStart)
    # Creating the file is what spawns this session's companion; "waving"
    # gives it a hello animation, which the app auto-reverts to idle a
    # couple of seconds after rendering.
    rm -rf "$AGENTS_DIR"
    AGENT_COUNT=0
    write_state "waving"
    ;;
  SessionEnd)
    # Removing the file despawns just this session's companion. The app
    # quits itself once the last one is gone, so there's no separate
    # "everyone out" signal to send.
    rm -f "$SESSIONS_DIR/$SESSION_ID.json" "$SESSIONS_DIR/.$SESSION_ID.tmp"
    rm -rf "$AGENTS_DIR"
    ;;
  SubagentStart)
    if [ -n "$AGENT_ID" ]; then
      mkdir -p "$AGENTS_DIR"
      : > "$AGENTS_DIR/${AGENT_ID//[^A-Za-z0-9_-]/_}"
      AGENT_COUNT="$(count_agents)"
    fi
    refresh_for_agent_change
    ;;
  SubagentStop)
    if [ -n "$AGENT_ID" ]; then
      rm -f "$AGENTS_DIR/${AGENT_ID//[^A-Za-z0-9_-]/_}"
      AGENT_COUNT="$(count_agents)"
    fi
    refresh_for_agent_change
    ;;
  UserPromptSubmit)
    write_state "thinking"
    ;;
  PreToolUse)
    if [ "$TOOL_NAME" = "ExitPlanMode" ]; then
      # ExitPlanMode means Claude just finished a plan and is presenting it
      # for approval -- a real "come look at this" moment, not generic tool
      # activity. Falling through to mood_for_tool's default ("working")
      # left this looking like ordinary background work, so the idle/
      # unfocused jump-for-attention fallback fired instead of a flash once
      # mood drifted back to idle -- no Notification event covers "plan is
      # awaiting your approval" the way it covers a permission prompt.
      write_state "needsAttention"
    else
      write_state "$(mood_for_tool "$TOOL_NAME")" "$(target_for_tool "$TOOL_NAME")"
    fi
    ;;
  Stop)
    # The main turn ended, but subagents (typically background ones) may
    # still be running -- Claude isn't actually done, so no completion
    # alert yet. The turn that follows once they report back ends with its
    # own Stop, which celebrates.
    if [ "$AGENT_COUNT" -gt 0 ]; then
      write_state "delegating"
    else
      write_state "celebrating"
    fi
    ;;
  Notification)
    # Fires for a permission prompt, an idle-waiting-on-you prompt, and a
    # few purely informational cases (e.g. auth_success) that don't
    # actually need the user to do anything -- only the former should make
    # Clawd flash and head back to the editor.
    if [ "$NOTIFICATION_TYPE" != "auth_success" ]; then
      write_state "needsAttention"
    fi
    ;;
esac

# Relaunch on any event that left a live session behind, not just
# SessionStart. The app now exits on its own once the last session file is
# gone, so a session that outlives one of those exits (or a crash, or a
# manual Quit) would otherwise never get its companion back.
if [ "$EVENT" != "SessionEnd" ]; then
  launch_app_if_needed
fi

exit 0
