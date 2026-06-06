extends Node

var ui: Control
var world: Node3D
var car: Node3D
var cam: Camera3D
var hud: Label
var mode := "menu"
var speed := 0.0
var nitro := 100.0
var t := 0.0
var score := 0
var max_kmh := 0.0
var drift := 0
var cp := 0
var cps := [Vector3(0,0,-70), Vector3(32,0,-145), Vector3(-28,0,-225), Vector3(18,0,-320), Vector3(0,0,-430)]
var left := false
var right := false
var gas := false
var brake := false
var hand := false
var boost := false

func _ready() -> void:
	Display