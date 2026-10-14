class_name District
extends Node2D
## One city block. Standing units push its control meter toward their family;
## the owner collects its income.

signal owner_changed(district: District, previous_owner: int)

const CAPTURE_RATE := 10.0  # control points per second per unit
const MAX_CAPTURERS := 4  # more units than this don't speed capture up
const PLAZA_RADIUS := 70.0

var index := 0
var district_name := ""
var income := 0
var rect := Rect2()
var owner_family := GameData.NEUTRAL
## Whose capture meter is showing: the owner once owned, else the family
## part-way through taking it.
var control_family := GameData.NEUTRAL
var control := 0.0  # 0..100
var presence := [0, 0, 0, 0]
var contested := false

var _buildings: Array = []


func setup(i: int, r: Rect2, data: Dictionary, rng: RandomNumberGenerator) -> void:
	index = i
	rect = r
	district_name = data["name"]
	income = data["income"]
	name = "District_%d" % i
	_generate_buildings(rng)


func center() -> Vector2:
	return rect.get_center()


func set_owner_family(f: int) -> void:
	owner_family = f
	control_family = f
	control = 0.0 if f == GameData.NEUTRAL else 100.0
	queue_redraw()


## True once the family owns the block and its meter is full.
func is_secured_by(f: int) -> bool:
	return owner_family == f and control >= 99.9


## Client side: take the host's latest state for this district.
func apply_net(new_owner: int, new_control_family: int, new_control: float, is_contested: bool) -> void:
	control_family = new_control_family
	control = new_control
	contested = is_contested
	if new_owner != owner_family:
		var previous := owner_family
		owner_family = new_owner
		owner_changed.emit(self, previous)
	queue_redraw()


## Units of exactly one team in the block move its meter: they top up a
## block their team owns, drain an enemy block to neutral, then claim it.
## `teams[f]` is family f's team.
func update_capture(delta: float, units: Array, teams: Array) -> void:
	presence = [0, 0, 0, 0]
	for u in units:
		if rect.has_point(u.position):
			presence[u.family] += 1
	var team_counts := {}
	for f in presence.size():
		if presence[f] > 0:
			team_counts[teams[f]] = team_counts.get(teams[f], 0) + presence[f]
	contested = team_counts.size() > 1
	queue_redraw()
	if team_counts.size() != 1:
		return
	var team: int = team_counts.keys()[0]
	var leader := -1  # the team's family with most units here takes the block
	for f in presence.size():
		if teams[f] == team and presence[f] > 0 and (leader < 0 or presence[f] > presence[leader]):
			leader = f
	var amount: float = CAPTURE_RATE * mini(team_counts[team], MAX_CAPTURERS) * delta

	var previous := owner_family
	if owner_family != GameData.NEUTRAL:
		if teams[owner_family] == team:
			control = minf(control + amount, 100.0)
		else:
			control -= amount
			if control <= 0.0:
				owner_family = GameData.NEUTRAL
				control_family = GameData.NEUTRAL
				control = 0.0
	elif control_family != GameData.NEUTRAL and control_family != leader and teams[control_family] != team:
		control -= amount
		if control <= 0.0:
			control_family = GameData.NEUTRAL
			control = 0.0
	else:
		control_family = leader
		control = minf(control + amount, 100.0)
		if control >= 100.0:
			owner_family = leader
	if previous != owner_family:
		owner_changed.emit(self, previous)


func _generate_buildings(rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-16.0)
	var lot := inner.size / 3.0
	for gy in 3:
		for gx in 3:
			if gx == 1 and gy == 1:
				continue  # plaza
			var cell := Rect2(inner.position + Vector2(gx, gy) * lot, lot).grow(-8.0)
			var split := rng.randf() < 0.5
			var parts: Array[Rect2] = []
			if split and cell.size.x > cell.size.y:
				var w := cell.size.x * rng.randf_range(0.4, 0.6)
				parts.append(Rect2(cell.position, Vector2(w - 4.0, cell.size.y)))
				parts.append(Rect2(cell.position + Vector2(w + 4.0, 0), Vector2(cell.size.x - w - 4.0, cell.size.y)))
			elif split:
				var h := cell.size.y * rng.randf_range(0.4, 0.6)
				parts.append(Rect2(cell.position, Vector2(cell.size.x, h - 4.0)))
				parts.append(Rect2(cell.position + Vector2(0, h + 4.0), Vector2(cell.size.x, cell.size.y - h - 4.0)))
			else:
				parts.append(cell)
			for p in parts:
				var shade := rng.randf_range(0.2, 0.34)
				var warm := rng.randf_range(0.0, 0.06)
				_buildings.append({"rect": p, "color": Color(shade + warm, shade, shade - warm * 0.5)})


func _draw() -> void:
	var base := Color(0.17, 0.17, 0.18)
	var tint := base
	var edge := Color(0.35, 0.35, 0.38)
	if owner_family != GameData.NEUTRAL:
		tint = base.lerp(GameData.FAMILY_COLORS[owner_family], 0.25)
		edge = GameData.FAMILY_COLORS[owner_family]
	draw_rect(rect, tint)
	for b in _buildings:
		var r: Rect2 = b["rect"]
		draw_rect(r, b["color"])
		draw_rect(r.grow(-5.0), b["color"].lightened(0.07))
	draw_rect(rect, edge, false, 4.0)

	var c := center()
	draw_circle(c, PLAZA_RADIUS, tint.darkened(0.25))
	if control > 0.5 and control_family != GameData.NEUTRAL:
		var col: Color = GameData.FAMILY_COLORS[control_family]
		draw_arc(c, PLAZA_RADIUS + 8.0, -PI / 2.0, -PI / 2.0 + TAU * control / 100.0, 64, col, 6.0)

	var font := ThemeDB.fallback_font
	var title_pos := rect.position + Vector2(0, 30)
	draw_string(font, title_pos + Vector2(2, 2), district_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color(0, 0, 0, 0.7))
	draw_string(font, title_pos, district_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color(0.95, 0.92, 0.85))
	var sub := "$%d" % income
	if contested:
		sub += "   CONTESTED"
	draw_string(font, title_pos + Vector2(0, 24), sub, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, Color(0.95, 0.85, 0.4))
