extends Node

func _ready():
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	var c:=Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var l:=Label.new()
	l.text="NEON ASPHALT RUSH\nSTART OK\nOrientation fixed"
	l.position=Vector2(60,80)
	l.size=Vector2(1160,360)
	l.add_theme_font_size_override("font_size",46)
	c.add_child(l)
