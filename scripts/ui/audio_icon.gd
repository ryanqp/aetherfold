extends Control

## Small gold icons for the audio panel, drawn in code: "speaker" (master), "note" (music), "swords" (effects).

const GOLD := Color(0.93, 0.78, 0.28)

var kind := "speaker"


func _init(icon_kind: String = "speaker") -> void:
	kind = icon_kind
	custom_minimum_size = Vector2(28, 28)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	match kind:
		"speaker":
			draw_colored_polygon(PackedVector2Array([Vector2(4, 10), Vector2(9, 10), Vector2(15, 5), Vector2(15, 23), Vector2(9, 18), Vector2(4, 18)]), GOLD)
			draw_arc(Vector2(15, 14), 5.0, -0.9, 0.9, 12, GOLD, 2.0, true)
			draw_arc(Vector2(15, 14), 9.0, -0.9, 0.9, 12, GOLD, 2.0, true)
		"note":
			draw_circle(Vector2(9, 21), 4.5, GOLD)
			draw_line(Vector2(13, 21), Vector2(13, 5), GOLD, 2.5, true)
			draw_line(Vector2(13, 5), Vector2(22, 9), GOLD, 3.5, true)
		"swords":
			draw_line(Vector2(5, 23), Vector2(23, 5), GOLD, 3.0, true)
			draw_line(Vector2(23, 23), Vector2(5, 5), GOLD, 3.0, true)
			draw_line(Vector2(3, 17), Vector2(11, 25), GOLD, 2.5, true)
			draw_line(Vector2(25, 17), Vector2(17, 25), GOLD, 2.5, true)
