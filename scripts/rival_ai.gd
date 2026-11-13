class_name RivalAI
extends Node
## Computer-controlled family. Thinks once a second: recruits, defends its
## headquarters, sends small crews to shake down the most profitable nearby
## businesses, buys out the rackets it already runs when it has spare cash,
## and goes all-in on the nearest enemy HQ once its army is large. Runs only
## where the match is simulated (single player, or the host).

const THINK_INTERVAL := 1.0
const DEFEND_RADIUS := 500.0
const RECALL_RADIUS := 1600.0
const ALL_IN_ARMY := 22
const ALL_IN_AFTER := 360.0  # seconds of racketeering before going for an HQ
const CREW_SIZE := 2
const CASH_RESERVE := 500  # kept back for recruiting before buying businesses

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
	_buy_out()


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

	if units.size() >= ALL_IN_ARMY and main.match_time > ALL_IN_AFTER and enemy_hq != null:
		for u in idle:
			u.command_attack_move(enemy_hq.position + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40)))
		return

	var min_crew := 1 if main.match_time < 120.0 else CREW_SIZE
	if idle.size() < min_crew:
		return

	var origin := Vector2.ZERO
	for u in idle:
		origin += u.position
	origin /= idle.size()

	# Leave businesses our allies hold alone.
	var targets: Array = main.businesses.filter(func(b): return _wants(b))
	if targets.is_empty():
		if enemy_hq != null:
			main.issue_attack_move(idle, enemy_hq.position)
		return
	targets.sort_custom(func(a, b): return _score(a, origin) > _score(b, origin))

	var crews := []
	for i in range(0, idle.size(), CREW_SIZE):
		crews.append(idle.slice(i, i + CREW_SIZE))
	if crews.size() > 1 and crews[-1].size() < min_crew:
		crews[0].append_array(crews.pop_back())  # leftovers reinforce
	for k in crews.size():
		var b = targets[k % targets.size()]
		main.issue_move(crews[k], b.center(), false)


## Businesses worth leaning on: free ones, rivals', and ours that are slipping.
func _wants(b) -> bool:
	if b.is_secured_by(family):
		return false
	return b.owner_family == GameData.NEUTRAL or b.owner_family == family or main.is_enemy(family, b.owner_family)


func _score(b, origin: Vector2) -> float:
	var s: float = b.takings * 4.0 - origin.distance_to(b.center()) / 8.0
	for f in b.presence.size():
		if main.is_enemy(family, f):
			s -= b.presence[f] * 25.0
		elif f == family:
			s -= b.presence[f] * 12.0  # someone's already on it
	if b.owner_family != GameData.NEUTRAL and main.is_enemy(family, b.owner_family):
		s += 10.0 if b.status == Business.Status.PROTECTED else -10.0
	var d = main.districts[b.district]
	if d.controller != family and d.held_by(family) >= d.businesses.size() * GameData.DISTRICT_MAJORITY - 1:
		s += 20.0  # one more and the district is ours
	return s


## Idle crew standing at a business we haven't secured keep leaning on it.
func _is_holding(u) -> bool:
	var b = main.business_at(u.position)
	return b != null and _wants(b)


## Spare cash goes into taking over the best racket we already run.
func _buy_out() -> void:
	var best = null
	for b in main.businesses:
		if b.takeover_error(family, main.money[family] - CASH_RESERVE) == "" and (best == null or b.takings > best.takings):
			best = b
	if best != null:
		main._do_takeover(family, best.index)


func _nearest(p: Vector2, list: Array):
	var best = null
	var best_d := INF
	for n in list:
		var dist := p.distance_to(n.position)
		if dist < best_d:
			best_d = dist
			best = n
	return best
