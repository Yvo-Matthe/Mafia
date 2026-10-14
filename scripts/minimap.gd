extends Control
## Whole-city overview. Click or drag on it to move the camera.

var main: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _to_map(p: Vector2) -> Vector2:
	return p * size / GameData.WORLD_SIZE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.04, 0.05, 0.9))
	for d in main.districts:
		var col := Color(0.25, 0.25, 0.27)
		if d.owner_family != GameData.NEUTRAL:
			col = GameData.FAMILY_COLORS[d.owner_family].darkened(0.35)
		draw_rect(Rect2(_to_map(d.rect.position), _to_map(d.rect.size)), col)
		if d.contested:
			draw_rect(Rect2(_to_map(d.rect.position), _to_map(d.rect.size)), Color(1, 0.85, 0.3), false, 1.5)
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
