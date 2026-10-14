class_name Unit
extends Node2D
## A family soldier. Walks where it's told, fights anything hostile nearby
## when idle or attack-moving, and takes districts just by standing in them.

const AGGRO := 120.0  # extra sight beyond weapon range
const LEASH := 320.0  # how far an auto-acquired chase may drag a unit
const SHOT_TIME := 0.08

var main: Node
var net_id := 0
var family := 0
var type_id := "thug"
var stats: Dictionary
var hp := 1.0
var radius := 10.0
var selected := false:
	set(v):
		selected = v
		queue_redraw()

var has_move_order := false
var attack_move := false
var move_target := Vector2.ZERO
var attack_target: Node2D = null

var _auto_target := false
var _auto_anchor := Vector2.ZERO
var _cooldown := 0.0
var _flash := 0.0
var _shot_time := 0.0
var _shot_to := Vector2.ZERO
## Attack counter and last target, streamed so a client can draw shots.
var shots := 0
var shot_to: Vector2:
	get:
		return _shot_to
var _net_pos := Vector2.ZERO


func setup(m: Node, f: int, t: String, pos: Vector2) -> void:
	main = m
	family = f
	type_id = t
	stats = GameData.UNIT_TYPES[t]
	hp = stats["hp"]
	radius = stats["radius"]
	position = pos
	z_index = 2
	add_to_group("units")


func is_alive() -> bool:
	return hp > 0.0


func is_idle() -> bool:
	return not has_move_order and not has_attack_target()


func has_attack_target() -> bool:
	return _is_valid_target(attack_target)


func command_move(p: Vector2) -> void:
	_set_move(p, false)


func command_attack_move(p: Vector2) -> void:
	_set_move(p, true)


func command_attack(t: Node2D) -> void:
	attack_target = t
	_auto_target = false
	has_move_order = false


func command_stop() -> void:
	has_move_order = false
	attack_target = null


func take_damage(amount: float, from: Node2D) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = 0.12
	if hp <= 0.0:
		_die()
		return
	if is_idle() and _is_valid_target(from):
		_acquire(from)


func _set_move(p: Vector2, attacking: bool) -> void:
	move_target = p.clamp(Vector2.ZERO, GameData.WORLD_SIZE)
	has_move_order = true
	attack_move = attacking
	attack_target = null
	_auto_target = false


func _acquire(t: Node2D) -> void:
	attack_target = t
	_auto_target = true
	_auto_anchor = position


func _is_valid_target(t) -> bool:
	return t != null and is_instance_valid(t) and t.hp > 0.0 and t.family != family


func _die() -> void:
	remove_from_group("units")
	main.on_unit_died(self)
	queue_free()


## Client side: take the host's latest state for this unit.
func apply_net(pos: Vector2, new_hp: float, new_shots: int, target: Vector2) -> void:
	if _net_pos == Vector2.ZERO:
		position = pos
	_net_pos = pos
	if new_hp < hp:
		_flash = 0.12
	hp = new_hp
	if new_shots != shots:
		shots = new_shots
		_shot_to = target
		_shot_time = SHOT_TIME


## Client side: the host no longer reports this unit, so it died.
func net_remove() -> void:
	hp = 0.0
	_die()


func _process(delta: float) -> void:
	if main.is_authority:
		return
	_flash = maxf(_flash - delta, 0.0)
	_shot_time = maxf(_shot_time - delta, 0.0)
	position = position.lerp(_net_pos, 1.0 - exp(-15.0 * delta))
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not main.is_authority:
		return
	_cooldown -= delta
	_flash = maxf(_flash - delta, 0.0)
	_shot_time = maxf(_shot_time - delta, 0.0)

	if attack_target != null and not _is_valid_target(attack_target):
		attack_target = null
	if attack_target != null and _auto_target and position.distance_to(_auto_anchor) > LEASH:
		attack_target = null
	if attack_target == null and (not has_move_order or attack_move):
		var enemy = main.find_enemy_near(position, family, stats["range"] + AGGRO)
		if enemy != null:
			_acquire(enemy)

	var step := Vector2.ZERO
	var speed: float = stats["speed"]
	if attack_target != null:
		var to_target := attack_target.position - position
		var reach: float = stats["range"] + radius + attack_target.radius
		if to_target.length() > reach:
			step = to_target.normalized() * speed * delta
		elif _cooldown <= 0.0:
			_cooldown = stats["cooldown"]
			_shot_to = attack_target.position
			_shot_time = SHOT_TIME
			shots += 1
			attack_target.take_damage(stats["damage"], self)
	elif has_move_order:
		var to_goal := move_target - position
		if to_goal.length() <= maxf(4.0, speed * delta):
			position = move_target
			has_move_order = false
			attack_move = false
		else:
			step = to_goal.normalized() * speed * delta

	position += step + main.separation(self) * delta
	position = position.clamp(Vector2(radius, radius), GameData.WORLD_SIZE - Vector2(radius, radius))
	queue_redraw()


func _draw() -> void:
	var col: Color = GameData.FAMILY_COLORS[family]
	if _flash > 0.0:
		col = Color.WHITE
	if selected:
		draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 24, Color(0.45, 1.0, 0.45), 2.0)
	draw_circle(Vector2(2, 3), radius, Color(0, 0, 0, 0.35))
	draw_circle(Vector2.ZERO, radius, col.darkened(0.45))
	draw_circle(Vector2.ZERO, radius - 2.0, col)
	# fedora brim
	draw_rect(Rect2(-radius * 0.8, -radius * 0.55, radius * 1.6, radius * 0.3), Color(0.08, 0.08, 0.08, 0.85))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-radius, radius * 0.75), stats["letter"], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, int(radius * 1.1), Color(0.05, 0.05, 0.05))

	if selected or hp < stats["hp"]:
		var w := radius * 2.4
		var frac: float = clampf(hp / stats["hp"], 0.0, 1.0)
		var bar := Rect2(Vector2(-w / 2.0, -radius - 9.0), Vector2(w, 4.0))
		draw_rect(bar, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bar.position, Vector2(w * frac, 4.0)), Color(0.3, 0.9, 0.3).lerp(Color(0.95, 0.25, 0.2), 1.0 - frac))

	if _shot_time > 0.0:
		draw_line(Vector2.ZERO, _shot_to - position, Color(1.0, 0.9, 0.5, _shot_time / SHOT_TIME), 2.0)
