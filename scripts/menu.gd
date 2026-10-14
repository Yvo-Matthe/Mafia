extends Control
## Title screen: play against the computer, host an online game, or join one.
## Command-line shortcuts (after `--`): --autoplay, --host, --join=<address>.

var _status: Label
var _port: LineEdit
var _address: LineEdit
var _buttons: Array[Button] = []
var _cancel: Button


func _ready() -> void:
	name = "Menu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_build()
	_status.text = Net.status_message
	Net.status_message = ""
	_handle_command_line.call_deferred()


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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(460, 0)
	panel.add_child(col)

	_label(col, "Mafia: City of Families", 36, Color(0.95, 0.85, 0.5))
	_label(col, "Take the city, one district at a time.", 16, Color(0.75, 0.75, 0.75))

	_buttons.append(_button(col, "Play against the computer", _on_single))

	_label(col, "Online, 2 players", 20, Color(0.92, 0.92, 0.92))
	var host_row := HBoxContainer.new()
	col.add_child(host_row)
	_port = LineEdit.new()
	_port.text = str(Net.DEFAULT_PORT)
	_port.placeholder_text = "Port"
	_port.custom_minimum_size = Vector2(110, 0)
	host_row.add_child(_port)
	var host_btn := _button(host_row, "Host a game", _on_host)
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buttons.append(host_btn)

	var join_row := HBoxContainer.new()
	col.add_child(join_row)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host address, e.g. 192.168.1.20 or 1.2.3.4:7777"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_address)
	_buttons.append(_button(join_row, "Join", _on_join))

	_cancel = _button(col, "Cancel", _on_cancel)
	_cancel.visible = false

	_status = _label(col, "", 15, Color(1.0, 0.9, 0.6))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(col, "The host plays the blue Corrado family, the player who joins plays the red Morettis.\nOver the internet the host must forward UDP port %d on their router." % Net.DEFAULT_PORT, 13, Color(0.6, 0.6, 0.6)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buttons.append(_button(col, "Quit", func(): get_tree().quit()))


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


func _handle_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	Net.autoplay = "--autoplay" in args
	for a in args:
		if a == "--host":
			_on_host()
			return
		if a.begins_with("--join="):
			_address.text = a.trim_prefix("--join=")
			_on_join()
			return
	if Net.autoplay:
		_on_single()


func _on_single() -> void:
	Net.play_single()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_host() -> void:
	var port := int(_port.text) if _port.text.is_valid_int() else Net.DEFAULT_PORT
	var err := Net.host(port)
	if err != OK:
		_status.text = "Could not open port %d (error %d). Is another game already hosting?" % [port, err]
		return
	var ips := Array(IP.get_local_addresses()).filter(
		func(a): return a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."))
	_status.text = "Waiting for a player to join on port %d.\nYour local address: %s" % [port, ", ".join(ips) if not ips.is_empty() else "unknown"]
	_set_waiting(true)
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


func _on_cancel() -> void:
	Net.leave()
	_status.text = ""
	_set_waiting(false)


func _on_peer_connected(_id: int) -> void:
	if Net.mode == Net.Mode.HOST:
		start_match.rpc()


func _on_connected() -> void:
	_status.text = "Connected. Waiting for the host to start..."


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
	_status.text = "The host closed the game."


@rpc("authority", "call_local", "reliable")
func start_match() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
