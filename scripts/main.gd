extends Node2D
## Root of a match: builds the city, tracks money and victory, and turns
## player input into orders.
##
## Up to four families take part, each run by a player or the computer, and
## families on the same team are allies. Online, the host runs the whole
## simulation (computer families included); joined players' games only draw
## the snapshots the host streams to them and send their orders back.

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
## Per family; null for an empty seat.
var hqs: Array = []
var money: Array = []
## Per family: its team, or -1 for an empty seat.
var teams: Array = []
var eliminated: Array = []
var selected: Array = []
var hq_selected := false
var game_over := false
var winning_team := -1
var match_time := 0.0
var autoplay := false
var attack_move_armed := false

## The family this screen controls.
var local_family := 0
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
var _peers_ready := false
var _snapshot_timer := 0.0
var _bot_timer := 0.0
var _orders_received := 0
var _ai_families := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	autoplay = Net.autoplay
	online = Net.is_online()
	is_authority = Net.mode != Net.Mode.CLIENT
	local_family = Net.local_family
	for i in GameData.MAX_FAMILIES:
		var slot: Dictionary = Net.slots[i]
		var active: bool = slot["kind"] == "human" or slot["kind"] == "ai"
		teams.append(slot["team"] if active else -1)
		hqs.append(null)
		money.append(GameData.START_MONEY)
		eliminated.append(not active)

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

	if is_authority:
		for f in GameData.MAX_FAMILIES:
			if Net.slots[f]["kind"] == "ai" or (autoplay and f == local_family):
				_add_ai(f)
	if autoplay:
		print("AUTOPLAY: match started (%s) as %s, families %s" % [
			["single player", "host", "client"][Net.mode], GameData.FAMILY_SHORT[local_family], str(teams)])

	if online:
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		if is_authority:
			hud.notify("Waiting for the other players to load...")
		Net.announce_loaded()


func _add_ai(family: int) -> void:
	if _ai_families.has(family):
		return
	_ai_families[family] = true
	var ai := RivalAI.new()
	ai.setup(self, family)
	world.add_child(ai)


func active_families() -> Array:
	return range(GameData.MAX_FAMILIES).filter(func(f): return teams[f] >= 0)


func is_enemy(a: int, b: int) -> bool:
	return a != b and a >= 0 and b >= 0 and teams[a] != teams[b]


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
	for f in active_families():
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
		if u.hp <= 0.0 or not is_enemy(family, u.family):
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
	var best_d := radius
	for h in hqs:
		if h != null and h.hp > 0.0 and is_enemy(family, h.family):
			var dist: float = pos.distance_to(h.position) - h.radius
			if dist < best_d:
				best_d = dist
				best = h
	return best


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


func team_name(team: int) -> String:
	var names := []
	for f in active_families():
		if teams[f] == team:
			names.append(GameData.FAMILY_SHORT[f])
	if names.size() == 1:
		return GameData.FAMILY_NAMES[active_families().filter(func(f): return teams[f] == team)[0]]
	return "The " + " and ".join(names) + " families"


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
		var who := "Our allies, the %ss," if teams[d.owner_family] == teams[local_family] else "The %ss"
		hud.notify((who + " took %s") % [GameData.FAMILY_SHORT[d.owner_family], d.district_name])


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
	if online and not _peers_ready:
		for s in Net.slots:
			if s["kind"] == "human" and s["peer"] != 1 and not Net.loaded_peers.has(s["peer"]):
				return
		_peers_ready = true
		hud.notify("Everyone is here. Take the city.")

	match_time += delta
	_income_timer += delta
	if _income_timer >= GameData.INCOME_INTERVAL:
		_income_timer -= GameData.INCOME_INTERVAL
		for f in active_families():
			money[f] += income_of(f)

	var units := get_units()
	for d in districts:
		d.update_capture(delta, units, teams)

	_check_victory()
	if online and not game_over:
		_snapshot_timer -= delta
		if _snapshot_timer <= 0.0:
			_snapshot_timer = SNAPSHOT_INTERVAL
			_send_snapshot()
	if autoplay and not game_over and match_time > AUTOPLAY_TIME_LIMIT:
		print("AUTOPLAY RESULT: draw after %.0fs" % match_time)
		get_tree().quit(0)


func _check_victory() -> void:
	if game_over:
		return
	for f in active_families():
		if not eliminated[f] and hqs[f].hp <= 0.0:
			_eliminate(f)
	var alive := {}
	for f in active_families():
		if not eliminated[f]:
			alive[teams[f]] = true
	if alive.size() <= 1:
		var team: int = alive.keys()[0] if alive.size() == 1 else -1
		_end_match(team, "Every rival headquarters has been burned to the ground.")
		return
	var owner_teams := {}
	for d in districts:
		owner_teams[teams[d.owner_family] if d.owner_family >= 0 else -1] = true
	if owner_teams.size() == 1 and not owner_teams.has(-1):
		var team: int = owner_teams.keys()[0]
		_end_match(team, "%s %s every district in the city." % [team_name(team), "control" if team_name(team).ends_with("families") else "controls"])


## A family whose HQ falls is out: its crew scatters and its blocks go neutral.
func _eliminate(f: int) -> void:
	eliminated[f] = true
	for u in get_units(f):
		u.net_remove()
	for d in districts:
		if d.owner_family == f or d.control_family == f:
			d.set_owner_family(GameData.NEUTRAL)
	if online:
		_net_eliminated.rpc(f)
	_announce_elimination(f)


func _announce_elimination(f: int) -> void:
	eliminated[f] = true
	if autoplay:
		print("AUTOPLAY: %s eliminated at %.0fs" % [GameData.FAMILY_SHORT[f], match_time])
		return
	if f == local_family:
		hud.show_eliminated()
	else:
		hud.notify("The %s headquarters has burned. Their family is finished." % GameData.FAMILY_SHORT[f])


@rpc("authority", "call_remote", "reliable")
func _net_eliminated(f: int) -> void:
	_announce_elimination(f)


func _end_match(team: int, reason: String) -> void:
	if online and is_authority and multiplayer.get_peers().size() > 0:
		_send_snapshot()
		_net_end_match.rpc(team, reason)
	_show_end(team, reason)


func _show_end(team: int, reason: String) -> void:
	if game_over:
		return
	game_over = true
	winning_team = team
	get_tree().paused = true
	if autoplay:
		var owned := active_families().map(func(f): return "%s %d" % [GameData.FAMILY_SHORT[f], districts_owned(f)])
		print("AUTOPLAY RESULT: winner=%s after %.0fs (%s) districts: %s" % [
			team_name(team) if team >= 0 else "none", match_time, reason, ", ".join(owned)])
		if online and is_authority:
			print("NET: host applied %d orders from joined players" % _orders_received)
		# Give a reliable end-of-match message time to reach the others.
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(0)
		return
	hud.show_end(team, reason)


## Single player starts a new match; online goes back to the menu.
func restart() -> void:
	get_tree().paused = false
	if online:
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	else:
		get_tree().reload_current_scene()


# --- Networking --------------------------------------------------------------

func _send_snapshot() -> void:
	_receive_units.rpc(_pack_units())
	_receive_state.rpc(_make_state())


## Units go as raw bytes, 11 per unit, so four full families (120 units)
## still fit in one network packet.
func _pack_units() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	for u in get_units():
		buf.put_u16(u.net_id & 0xFFFF)
		buf.put_u8(u.family * 16 + GameData.UNIT_ORDER.find(u.type_id))
		buf.put_u16(clampi(int(u.position.x), 0, 65535))
		buf.put_u16(clampi(int(u.position.y), 0, 65535))
		buf.put_u8(clampi(int(ceil(u.hp / u.stats["hp"] * 255.0)), 1, 255))
		buf.put_u8(u.shots & 0xFF)
		var shot: Vector2 = (u.shot_to - u.position) / 4.0
		buf.put_8(clampi(int(shot.x), -127, 127))
		buf.put_8(clampi(int(shot.y), -127, 127))
	return buf.data_array


func _make_state() -> Array:
	var ds := []
	for d in districts:
		ds.append([d.owner_family, d.control_family, d.control, d.contested])
	var hs := []
	for h in hqs:
		hs.append([] if h == null else [h.hp, Array(h.queue), h.build_progress, h.rally_point, h.shots, h.shot_to])
	return [match_time, money.duplicate(), ds, hs]


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_units(data: PackedByteArray) -> void:
	if is_authority:
		return
	var seen := {}
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	while buf.get_position() < buf.get_size():
		var id := buf.get_u16()
		var kind := buf.get_u8()
		var pos := Vector2(buf.get_u16(), buf.get_u16())
		var hp_frac := buf.get_u8() / 255.0
		var shots := buf.get_u8()
		var shot_to := pos + Vector2(buf.get_8(), buf.get_8()) * 4.0
		var type_id: String = GameData.UNIT_ORDER[kind % 16]
		seen[id] = true
		var u = _units_by_id.get(id)
		if u == null or not is_instance_valid(u):
			u = spawn_unit(kind / 16, type_id, pos, id)
		u.apply_net(pos, hp_frac * GameData.UNIT_TYPES[type_id]["hp"], shots, shot_to)
	for id in _units_by_id.keys():
		if not seen.has(id):
			_units_by_id[id].net_remove()


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_state(s: Array) -> void:
	if is_authority:
		return
	match_time = s[0]
	money = s[1]
	for i in districts.size():
		var d: Array = s[2][i]
		districts[i].apply_net(d[0], d[1], d[2], d[3])
	for f in hqs.size():
		if hqs[f] != null and not s[3][f].is_empty():
			hqs[f].apply_net(s[3][f])


@rpc("authority", "call_remote", "reliable")
func _net_end_match(team: int, reason: String) -> void:
	_show_end(team, reason)


## On the host: a player who leaves hands their family to the computer.
func _on_peer_disconnected(id: int) -> void:
	var f := Net.family_of_peer(id)
	if game_over or f < 0:
		return
	Net.slots[f]["kind"] = "ai"
	if autoplay:
		print("NET: %s player left at %.0fs, computer takes over" % [GameData.FAMILY_SHORT[f], match_time])
	if not eliminated[f]:
		_add_ai(f)
		hud.notify("The %s player left. The computer runs their family now." % GameData.FAMILY_SHORT[f])


func _on_server_disconnected() -> void:
	if not game_over:
		_show_end(-1, "Lost the connection to the host.")


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


## The family a joined player's order is for, or -1 to ignore it.
func _sender_family() -> int:
	if not is_authority:
		return -1
	_orders_received += 1
	var f := Net.family_of_peer(multiplayer.get_remote_sender_id())
	return f if f >= 0 and not eliminated[f] else -1


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
	var f := _sender_family()
	if f >= 0 and GameData.UNIT_TYPES.has(type_id):
		_do_recruit(f, type_id)


@rpc("any_peer", "call_remote", "reliable")
func _net_move(ids: PackedInt32Array, target: Vector2, attacking: bool) -> void:
	var f := _sender_family()
	if f >= 0:
		issue_move(_own_units(f, ids), target, attacking)


@rpc("any_peer", "call_remote", "reliable")
func _net_attack(ids: PackedInt32Array, code: int) -> void:
	var f := _sender_family()
	if f < 0:
		return
	var target = null
	if code < 0 and -1 - code < hqs.size():
		target = hqs[-1 - code]
	elif code >= 0:
		target = _units_by_id.get(code)
	if target == null or not is_instance_valid(target):
		return
	for u in _own_units(f, ids):
		u.command_attack(target)


@rpc("any_peer", "call_remote", "reliable")
func _net_stop(ids: PackedInt32Array) -> void:
	var f := _sender_family()
	if f >= 0:
		for u in _own_units(f, ids):
			u.command_stop()


@rpc("any_peer", "call_remote", "reliable")
func _net_rally(p: Vector2) -> void:
	var f := _sender_family()
	if f >= 0:
		hqs[f].rally_point = p.clamp(Vector2.ZERO, GameData.WORLD_SIZE)


## Test stand-in for a joined player under --autoplay: exercises every order
## type over the network without needing the AI's view of unit state.
func _client_bot(delta: float) -> void:
	_bot_timer -= delta
	if _bot_timer > 0.0 or eliminated[local_family]:
		return
	_bot_timer = 2.0
	request_recruit(GameData.UNIT_ORDER[randi() % GameData.UNIT_ORDER.size()])
	var mine := get_units(local_family)
	if mine.is_empty():
		return
	var hq_pos: Vector2 = hqs[local_family].position
	var targets := districts.filter(func(d):
		return d.owner_family == GameData.NEUTRAL or is_enemy(local_family, d.owner_family))
	if targets.is_empty() or mine.size() >= 15:
		var enemy = find_enemy_near(hq_pos, local_family, INF)
		if enemy != null:
			request_attack(mine, enemy)
		return
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
