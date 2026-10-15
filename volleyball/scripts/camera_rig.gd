class_name VolleyCameraRig
extends Node3D

var athlete: ContextAthlete
var ball: VolleyBall
var camera: Camera3D
var yaw := 0.0
var pitch := -0.24
var sensitivity := 1.0
var distance := 5.8
var followed := Vector3.ZERO
var rendered_yaw := 0.0
var rendered_pitch := -0.24

func _ready() -> void:
 camera = Camera3D.new()
 camera.fov = 72
 camera.near = 0.08
 add_child(camera)
 camera.current = true
 followed = athlete.global_position + Vector3.UP * 1.4

func look(delta: Vector2) -> void:
 yaw -= delta.x * 0.0035 * sensitivity
 pitch = clampf(pitch - delta.y * 0.0035 * sensitivity, -0.85, 0.95)
 athlete.camera_yaw = yaw
 athlete.camera_pitch = pitch

func _process(dt: float) -> void:
 var target := athlete.global_position + Vector3.UP * 1.45
 followed = followed.lerp(target, 1 - exp(-12 * dt))
 rendered_yaw = lerp_angle(rendered_yaw, yaw, 1 - exp(-22 * dt))
 rendered_pitch = lerpf(rendered_pitch, pitch, 1 - exp(-22 * dt))
 var rotation_basis := Basis(Vector3.UP, rendered_yaw) * Basis(Vector3.RIGHT, rendered_pitch)
 var desired := followed + rotation_basis.z * distance + rotation_basis.x * 0.42
 var ray := PhysicsRayQueryParameters3D.create(followed, desired, 1)
 var hit := get_world_3d().direct_space_state.intersect_ray(ray)
 if not hit.is_empty():
  desired = hit.position + hit.normal * 0.22
 camera.global_position = desired
 camera.look_at(followed - rotation_basis.z * 5)
 athlete.camera_yaw = yaw
 athlete.camera_pitch = pitch

func movement(axis: Vector2) -> Vector2:
 var vector := Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y)
 return Vector2(vector.x, vector.z)
