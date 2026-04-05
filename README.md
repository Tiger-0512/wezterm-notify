# wezterm-notify

[日本語](docs/README.ja.md)

A WezTerm plugin that provides a notification system for long-running commands. When a process sends a bell character (`\a`) or a custom user-var, the plugin captures the pane content and displays notifications with toast alerts, tab indicators, and an interactive notification viewer.

## Features

- Bell character (`\a`) detection for command completion notifications
- Custom notification via `WEZTERM_NOTIFY` user-var (supports `title:body` format)
- Tab indicator with bell icon for unread notifications
- OS toast notifications with optional sound
- Interactive notification viewer powered by fzf (Ctrl+Shift+N)
- Pane content capture for context in notification details
- Notification persistence across sessions (stored in `~/.local/share/wezterm-notify/`)

## Requirements

- [WezTerm](https://wezfurlong.org/wezterm/) (nightly or recent release with plugin support)
- [fzf](https://github.com/junegunn/fzf) (for the notification viewer)
- [jq](https://jqlang.github.io/jq/) (for JSON processing in the viewer)

## Installation

Add to your `wezterm.lua`:

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

local notify = wezterm.plugin.require("https://github.com/<your-username>/wezterm-notify")

-- ... your other config ...

notify.apply_to_config(config)

return config
```

### Options

```lua
notify.apply_to_config(config, {
  mods = "CTRL|SHIFT",   -- Keybinding modifier for notification viewer (default: "CTRL|SHIFT")
  key = "phys:n",        -- Keybinding key (default: "phys:n")
  play_sound = true,     -- Play beep sound on notification (default: true)
  toast = true,          -- Show OS toast notification (default: true)
  toast_title = "WezTerm", -- Toast notification title (default: "WezTerm")
  notify_processes = {   -- Whitelist of process names to notify on bell (default: nil = all)
    "claude",            --   Only these processes trigger bell notifications.
    "make",              --   Matches against the basename of the foreground process.
    "cargo",             --   When nil or empty, all bell events trigger notifications.
    "npm",
    "docker",
    "python",
  },
})
```

> **Note**: `notify_processes` filters only bell-based notifications. Custom notifications via `WEZTERM_NOTIFY` user-var are always delivered regardless of this setting.

## Tab indicator

To show a bell icon on tabs with unread notifications, add this to your `format-tab-title` handler:

```lua
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  local has_notif = notify.has_notification(tab.tab_id)
  -- Use has_notif to change tab background color or add an icon
  local notif_icon = has_notif and " \xF0\x9F\x94\x94" or ""
  -- ...
end)
```

To clear notifications when a tab becomes active:

```lua
wezterm.on("update-status", function(window, pane)
  notify.clear_active_tab(window)
end)
```

## How it works

### Bell notifications

Any process that sends a bell character (`\a`) to the terminal triggers a notification. This is the standard Unix mechanism for signaling command completion.

```bash
# Notify when a long command finishes
make build; printf '\a'

# Or add to your shell prompt for automatic notification
```

### Custom notifications via user-var

For more control over the notification title and body:

```bash
# With title and body
printf '\033]1337;SetUserVar=%s=%s\007' 'WEZTERM_NOTIFY' "$(printf '%s' 'My Title:Task completed' | base64)"

# Body only (uses pane title as the notification title)
printf '\033]1337;SetUserVar=%s=%s\007' 'WEZTERM_NOTIFY' "$(printf '%s' 'Task completed' | base64)"
```

## Integration with CLI tools

### Claude Code

Add a [Stop hook](https://docs.anthropic.com/en/docs/claude-code/hooks) to send a bell when Claude Code finishes:

**`~/.claude/settings.json`**:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "TTY=$(pid=$$; while [ \"$pid\" != \"1\" ]; do t=$(ps -o tty= -p \"$pid\" 2>/dev/null | tr -d ' '); if [ -n \"$t\" ] && [ \"$t\" != \"??\" ] && [ \"$t\" != \"-\" ]; then echo \"/dev/$t\"; break; fi; pid=$(ps -o ppid= -p \"$pid\" 2>/dev/null | tr -d ' '); done); [ -n \"$TTY\" ] && printf '\\a' > \"$TTY\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

> **Note**: Claude Code hooks run in a subprocess without direct TTY access. The command above walks the process tree to find the parent terminal's PTY device and sends the bell character there.

### Generic long-running commands

Add to your `.zshrc` or `.bashrc` to notify on any command taking longer than N seconds:

```bash
# Notify on commands that take longer than 30 seconds
notify_on_long_command() {
  local duration=$1
  if [ "$duration" -gt 30 ]; then
    printf '\a'
  fi
}
```

### tmux

If using tmux, ensure bell passthrough is enabled:

```tmux
set -g bell-action any
set -g visual-bell off
```

## Notification viewer

Press **Ctrl+Shift+N** (default) to open the notification viewer:

- **Enter**: Jump to the tab/pane that triggered the notification
- **Ctrl-X**: Clear all notifications
- **Ctrl-U/D**: Scroll the preview pane
- **Esc**: Close the viewer

## API

| Function | Description |
|----------|-------------|
| `notify.apply_to_config(config, opts)` | Initialize the plugin with WezTerm config |
| `notify.has_notification(tab_id)` | Check if a tab has unread notifications |
| `notify.clear_tab(tab_id)` | Clear notification for a specific tab |
| `notify.clear_active_tab(window)` | Clear notification for the currently active tab |
| `notify.show_notifications()` | Returns a WezTerm action that opens the notification viewer |

## License

MIT
