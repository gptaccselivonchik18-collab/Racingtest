class_name VolleyBall
extends RigidBody3D

signal surface_contact(surface: String)
@export var air_density := 1.2
@export var drag_coefficient := 0.20
@export var magnus_coefficient := 0.0004
@export var magnus_force_limit := 0.15
var previous_center := Vector3.ZERO
var previous_center_valid := false

var athlete: VolleyAthlete
var acceleration := Vector3.ZERO
var last_velocity := Vector3.ZERO
var pending_feed := false
var feed_position := Vector3.ZERO
var feed_velocity := Vector3.ZERO
var held := false
var toss_yaw := 0.0
var toss_elevation := deg_to_rad(86.0)
var jump_toss := false
const FEED_SPIN := Vector3(2.3, 0.6, 1.1)

func aim_toss(relative: Vector2) -> void:
 toss_yaw = clampf(toss_yaw - relative.x * 0.0035, -PI / 3, PI / 3)
 toss_elevation = clampf(toss_elevation - relative.y * 0.0025, deg_to_rad(50), deg_to_rad(88))

func toss_velocity() -> Vector3:
 var forward := -athlete.visual.global_basis.z
 forward.y = 0
 forward = forward.normalized().rotated(Vector3.UP, toss_yaw)
 return (forward * cos(toss_elevation) + Vector3.UP * sin(toss_elevation)) * (6.8 if jump_toss else 5.4) + athlete.velocity

func aiming_throw() -> bool:
 return held and athlete.technique == VolleyAthlete.Technique.THROW and athlete.action == VolleyAthlete.Action.PREPARE

func throw_velocity() -> Vector3:
 return athlete.desired_direction() * lerpf(2.0, 12.0, athlete.power) + athlete.velocity

func aero_force(speed: Vector3, spin: Vector3) -> Vector3:
 var area := PI * VolleyAthlete.BALL_RADIUS * VolleyAthlete.BALL_RADIUS
 return (spin.cross(speed) * magnus_coefficient).limit_length(magnus_force_limit) - speed * speed.length() * 0.5 * air_density * drag_coefficient * area

func preview_points() -> PackedVector3Array:
 var points := PackedVector3Array()
 var at := athlete.hold_position()
 var speed := throw_velocity() if aiming_throw() else toss_velocity()
 var spin := FEED_SPIN
 var step := 1.0 / 120.0
 points.append(at)
 for tick in range(240):
  speed += (Vector3.DOWN * 9.81 + aero_force(speed, spin) / mass) * step
  spin *= 1.0 - angular_damp * step
  var next := at + speed * step
  var ray := PhysicsRayQueryParameters3D.create(at, next, 1)
  if next.y <= VolleyAthlete.BALL_RADIUS or not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
   break
  at = next
  if tick % 5 == 4:
   points.append(at)
 return points

func can_pick_up() -> bool:
 if held or pending_feed or linear_velocity.length() > 3.0:
  return false
 var offset := global_position - athlete.global_position
 if Vector2(offset.x, offset.z).length() > 1.15 or offset.y > 1.8 or offset.y < -0.2:
  return false
 var ray := PhysicsRayQueryParameters3D.create(athlete.global_position + Vector3(0, 1.0, 0), global_position, 1)
 return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func pick_up() -> bool:
 if not can_pick_up():
  athlete.last_result = "Подойдите к медленному мячу (до 1.15 м)"
  return false
 held = true
 toss_yaw = 0
 toss_elevation = deg_to_rad(86)
 athlete.holding_ball = true
 athlete.cancel_input()
 athlete.action = VolleyAthlete.Action.IDLE
 freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
 freeze = true
 collision_mask = 0
 linear_velocity = Vector3.ZERO
 angular_velocity = Vector3.ZERO
 athlete.last_result = "Мяч в руках • ПОДБРОС или БРОСОК"
 return true

func _physics_process(_dt: float) -> void:
 if held:
  global_position = athlete.hold_position()

func drop() -> void:
 if held:
  feed(athlete.hold_position(), athlete.velocity)

func toss() -> bool:
 if not held:
  athlete.last_result = "Сначала подберите мяч"
  return false
 jump_toss = athlete.technique == VolleyAthlete.Technique.JUMP_SERVE
 feed(athlete.hold_position(), toss_velocity())
 athlete.last_result = "Подброс • удержать и отпустить основную кнопку для удара"
 return true

func throw_held() -> bool:
 if not held:
  athlete.last_result = "Бросок: сначала подберите мяч"
  return false
 feed(athlete.hold_position(), throw_velocity())
 athlete.action = VolleyAthlete.Action.RECOVER
 athlete.strike_technique = VolleyAthlete.Technique.THROW
 athlete.action_time = 0.0
 athlete.last_result = "Бросок • направление и сила заданы вами"
 return true

func _ready() -> void:
 mass = 0.27
 continuous_cd = true
 collision_layer = 4
 collision_mask = 1
 linear_damp = 0.0
 angular_damp = 0.15
 contact_monitor = true
 max_contacts_reported = 8
 body_entered.connect(func(body: Node): surface_contact.emit(str(body.get_meta("surface", "world"))))
 var mat := PhysicsMaterial.new()
 mat.bounce = 0.73
 mat.friction = 0.45
 physics_material_override = mat
 var cs := CollisionShape3D.new()
 var shape := SphereShape3D.new()
 shape.radius = VolleyAthlete.BALL_RADIUS
 cs.shape = shape
 add_child(cs)
 var ball_mesh := VolleyGeometry.sphere(self, Vector3.ZERO, VolleyAthlete.BALL_RADIUS, Color("ffdf79"))
 var shader := Shader.new()
 shader.code = "shader_type spatial; void fragment(){float p=sin(UV.x*18.8496+sin(UV.y*12.566)*0.6); ALBEDO=p>0.25?vec3(0.97,0.96,0.88):(p< -0.25?vec3(0.08,0.27,0.44):vec3(0.98,0.72,0.17)); ROUGHNESS=0.7;}"
 var material := ShaderMaterial.new()
 material.shader = shader
 ball_mesh.material_override = material

func feed(at: Vector3, speed: Vector3) -> void:
 held = false
 athlete.holding_ball = false
 freeze = false
 collision_mask = 1
 feed_position = at
 feed_velocity = speed
 pending_feed = true
 sleeping = false
 previous_center_valid = false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
 if pending_feed:
  state.transform = Transform3D(Basis.IDENTITY, feed_position)
  state.linear_velocity = feed_velocity
  state.angular_velocity = FEED_SPIN
  pending_feed = false
  last_velocity = feed_velocity
  previous_center = feed_position
  previous_center_valid = true
  return
 if is_instance_valid(athlete):
  var center := state.transform.origin
  var from := previous_center if previous_center_valid else center
  # Clip swept hand checks at solid world geometry so a fast ball cannot hit
  # hands through the net. The rigid-body CCD handles the world collision.
  var ray := PhysicsRayQueryParameters3D.create(from, center, 1)
  var obstacle := get_world_3d().direct_space_state.intersect_ray(ray) if from.distance_to(center) > 0.001 else {}
  var delta_v := Vector3.ZERO
  if obstacle.is_empty():
   if athlete is ContextAthlete:
    delta_v = athlete.try_swept_contact(from, center, state.linear_velocity)
   else:
    delta_v = athlete.try_contact(center, state.linear_velocity)
  if delta_v != Vector3.ZERO:
   state.apply_central_impulse(delta_v * mass)
   state.angular_velocity = (state.angular_velocity + athlete.hand_velocity.cross(delta_v) * 0.12).limit_length(50)
  previous_center = center
  previous_center_valid = true
 # Approximate, bounded Magnus force; no target or player tracking.
 state.apply_central_force(aero_force(state.linear_velocity, state.angular_velocity))
 acceleration = (state.linear_velocity - last_velocity) / state.step
 last_velocity = state.linear_velocity
