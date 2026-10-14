extends Control
## Title screen and pre-match lobby. Single player and hosting both lead to
## the lobby, where each of the four family seats is set to a player, a
## computer family or empty, and given a team.
## Command-line shortcuts (after `--`): --autoplay, --host, --join=<address>,
## --slots=you,ai,open,closed  --teams=0,1,2,3

const SEAT_CHOICES_ONLINE := ["open", "ai", "closed"]
const SEAT_CHOICES_OFFLINE := ["ai", "closed"]
const SEAT_LABELS := {"open": "Open for a player", "ai": "Computer", "closed": "Empty"}

var _main_box: VBoxContainer
var _lobby_box: VBoxContainer
var _rows: VBoxContainer
var _status: Label
var _lobby_status: Label
var _start: Button
var _port: LineEdit
var _address: LineEdit
var _buttons: Array[Button] = []
var _cancel: Button


func _ready() -> void:
	name = "Menu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_build()
	_status.text = Net.status_message
	Net.status_message = ""
	_handle_command_line.call_deferred()


# --- Layout ------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.09, 0.08)
	sb.border_color = Color(0.55, 0.45, 0.25)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 14)
	_main_box.custom_minimum_size = Vector2(500, 0)
	stack.add_child(_main_box)
	_label(_main_box, "Mafia: City of Families", 36, Color(0.95, 0.85, 0.5))
	_label(_main_box, "Take the city, one district at a time.", 16, Color(0.75, 0.75, 0.75))
	_buttons.append(_button(_main_box, "Play against the computer", _on_single))

	_label(_main_box, "Online, up to 4 players", 20, Color(0.92, 0.92, 0.92))
	var host_row := HBoxContainer.new()
	_main_box.add_child(host_row)
	_port = LineEdit.new()
	_port.text = str(Net.DEFAULT_PORT)
	_port.placeholder_text = "Port"
	_port.custom_minimum_size = Vector2(110, 0)
	host_row.add_child(_port)
	var host_btn := _button(host_row, "Host a game", _on_host)
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buttons.append(host_btn)

	var join_row := HBoxContainer.new()
	_main_box.add_child(join_row)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host address, e.g. 192.168.1.20 or 1.2.3.4:7777"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_address)
	_buttons.append(_button(join_row, "Join", _on_join))

	_cancel = _button(_main_box, "Cancel", _on_leave_lobby)
	_cancel.visible = false
	_status = _label(_main_box, "", 15, Color(1.0, 0.9, 0.6))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(_main_box, "Over the internet the host must forward UDP port %d on their router." % Net.DEFAULT_PORT,
		13, Color(0.6, 0.6, 0.6)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buttons.append(_button(_main_box, "Quit", func(): get_tree().quit()))

	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 12)
	_lobby_box.custom_minimum_size = Vector2(560, 0)
	_lobby_box.visible = false
	stack.add_child(_lobby_box)
	_label(_lobby_box, "Set up the match", 30, Color(0.95, 0.85, 0.5))
	_label(_lobby_box, "Families on the same team are allies. Computer families can fill any seat.",
		14, Color(0.7, 0.7, 0.7)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	_lobby_box.add_child(_rows)
	_lobby_status = _label(_lobby_box, "", 15, Color(1.0, 0.9, 0.6))
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_lobby_box.add_child(actions)
	var back := _button(actions, "Back", _on_leave_lobby)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start = _button(actions, "Start the war", _on_start)
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _set_waiting(waiting: bool) -> void:
	for b in _buttons:
		b.disabled = waiting
	_cancel.visible = waiting


func _show_lobby(show: bool) -> void:
	_lobby_box.visible = show
	_main_box.visible = not show
	if show:
		_refresh_lobby()


# --- Lobby ---------------------------------------------------------------------

func _can_edit() -> bool:
	return Net.mode != Net.Mode.CLIENT


func _refresh_lobby() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var me := multiplayer.get_unique_id()
	for i in Net.slots.size():
		var slot: Dictionary = Net.slots[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_rows.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = GameData.FAMILY_COLORS[i]
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var fam := Label.new()
		fam.text = GameData.FAMILY_SHORT[i]
		fam.custom_minimum_size = Vector2(90, 0)
		row.add_child(fam)

		if slot["kind"] == "human":
			var who := Label.new()
			who.text = "You" if slot["peer"] == me else "Player (joined)"
			who.custom_minimum_size = Vector2(220, 0)
			row.add_child(who)
		else:
			var choices: Array = SEAT_CHOICES_ONLINE if Net.is_online() else SEAT_CHOICES_OFFLINE
			var seat := OptionButton.new()
			seat.custom_minimum_size = Vector2(220, 0)
			for k in choices:
				seat.add_item(SEAT_LABELS[k])
			var at := choices.find(slot["kind"])
			if at < 0:
				seat.add_item(SEAT_LABELS[slot["kind"]])
				at = seat.item_count - 1
			seat.select(at)
			seat.disabled = not _can_edit()
			seat.item_selected.connect(func(idx): _set_seat(i, choices[idx] if idx < choices.size() else slot["kind"]))
			row.add_child(seat)

		var team := OptionButton.new()
		for t in GameData.MAX_FAMILIES:
			team.add_item("Team %d" % (t + 1))
		team.select(slot["team"])
		team.disabled = not _can_edit() or slot["kind"] == "closed"
		team.item_selected.connect(func(idx): _set_team(i, idx))
		row.add_child(team)

	var err := _setup_error()
	_start.visible = _can_edit()
	_start.disabled = err != ""
	if not _can_edit():
		_lobby_status.text = "Waiting for the host to start the match..."
	elif err != "":
		_lobby_status.text = err
	elif Net.slots.any(func(s): return s["kind"] == "open"):
		_lobby_status.text = "Open seats will be left empty if you start now."
	else:
		_lobby_status.text = ""


func _setup_error() -> String:
	var teams := {}
	for s in Net.slots:
		if s["kind"] == "human" or s["kind"] == "ai":
			teams[s["team"]] = true
	if teams.size() < 2:
		return "Put at least two families on different teams."
	return ""


func _set_seat(i: int, kind: String) -> void:
	Net.slots[i]["kind"] = kind
	_sync_lobby()


func _set_team(i: int, team: int) -> void:
	Net.slots[i]["team"] = team
	_sync_lobby()


func _sync_lobby() -> void:
	_refresh_lobby()
	if Net.mode == Net.Mode.HOST:
		_lobby_sync.rpc(Net.slots)


@rpc("authority", "call_remote", "reliable")
func _lobby_sync(slots: Array) -> void:
	Net.slots = slots
	_show_lobby(true)


func _on_start() -> void:
	if _setup_error() != "":
		return
	if Net.mode == Net.Mode.HOST:
		start_match.rpc(Net.match_slots())
	else:
		start_match(Net.match_slots())


@rpc("authority", "call_local", "reliable")
func start_match(slots: Array) -> void:
	Net.slots = slots
	Net.local_family = Net.family_of_peer(multiplayer.get_unique_id())
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_leave_lobby() -> void:
	Net.leave()
	Net.slots = Net.default_slots(false)
	_status.text = ""
	_set_waiting(false)
	_show_lobby(false)


# --- Main menu actions ---------------------------------------------------------

func _handle_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	Net.autoplay = "--autoplay" in args
	var join_to := ""
	var hosting := false
	for a in args:
		if a == "--host":
			hosting = true
		elif a.begins_with("--join="):
			join_to = a.trim_prefix("--join=")
	if join_to != "":
		_address.text = join_to
		_on_join()
		return
	if hosting:
		_on_host()
	elif Net.autoplay:
		_on_single()
	else:
		return
	_apply_slot_args(args)
	if Net.autoplay:
		_maybe_autostart()


func _apply_slot_args(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--slots="):
			var kinds := a.trim_prefix("--slots=").split(",")
			for i in mini(kinds.size(), Net.slots.size()):
				if i > 0 and kinds[i] in ["ai", "open", "closed"]:
					Net.slots[i]["kind"] = kinds[i]
		elif a.begins_with("--teams="):
			var teams := a.trim_prefix("--teams=").split(",")
			for i in mini(teams.size(), Net.slots.size()):
				Net.slots[i]["team"] = clampi(int(teams[i]), 0, GameData.MAX_FAMILIES - 1)
	_sync_lobby()


## Under --autoplay, start as soon as no seat is waiting for a player.
func _maybe_autostart() -> void:
	if Net.autoplay and _can_edit() and not Net.slots.any(func(s): return s["kind"] == "open"):
		_on_start()


func _on_single() -> void:
	Net.play_single()
	_show_lobby(true)


func _on_host() -> void:
	var port := int(_port.text) if _port.text.is_valid_int() else Net.DEFAULT_PORT
	var err := Net.host(port)
	if err != OK:
		_status.text = "Could not open port %d (error %d). Is another game already hosting?" % [port, err]
		return
	_show_lobby(true)
	var ips := Array(IP.get_local_addresses()).filter(
		func(a): return a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."))
	_lobby_status.text = "Hosting on port %d. Your local address: %s" % [port, ", ".join(ips) if not ips.is_empty() else "unknown"]
	if Net.autoplay:
		print("NET: hosting on port %d" % port)


func _on_join() -> void:
	var text := _address.text.strip_edges()
	var port := Net.DEFAULT_PORT
	if text.contains(":"):
		port = int(text.get_slice(":", 1))
		text = text.get_slice(":", 0)
	var err := Net.join(text, port)
	if err != OK:
		_status.text = "Could not connect to %s:%d (error %d)." % [text, port, err]
		return
	_status.text = "Connecting to %s:%d..." % [text, port]
	_set_waiting(true)


func _on_peer_connected(id: int) -> void:
	if Net.mode != Net.Mode.HOST:
		return
	var seat := -1
	for kind in ["open", "closed"]:
		for i in range(1, Net.slots.size()):
			if seat < 0 and Net.slots[i]["kind"] == kind:
				seat = i
	if seat < 0:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	Net.slots[seat]["kind"] = "human"
	Net.slots[seat]["peer"] = id
	_sync_lobby()
	_maybe_autostart()


func _on_peer_disconnected(id: int) -> void:
	if Net.mode != Net.Mode.HOST:
		return
	var seat := Net.family_of_peer(id)
	if seat >= 0:
		Net.slots[seat]["kind"] = "open"
		Net.slots[seat]["peer"] = 0
		_sync_lobby()


func _on_connected() -> void:
	_status.text = "Connected. Waiting for the host..."


func _on_connection_failed() -> void:
	Net.leave()
	_set_waiting(false)
	_status.text = "Could not reach the host. Check the address and that port %d is open." % Net.DEFAULT_PORT
	if Net.autoplay:
		print("NET: connection failed")
		get_tree().quit(1)


func _on_server_disconnected() -> void:
	Net.leave()
	_set_waiting(false)
	_show_lobby(false)
	_status.text = "The host closed the game."
