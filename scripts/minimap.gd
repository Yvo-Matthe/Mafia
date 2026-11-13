extends Control
## Whole-city overview. Click or drag on it to move the camera.

var main: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _to_map(p: Vector2) -> Vector2:
	return p * size / GameData.WORLD_SIZE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.04, 0.05, 0.9))
	for d in main.districts:
		for blk in d.blocks:
			var col := Color(0.2, 0.2, 0.22)
			if d.controller != GameData.NEUTRAL:
				col = col.lerp(GameData.FAMILY_COLORS[d.controller], 0.3)
			draw_rect(Rect2(_to_map(blk.position), _to_map(blk.size)), col)
	for b in main.businesses:
		var r := Rect2(_to_map(b.rect.position), _to_map(b.rect.size)).grow(-1.0)
		if b.owner_family != GameData.NEUTRAL:
			var fc: Color = GameData.FAMILY_COLORS[b.owner_family]
			draw_rect(r, fc if b.status == Business.Status.OWNED else fc.darkened(0.4))
		else:
			draw_rect(r, Color(0.36, 0.35, 0.33))
		if b.contested:
			draw_rect(r, Color(1, 0.85, 0.3), false, 1.0)
	for hq in main.hqs:
		if hq != null and hq.hp > 0.0:
			var c := _to_map(hq.position)
			draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), GameData.FAMILY_COLORS[hq.family].lightened(0.4))
	for u in main.get_units():
		draw_rect(Rect2(_to_map(u.position) - Vector2(1.5, 1.5), Vector2(3, 3)), GameData.FAMILY_COLORS[u.family].lightened(0.45))
	var cam: Camera2D = main.camera
	var view := get_viewport_rect().size / cam.zoom
	draw_rect(Rect2(_to_map(cam.position - view / 2.0), _to_map(view)), Color.WHITE, false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0.4, 0.42), false, 2.0)


func _gui_input(event: InputEvent) -> void:
	var press: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var drag: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if press or drag:
		main.center_camera(event.position / size * GameData.WORLD_SIZE)
		accept_event()
