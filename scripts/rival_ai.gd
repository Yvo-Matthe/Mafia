class_name RivalAI
extends Node
## Computer-controlled family. Thinks once a second: recruits, defends its
## headquarters, sends crews to grab the most profitable nearby districts,
## and goes all-in on the nearest enemy HQ once its army is large. Runs only
## where the match is simulated (single player, or the host).

const THINK_INTERVAL := 1.0
const DEFEND_RADIUS := 450.0
const RECALL_RADIUS := 1100.0
const ALL_IN_ARMY := 18
const CREW_SIZE := 3

var main: Node
var family := 1

var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup(m: Node, f: int) -> void:
	main = m
	family = f
	name = "AI_%d" % f
	_rng.randomize()


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = THINK_INTERVAL
	var hq = main.hqs[family]
	if hq == null or hq.hp <= 0.0:
		return
	_recruit(hq)
	_defend(hq)
	_expand(hq)


func _recruit(hq) -> void:
	if hq.queue.size() >= 2:
		return
	var t := "thug"
	if main.get_units(family).size() >= 4:
		var roll := _rng.randf()
		if roll < 0.4:
			t = "enforcer"
		elif roll < 0.65:
			t = "hitman"
	if hq.enqueue_error(t) != "":
		t = "thug"
	hq.enqueue(t)


func _enemy_units() -> Array:
	return main.get_units().filter(func(u): return main.is_enemy(family, u.family))


func _defend(hq) -> void:
	var threats := _enemy_units().filter(
		func(u): return u.position.distance_to(hq.position) < DEFEND_RADIUS)
	if threats.is_empty():
		return
	for u in main.get_units(family):
		if u.position.distance_to(hq.position) < RECALL_RADIUS and not u.has_attack_target():
			u.command_attack(_nearest(u.position, threats))


func _expand(hq) -> void:
	var units: Array = main.get_units(family)
	var idle: Array = units.filter(func(u): return u.is_idle() and not _is_holding(u))
	var enemy_hq = _nearest(hq.position, main.hqs.filter(
		func(h): return h != null and h.hp > 0.0 and main.is_enemy(family, h.family)))

	if units.size() >= ALL_IN_ARMY and enemy_hq != null:
		for u in idle:
			u.command_attack_move(enemy_hq.position + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40)))
		return

	var min_crew := 2 if main.match_time < 90.0 else CREW_SIZE
	if idle.size() < min_crew:
		return

	var origin := Vector2.ZERO
	for u in idle:
		origin += u.position
	origin /= idle.size()

	# Leave blocks our allies hold alone.
	var targets: Array = main.districts.filter(func(d):
		return not d.is_secured_by(family) and (d.owner_family == GameData.NEUTRAL or d.owner_family == family or main.is_enemy(family, d.owner_family)))
	if targets.is_empty():
		if enemy_hq != null:
			main.issue_attack_move(idle, enemy_hq.position)
		return
	targets.sort_custom(func(a, b): return _score(a, origin) > _score(b, origin))

	var crew_index := 0
	for i in range(0, idle.size(), CREW_SIZE):
		var crew := idle.slice(i, i + CREW_SIZE)
		if crew.size() < min_crew and crew_index > 0:
			# Leftovers reinforce the first crew instead of going alone.
			crew_index = 0
		var d = targets[crew_index % targets.size()]
		main.issue_attack_move(crew, d.center())
		crew_index += 1


func _score(d, origin: Vector2) -> float:
	var s: float = d.income * 3.0 - origin.distance_to(d.center()) / 6.0
	for f in d.presence.size():
		if main.is_enemy(family, f):
			s -= d.presence[f] * 25.0
	if d.owner_family != GameData.NEUTRAL and main.is_enemy(family, d.owner_family):
		s += 15.0
	return s


## Idle units standing in a district we haven't secured yet keep capturing.
func _is_holding(u) -> bool:
	for d in main.districts:
		if d.rect.has_point(u.position):
			return not d.is_secured_by(family) and (d.owner_family == GameData.NEUTRAL or d.owner_family == family or main.is_enemy(family, d.owner_family))
	return false


func _nearest(p: Vector2, list: Array):
	var best = null
	var best_d := INF
	for n in list:
		var dist := p.distance_to(n.position)
		if dist < best_d:
			best_d = dist
			best = n
	return best
