{
  "hooks": {
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "printf '#[bg=colour208,fg=colour16,bold] [{{SESSION_NUM}}:🔔承認待ち] #[default]' > ~/.tmux-workspace-status/s{{SESSION_NUM}}; tmux select-pane -t claude-parallel:0.{{PANE_INDEX}} -P 'bg=colour52' 2>/dev/null; tmux refresh-client -S 2>/dev/null; true"
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "printf '#[bg=colour220,fg=colour16] [{{SESSION_NUM}}:🔔待機] #[default]' > ~/.tmux-workspace-status/s{{SESSION_NUM}}; tmux select-pane -t claude-parallel:0.{{PANE_INDEX}} -P 'bg=colour52' 2>/dev/null; tmux refresh-client -S 2>/dev/null; true"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "printf '#[bg=colour28,fg=colour231] [{{SESSION_NUM}}:✅完了] #[default]' > ~/.tmux-workspace-status/s{{SESSION_NUM}}; tmux select-pane -t claude-parallel:0.{{PANE_INDEX}} -P 'bg=colour22' 2>/dev/null; tmux refresh-client -S 2>/dev/null; true"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "printf '#[bg=colour27,fg=colour231] [{{SESSION_NUM}}:🔵作業中] #[default]' > ~/.tmux-workspace-status/s{{SESSION_NUM}}; tmux select-pane -t claude-parallel:0.{{PANE_INDEX}} -P 'bg=default' 2>/dev/null; tmux refresh-client -S 2>/dev/null; true"
          }
        ]
      }
    ]
  }
}
