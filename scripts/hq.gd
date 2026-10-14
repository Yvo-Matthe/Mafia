class_name HQ
extends Node2D
## A family's headquarters: recruits soldiers, pays a base income and
## defends itself. Lose it and the family is finished.

const MAX_HP := 1500.0
const GUN_DAMAGE := 9.0
const GUN_RANGE := 170.0
const GUN_COOLDOWN := 1.0
const SHOT_TIME := 0.1

var main: Node
var family := 0
var hp := MAX_HP
var radius := 42.0
var queue: Array[String] = []
var build_progress := 0.0
var rally_point := Vector2.ZERO
var selected := false:
	set(v):
		selected = v
		queue_redraw()

var _cooldown := 0.0
var _flash := 0.0
var _shot_time := 0.0
var _shot_to := Vector2.ZERO


func setup(m: Node, f: int, pos: Vector2) -> void:
	main = m
	family = f
	position = pos
	z_index = 1
	name = "HQ_%d" % f
	var toward_center := (GameData.WORLD_SIZE / 2.0 - pos).normalized()
	rally_point = pos + toward_center * 130.0


## Returns "" if the unit can be queued, otherwise the reason it can't.
func enqueue_error(t: String) -> String:
	if hp <= 0.0:
		return "Headquarters destroyed"
	if queue.size() >= GameData.QUEUE_MAX:
		return "Recruitment queue full"
	if main.get_units(family).size() + queue.size() >= GameData.POP_CAP:
		return "Family is at full strength (%d)" % GameData.POP_CAP
	if main.money[family] < GameData.UNIT_TYPES[t]["cost"]:
		return "Not enough money"
	return ""


func enqueue(t: String) -> bool:
	if enqueue_error(t) != "":
		return false
	main.money[family] -= GameData.UNIT_TYPES[t]["cost"]
	queue.append(t)
	return true


func current_build_fraction() -> float:
	if queue.is_empty():
		return 0.0
	return build_progress / GameData.UNIT_TYPES[queue[0]]["build_time"]


func take_damage(amount: float, _from: Node2D) -> void:
	if hp <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_flash = 0.1
	queue_redraw()


func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return
	_flash = maxf(_flash - delta, 0.0)
	_shot_time = maxf(_shot_time - delta, 0.0)
	_cooldown -= delta

	if not queue.is_empty():
		build_progress += delta
		if build_progress >= GameData.UNIT_TYPES[queue[0]]["build_time"]:
			build_progress = 0.0
			var t: String = queue.pop_front()
			var out := (rally_point - position).normalized()
			var spawn_at := position + out * (radius + 14.0) + Vector2(randf_range(-12, 12), randf_range(-12, 12))
			var u = main.spawn_unit(family, t, spawn_at)
			u.command_move(rally_point + Vector2(randf_range(-30, 30), randf_range(-30, 30)))

	if _cooldown <= 0.0:
		var enemy = main.find_enemy_unit_near(position, family, GUN_RANGE + radius)
		if enemy != null:
			_cooldown = GUN_COOLDOWN
			_shot_to = enemy.position
			_shot_time = SHOT_TIME
			enemy.take_damage(GUN_DAMAGE, self)
	queue_redraw()


func _draw() -> void:
	var col: Color = GameData.FAMILY_COLORS[family]
	var font := ThemeDB.fallback_font
	var body := Rect2(Vector2(-radius, -radius), Vector2(radius, radius) * 2.0)
	if hp <= 0.0:
		draw_rect(body, Color(0.12, 0.11, 0.1))
		for i in 6:
			var p := Vector2(-radius + 10 + (i % 3) * 26, -radius + 14 + (i / 3) * 40)
			draw_rect(Rect2(p, Vector2(18, 12)), Color(0.25, 0.22, 0.2))
		draw_string(font, Vector2(-radius, 6), "RUBBLE", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 14, Color(0.6, 0.6, 0.6))
		return

	if selected:
		draw_arc(Vector2.ZERO, radius * 1.5, 0.0, TAU, 48, Color(0.45, 1.0, 0.45), 2.0)
		draw_line(Vector2.ZERO, rally_point - position, Color(0.45, 1.0, 0.45, 0.6), 1.5)
		draw_circle(rally_point - position, 5.0, Color(0.45, 1.0, 0.45))
	draw_rect(body.grow(4.0), Color(0, 0, 0, 0.4))
	draw_rect(body, Color.WHITE if _flash > 0.0 else Color(0.28, 0.24, 0.2))
	draw_rect(body.grow(-8.0), col.darkened(0.35))
	draw_rect(body.grow(-16.0), col)
	draw_string(font, Vector2(-radius, 6), "HQ", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 20, Color(0.05, 0.05, 0.05))

	var w := radius * 2.4
	var frac := hp / MAX_HP
	var bar := Rect2(Vector2(-w / 2.0, -radius - 14.0), Vector2(w, 6.0))
	draw_rect(bar, Color(0, 0, 0, 0.7))
	draw_rect(Rect2(bar.position, Vector2(w * frac, 6.0)), Color(0.3, 0.9, 0.3).lerp(Color(0.95, 0.25, 0.2), 1.0 - frac))
	if not queue.is_empty():
		draw_rect(Rect2(bar.position + Vector2(0, 9), Vector2(w * current_build_fraction(), 3.0)), Color(0.95, 0.85, 0.4))

	if _shot_time > 0.0:
		draw_line(Vector2.ZERO, _shot_to - position, Color(1.0, 0.9, 0.5, _shot_time / SHOT_TIME), 3.0)
