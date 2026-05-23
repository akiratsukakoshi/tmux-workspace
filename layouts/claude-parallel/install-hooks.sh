#!/usr/bin/env bash
# =============================================================================
# install-hooks.sh — install Claude Code hooks into a worktree
#
# Usage:
#   ./install-hooks.sh <worktree_path> <session_num>
#
# Example:
#   ./install-hooks.sh ~/projects/web-app 1
#
# Renders templates/claude-settings.json.tpl with {{SESSION_NUM}} and
# {{PANE_INDEX}} substituted ({{PANE_INDEX}} = SESSION_NUM - 1, matching
# start.sh's pane ordering), then writes it to <worktree>/.claude/settings.json.
#
# If a settings.json already exists in the worktree, the file is *merged*: the
# existing settings are preserved (env, permissions, mcpServers, ...) and only
# the Notification / Stop / PreToolUse hooks are replaced by the new versions.
# Other hook event types in the existing file are preserved as-is. A timestamped
# backup of the previous settings.json is always written next to the original.
# =============================================================================

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <worktree_path> <session_num>" >&2
  echo "  session_num: integer 1..4" >&2
  exit 2
fi

WORKTREE_PATH="$1"
SESSION_NUM="$2"

WORKTREE_PATH="${WORKTREE_PATH/#\~/$HOME}"

if [[ ! -d "$WORKTREE_PATH" ]]; then
  echo "error: worktree path does not exist: $WORKTREE_PATH" >&2
  exit 1
fi

if ! [[ "$SESSION_NUM" =~ ^[1-4]$ ]]; then
  echo "error: session_num must be 1, 2, 3, or 4 (got: $SESSION_NUM)" >&2
  exit 1
fi

PANE_INDEX=$((SESSION_NUM - 1))

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/claude-settings.json.tpl"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "error: template not found: $TEMPLATE" >&2
  exit 1
fi

CLAUDE_DIR="$WORKTREE_PATH/.claude"
TARGET="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

# Render the template into a temp file so we can hand a complete JSON document
# to the python merge step regardless of whether a target exists.
RENDERED="$(mktemp)"
trap 'rm -f "$RENDERED"' EXIT
sed \
  -e "s/{{SESSION_NUM}}/$SESSION_NUM/g" \
  -e "s/{{PANE_INDEX}}/$PANE_INDEX/g" \
  "$TEMPLATE" > "$RENDERED"

if [[ -e "$TARGET" ]]; then
  BACKUP="$TARGET.bak.$(date +%Y%m%d_%H%M%S)"
  cp -p "$TARGET" "$BACKUP"
  echo "backed up existing settings to: $BACKUP"

  # Merge strategy:
  #   - Top-level keys (env, permissions, mcpServers, ...) are preserved as-is.
  #   - Under "hooks", every event we've ever managed gets cleared first, then
  #     the current template is written. That way, removing an event from the
  #     template actually removes it from the worktree on the next install,
  #     instead of leaving stale entries behind. Events outside MANAGED_EVENTS
  #     (anything we don't ship) are left untouched, so users can add their
  #     own hooks alongside ours.
  python3 - "$TARGET" "$RENDERED" <<'PY' > "$TARGET.new"
import json, sys

# Every hook event this layout has ever owned. Keep this list append-only so
# that older deployments get cleaned up correctly on re-install.
MANAGED_EVENTS = [
    "PermissionRequest",
    "Notification",
    "Stop",
    "PreToolUse",
    "PostToolUse",
    "UserPromptSubmit",
]

existing_path, rendered_path = sys.argv[1], sys.argv[2]
with open(existing_path, encoding="utf-8") as f:
    existing = json.load(f)
with open(rendered_path, encoding="utf-8") as f:
    rendered = json.load(f)

existing_hooks = existing.get("hooks") or {}
new_hooks = rendered.get("hooks") or {}

for event in MANAGED_EVENTS:
    existing_hooks.pop(event, None)
for event, value in new_hooks.items():
    existing_hooks[event] = value

if existing_hooks:
    existing["hooks"] = existing_hooks
elif "hooks" in existing:
    del existing["hooks"]

json.dump(existing, sys.stdout, indent=2, ensure_ascii=False)
sys.stdout.write("\n")
PY
  mv "$TARGET.new" "$TARGET"
  echo "merged hooks into existing settings: $TARGET"
else
  cp "$RENDERED" "$TARGET"
  echo "installed hooks: $TARGET"
fi

echo "  session=$SESSION_NUM, pane=claude-parallel:0.$PANE_INDEX"
