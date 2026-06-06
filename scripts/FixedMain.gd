extends Node

var root_ui: Control
var world: Node3D
var car: Node3D
var camera: Camera3D
var hud: Control
var screen := "menu"
var selected_track := "city_night"
var selected_car := "street_starter"
var speed := 0.0
var steer := 0.0
var nitro := 100.0
var race_time := 0.0
var drift_score := 0
var score := 0
var max_speed := 0.0
var cp_index := 0
var checkpoints: Array[Vector3] = []
var touch := {"left":false,"right":false,"gas":false,"brake":false,"