class_name VolleyMenuArt
extends Control

var show_ball := true

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 resized.connect(queue_redraw)

func _draw() -> void:
 draw_rect(Rect2(Vector2.ZERO, size), Color("0b1828"))
 var glow := Vector2(size.x * 0.82, size.y * 0.35)
 for ring in range(18, 0, -1):
  draw_circle(glow, ring * size.y * 0.043, Color(0.07, 0.25, 0.30, 0.024))
 var corner := Vector2(size.x * 0.94, size.y * 1.08)
 draw_circle(corner, size.y * 0.43, Color("e46f50"))
 draw_circle(corner, size.y * 0.32, Color("f18b58"))
 draw_line(Vector2(size.x * 0.57, size.y), Vector2(size.x, size.y * 0.60), Color("39636a"), 2, true)
 draw_line(Vector2(size.x * 0.69, size.y), Vector2(size.x, size.y * 0.76), Color("39636a"), 2, true)
 if not show_ball or size.x < size.y * 1.45:
  return
 var center := Vector2(size.x * 0.77, size.y * 0.44)
 var radius := minf(size.y * 0.205, size.x * 0.14)
 draw_set_transform(center + Vector2(10, radius * 1.25), 0, Vector2(1, 0.16))
 draw_circle(Vector2.ZERO, radius * 0.78, Color(0, 0, 0, 0.18), true, -1, true)
 draw_set_transform(Vector2.ZERO)
 draw_arc(center, radius * 1.22, -2.70, -0.60, 48, Color("d9f36b"), 3, true)
 draw_arc(center, radius * 1.38, 0.30, 1.20, 32, Color("427477"), 2, true)
 draw_circle(center, radius, Color("f5edcf"), true, -1, true)
 # Three curved panel groups give the ball its volleyball silhouette.
 for section in range(3):
  draw_set_transform(center, -0.30 + section * TAU / 3.0)
  _seam(Vector2.ZERO, Vector2(0.15, 0.40), Vector2(0.68, 0.38), Vector2.RIGHT, radius)
  _seam(Vector2(0.20, 0.26), Vector2(0.12, 0.56), Vector2(0.40, 0.76), Vector2.from_angle(0.90), radius)
  _seam(Vector2(0.55, 0.29), Vector2(0.50, 0.48), Vector2(0.65, 0.60), Vector2.from_angle(0.60), radius)
 draw_set_transform(Vector2.ZERO)

func _seam(a: Vector2, b: Vector2, c: Vector2, d: Vector2, radius: float) -> void:
 var points := PackedVector2Array()
 for sample in range(41):
  var t := sample / 40.0
  var u := 1.0 - t
  points.append((a * u * u * u + b * 3 * u * u * t + c * 3 * u * t * t + d * t * t * t) * radius)
 draw_polyline(points, Color("193a48"), maxf(2, radius * 0.022), true)

static func typeface(weight := 600) -> SystemFont:
 var font := SystemFont.new()
 font.font_names = PackedStringArray(["Inter", "Arial", "Helvetica Neue", "Roboto", "Noto Sans"])
 font.font_weight = weight
 return font

static func panel(color: Color, radius := 16) -> StyleBoxFlat:
 var style := StyleBoxFlat.new()
 style.bg_color = color
 style.set_corner_radius_all(radius)
 style.content_margin_left = 22
 style.content_margin_right = 22
 style.content_margin_top = 12
 style.content_margin_bottom = 12
 return style

static func style_button(button: Button, primary := false) -> void:
 button.add_theme_font_override("font", typeface(700))
 button.add_theme_font_size_override("font_size", 20)
 button.add_theme_color_override("font_color", Color("112332") if primary else Color("f5f2df"))
 button.add_theme_color_override("font_hover_color", Color("112332") if primary else Color.WHITE)
 button.add_theme_color_override("font_pressed_color", Color("112332") if primary else Color.WHITE)
 button.add_theme_color_override("font_disabled_color", Color("708b99"))
 button.add_theme_stylebox_override("normal", panel(Color("d9f36b") if primary else Color("1b3546")))
 button.add_theme_stylebox_override("hover", panel(Color("e6ff85") if primary else Color("294a5b")))
 button.add_theme_stylebox_override("pressed", panel(Color("bfd65c") if primary else Color("122a3b")))
 button.add_theme_stylebox_override("disabled", panel(Color("152c3d")))
 var focus := panel(Color.TRANSPARENT)
 focus.set_border_width_all(2)
 focus.border_color = Color("f18b58")
 button.add_theme_stylebox_override("focus", focus)

