extends Node

var ui: Control
var car: Node3D
var speed := 0.0
var steer := 0.0
var nitro := 100.0
var t := 0.0
var score := 0
var racing := false
var left := false
var right := false
var gas := false
var brake := false
var boost := false

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	Engine.max_fps = 60
	show_menu()

func clear()