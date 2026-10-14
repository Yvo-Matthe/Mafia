extends Node2D
## Root of a match: builds the city, tracks money and victory, and turns
## player input into orders.
##
## Online, the host runs the whole simulation. The joining player's game only
## draws the snapshots the host streams to it and sends its orders back.

const DRAG_THRESHOLD := 6.0
const CAMERA_SPEED := 900.0
const EDGE_MARGIN := 10.0
const ZOOM_MIN := 0.45
const ZOOM_MAX := 1.6
const AUTOPLAY_TIME_LIMIT := 1800.0
const SNAPSHOT_INTERVAL := 1.0 / 20.0

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

## The family this screen controls.
var local_family := GameData.PLAYER
## True everywhere except on a joined client, which only mirrors the host.
var is_authority := true
var online := false

var drag_active := false
var drag_start := Vector2.ZERO
var markers: Array = []  # {pos, age, attack}

var _units_by_id := {}
var _next_unit_id := 1
var _income_timer := 0.0
var _left_down := false
var _pan_drag := false
var _peer_ready := false
var _snapshot_timer := 0.0
var _bot_timer := 0.0
var _orders_received := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	autoplay = Net.autoplay
	online = Net.is_online()
	is_authority = Net.mode != Net.Mode.CLIENT
	local_family = Net.local_family

	world = Node2D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	_build_city()
	_spawn_families()

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	var toward_center: Vector2 = (GameData.WORLD_SIZE / 2.0 - hqs[local_family].position).normalized()
	center_camera(hqs[local_family].position + toward_center * 280.0)

	overlay = preload("res://scripts/overlay.gd").new()
	overlay.main = self
	overlay.z_index = 100
	add_child(overlay)

	hud = preload("res://scripts/hud.gd").new()
	hud.main = self
	add_child(hud)

	if not online:
		_add_ai(GameData.RIVAL)
	if autoplay and is_authority:
		_add_ai(local_family)
		print("AUTOPLAY: AI match started (%s)" % ["single player", "host", "client"][Net.mode])

	if online:
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		if is_authority:
			hud.notify("Waiting for the other player to load...")
		Net.announce_loaded()


func _add_ai(family: int) -> void:
	var ai := RivalAI.new()
	ai.setup(self, family)
	world.add_child(ai)


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
		if not is_authority:
			continue  # the host's snapshots bring the starting crews
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


func spawn_unit(family: int, type_id: String, pos: Vector2, id := -1):
	if id < 0:
		id = _next_unit_id
		_next_unit_id = _next_unit_id % 65535 + 1  # ids travel as 16 bits
	var u := Unit.new()
	u.setup(self, family, type_id, pos)
	u.net_id = id
	_units_by_id[id] = u
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
	_units_by_id.erase(u.net_id)


func _on_district_owner_changed(d, previous: int) -> void:
	if autoplay:
		return
	if d.owner_family == local_family:
		hud.notify("We took %s" % d.district_name)
	elif previous == local_family:
		hud.notify("We lost %s" % d.district_name)
	elif d.owner_family != GameData.NEUTRAL:
		hud.notify("The %ss took %s" % [GameData.FAMILY_SHORT[d.owner_family], d.district_name])


# --- Simulation ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if get_tree().paused or game_over:
		return
	for m in markers:
		m["age"] += delta
	markers = markers.filter(func(m): return m["age"] < 0.6)
	if not is_authority:
		if autoplay:
			_client_bot(delta)
		return
	if online and not _peer_ready:
		if not Net.remote_loaded:
			return
		_peer_ready = true
		hud.notify("The %s family has arrived. Take the city." % GameData.FAMILY_SHORT[1 - local_family])

	match_time += delta
	_income_timer += delta
	if _income_timer >= GameData.INCOME_INTERVAL:
		_income_timer -= GameData.INCOME_INTERVAL
		for f in 2:
			money[f] += income_of(f)

	var units := get_units()
	for d in districts:
		d.update_capture(delta, units)

	_check_victory()
	if online and not game_over:
		_snapshot_timer -= delta
		if _snapshot_timer <= 0.0:
			_snapshot_timer = SNAPSHOT_INTERVAL
			_receive_snapshot.rpc(_make_snapshot())
	if autoplay and not game_over and match_time > AUTOPLAY_TIME_LIMIT:
		print("AUTOPLAY RESULT: draw after %.0fs, districts %d-%d" % [match_time, districts_owned(0), districts_owned(1)])
		get_tree().quit(0)


func _check_victory() -> void:
	if game_over:
		return
	for f in 2:
		if hqs[f].hp <= 0.0:
			_end_match(1 - f, "The %s headquarters was burned to the ground." % GameData.FAMILY_SHORT[f])
			return
		if districts_owned(f) == districts.size():
			_end_match(f, "%s controls every district in the city." % GameData.FAMILY_NAMES[f])
			return


func _end_match(w: int, reason: String) -> void:
	if online and is_authority and multiplayer.get_peers().size() > 0:
		_receive_snapshot.rpc(_make_snapshot())
		_net_end_match.rpc(w, reason)
	_show_end(w, reason)


func _show_end(w: int, reason: String) -> void:
	if game_over:
		return
	game_over = true
	winner = w
	get_tree().paused = true
	if autoplay:
		print("AUTOPLAY RESULT: winner=%s after %.0fs (%s) districts %d-%d" % [
			GameData.FAMILY_NAMES[w] if w >= 0 else "none", match_time, reason, districts_owned(0), districts_owned(1)])
		if online and is_authority:
			print("NET: host applied %d orders from the joined player" % _orders_received)
		# Give a reliable end-of-match message time to reach the other side.
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(0)
		return
	hud.show_end(w, reason)


## Single player starts a new match; online goes back to the menu.
func restart() -> void:
	get_tree().paused = false
	if online:
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	else:
		get_tree().reload_current_scene()


# --- Networking --------------------------------------------------------------

func _make_snapshot() -> Array:
	# Units are packed into bytes (15 per unit) so a full army fits one packet.
	var buf := StreamPeerBuffer.new()
	for u in get_units():
		buf.put_u16(u.net_id & 0xFFFF)
		buf.put_u8(u.family)
		buf.put_u8(GameData.UNIT_ORDER.find(u.type_id))
		buf.put_16(int(u.position.x))
		buf.put_16(int(u.position.y))
		buf.put_u16(int(ceil(u.hp)))
		buf.put_u8(u.shots & 0xFF)
		buf.put_16(int(u.shot_to.x))
		buf.put_16(int(u.shot_to.y))
	var ds := []
	for d in districts:
		ds.append([d.owner_family, d.control, d.contested])
	var hs := []
	for h in hqs:
		hs.append([h.hp, Array(h.queue), h.build_progress, h.rally_point, h.shots, h.shot_to])
	return [match_time, money.duplicate(), buf.data_array, ds, hs]


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_snapshot(s: Array) -> void:
	if is_authority:
		return
	match_time = s[0]
	money = s[1]
	var seen := {}
	var buf := StreamPeerBuffer.new()
	buf.data_array = s[2]
	while buf.get_position() < buf.get_size():
		var id := buf.get_u16()
		var family := buf.get_u8()
		var type_index := buf.get_u8()
		var pos := Vector2(buf.get_16(), buf.get_16())
		var hp := float(buf.get_u16())
		var shots := buf.get_u8()
		var shot_to := Vector2(buf.get_16(), buf.get_16())
		seen[id] = true
		var u = _units_by_id.get(id)
		if u == null or not is_instance_valid(u):
			u = spawn_unit(family, GameData.UNIT_ORDER[type_index], pos, id)
		u.apply_net(pos, hp, shots, shot_to)
	for id in _units_by_id.keys():
		if not seen.has(id):
			_units_by_id[id].net_remove()
	for i in districts.size():
		districts[i].apply_net(s[3][i][0], s[3][i][1], s[3][i][2])
	for f in 2:
		hqs[f].apply_net(s[4][f])


@rpc("authority", "call_remote", "reliable")
func _net_end_match(w: int, reason: String) -> void:
	_show_end(w, reason)


func _on_peer_disconnected(_id: int) -> void:
	if not game_over:
		_show_end(local_family, "The %s family walked away from the table." % GameData.FAMILY_SHORT[1 - local_family])


func _on_server_disconnected() -> void:
	if not game_over:
		_show_end(-1, "Lost the connection to the host.")


func _sender_family() -> int:
	# Only the joining player sends orders; they always run the rival family.
	return GameData.RIVAL


func _ids(units: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for u in units:
		out.append(u.net_id)
	return out


func _own_units(family: int, ids: PackedInt32Array) -> Array:
	var out := []
	for id in ids:
		var u = _units_by_id.get(id)
		if u != null and is_instance_valid(u) and u.hp > 0.0 and u.family == family:
			out.append(u)
	return out


# --- Orders (applied directly on the host, sent to it from a client) ------

func request_recruit(type_id: String) -> void:
	if is_authority:
		_do_recruit(local_family, type_id)
	else:
		_net_recruit.rpc_id(1, type_id)


func request_move(units: Array, target: Vector2, attacking: bool) -> void:
	if is_authority:
		issue_move(units, target, attacking)
	else:
		_net_move.rpc_id(1, _ids(units), target, attacking)


func request_attack(units: Array, target) -> void:
	if is_authority:
		for u in units:
			u.command_attack(target)
	else:
		var code: int = target.net_id if target is Unit else -1 - target.family
		_net_attack.rpc_id(1, _ids(units), code)


func request_stop(units: Array) -> void:
	if is_authority:
		for u in units:
			u.command_stop()
	else:
		_net_stop.rpc_id(1, _ids(units))


func request_rally(p: Vector2) -> void:
	hqs[local_family].rally_point = p
	if not is_authority:
		_net_rally.rpc_id(1, p)


func _do_recruit(family: int, type_id: String) -> String:
	var err: String = hqs[family].enqueue_error(type_id)
	if err == "":
		hqs[family].enqueue(type_id)
	return err


@rpc("any_peer", "call_remote", "reliable")
func _net_recruit(type_id: String) -> void:
	_orders_received += 1
	if is_authority and GameData.UNIT_TYPES.has(type_id):
		_do_recruit(_sender_family(), type_id)


@rpc("any_peer", "call_remote", "reliable")
func _net_move(ids: PackedInt32Array, target: Vector2, attacking: bool) -> void:
	_orders_received += 1
	if is_authority:
		issue_move(_own_units(_sender_family(), ids), target, attacking)


@rpc("any_peer", "call_remote", "reliable")
func _net_attack(ids: PackedInt32Array, code: int) -> void:
	_orders_received += 1
	if not is_authority:
		return
	var target = hqs[-1 - code] if code < 0 and code >= -2 else _units_by_id.get(code)
	if target == null or not is_instance_valid(target):
		return
	for u in _own_units(_sender_family(), ids):
		u.command_attack(target)


@rpc("any_peer", "call_remote", "reliable")
func _net_stop(ids: PackedInt32Array) -> void:
	_orders_received += 1
	if is_authority:
		for u in _own_units(_sender_family(), ids):
			u.command_stop()


@rpc("any_peer", "call_remote", "reliable")
func _net_rally(p: Vector2) -> void:
	_orders_received += 1
	if is_authority:
		hqs[_sender_family()].rally_point = p.clamp(Vector2.ZERO, GameData.WORLD_SIZE)


## Test stand-in for a joined player under --autoplay: exercises every order
## type over the network without needing the AI's view of unit state.
func _client_bot(delta: float) -> void:
	_bot_timer -= delta
	if _bot_timer > 0.0:
		return
	_bot_timer = 2.0
	request_recruit(GameData.UNIT_ORDER[randi() % GameData.UNIT_ORDER.size()])
	var mine := get_units(local_family)
	if mine.is_empty():
		return
	var targets := districts.filter(func(d): return not d.is_secured_by(local_family))
	if targets.is_empty() or mine.size() >= 15:
		request_attack(mine, hqs[1 - local_family])
		return
	var hq_pos: Vector2 = hqs[local_family].position
	targets.sort_custom(func(a, b): return a.center().distance_to(hq_pos) < b.center().distance_to(hq_pos))
	request_move(mine, targets[0].center(), true)


# --- Player commands ----------------------------------------------------------

func recruit(type_id: String) -> void:
	if game_over or get_tree().paused:
		return
	var err: String = hqs[local_family].enqueue_error(type_id)
	if err != "":
		hud.notify(err)
		return
	request_recruit(type_id)


func set_selection(units: Array, select_hq := false) -> void:
	for u in selected:
		if is_instance_valid(u):
			u.selected = false
	selected = units.duplicate()
	for u in selected:
		u.selected = true
	hq_selected = select_hq
	hqs[local_family].selected = select_hq


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
			if not online:  # an online match can't be frozen by one player
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
			request_stop(selected)
		KEY_F:
			set_selection(get_units(local_family))
		KEY_H, KEY_SPACE:
			center_camera(hqs[local_family].position)
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
		for u in get_units(local_family):
			if box.has_point(u.position):
				picked.append(u)
	else:
		var best = null
		var best_d := INF
		for u in get_units(local_family):
			var dist: float = wp.distance_to(u.position)
			if dist < u.radius + 6.0 and dist < best_d:
				best = u
				best_d = dist
		if best != null:
			picked.append(best)
		elif not additive and wp.distance_to(hqs[local_family].position) < hqs[local_family].radius:
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
			request_rally(wp)
		return
	var target = find_enemy_near(wp, local_family, 14.0)
	if target != null:
		request_attack(selected, target)
		markers.append({"pos": target.position, "age": 0.0, "attack": true})
		return
	request_move(selected, wp, attack_move)
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
