extends CanvasLayer
## Screen-space interface: treasury bar, recruit panel, selection info,
## business panel, territory screen, notifications, minimap and the
## end-of-match banner.

var main: Node

var _money: Label
var _income: Label
var _districts: Label
var _army: Label
var _rivals := {}  # family -> Label
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
var _rackets: Label
var _biz_panel: PanelContainer
var _biz_title: Label
var _biz_info: Label
var _biz_button: Button
var _territory: PanelContainer
var _territory_grid: GridContainer
var _territory_totals: Label
var _territory_timer := 0.0


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
	bar.add_theme_constant_override("separation", 22)
	top.add_child(bar)
	_money = _label(bar, 22, Color(0.95, 0.85, 0.4))
	_income = _label(bar, 18)
	_districts = _label(bar, 18)
	_rackets = _label(bar, 18)
	_army = _label(bar, 18)
	for f in main.active_families():
		if f != main.local_family:
			_rivals[f] = _label(bar, 16, GameData.FAMILY_COLORS[f].lightened(0.3))
	var terr_btn := Button.new()
	terr_btn.text = "Territory  [Tab]"
	terr_btn.focus_mode = Control.FOCUS_NONE
	terr_btn.pressed.connect(toggle_territory)
	bar.add_child(terr_btn)

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
	help.text = "Left-drag: select · Right-click: move / attack / lean on a business · A + click: attack-move · S: stop\nClick a business: details · T: take it over · Tab: territory · F: select all · 1/2/3: recruit · H: home\nP: pause · Arrows, screen edge or middle-drag: pan · Wheel: zoom"

	# Minimap (bottom-right)
	_minimap = preload("res://scripts/minimap.gd").new()
	_minimap.main = main
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -312
	_minimap.offset_top = -218
	_minimap.offset_right = -12
	_minimap.offset_bottom = -12
	root.add_child(_minimap)

	_build_business_panel(root)
	_build_territory(root)

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
	again.text = "Back to menu  [R]" if main.online else "Play again  [R]"
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(main.restart)
	end_box.add_child(again)
	for l in [_end_title, _end_reason]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_business_panel(root: Control) -> void:
	_biz_panel = PanelContainer.new()
	_biz_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_biz_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_biz_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_biz_panel.offset_bottom = -12
	_biz_panel.custom_minimum_size = Vector2(360, 0)
	_biz_panel.add_theme_stylebox_override("panel", _panel_style())
	_biz_panel.visible = false
	root.add_child(_biz_panel)
	var col := VBoxContainer.new()
	_biz_panel.add_child(col)
	_biz_title = _label(col, 20, Color(0.95, 0.85, 0.5))
	_biz_info = _label(col, 14)
	_biz_button = Button.new()
	_biz_button.focus_mode = Control.FOCUS_NONE
	_biz_button.pressed.connect(main.takeover_selected)
	col.add_child(_biz_button)


func _build_territory(root: Control) -> void:
	_territory = PanelContainer.new()
	_territory.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_territory.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_territory.grow_vertical = Control.GROW_DIRECTION_BOTH
	_territory.add_theme_stylebox_override("panel", _panel_style())
	_territory.visible = false
	root.add_child(_territory)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_territory.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label(head, 26, Color(0.95, 0.85, 0.5))
	title.text = "Territory and rackets"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "Close  [Tab]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle_territory)
	head.add_child(close)
	var hint := _label(col, 13, Color(0.7, 0.7, 0.7))
	hint.text = "Income is per %d seconds. Run a district by holding more than half its businesses. Click a district to go there." % GameData.INCOME_INTERVAL
	_territory_grid = GridContainer.new()
	_territory_grid.columns = 7
	_territory_grid.add_theme_constant_override("h_separation", 22)
	_territory_grid.add_theme_constant_override("v_separation", 4)
	col.add_child(_territory_grid)
	_territory_totals = _label(col, 16, Color(0.95, 0.85, 0.4))


func territory_visible() -> bool:
	return _territory.visible


func toggle_territory() -> void:
	_territory.visible = not _territory.visible
	if _territory.visible:
		_refresh_territory()


func _refresh_territory() -> void:
	for c in _territory_grid.get_children():
		_territory_grid.remove_child(c)
		c.queue_free()
	var p: int = main.local_family
	for h in ["District", "Run by", "Businesses", "Ours (protected / owned)", "Rivals", "Our income", "Bonus"]:
		_label(_territory_grid, 14, Color(0.7, 0.65, 0.5)).text = h
	var total_ours := 0
	for d in main.districts:
		var go := Button.new()
		go.text = d.district_name
		go.flat = true
		go.alignment = HORIZONTAL_ALIGNMENT_LEFT
		go.focus_mode = Control.FOCUS_NONE
		go.pressed.connect(func():
			main.center_camera(d.center())
			toggle_territory())
		_territory_grid.add_child(go)
		var boss := "nobody"
		var boss_col := Color(0.7, 0.7, 0.7)
		if d.controller != GameData.NEUTRAL:
			boss = GameData.FAMILY_SHORT[d.controller]
			boss_col = GameData.FAMILY_COLORS[d.controller].lightened(0.3)
		_label(_territory_grid, 15, boss_col).text = boss
		_label(_territory_grid, 15).text = "%d  ($%d takings)" % [d.businesses.size(), d.total_takings()]
		var held: int = d.held_by(p)
		var owned: int = d.owned_by(p)
		total_ours += held
		_label(_territory_grid, 15, GameData.FAMILY_COLORS[p].lightened(0.4)).text = "%d  (%d / %d)" % [held, held - owned, owned]
		var rivals := []
		for f in main.active_families():
			if f != p and d.held_by(f) > 0:
				rivals.append("%s %d" % [GameData.FAMILY_SHORT[f], d.held_by(f)])
		_label(_territory_grid, 14, Color(0.85, 0.7, 0.7)).text = ", ".join(rivals) if not rivals.is_empty() else "-"
		_label(_territory_grid, 15, Color(0.95, 0.85, 0.4)).text = "$%d" % d.income_for(p)
		_label(_territory_grid, 14, Color(0.8, 0.8, 0.8)).text = "$%d%s" % [d.bonus, "  (ours)" if d.controller == p else ""]
	var parts: Dictionary = main.income_breakdown(p)
	_territory_totals.text = "Protection $%d  +  Owned businesses $%d  +  District bonuses $%d  +  Headquarters $%d  =  $%d per %ds\nBusinesses: %d of %d (%d owned)  ·  Districts run: %d of %d" % [
		parts["protection"], parts["owned"], parts["bonus"], parts["hq"], main.income_of(p), GameData.INCOME_INTERVAL,
		total_ours, main.businesses.size(), main.businesses_held(p, true), main.districts_owned(p), main.districts.size()]


func _update_business_panel() -> void:
	var b = main.selected_business
	_biz_panel.visible = b != null
	if b == null:
		return
	var p: int = main.local_family
	_biz_title.text = b.business_name
	var lines := [
		"%s in %s, %s" % [b.type_name(), main.districts[b.district].district_name, b.status_text()],
		"Takings $%d · protection $%d · takeover $%d" % [b.takings, b.protection(), b.takeover_cost()],
	]
	if b.contested:
		lines.append("Rival crews are fighting over it")
	elif b.control_family != GameData.NEUTRAL and b.control < 99.5:
		lines.append("%s pressure: %d%%" % [GameData.FAMILY_SHORT[b.control_family], int(b.control)])
	if b.owner_family != p:
		lines.append("Select crew and right-click it to lean on it")
	_biz_info.text = "\n".join(lines)
	var err: String = b.takeover_error(p, main.money[p])
	_biz_button.visible = b.owner_family == p and b.status != Business.Status.OWNED
	_biz_button.disabled = err != ""
	_biz_button.text = "Take over for $%d  [T]" % b.takeover_cost()
	_biz_button.tooltip_text = err if err != "" else "Pays its full takings ($%d) instead of protection ($%d)" % [b.takings, b.protection()]


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


## The local family is out but the war goes on; the player can keep watching.
func show_eliminated() -> void:
	_end_title.text = "Your family has fallen."
	_end_title.add_theme_color_override("font_color", GameData.FAMILY_COLORS[main.local_family].lightened(0.3))
	_end_reason.text = "Your headquarters burned. The war goes on without you."
	_end_panel.visible = true


func show_end(team: int, reason: String) -> void:
	if team < 0:
		_end_title.text = "Match over."
	else:
		var won: bool = team == main.teams[main.local_family]
		var allied: bool = main.active_families().filter(func(f): return main.teams[f] == team).size() > 1
		if won:
			_end_title.text = "Your side takes the city." if allied else "The city is yours."
		else:
			_end_title.text = "Your family has fallen."
		var lead: int = main.local_family if won else main.active_families().filter(func(f): return main.teams[f] == team)[0]
		_end_title.add_theme_color_override("font_color", GameData.FAMILY_COLORS[lead].lightened(0.3))
	_end_reason.text = reason + "\nTime: %d:%02d" % [int(main.match_time) / 60, int(main.match_time) % 60]
	_end_panel.visible = true


func _process(delta: float) -> void:
	var p: int = main.local_family
	var units: Array = main.get_units(p)
	_money.text = "%s  $%d" % [GameData.FAMILY_SHORT[p], main.money[p]]
	_income.text = "+$%d every %ds" % [main.income_of(p), GameData.INCOME_INTERVAL]
	_districts.text = "Districts %d / %d" % [main.districts_owned(p), main.districts.size()]
	_rackets.text = "Businesses %d (%d owned)" % [main.businesses_held(p), main.businesses_held(p, true)]
	_army.text = "Crew %d / %d" % [units.size(), GameData.POP_CAP]
	for f in _rivals:
		var tag := ""
		if main.eliminated[f]:
			tag = "  (out)"
		elif main.teams[f] == main.teams[p]:
			tag = "  (ally)"
		_rivals[f].text = "%s %d dist · %d biz · %d crew%s" % [GameData.FAMILY_SHORT[f], main.districts_owned(f), main.businesses_held(f), main.get_units(f).size(), tag]

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

	_update_business_panel()
	if _territory.visible:
		_territory_timer -= delta
		if _territory_timer <= 0.0:
			_territory_timer = 0.5
			_refresh_territory()

	_notice_time -= delta
	_notice.visible = _notice_time > 0.0
	_minimap.queue_redraw()
