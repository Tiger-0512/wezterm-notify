local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

-- ============================================================
-- Internal state
-- ============================================================
local MAX_NOTIFICATIONS = 50
local notifications = {}
local notified_tabs = {}
local notified_panes = {}

local HOME = os.getenv("HOME")
local NOTIF_DIR = HOME .. "/.local/share/wezterm-notify"
local NOTIF_FILE = NOTIF_DIR .. "/notifications.json"

-- ============================================================
-- JSON helpers
-- ============================================================
local function esc(s)
	return (s or "")
		:gsub("\\", "\\\\")
		:gsub('"', '\\"')
		:gsub("\n", "\\n")
		:gsub("\r", "")
		:gsub("\t", "  ")
		:gsub("[%c]", "")
end

local function save()
	os.execute("mkdir -p '" .. NOTIF_DIR .. "'")
	local f = io.open(NOTIF_FILE, "w")
	if not f then
		return
	end
	f:write("[\n")
	for i, n in ipairs(notifications) do
		if i > 1 then
			f:write(",\n")
		end
		f:write(string.format(
			'{"tab_id":%d,"pane_id":%d,"title":"%s","body":"%s","time":%d,"pane_text":"%s"}',
			n.tab_id,
			n.pane_id,
			esc(n.title),
			esc(n.body),
			n.time,
			esc(n.pane_text)
		))
	end
	f:write("\n]")
	f:close()
end

local function load()
	local f = io.open(NOTIF_FILE, "r")
	if not f then
		return
	end
	local content = f:read("*a")
	f:close()
	local ok, data = pcall(wezterm.json_parse, content)
	if ok and type(data) == "table" then
		for _, n in ipairs(data) do
			notifications[#notifications + 1] = n
		end
	end
end

load()

-- ============================================================
-- Pane text capture
-- ============================================================
local function get_pane_text(pane)
	local ok, text = pcall(function()
		return pane:get_lines_as_text()
	end)
	return ok and text or ""
end

-- ============================================================
-- Notification management
-- ============================================================
local function add_notification(tab_id, pane_id, title, body, pane_text)
	table.insert(notifications, 1, {
		tab_id = tab_id,
		pane_id = pane_id,
		title = title,
		body = body,
		time = os.time(),
		pane_text = pane_text or "",
	})
	while #notifications > MAX_NOTIFICATIONS do
		table.remove(notifications)
	end
	notified_panes[tostring(pane_id)] = tab_id
	pcall(save)
end

function M.has_notification(tab_id)
	return notified_tabs[tostring(tab_id)] == true
end

function M.clear_tab(tab_id)
	notified_tabs[tostring(tab_id)] = nil
end

function M.clear_active_tab(window)
	local tab = window:mux_window():active_tab()
	if not tab then
		return
	end
	local tk = tostring(tab:tab_id())
	notified_tabs[tk] = nil
	for pk, tid in pairs(notified_panes) do
		if tostring(tid) == tk then
			notified_panes[pk] = nil
		end
	end
end

-- ============================================================
-- Notification viewer (fzf-based)
-- ============================================================
function M.show_notifications()
	return wezterm.action_callback(function(window, pane)
		local mux_win = window:mux_window()
		for i, tab in ipairs(mux_win:tabs()) do
			local title = tab:active_pane():get_title()
			if title:find("Notifications") then
				local ap = tab:active_pane()
				window:perform_action(act.ActivateTab(i - 1), ap)
				window:perform_action(act.CloseCurrentTab({ confirm = false }), ap)
				return
			end
		end

		pcall(save)
		local nf = NOTIF_FILE
		local script = 'export PATH="/opt/homebrew/bin:$PATH"\n'
			.. 'NOTIF_FILE="'
			.. nf
			.. '"\nexport NOTIF_FILE\n'
			.. [=[
printf "\033]2;Notifications\xF0\x9F\x94\x94\007"
count=$(jq length < "$NOTIF_FILE" 2>/dev/null)
if [ -z "$count" ] || [ "$count" = "0" ]; then
  echo "No notifications"
  sleep 1
  exit 0
fi

selected=$(fzf \
  --ansi \
  --layout=reverse \
  --border=rounded \
  --border-label=" \xF0\x9F\x94\x94 Notifications " \
  --header="Enter: Jump / Ctrl-X: Clear all / Ctrl-U/D: Scroll / Esc: Close" \
  --preview='idx=$(echo {} | cut -d: -f1); echo "\xF0\x9F\x94\x94 Notification Detail"; echo "\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80"; jq -r --argjson i "$idx" "\"\xe2\x8f\xb0 \" + (.[\$i].time | strftime(\"%H:%M:%S\")) + \"  \" + .[\$i].title + \" - \" + .[\$i].body + \"\n\xf0\x9f\x93\x91 Tab:#\" + (.[\$i].tab_id|tostring) + \"  \xf0\x9f\x94\xb2 Pane:#\" + (.[\$i].pane_id|tostring)" "$NOTIF_FILE"; echo ""; echo "\xe2\x94\x80\xe2\x94\x80 Pane Content \xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80"; jq -r --argjson i "$idx" ".[\$i].pane_text" "$NOTIF_FILE"' \
  --preview-window=right:50%:wrap \
  --bind="ctrl-d:preview-half-page-down" \
  --bind="ctrl-u:preview-half-page-up" \
  --bind="ctrl-x:become(echo clear_all)" \
  < <(jq -r 'to_entries[] | "\(.key):\(.value.time | strftime("%H:%M:%S"))  \(.value.title) - \(.value.body)"' "$NOTIF_FILE") \
  || true)

if [ -n "$selected" ]; then
  if [ "$selected" = "clear_all" ]; then
    printf "\033]1337;SetUserVar=%s=%s\007" "WEZTERM_NOTIF_RESULT" "$(echo -n 'clear_all' | base64)"
  else
    key=$(echo "$selected" | cut -d: -f1)
    printf "\033]1337;SetUserVar=%s=%s\007" "WEZTERM_NOTIF_RESULT" "$(echo -n "$key" | base64)"
  fi
  sleep 0.5
fi
]=]
		window:perform_action(act.SpawnCommandInNewTab({ args = { "bash", "-c", script } }), pane)
	end)
end

-- ============================================================
-- apply_to_config: main entry point
-- ============================================================
--- Options:
---   mods       : string  - keybinding modifier (default: "CTRL|SHIFT")
---   key        : string  - keybinding key (default: "phys:n")
---   play_sound : boolean - play beep on notification (default: true)
---   toast      : boolean - show OS toast notification (default: true)
function M.apply_to_config(config, opts)
	opts = opts or {}
	local play_sound = opts.play_sound ~= false
	local toast = opts.toast ~= false

	config.audible_bell = "Disabled"

	wezterm.on("bell", function(window, pane)
		local tab = pane:tab()
		if not tab then
			return
		end
		local tab_id = tab:tab_id()
		local title = pane:get_title()

		-- Ignore notification viewer tab
		if title:find("Notifications") then
			return
		end

		-- Only notify for background panes (ignore bells from the active pane
		-- such as zsh completions and other routine shell interactions)
		local active_pane = window:active_pane()
		local is_active_pane = active_pane and active_pane:pane_id() == pane:pane_id()
		if is_active_pane then
			return
		end

		local pane_text = get_pane_text(pane)
		add_notification(tab_id, pane:pane_id(), title, "completed", pane_text)
		notified_tabs[tostring(tab_id)] = true

		if toast then
			window:toast_notification("WezTerm", title .. " - completed")
		end
		window:set_right_status("")

		if play_sound then
			wezterm.background_child_process({ "osascript", "-e", "beep" })
		end
	end)

	-- Custom notification via user-var: WEZTERM_NOTIFY
	-- Format: "title:body" or just "body" (uses pane title)
	wezterm.on("user-var-changed", function(window, pane, name, value)
		if name == "WEZTERM_NOTIFY" and value ~= "" then
			local tab = pane:tab()
			local tab_id = tab and tab:tab_id() or 0
			local title, body = value:match("^([^:]*):(.*)$")
			if not title then
				title = pane:get_title()
				body = value
			end
			local pane_text = get_pane_text(pane)
			add_notification(tab_id, pane:pane_id(), title, body, pane_text)

			if toast then
				window:toast_notification("WezTerm", title .. " - " .. body)
			end
			if play_sound then
				wezterm.background_child_process({ "osascript", "-e", "beep" })
			end
		elseif name == "WEZTERM_NOTIF_RESULT" and value ~= "" then
			window:perform_action(act.CloseCurrentTab({ confirm = false }), pane)
			if value == "clear_all" then
				notifications = {}
				notified_tabs = {}
				notified_panes = {}
				pcall(save)
			else
				local idx = tonumber(value)
				if idx then
					local n = notifications[idx + 1]
					if n then
						local mux_win = window:mux_window()
						for i, tab in ipairs(mux_win:tabs()) do
							if tab:tab_id() == n.tab_id then
								local ap = tab:active_pane()
								window:perform_action(act.ActivateTab(i - 1), ap)
								for _, pi in ipairs(tab:panes_with_info()) do
									if pi.pane:pane_id() == n.pane_id then
										pi.pane:activate()
										break
									end
								end
								break
							end
						end
					end
				end
			end
		end
	end)

	-- Keybinding for notification viewer
	if not config.keys then
		config.keys = {}
	end
	config.keys[#config.keys + 1] = {
		key = opts.key or "phys:n",
		mods = opts.mods or "CTRL|SHIFT",
		action = M.show_notifications(),
	}
end

return M
