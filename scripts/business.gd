class_name Business
extends Node2D
## One shop, bar or casino on a city block. Crew standing at it lean on it:
## a free business starts paying its family protection, a rival's has to be
## drained first. A family can then buy out a business it protects to take
## over its full takings.

signal owner_changed(business: Business, previous_owner: int)

enum Status { FREE, PROTECTED, OWNED }

## Partial pressure leaks away (or a family's hold recovers) at this rate
## once nobody is leaning on the business.
const RECOVER_RATE := 3.0

var index := 0
var district := 0
var type_id := "bar"
var business_name := ""
var takings := 0
var rect := Rect2()
var faces_down := false  # awning on the bottom edge (faces the street below)
var owner_family := GameData.NEUTRAL
var status := Status.FREE
var control_family := GameData.NEUTRAL
var control := 0.0  # 0..100
var contested := false
var presence := [0, 0, 0, 0]
var highlighted := false:
	set(v):
		if v != highlighted:
			highlighted = v
			queue_redraw()


func setup(i: int, d: int, t: String, owner_name: String, r: Rect2, wealth: float, down: bool) -> void:
	index = i
	district = d
	type_id = t
	rect = r
	faces_down = down
	var info: Dictionary = GameData.BUSINESS_TYPES[t]
	business_name = "%s %s" % [owner_name, info["name"]]
	takings = maxi(1, roundi(info["takings"] * wealth))
	name = "Business_%d" % i
	z_index = 0


func center() -> Vector2:
	return rect.get_center()


func type_name() -> String:
	return GameData.BUSINESS_TYPES[type_id]["name"]


func protection() -> int:
	return maxi(1, roundi(takings * GameData.PROTECTION_SHARE))


func takeover_cost() -> int:
	return takings * GameData.TAKEOVER_PRICE


## What the business pays its family every income interval.
func income() -> int:
	match status:
		Status.PROTECTED:
			return protection()
		Status.OWNED:
			return takings
	return 0


func status_text() -> String:
	match status:
		Status.PROTECTED:
			return "pays protection to the %ss" % GameData.FAMILY_SHORT[owner_family]
		Status.OWNED:
			return "owned by the %ss" % GameData.FAMILY_SHORT[owner_family]
	return "independent"


## Distance from a point to the walls, 0 inside.
func distance_to(p: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
	var dy := maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
	return Vector2(dx, dy).length()


func is_secured_by(f: int) -> bool:
	return owner_family == f and control >= 99.9


func set_owner_family(f: int, new_status := Status.PROTECTED) -> void:
	var previous := owner_family
	owner_family = f
	control_family = f
	status = Status.FREE if f == GameData.NEUTRAL else new_status
	control = 0.0 if f == GameData.NEUTRAL else 100.0
	queue_redraw()
	if previous != f:
		owner_changed.emit(self, previous)


## Host side: the family buys out a business it protects.
func take_over(f: int) -> String:
	var err := takeover_error(f, INF)
	if err != "":
		return err
	status = Status.OWNED
	control = 100.0
	queue_redraw()
	return ""


## "" if `f` with `money` could take this business over now.
func takeover_error(f: int, money: float) -> String:
	if owner_family != f:
		return "Lean on %s first: it doesn't pay us protection" % business_name
	if status == Status.OWNED:
		return "We already own %s" % business_name
	if contested or control < 99.9:
		return "%s isn't safely ours yet" % business_name
	if money < takeover_cost():
		return "Taking over %s costs $%d" % [business_name, takeover_cost()]
	return ""


## Host side: `counts[f]` is how many of family f's crew stand at this
## business. Crew of exactly one team move the meter.
func update_extortion(delta: float, counts: Array, teams: Array) -> void:
	var was := [owner_family, status, control_family, int(control), contested]
	presence = counts
	var team_counts := {}
	for f in counts.size():
		if counts[f] > 0:
			team_counts[teams[f]] = team_counts.get(teams[f], 0) + counts[f]
	contested = team_counts.size() > 1
	var previous := owner_family
	if team_counts.is_empty():
		if owner_family != GameData.NEUTRAL:
			control = minf(control + RECOVER_RATE * delta, 100.0)
		elif control > 0.0:
			control = maxf(control - RECOVER_RATE * delta, 0.0)
			if control <= 0.0:
				control_family = GameData.NEUTRAL
	elif team_counts.size() == 1:
		var team: int = team_counts.keys()[0]
		var leader := -1  # the team's family with most crew here takes it
		for f in counts.size():
			if teams[f] == team and counts[f] > 0 and (leader < 0 or counts[f] > counts[leader]):
				leader = f
		var amount: float = GameData.EXTORT_RATE * mini(team_counts[team], GameData.MAX_EXTORTERS) * delta
		if owner_family != GameData.NEUTRAL:
			if teams[owner_family] == team:
				control = minf(control + amount, 100.0)
			else:
				if status == Status.OWNED:
					amount *= GameData.OWNED_DRAIN_FACTOR
				control -= amount
				if control <= 0.0:
					owner_family = GameData.NEUTRAL
					status = Status.FREE
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
				status = Status.PROTECTED
	if was != [owner_family, status, control_family, int(control), contested]:
		queue_redraw()
	if previous != owner_family:
		owner_changed.emit(self, previous)


## Three bytes for the network: owner + status + contested, meter family,
## meter.
func pack(buf: StreamPeerBuffer) -> void:
	buf.put_u8((owner_family + 1) | (status << 3) | (int(contested) << 5))
	buf.put_u8(control_family + 1)
	buf.put_u8(clampi(roundi(control * 2.55), 0, 255))


## Client side: take the host's latest state.
func unpack(buf: StreamPeerBuffer) -> void:
	var a := buf.get_u8()
	var new_control_family := buf.get_u8() - 1
	var new_control := buf.get_u8() / 2.55
	var new_owner := (a & 7) - 1
	var new_status: int = (a >> 3) & 3
	var new_contested := (a >> 5) & 1 == 1
	if new_status != status or new_control_family != control_family or new_contested != contested or absf(new_control - control) > 0.5:
		queue_redraw()
	status = new_status
	control_family = new_control_family
	control = new_control
	contested = new_contested
	if new_owner != owner_family:
		var previous := owner_family
		owner_family = new_owner
		queue_redraw()
		owner_changed.emit(self, previous)


func _draw() -> void:
	var info: Dictionary = GameData.BUSINESS_TYPES[type_id]
	var col: Color = info["color"]
	var wall := Color(0.24, 0.23, 0.22).lerp(col, 0.18)
	if status == Status.OWNED:
		wall = wall.lerp(GameData.FAMILY_COLORS[owner_family], 0.45)
	draw_rect(rect, wall)
	draw_rect(rect.grow(-6.0), wall.lightened(0.06))
	# Awning toward the street the shop faces.
	var awning := Rect2(rect.position.x + 6.0, rect.end.y - 14.0 if faces_down else rect.position.y, rect.size.x - 12.0, 14.0)
	draw_rect(awning, col)
	var stripes := int(awning.size.x / 12.0)
	for s in stripes:
		if s % 2 == 0:
			draw_rect(Rect2(awning.position + Vector2(s * 12.0, 0), Vector2(6.0, awning.size.y)), col.lightened(0.35))

	var font := ThemeDB.fallback_font
	var mid := rect.position.y + rect.size.y * 0.5
	draw_string(font, Vector2(rect.position.x, mid - 4.0), info["letter"], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, col.lightened(0.4))
	draw_string(font, Vector2(rect.position.x + 4.0, mid + 16.0), business_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8.0, 11, Color(0.92, 0.9, 0.84))
	var tag := "$%d" % takings
	if owner_family != GameData.NEUTRAL:
		tag = "$%d / %d" % [income(), takings]
	draw_string(font, Vector2(rect.position.x, mid + 32.0), tag, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, Color(0.95, 0.85, 0.4))

	if owner_family != GameData.NEUTRAL:
		var fc: Color = GameData.FAMILY_COLORS[owner_family]
		draw_rect(rect, fc, false, 4.0 if status == Status.OWNED else 2.5)
		# A small flag: hollow for protection, filled for owned.
		var flag := Rect2(rect.end.x - 20.0, rect.position.y + (4.0 if faces_down else 18.0), 14.0, 10.0)
		if status == Status.OWNED:
			draw_rect(flag, fc)
		else:
			draw_rect(flag, fc, false, 2.0)
	if control_family != GameData.NEUTRAL and control > 0.5 and control < 99.5:
		var bar := Rect2(rect.position.x + 8.0, rect.get_center().y - 30.0, rect.size.x - 16.0, 6.0)
		draw_rect(bar, Color(0, 0, 0, 0.75))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * control / 100.0, bar.size.y)), GameData.FAMILY_COLORS[control_family])
	if contested:
		draw_rect(rect.grow(3.0), Color(1.0, 0.85, 0.3), false, 2.0)
	if highlighted:
		draw_rect(rect.grow(6.0), Color(0.45, 1.0, 0.45), false, 2.0)
