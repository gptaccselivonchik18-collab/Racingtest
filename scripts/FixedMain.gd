extends Node

var ui: Control
var world: Node3D
var car: Node3D
var cam: Camera3D
var hud: Control
var mode := "menu"
var car_id := "street_starter"
var track_id := "city_night"
var speed := 0.0
var nitro := 100.0
var time := 0.0
var score := 0
var drift_score := 0
var max_kmh := 0.0
var cp_i := 0
var cps: Array[Vector3] = []
var touch_left := false
var touch_right := false
var touch_gas := false
var touch_brake := false
var touch_drift := false
var touch_n