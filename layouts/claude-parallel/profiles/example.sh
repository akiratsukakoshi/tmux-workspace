# Example profile for claude-parallel.
#
# Copy this file to <name>.local.sh and edit the paths. The *.local.sh
# variant takes priority and is gitignored, so personal worktree paths stay
# out of the repo.
#
#   cp profiles/example.sh profiles/my-set.local.sh
#   $EDITOR profiles/my-set.local.sh
#   ./start.sh my-set

WORKTREE_1="$HOME/path/to/project-a"
WORKTREE_2="$HOME/path/to/project-b"
WORKTREE_3="$HOME/path/to/project-c"
WORKTREE_4="$HOME/path/to/project-d"

# Optional. Layout for the 4 panes. Default: tiled.
#   tiled            — 2x2 grid (best for square/landscape windows)
#   even-horizontal  — 4 panes side-by-side (best for thin & wide windows, e.g. bottom strip)
#   even-vertical    — 4 panes stacked (best for tall & narrow windows, e.g. right strip)
LAYOUT="tiled"
