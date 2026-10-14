extends CanvasLayer
## Screen-space interface: treasury bar, recruit panel, selection info,
## notifications, minimap and the end-of-match banner.

var main: Node

var _money: Label
var _income: Label
var _districts: Label
var _army: Label
var _rival: Label
var _buttons := {}
var _queue: Label
var _selection: Label
var _notice: Label
var _notice_time := 0.0
var _paused: Label
var _end_panel: PanelContainer
var _end_title: Label
var _end_reason: Label
var _minimap: Control


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top bar
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 36)
	top.add_child(bar)
	_money = _label(bar, 22, Color(0.95, 0.85, 0.4))
	_income = _label(bar, 18)
	_districts = _label(bar, 18)
	_army = _label(bar, 18)
	_rival = _label(bar, 18, GameData.FAMILY_COLORS[GameData.RIVAL].lightened(0.3))

	# Recruit panel (bottom-left)
	var cmd := PanelContainer.new()
	cmd.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	cmd.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cmd.offset_left = 12
	cmd.offset_bottom = -12
	cmd.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(cmd)
	var col := VBoxContainer.new()
	cmd.add_child(col)
	_label(col, 16).text = "Recruit at headquarters"
	var row := HBoxContainer.new()
	col.add_child(row)
	for i in GameData.UNIT_ORDER.size():
		var t: String = GameData.UNIT_ORDER[i]
		var s: Dictionary = GameData.UNIT_TYPES[t]
		var b := Button.new()
		b.text = "%s\n$%d   [%d]" % [s["name"], s["cost"], i + 1]
		b.tooltip_text = "HP %d  ·  Damage %d  ·  Range %d  ·  Speed %d" % [s["hp"], s["damage"], s["range"], s["speed"]]
		b.custom_minimum_size = Vector2(120, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(main.recruit.bind(t))
		row.add_child(b)
		_buttons[t] = b
	_queue = _label(col, 14)
	_selection = _label(col, 14, Color(0.6, 1.0, 0.6))
	var help := _label(col, 12, Color(0.7, 0.7, 0.7))
	help.text = "Left-drag: select · Right-click: move / attack · A + click: attack-move · S: stop\nF: select all · 1/2/3: recruit · H: home · P: pause · Arrows, screen edge or middle-drag: pan · Wheel: zoom"

	# Minimap (bottom-right)
	_minimap = preload("res://scripts/minimap.gd").new()
	_minimap.main = main
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -252
	_minimap.offset_top = -192
	_minimap.offset_right = -12
	_minimap.offset_bottom = -12
	root.add_child(_minimap)

	# Notifications and pause
	_notice = _label(root, 20, Color(1.0, 0.92, 0.6))
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.offset_top = 96
	_notice.offset_left = -300
	_notice.offset_right = 300
	_paused = _label(root, 48)
	_paused.text = "PAUSED"
	_paused.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_paused.visible = false

	# End banner
	_end_panel = PanelContainer.new()
	_end_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_end_panel.visible = false
	_end_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_end_panel)
	var end_box := VBoxContainer.new()
	end_box.alignment = BoxContainer.ALIGNMENT_CENTER
	end_box.add_theme_constant_override("separation", 14)
	_end_panel.add_child(end_box)
	_end_title = _label(end_box, 44)
	_end_reason = _label(end_box, 20)
	var again := Button.new()
	again.text = "Play again  [R]"
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(main.restart)
	end_box.add_child(again)
	for l in [_end_title, _end_reason]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.06, 0.88)
	sb.border_color = Color(0.55, 0.45, 0.25, 0.8)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	return sb


func _label(parent: Node, font_size: int, color := Color(0.92, 0.92, 0.92)) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func notify(text: String) -> void:
	_notice.text = text
	_notice_time = 3.0


func set_paused(p: bool) -> void:
	_paused.visible = p


func show_end(winner: int, reason: String) -> void:
	_end_title.text = "The city is yours." if winner == GameData.PLAYER else "Your family has fallen."
	_end_title.add_theme_color_override("font_color", GameData.FAMILY_COLORS[winner].lightened(0.3))
	_end_reason.text = reason + "\nTime: %d:%02d" % [int(main.match_time) / 60, int(main.match_time) % 60]
	_end_panel.visible = true


func _process(delta: float) -> void:
	var p := GameData.PLAYER
	var units: Array = main.get_units(p)
	_money.text = "$%d" % main.money[p]
	_income.text = "+$%d every %ds" % [main.income_of(p), GameData.INCOME_INTERVAL]
	_districts.text = "Districts %d / %d" % [main.districts_owned(p), main.districts.size()]
	_army.text = "Crew %d / %d" % [units.size(), GameData.POP_CAP]
	_rival.text = "Morettis: %d districts, %d crew" % [main.districts_owned(GameData.RIVAL), main.get_units(GameData.RIVAL).size()]

	var hq = main.hqs[p]
	for t in _buttons:
		_buttons[t].disabled = hq.enqueue_error(t) != ""
	if hq.queue.is_empty():
		_queue.text = "Queue: empty"
	else:
		var names: Array = hq.queue.map(func(t): return GameData.UNIT_TYPES[t]["name"])
		_queue.text = "Queue: %s  (%d%%)" % [", ".join(names), int(hq.current_build_fraction() * 100.0)]

	if main.hq_selected:
		_selection.text = "Headquarters selected: right-click to set the rally point"
	elif main.selected.is_empty():
		_selection.text = ""
	else:
		var counts := {}
		for u in main.selected:
			counts[u.stats["name"]] = counts.get(u.stats["name"], 0) + 1
		var parts := []
		for k in counts:
			parts.append("%d %s%s" % [counts[k], k, "s" if counts[k] > 1 else ""])
		_selection.text = "Selected: " + ", ".join(parts)

	_notice_time -= delta
	_notice.visible = _notice_time > 0.0
	_minimap.queue_redraw()
