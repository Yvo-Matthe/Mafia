extends Node2D
## Draws input feedback above the world: the drag box and order markers.

var main: Node


func _draw() -> void:
	if main.drag_active:
		var box := Rect2(main.drag_start, get_global_mouse_position() - main.drag_start).abs()
		draw_rect(box, Color(0.45, 1.0, 0.45, 0.12))
		draw_rect(box, Color(0.45, 1.0, 0.45, 0.8), false, 1.5)
	for m in main.markers:
		var a: float = 1.0 - m["age"] / 0.6
		var col := Color(1.0, 0.35, 0.3, a) if m["attack"] else Color(0.45, 1.0, 0.45, a)
		var s: float = 10.0 + m["age"] * 20.0
		draw_line(m["pos"] + Vector2(-s, -s), m["pos"] + Vector2(s, s), col, 2.0)
		draw_line(m["pos"] + Vector2(-s, s), m["pos"] + Vector2(s, -s), col, 2.0)
	if main.attack_move_armed:
		var p := get_global_mouse_position()
		draw_arc(p, 14.0, 0.0, TAU, 24, Color(1.0, 0.35, 0.3), 2.0)
