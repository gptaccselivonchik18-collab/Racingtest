class_name VolleyCameraRig
extends Node3D

var athlete: ContextAthlete
var ball: VolleyBall
var camera: Camera3D
var yaw := 0.0
var pitch := 0.18
var sensitivity := 1.0
# Kept for saved/test integrations; the gameplay camera is attached to the eyes.
var distance := 0.0
var followed := Vector3.ZERO
var rendered_yaw := 0.0
var rendered_pitch := 0.18

func _ready() -> void:
 process_priority = 10
 camera = Camera3D.new()
 camera.fov = 92
 camera.near = 0.025
 add_child(camera)
 camera.current = true
 _process(0)

func look(delta: Vector2) -> void:
 yaw -= delta.x * 0.0035 * sensitivity
 pitch = clampf(pitch - delta.y * 0.0035 * sensitivity, -1.48, 1.48)
 athlete.camera_yaw = yaw
 athlete.camera_pitch = pitch

func _process(_dt: float) -> void:
 # No chase/orbit delay: aim, head and camera share the same view angles.
 rendered_yaw = yaw
 rendered_pitch = pitch
 athlete.camera_yaw = yaw
 athlete.camera_pitch = pitch
 if is_instance_valid(athlete.limb_rig):
  athlete.limb_rig.update_head()
 camera.global_transform = athlete.eye_transform()
 followed = camera.global_position

func movement(axis: Vector2) -> Vector2:
 var vector := Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y)
 return Vector2(vector.x, vector.z)
