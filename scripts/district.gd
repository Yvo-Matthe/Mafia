class_name District
extends Node2D
## A named neighbourhood of 2 x 2 city blocks, each lined with businesses and
## apartment houses. Whoever holds more than half of its businesses runs the
## district and collects its bonus on top of the rackets themselves.

signal controller_changed(district: District, previous: int)

const LOT_COLS := 3
const LOT_ROWS := 2
const LOT_GAP := 8.0
const SIDEWALK := 10.0
const BUSINESS_CHANCE := 0.7
const MIN_BUSINESSES := 3  # per block

var index := 0
var district_name := ""
var bonus := 0
var wealth := 1.0
var rect := Rect2()
var blocks: Array[Rect2] = []
var businesses: Array = []
## The family that runs the district, or NEUTRAL.
var controller := GameData.NEUTRAL

var _houses: Array = []  # {rect, color}


func setup(i: int, block_rects: Array[Rect2], data: Dictionary) -> void:
	index = i
	district_name = data["name"]
	bonus = data["bonus"]
	wealth = data["wealth"]
	blocks = block_rects
	rect = blocks[0]
	for b in blocks:
		rect = rect.merge(b)
	name = "District_%d" % i


## Lays out the lots of every block. Returns the new businesses (not yet in
## the tree); `next_index` is the first business number to use.
func generate(rng: RandomNumberGenerator, next_index: int, mix: Array) -> Array:
	var out := []
	for block in blocks:
		var inner := block.grow(-SIDEWALK)
		var lot := Vector2(inner.size.x / LOT_COLS, inner.size.y / LOT_ROWS)
		var lots := []
		for gy in LOT_ROWS:
			for gx in LOT_COLS:
				lots.append(Rect2(inner.position + Vector2(gx, gy) * lot, lot).grow(-LOT_GAP / 2.0))
		var is_shop := []
		var shop_count := 0
		for l in lots:
			var shop := rng.randf() < BUSINESS_CHANCE
			is_shop.append(shop)
			shop_count += int(shop)
		while shop_count < MIN_BUSINESSES:
			var k := rng.randi() % lots.size()
			if not is_shop[k]:
				is_shop[k] = true
				shop_count += 1
		for k in lots.size():
			var r: Rect2 = lots[k]
			if is_shop[k]:
				var b := Business.new()
				var t: String = mix[rng.randi() % mix.size()]
				var who: String = GameData.BUSINESS_OWNERS[rng.randi() % GameData.BUSINESS_OWNERS.size()]
				b.setup(next_index + out.size(), index, t, who, r, wealth, k >= LOT_COLS)
				out.append(b)
			else:
				# Apartment houses: one or two buildings on the lot.
				var parts: Array[Rect2] = [r]
				if rng.randf() < 0.5:
					var w := r.size.x * rng.randf_range(0.4, 0.6)
					parts = [Rect2(r.position, Vector2(w - 3.0, r.size.y)),
						Rect2(r.position + Vector2(w + 3.0, 0), Vector2(r.size.x - w - 3.0, r.size.y))]
				for p in parts:
					var shade := rng.randf_range(0.17, 0.27)
					var warm := rng.randf_range(0.0, 0.05)
					_houses.append({"rect": p, "color": Color(shade + warm, shade, shade - warm * 0.5)})
	businesses = out
	return out


func center() -> Vector2:
	return rect.get_center()


## Businesses held (protected or owned) by family f.
func held_by(f: int) -> int:
	return businesses.filter(func(b): return b.owner_family == f).size()


func owned_by(f: int) -> int:
	return businesses.filter(func(b): return b.owner_family == f and b.status == Business.Status.OWNED).size()


## What family f collects from this district each interval.
func income_for(f: int) -> int:
	var total := 0
	for b in businesses:
		if b.owner_family == f:
			total += b.income()
	if controller == f:
		total += bonus
	return total


func total_takings() -> int:
	var total := 0
	for b in businesses:
		total += b.takings
	return total


## Works out who runs the district after a business changed hands.
func recompute() -> void:
	var counts := [0, 0, 0, 0]
	for b in businesses:
		if b.owner_family >= 0:
			counts[b.owner_family] += 1
	var best := GameData.NEUTRAL
	for f in counts.size():
		if counts[f] > businesses.size() * GameData.DISTRICT_MAJORITY:
			best = f
	if best != controller:
		var previous := controller
		controller = best
		queue_redraw()
		controller_changed.emit(self, previous)


func _draw() -> void:
	var tint := Color(0.2, 0.2, 0.21)
	if controller != GameData.NEUTRAL:
		tint = tint.lerp(GameData.FAMILY_COLORS[controller], 0.22)
	for b in blocks:
		draw_rect(b, tint)  # sidewalk
		draw_rect(b.grow(-SIDEWALK + 2.0), tint.darkened(0.2))
	for h in _houses:
		var r: Rect2 = h["rect"]
		draw_rect(r, h["color"])
		draw_rect(r.grow(-5.0), h["color"].lightened(0.05))
		# rooftop details
		draw_rect(Rect2(r.position + Vector2(8, 8), Vector2(10, 8)), h["color"].darkened(0.3))
	if controller != GameData.NEUTRAL:
		draw_rect(rect.grow(GameData.STREET / 2.0 - 6.0), GameData.FAMILY_COLORS[controller], false, 3.0)

	var font := ThemeDB.fallback_font
	var title_pos := Vector2(rect.position.x, rect.position.y - GameData.STREET / 2.0 + 9.0)
	var title := district_name.to_upper()
	if controller != GameData.NEUTRAL:
		title += "  ·  %s turf" % GameData.FAMILY_SHORT[controller]
	draw_string(font, title_pos + Vector2(2, 2), title, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color(0, 0, 0, 0.7))
	var col: Color = Color(0.95, 0.92, 0.85) if controller == GameData.NEUTRAL else GameData.FAMILY_COLORS[controller].lightened(0.45)
	draw_string(font, title_pos, title, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, col)
