#!/usr/bin/env bash
# =============================================================================
# start.sh — launch the "claude-parallel" tmux layout
#
# Usage:
#   ./start.sh <profile>          # load profiles/<profile>(.local).sh and start
#   ./start.sh                    # list available profiles
#
# A profile is a small shell file that defines WORKTREE_1..WORKTREE_4. Profiles
# are looked up under ./profiles/ — first <name>.local.sh (user-private,
# gitignored), then <name>.sh (committed example). Add new profiles by dropping
# a new file in there; no edits to this script needed.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="$SCRIPT_DIR/profiles"
SESSION="claude-parallel"

list_profiles() {
  echo "available profiles (in $PROFILES_DIR):"
  if [[ ! -d "$PROFILES_DIR" ]] || [[ -z "$(ls -A "$PROFILES_DIR" 2>/dev/null)" ]]; then
    echo "  (none — create one, e.g. profiles/myset.local.sh)"
    return
  fi
  # Show profile names (strip .local.sh / .sh, dedupe), preferring .local.sh
  # over .sh in display by marking which file would be picked.
  shopt -s nullglob
  declare -A seen=()
  for f in "$PROFILES_DIR"/*.local.sh "$PROFILES_DIR"/*.sh; do
    base="$(basename "$f")"
    name="${base%.local.sh}"
    name="${name%.sh}"
    if [[ -z "${seen[$name]:-}" ]]; then
      seen[$name]=1
      printf '  - %s\n' "$name"
    fi
  done
  shopt -u nullglob
}

if [[ $# -eq 0 ]]; then
  list_profiles
  echo ""
  echo "usage: $0 <profile>"
  exit 0
fi

PROFILE_NAME="$1"

# Prefer the .local.sh variant so that a private override shadows the example.
PROFILE_FILE=""
for candidate in "$PROFILES_DIR/$PROFILE_NAME.local.sh" "$PROFILES_DIR/$PROFILE_NAME.sh"; do
  if [[ -f "$candidate" ]]; then
    PROFILE_FILE="$candidate"
    break
  fi
done

if [[ -z "$PROFILE_FILE" ]]; then
  echo "error: profile not found: $PROFILE_NAME" >&2
  echo "looked for: $PROFILES_DIR/$PROFILE_NAME.local.sh, $PROFILES_DIR/$PROFILE_NAME.sh" >&2
  echo "" >&2
  list_profiles >&2
  exit 1
fi

# Sandbox the variables we expect the profile to set. Anything else the profile
# might define leaks into our shell, which is fine — it's just a config file.
WORKTREE_1=""
WORKTREE_2=""
WORKTREE_3=""
WORKTREE_4=""
LAYOUT=""
# shellcheck disable=SC1090
source "$PROFILE_FILE"

# Validate / default the layout choice. Anything tmux's select-layout accepts is
# fine, but we whitelist the three useful for this layout so a typo doesn't
# silently fall back to something unexpected.
LAYOUT="${LAYOUT:-tiled}"
case "$LAYOUT" in
  tiled|even-horizontal|even-vertical|main-horizontal|main-vertical) ;;
  *)
    echo "error: unsupported LAYOUT '$LAYOUT' in $PROFILE_FILE" >&2
    echo "  use one of: tiled, even-horizontal, even-vertical, main-horizontal, main-vertical" >&2
    exit 1
    ;;
esac

# Expand leading ~ if a profile used a quoted "~/foo" instead of "$HOME/foo".
for i in 1 2 3 4; do
  var="WORKTREE_$i"
  val="${!var}"
  if [[ -n "$val" && "${val:0:1}" == "~" ]]; then
    printf -v "$var" '%s' "${HOME}${val:1}"
  fi
done

# Validate before touching tmux so we fail fast instead of dropping the user
# into a half-broken session.
missing=0
for i in 1 2 3 4; do
  var="WORKTREE_$i"
  val="${!var}"
  if [[ -z "$val" ]]; then
    echo "error: profile '$PROFILE_NAME' does not set $var" >&2
    missing=1
  elif [[ ! -d "$val" ]]; then
    echo "error: $var path does not exist: $val" >&2
    missing=1
  fi
done
if [[ $missing -ne 0 ]]; then
  echo "fix $PROFILE_FILE and re-run." >&2
  exit 1
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "session '$SESSION' already exists. attach with: tmux attach -t $SESSION"
  exit 0
fi

echo "profile: $PROFILE_NAME ($PROFILE_FILE)"
for i in 1 2 3 4; do
  var="WORKTREE_$i"
  echo "  S$i: ${!var}"
done

# Build the 4-pane layout. New panes are appended; select-layout tiled then
# arranges them as a 2x2 grid. Pane indices match creation order:
#   0: top-left  1: top-right  2: bottom-left  3: bottom-right
tmux new-session  -d -s "$SESSION" -c "$WORKTREE_1"
tmux split-window    -t "$SESSION" -c "$WORKTREE_2"
tmux split-window    -t "$SESSION" -c "$WORKTREE_3"
tmux split-window    -t "$SESSION" -c "$WORKTREE_4"
tmux select-layout   -t "$SESSION" "$LAYOUT"

tmux set-option -t "$SESSION" -g allow-rename off
tmux set-option -t "$SESSION" -g automatic-rename off
tmux rename-window -t "$SESSION:0" "claude-parallel"

# Re-apply the layout on window resize so that shrinking the terminal window
# keeps all four panes evenly sized instead of squashing only one of them.
# window-resized is a window-scoped hook, so target the layout's window
# directly. Other sessions/windows are unaffected.
tmux set-hook -w -t "$SESSION:0" window-resized "select-layout $LAYOUT"

# Each pane is left as a bare shell. The actual claude conversations happen
# elsewhere (typically the VSCode Claude Code extension), and the hooks in each
# worktree's .claude/settings.json reach back into this tmux session by name to
# update the status bar / pane background. The shells stay around as handy
# scratch windows ("git status", quick file peek, etc.) without launching a
# second claude process that nobody talks to.
for i in 1 2 3 4; do
  var="WORKTREE_$i"
  path="${!var}"
  pane_idx=$((i - 1))
  title="S${i}:$(basename "$path")"
  tmux select-pane -t "$SESSION:0.$pane_idx" -T "$title"
done

tmux select-pane -t "$SESSION:0.0"

echo ""
echo "started session '$SESSION'."
echo "attach with: tmux attach -t $SESSION"
