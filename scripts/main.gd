extends Node2D
## Root of a match: builds the city, tracks money and victory, and turns
## player input into orders.

const DRAG_THRESHOLD := 6.0
const CAMERA_SPEED := 900.0
const EDGE_MARGIN := 10.0
const ZOOM_MIN := 0.45
const ZOOM_MAX := 1.6
const AUTOPLAY_TIME_LIMIT := 1800.0

var world: Node2D
var camera: Camera2D
var hud: CanvasLayer
var overlay: Node2D
var districts: Array = []
var hqs: Array = [null, null]
var money: Array = [GameData.START_MONEY, GameData.START_MONEY]
var selected: Array = []
var hq_selected := false
var game_over := false
var winner := -1
var match_time := 0.0
var autoplay := false
var attack_move_armed := false

var drag_active := false
var drag_start := Vector2.ZERO
var markers: Array = []  # {pos, age, attack}

var _income_timer := 0.0
var _left_down := false
var _pan_drag := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	autoplay = "--autoplay" in OS.get_cmdline_user_args()

	world = Node2D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	_build_city()
	_spawn_families()

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	center_camera(hqs[GameData.PLAYER].position + Vector2(250, 150))

	overlay = preload("res://scripts/overlay.gd").new()
	overlay.main = self
	overlay.z_index = 100
	add_child(overlay)

	hud = preload("res://scripts/hud.gd").new()
	hud.main = self
	add_child(hud)

	var rival := RivalAI.new()
	rival.setup(self, GameData.RIVAL)
	world.add_child(rival)
	if autoplay:
		var stand_in := RivalAI.new()
		stand_in.setup(self, GameData.PLAYER)
		world.add_child(stand_in)
		print("AUTOPLAY: AI vs AI match started")


func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1931
	var block := Vector2(
		(GameData.WORLD_SIZE.x - GameData.STREET * (GameData.COLS + 1)) / GameData.COLS,
		(GameData.WORLD_SIZE.y - GameData.STREET * (GameData.ROWS + 1)) / GameData.ROWS)
	for r in GameData.ROWS:
		for c in GameData.COLS:
			var i := r * GameData.COLS + c
			var pos := Vector2(GameData.STREET + c * (block.x + GameData.STREET), GameData.STREET + r * (block.y + GameData.STREET))
			var d := District.new()
			d.setup(i, Rect2(pos, block), GameData.DISTRICTS[i], rng)
			d.owner_changed.connect(_on_district_owner_changed)
			world.add_child(d)
			districts.append(d)


func _spawn_families() -> void:
	for f in 2:
		var home: District = districts[GameData.HOME_DISTRICTS[f]]
		home.set_owner_family(f)
		var hq := HQ.new()
		hq.setup(self, f, home.center())
		world.add_child(hq)
		hqs[f] = hq
		for i in 3:
			var u = spawn_unit(f, "thug", hq.rally_point + Vector2(i * 26 - 26, 0))
			u.command_stop()


# --- Queries used by units, HQs and the AI -------------------------------

func get_units(family := -1) -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("units"):
		if n.hp > 0.0 and (family < 0 or n.family == family):
			out.append(n)
	return out


func find_enemy_unit_near(pos: Vector2, family: int, radius: float):
	var best = null
	var best_d := radius
	for u in get_tree().get_nodes_in_group("units"):
		if u.family == family or u.hp <= 0.0:
			continue
		var dist: float = pos.distance_to(u.position) - u.radius
		if dist < best_d:
			best_d = dist
			best = u
	return best


func find_enemy_near(pos: Vector2, family: int, radius: float):
	var best = find_enemy_unit_near(pos, family, radius)
	if best != null:
		return best
	var enemy_hq = hqs[1 - family]
	if enemy_hq != null and enemy_hq.hp > 0.0 and pos.distance_to(enemy_hq.position) - enemy_hq.radius < radius:
		return enemy_hq
	return null


## Push-apart vector so crowds don't stack on one pixel.
func separation(unit) -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("units"):
		if other == unit:
			continue
		var offset: Vector2 = unit.position - other.position
		var min_dist: float = unit.radius + other.radius + 2.0
		var dist := offset.length()
		if dist < min_dist:
			if dist < 0.01:
				offset = Vector2.RIGHT.rotated(randf() * TAU)
				dist = 0.01
			push += offset / dist * (min_dist - dist) * 8.0
	return push


func income_of(family: int) -> int:
	var total := 0
	if hqs[family] != null and hqs[family].hp > 0.0:
		total += GameData.HQ_INCOME
	for d in districts:
		if d.owner_family == family:
			total += d.income
	return total


func districts_owned(family: int) -> int:
	return districts.filter(func(d): return d.owner_family == family).size()


func spawn_unit(family: int, type_id: String, pos: Vector2):
	var u := Unit.new()
	u.setup(self, family, type_id, pos)
	world.add_child(u)
	return u


func issue_move(units: Array, target: Vector2, attacking: bool) -> void:
	var spots := _formation(target, units.size())
	for i in units.size():
		if attacking:
			units[i].command_attack_move(spots[i])
		else:
			units[i].command_move(spots[i])


func issue_attack_move(units: Array, target: Vector2) -> void:
	issue_move(units, target, true)


func _formation(center: Vector2, n: int) -> Array:
	var cols := int(ceil(sqrt(n)))
	var rows := int(ceil(float(n) / cols))
	var spacing := 30.0
	var out := []
	for i in n:
		var cell := Vector2(i % cols, i / cols)
		out.append(center + (cell - Vector2(cols - 1, rows - 1) / 2.0) * spacing)
	return out


func on_unit_died(u) -> void:
	selected.erase(u)


func _on_district_owner_changed(d, previous: int) -> void:
	if autoplay:
		return
	if d.owner_family == GameData.PLAYER:
		hud.notify("We took %s" % d.district_name)
	elif previous == GameData.PLAYER:
		hud.notify("We lost %s" % d.district_name)
	elif d.owner_family == GameData.RIVAL:
		hud.notify("The Morettis took %s" % d.district_name)


# --- Simulation ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	match_time += delta
	_income_timer += delta
	if _income_timer >= GameData.INCOME_INTERVAL:
		_income_timer -= GameData.INCOME_INTERVAL
		for f in 2:
			money[f] += income_of(f)

	var units := get_units()
	for d in districts:
		d.update_capture(delta, units)

	for m in markers:
		m["age"] += delta
	markers = markers.filter(func(m): return m["age"] < 0.6)

	_check_victory()
	if autoplay and not game_over and match_time > AUTOPLAY_TIME_LIMIT:
		print("AUTOPLAY RESULT: draw after %.0fs, districts %d-%d" % [match_time, districts_owned(0), districts_owned(1)])
		get_tree().quit(0)


func _check_victory() -> void:
	if game_over:
		return
	for f in 2:
		if hqs[f].hp <= 0.0:
			_end_match(1 - f, "%s headquarters was burned to the ground." % ("Your" if f == GameData.PLAYER else "The Moretti"))
			return
		if districts_owned(f) == districts.size():
			_end_match(f, "%s controls every district in the city." % GameData.FAMILY_NAMES[f])
			return


func _end_match(w: int, reason: String) -> void:
	game_over = true
	winner = w
	get_tree().paused = true
	if autoplay:
		print("AUTOPLAY RESULT: winner=%s after %.0fs (%s) districts %d-%d" % [
			GameData.FAMILY_NAMES[w], match_time, reason, districts_owned(0), districts_owned(1)])
		get_tree().quit(0)
		return
	hud.show_end(w, reason)


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# --- Player commands ----------------------------------------------------------

func recruit(type_id: String) -> void:
	if game_over or get_tree().paused:
		return
	var hq = hqs[GameData.PLAYER]
	var err: String = hq.enqueue_error(type_id)
	if err != "":
		hud.notify(err)
		return
	hq.enqueue(type_id)


func set_selection(units: Array, select_hq := false) -> void:
	for u in selected:
		if is_instance_valid(u):
			u.selected = false
	selected = units.duplicate()
	for u in selected:
		u.selected = true
	hq_selected = select_hq
	hqs[GameData.PLAYER].selected = select_hq


func center_camera(p: Vector2) -> void:
	camera.position = p
	_clamp_camera()


func _clamp_camera() -> void:
	var half := get_viewport_rect().size / camera.zoom / 2.0
	var lo := half - Vector2(200, 200)
	var hi := GameData.WORLD_SIZE - half + Vector2(200, 200)
	camera.position = Vector2(
		clampf(camera.position.x, minf(lo.x, hi.x), maxf(lo.x, hi.x)),
		clampf(camera.position.y, minf(lo.y, hi.y), maxf(lo.y, hi.y)))


func _process(delta: float) -> void:
	selected = selected.filter(func(u): return is_instance_valid(u) and u.hp > 0.0)
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if not autoplay and DisplayServer.window_is_focused() and not _pan_drag:
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		if Rect2(Vector2.ZERO, vs).has_point(mp):
			if mp.x < EDGE_MARGIN:
				dir.x -= 1
			elif mp.x > vs.x - EDGE_MARGIN:
				dir.x += 1
			if mp.y < EDGE_MARGIN:
				dir.y -= 1
			elif mp.y > vs.y - EDGE_MARGIN:
				dir.y += 1
	if dir != Vector2.ZERO:
		camera.position += dir.normalized() * CAMERA_SPEED * delta / camera.zoom.x
		_clamp_camera()
	overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _pan_drag:
			camera.position -= event.relative / camera.zoom
			_clamp_camera()
		elif _left_down and not drag_active:
			if (get_global_mouse_position() - drag_start).length() * camera.zoom.x > DRAG_THRESHOLD:
				drag_active = true


func _handle_key(event: InputEventKey) -> void:
	if game_over:
		if event.keycode == KEY_R:
			restart()
		return
	match event.keycode:
		KEY_P:
			get_tree().paused = not get_tree().paused
			hud.set_paused(get_tree().paused)
		KEY_1:
			recruit("thug")
		KEY_2:
			recruit("enforcer")
		KEY_3:
			recruit("hitman")
		KEY_A:
			if not selected.is_empty():
				attack_move_armed = true
		KEY_S:
			for u in selected:
				u.command_stop()
		KEY_F:
			set_selection(get_units(GameData.PLAYER))
		KEY_H, KEY_SPACE:
			center_camera(hqs[GameData.PLAYER].position)
		KEY_ESCAPE:
			if attack_move_armed:
				attack_move_armed = false
			else:
				set_selection([])


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var wp := get_global_mouse_position()
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var factor := 1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
				var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
				camera.zoom = Vector2(z, z)
				_clamp_camera()
		MOUSE_BUTTON_MIDDLE:
			_pan_drag = event.pressed
		MOUSE_BUTTON_LEFT:
			if get_tree().paused:
				return
			if event.pressed:
				if attack_move_armed:
					attack_move_armed = false
					_order_at(wp, true)
					return
				_left_down = true
				drag_active = false
				drag_start = wp
			elif _left_down:
				_left_down = false
				_finish_selection(wp, event.shift_pressed)
				drag_active = false
		MOUSE_BUTTON_RIGHT:
			if event.pressed and not get_tree().paused:
				attack_move_armed = false
				_order_at(wp, false)


func _finish_selection(wp: Vector2, additive: bool) -> void:
	var picked := []
	if drag_active:
		var box := Rect2(drag_start, wp - drag_start).abs()
		for u in get_units(GameData.PLAYER):
			if box.has_point(u.position):
				picked.append(u)
	else:
		var best = null
		var best_d := INF
		for u in get_units(GameData.PLAYER):
			var dist: float = wp.distance_to(u.position)
			if dist < u.radius + 6.0 and dist < best_d:
				best = u
				best_d = dist
		if best != null:
			picked.append(best)
		elif not additive and wp.distance_to(hqs[GameData.PLAYER].position) < hqs[GameData.PLAYER].radius:
			set_selection([], true)
			return
	if additive:
		for u in selected:
			if not picked.has(u):
				picked.append(u)
	set_selection(picked)


func _order_at(wp: Vector2, attack_move: bool) -> void:
	if selected.is_empty():
		if hq_selected:
			hqs[GameData.PLAYER].rally_point = wp
		return
	var target = find_enemy_near(wp, GameData.PLAYER, 14.0)
	if target != null:
		for u in selected:
			u.command_attack(target)
		markers.append({"pos": target.position, "age": 0.0, "attack": true})
		return
	issue_move(selected, wp, attack_move)
	markers.append({"pos": wp, "age": 0.0, "attack": attack_move})


func _draw() -> void:
	# Asphalt and lane markings under the blocks.
	draw_rect(Rect2(Vector2.ZERO, GameData.WORLD_SIZE), Color(0.11, 0.11, 0.12))
	var dash := Color(0.75, 0.68, 0.35, 0.5)
	var block: Vector2 = districts[0].rect.size if not districts.is_empty() else Vector2(500, 500)
	for c in GameData.COLS + 1:
		var x: float = GameData.STREET / 2.0 + c * (block.x + GameData.STREET)
		for y in range(0, int(GameData.WORLD_SIZE.y), 40):
			draw_line(Vector2(x, y), Vector2(x, y + 20), dash, 2.0)
	for r in GameData.ROWS + 1:
		var y: float = GameData.STREET / 2.0 + r * (block.y + GameData.STREET)
		for x in range(0, int(GameData.WORLD_SIZE.x), 40):
			draw_line(Vector2(x, y), Vector2(x + 20, y), dash, 2.0)
	draw_rect(Rect2(Vector2.ZERO, GameData.WORLD_SIZE), Color(0.3, 0.3, 0.32), false, 6.0)
