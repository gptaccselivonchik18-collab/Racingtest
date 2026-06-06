extends Node

var car: Node3D
var sp := 0.0
var ui: Label

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	Engine.max_fps = 60
	menu()

func wipe() -> void:
	for c in get_children():
		c.queue_free()

func menu() -> void:
	wipe()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.01,0.015,