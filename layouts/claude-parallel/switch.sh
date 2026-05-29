#!/usr/bin/env bash
# =============================================================================
# switch.sh — re-point a claude-parallel slot to a different worktree, live.
#
# Usage:
#   ./switch.sh <slot> [worktree_path]
#
#   <slot>           1..4 — which monitor slot / pane to repoint
#   [worktree_path]  directory to bind to that slot (default: current dir $PWD)
#
# Designed to be run from anywhere (e.g. a VSCode terminal sitting in the
# project you want to monitor). It does NOT restart the tmux session, so the
# slots you leave alone — typically the resident top ones — keep running.
#
# What it does:
#   1. install-hooks.sh <path> <slot>  — bind that worktree's Claude hooks to
#      the slot, so its status updates land in the right pane from now on.
#   2. respawn the live pane in the new dir + retitle it (if the session exists).
#   3. clear the slot's old status string + reset the pane background, so the
#      previous project's "completed/waiting" state doesn't linger.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION="claude-parallel"
STATUS_DIR="$HOME/.tmux-workspace-status"

usage() {
  echo "Usage: $0 <slot> [worktree_path]" >&2
  echo "  slot:          integer 1..4" >&2
  echo "  worktree_path: directory to bind (default: \$PWD = $PWD)" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

SLOT="$1"
WORKTREE_PATH="${2:-$PWD}"

if ! [[ "$SLOT" =~ ^[1-4]$ ]]; then
  echo "error: slot must be 1, 2, 3, or 4 (got: $SLOT)" >&2
  exit 1
fi

# Expand a leading ~ and normalize to an absolute path.
WORKTREE_PATH="${WORKTREE_PATH/#\~/$HOME}"
if [[ ! -d "$WORKTREE_PATH" ]]; then
  echo "error: worktree path does not exist: $WORKTREE_PATH" >&2
  exit 1
fi
WORKTREE_PATH="$(cd "$WORKTREE_PATH" && pwd)"

PANE_INDEX=$((SLOT - 1))
NAME="$(basename "$WORKTREE_PATH")"

# 1. Bind this worktree's Claude hooks to the slot (re-points status updates).
"$SCRIPT_DIR/install-hooks.sh" "$WORKTREE_PATH" "$SLOT"

# 2 & 3. Update the live session if it's running. If not, the hooks are still
# installed and will take effect the next time the session is started.
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "hooks installed for slot $SLOT -> $WORKTREE_PATH"
  echo "note: tmux session '$SESSION' is not running; start it with ./start.sh <profile>"
  exit 0
fi

TARGET="$SESSION:0.$PANE_INDEX"

if ! tmux list-panes -t "$SESSION:0" -F '#{pane_index}' | grep -qx "$PANE_INDEX"; then
  echo "error: pane $PANE_INDEX not found in session '$SESSION' (is the layout 4 panes?)" >&2
  echo "hooks were installed for slot $SLOT, but the live pane was not updated." >&2
  exit 1
fi

# Respawn the scratch shell in the new directory (-k kills whatever was there;
# these panes are bare scratch shells, so this is safe).
tmux respawn-pane -k -t "$TARGET" -c "$WORKTREE_PATH"
tmux select-pane -t "$TARGET" -T "S${SLOT}:${NAME}"
tmux select-pane -t "$TARGET" -P 'bg=default'

# Removing the status file (rather than emptying it) makes status-right fall
# back to its neutral "[N:-]" placeholder.
rm -f "$STATUS_DIR/s$SLOT"
tmux refresh-client -S 2>/dev/null || true

echo "switched slot $SLOT -> $WORKTREE_PATH (pane $TARGET updated)"
