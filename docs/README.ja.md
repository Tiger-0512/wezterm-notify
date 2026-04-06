# wezterm-notify

長時間実行コマンドの完了通知を提供するWezTermプラグインです。プロセスがbell文字（`\a`）またはカスタムuser-varを送信すると、ペインの内容をキャプチャし、トースト通知・タブインジケータ・インタラクティブな通知ビューアで表示します。

## 機能

- bell文字（`\a`）によるコマンド完了通知
- `WEZTERM_NOTIFY` user-varによるカスタム通知（`タイトル:本文` 形式対応）
- 未読通知のあるタブにベルアイコンを表示
- OSトースト通知（サウンド付き、オプション）
- fzfベースのインタラクティブ通知ビューア（Ctrl+Shift+N）
- 通知詳細にペインの内容をキャプチャ
- セッション間で通知を永続化（`~/.local/share/wezterm-notify/` に保存）

## 必要条件

- [WezTerm](https://wezfurlong.org/wezterm/)（プラグインサポートのあるnightlyまたは最新リリース）
- [fzf](https://github.com/junegunn/fzf)（通知ビューア用）
- [jq](https://jqlang.github.io/jq/)（ビューアでのJSON処理用）

## インストール

`wezterm.lua` に以下を追加してください：

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

local notify = wezterm.plugin.require("https://github.com/Tiger-0512/wezterm-notify")

-- ... 他の設定 ...

notify.apply_to_config(config)

return config
```

### オプション

```lua
notify.apply_to_config(config, {
  mods = "CTRL|SHIFT",   -- 通知ビューアのキーバインド修飾キー（デフォルト: "CTRL|SHIFT"）
  key = "phys:n",        -- 通知ビューアのキー（デフォルト: "phys:n"）
  play_sound = true,     -- 通知時にビープ音を鳴らす（デフォルト: true）
  toast = true,          -- OSトースト通知を表示する（デフォルト: true）
})
```

## タブインジケータ

未読通知のあるタブにベルアイコンを表示するには、`format-tab-title` ハンドラに以下を追加してください：

```lua
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  local has_notif = notify.has_notification(tab.tab_id)
  -- has_notifを使ってタブの背景色を変えたり、アイコンを追加したりできます
  local notif_icon = has_notif and " \xF0\x9F\x94\x94" or ""
  -- ...
end)
```

タブがアクティブになったときに通知をクリアするには：

```lua
wezterm.on("update-status", function(window, pane)
  notify.clear_active_tab(window)
end)
```

## 仕組み

### bell通知

バックグラウンドのペインがbell文字（`\a`）を送信すると通知がトリガーされます。アクティブペインからのbellは、zsh補完などの日常的なシェル操作によるノイズを抑制するため無視されます。これはコマンド完了を通知するための標準的なUnixの仕組みです。

```bash
# 長時間コマンドの完了時に通知
make build; printf '\a'

# シェルプロンプトに追加して自動通知することも可能
```

### user-varによるカスタム通知

通知のタイトルと本文を細かく制御したい場合：

```bash
# タイトルと本文を指定
printf '\033]1337;SetUserVar=%s=%s\007' 'WEZTERM_NOTIFY' "$(printf '%s' 'タイトル:タスクが完了しました' | base64)"

# 本文のみ（ペインタイトルが通知タイトルとして使用されます）
printf '\033]1337;SetUserVar=%s=%s\007' 'WEZTERM_NOTIFY' "$(printf '%s' 'タスクが完了しました' | base64)"
```

## CLIツールとの連携

### Claude Code

Claude Codeのタスク完了時やユーザー入力待ち時にbellを送信する[フック](https://docs.anthropic.com/en/docs/claude-code/hooks)を追加します：

- **Stop** — Claude Codeがタスクを完了したときに発火
- **Notification** — Claude Codeがユーザー入力待ち（権限確認など）のときに発火

**`~/.claude/settings.json`**:

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "TTY=$(pid=$$; while [ \"$pid\" != \"1\" ]; do t=$(ps -o tty= -p \"$pid\" 2>/dev/null | tr -d ' '); if [ -n \"$t\" ] && [ \"$t\" != \"??\" ] && [ \"$t\" != \"-\" ]; then echo \"/dev/$t\"; break; fi; pid=$(ps -o ppid= -p \"$pid\" 2>/dev/null | tr -d ' '); done); [ -n \"$TTY\" ] && printf '\\a' > \"$TTY\"",
            "timeout": 5
          }
        ]
      }
    ],
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

> **注意**: Claude Codeのフックはサブプロセスとして実行されるため、直接TTYにアクセスできません。上記のコマンドはプロセスツリーを辿って親ターミナルのPTYデバイスを特定し、そこにbell文字を送信します。

### 汎用的な長時間コマンド

`.zshrc` や `.bashrc` に追加して、N秒以上かかるコマンドを自動通知：

```bash
# 30秒以上かかるコマンドを通知
notify_on_long_command() {
  local duration=$1
  if [ "$duration" -gt 30 ]; then
    printf '\a'
  fi
}
```

### tmux

tmuxを使用している場合は、bellパススルーを有効にしてください：

```tmux
set -g bell-action any
set -g visual-bell off
```

## 通知ビューア

**Ctrl+Shift+N**（デフォルト）で通知ビューアを開きます：

- **Enter**: 通知元のタブ/ペインにジャンプ
- **Ctrl-X**: 全通知をクリア
- **Ctrl-U/D**: プレビューペインをスクロール
- **Esc**: ビューアを閉じる

## API

| 関数 | 説明 |
|------|------|
| `notify.apply_to_config(config, opts)` | WezTerm設定でプラグインを初期化 |
| `notify.has_notification(tab_id)` | タブに未読通知があるか確認 |
| `notify.clear_tab(tab_id)` | 特定のタブの通知をクリア |
| `notify.clear_active_tab(window)` | 現在アクティブなタブの通知をクリア |
| `notify.show_notifications()` | 通知ビューアを開くWezTermアクションを返す |

## ライセンス

MIT
