class_name VolleySettingsTheme
extends RefCounted

static func box(color: String, radius := 12) -> StyleBoxFlat:
 var style := VolleyMenuArt.panel(Color(color), radius)
 style.content_margin_left = 14
 style.content_margin_right = 14
 style.content_margin_top = 9
 style.content_margin_bottom = 9
 return style

static func build() -> Theme:
 var theme := Theme.new()
 theme.default_font = VolleyMenuArt.typeface(500)
 theme.default_font_size = 16
 for control in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "PopupMenu"]:
  theme.set_color("font_color", control, Color("f4f0e5"))
  theme.set_color("font_disabled_color", control, Color("718b96"))
 for control in ["Button", "OptionButton"]:
  theme.set_stylebox("normal", control, box("1b3b48"))
  theme.set_stylebox("hover", control, box("2a505b"))
  theme.set_stylebox("pressed", control, box("31545a"))
  theme.set_stylebox("disabled", control, box("122c37"))
  var focus := box("1b3b48")
  focus.set_border_width_all(2)
  focus.border_color = Color("ff9b76")
  theme.set_stylebox("focus", control, focus)
 theme.set_stylebox("panel", "PopupMenu", box("13303d", 16))
 theme.set_stylebox("hover", "PopupMenu", box("31545a", 8))
 theme.set_constant("v_separation", "PopupMenu", 14)
 theme.set_stylebox("normal", "LineEdit", box("0d222e", 10))
 theme.set_stylebox("focus", "LineEdit", box("244654", 10))
 theme.set_color("selection_color", "LineEdit", Color("44776e"))
 theme.set_stylebox("slider", "HSlider", bar("274552", 5))
 theme.set_stylebox("grabber_area", "HSlider", bar("b9e995", 5))
 theme.set_stylebox("grabber_area_highlight", "HSlider", bar("d8f2b9", 5))
 theme.set_icon("grabber", "HSlider", knob(Color("b9e995")))
 theme.set_icon("grabber_highlight", "HSlider", knob(Color("f4eccc")))
 theme.set_stylebox("scroll", "VScrollBar", bar("163440", 4))
 theme.set_stylebox("grabber", "VScrollBar", bar("496d74", 4))
 theme.set_stylebox("grabber_highlight", "VScrollBar", bar("85a5a3", 4))
 theme.set_stylebox("grabber_pressed", "VScrollBar", bar("b9e995", 4))
 return theme

static func bar(color: String, height: int) -> StyleBoxFlat:
 var style := box(color, height)
 style.content_margin_top = height
 style.content_margin_bottom = height
 style.content_margin_left = 3
 style.content_margin_right = 3
 return style

static func knob(color: Color) -> ImageTexture:
 var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
 image.fill(Color.TRANSPARENT)
 for x in range(24):
  for y in range(24):
   var distance := Vector2(x - 11.5, y - 11.5).length()
   if distance < 10.5:
    image.set_pixel(x, y, color if distance < 8 else color.darkened(0.20))
 return ImageTexture.create_from_image(image)

static func navigation(button: Button, selected: bool) -> void:
 if not button.has_meta("navigation_font"):
  button.add_theme_font_override("font", VolleyMenuArt.typeface(600))
  button.set_meta("navigation_font", true)
 button.add_theme_font_size_override("font_size", 15)
 button.add_theme_color_override("font_color", Color("122a35") if selected else Color("aac2c8"))
 button.add_theme_color_override("font_hover_color", Color("122a35") if selected else Color("f4f0e5"))
 button.add_theme_color_override("font_pressed_color", Color("122a35"))
 button.add_theme_stylebox_override("normal", box("b9e995" if selected else "102934", 10))
 button.add_theme_stylebox_override("hover", box("c9f2a8" if selected else "1d3d48", 10))
 button.add_theme_stylebox_override("pressed", box("b9e995", 10))
