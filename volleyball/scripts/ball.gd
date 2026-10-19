class_name VolleyBall
extends RigidBody3D

const RADIUS := 0.155

signal surface_contact(surface: String)
@export var air_density := 1.2
@export var drag_coefficient := 0.20
@export var magnus_coefficient := 0.0004
@export var magnus_force_limit := 0.15
var previous_center := Vector3.ZERO
var previous_center_valid := false

var contact_athletes: Array = []
var replica := false
var athlete: VolleyAthlete
var acceleration := Vector3.ZERO
var last_velocity := Vector3.ZERO
var pending_feed := false
var feed_position := Vector3.ZERO
var feed_velocity := Vector3.ZERO
var feed_spin := FEED_SPIN
var float_active := false
var float_age := 0.0
var float_flight := VolleyFloatFlight.new()
var attack_owner: WeakRef
var attack_team := -1
var attack_skill := 0.5
var attack_factor := 1.0
var attack_quality := 0.0
var attack_kind := -1
var last_duel: Dictionary = {}
var quick_pending := false
var quick_active := false
var quick_age := 0.0
var quick_arrival := 0.0
var quick_braked := false
var quick_target: WeakRef
var quick_brakes := 0
func configure_quick(arrival: float, recipient: ContextAthlete) -> void:
 quick_pending = true
 quick_arrival = arrival
 quick_target = weakref(recipient)
 quick_age = 0
 quick_braked = false
func clear_quick() -> void:
 quick_active = false
 quick_pending = false
 quick_target = null
var held := false
var toss_yaw := 0.0
var jump_toss := false
enum HeldMode { TOSS, THROW }
var held_mode := HeldMode.TOSS
var standing_height := 1.5
var jumping_height := 2.35
var throw_height := 1.0
var throw_target := Vector3.ZERO
const FEED_SPIN := Vector3(2.3, 0.6, 1.1)

func release_height() -> float:
 if held_mode == HeldMode.THROW:
  return throw_height
 return jumping_height if jump_toss else standing_height

func set_release_height(value: float) -> void:
 value = clampf(value, 0.35, 3.5)
 if held_mode == HeldMode.THROW:
  throw_height = value
 elif jump_toss:
  jumping_height = value
 else:
  standing_height = value

func toggle_held_mode() -> void:
 held_mode = HeldMode.THROW if held_mode == HeldMode.TOSS else HeldMode.TOSS

func aim_throw_at(camera: Camera3D, screen: Vector2) -> bool:
 var ray := camera.project_ray_normal(screen)
 if ray.y >= -0.025:
  return false
 var origin := camera.project_ray_origin(screen)
 var target := origin + ray * ((VolleyBall.RADIUS - origin.y) / ray.y)
 var offset := target - athlete.hold_position()
 offset.y = 0
 throw_target = athlete.hold_position() + offset.limit_length(14)
 throw_target.y = VolleyBall.RADIUS
 return true

func aim_toss(relative: Vector2) -> void:
 toss_yaw = clampf(toss_yaw - relative.x * 0.0035, -PI / 3, PI / 3)

func upward_for_height(height: float) -> float:
 # Integrate quadratic vertical drag analytically to reach the chosen apex.
 var drag := 0.5 * air_density * drag_coefficient * PI * VolleyBall.RADIUS * VolleyBall.RADIUS / mass
 if drag < 0.00001:
  return sqrt(2.0 * 9.81 * height)
 return sqrt(9.81 / drag * (exp(2.0 * drag * height) - 1.0))

func toss_velocity() -> Vector3:
 var forward := -athlete.visual.global_basis.z
 forward.y = 0
 forward = -Basis(Vector3.UP, athlete.camera_yaw).z if athlete is ContextAthlete else forward.normalized().rotated(Vector3.UP, toss_yaw)
 var drift := 0.35
 if athlete is ContextAthlete:
  var kind: int = athlete.delivery_kind()
  drift = float(athlete.mechanic(kind).get("toss_drift", lerpf(0.50, 0.20, athlete.style_stats.n("spike"))))
 return forward * drift + Vector3.UP * upward_for_height(release_height()) + athlete.velocity

func aiming_throw() -> bool:
 return held and held_mode == HeldMode.THROW

func throw_velocity() -> Vector3:
 return solve_launch(athlete.hold_position(), throw_target, throw_height)

func solve_launch(start: Vector3, destination: Vector3, apex: float, launch_spin := FEED_SPIN) -> Vector3:
 var upward := upward_for_height(apex)
 var flight_time := (upward + sqrt(upward * upward + 2 * 9.81 * maxf(0, start.y - VolleyBall.RADIUS))) / 9.81
 var offset := destination - start
 offset.y = 0
 var speed := offset / flight_time + Vector3.UP * upward
 # Solve launch velocity before release. The free ball receives no guidance.
 for iteration in range(3):
  var at := start
  var v := speed
  var spin := launch_spin
  var step := 1.0 / 120.0
  var time := 0.0
  for tick in range(360):
   v += (Vector3.DOWN * 9.81 + aero_force(v, spin) / mass) * step
   spin *= 1.0 - angular_damp * step
   at += v * step
   time += step
   if at.y <= VolleyBall.RADIUS:
    break
  var correction := (destination - at) / maxf(time, 0.1)
  correction.y = 0
  speed += correction
 return speed

func solve_pass(start: Vector3, contact: Vector3, apex: float, launch_spin: Vector3) -> Vector3:
 # Meet a moving teammate above their hands on descent rather than aim a
 # floor landing under their feet. This is solved only before the contact.
 var upward := upward_for_height(maxf(apex, contact.y - start.y + 0.5))
 var duration := (upward + sqrt(maxf(0.1, upward * upward + 19.62 * (start.y - contact.y)))) / 9.81
 var steps := maxi(1, roundi(duration * 120))
 duration = steps / 120.0
 var speed := (contact - start) / duration + Vector3.UP * 4.905 * duration
 for iteration in range(4):
  var at := start
  var v := speed
  var spin := launch_spin
  for tick in range(steps):
   v += (Vector3.DOWN * 9.81 + aero_force(v, spin) / mass) / 120.0
   spin *= 1.0 - angular_damp / 120.0
   at += v / 120.0
  speed += (contact - at) / duration
 return speed

func power_serve_flight(start: Vector3, velocity: Vector3, spin: Vector3) -> Dictionary:
 var at := start
 var net_height := INF
 var net_clearance := INF
 for tick in range(600):
  velocity += (Vector3.DOWN * 9.81 + aero_force(velocity, spin) / mass) / 120.0
  spin *= 1.0 - angular_damp / 120.0
  var previous := at
  at += velocity / 120.0
  if previous.z * at.z < 0:
   net_height = previous.lerp(at, previous.z / (previous.z - at.z)).y
  # A steep short shot must clear both edges of the ball-sized net corridor.
  # Checking the centre plane alone can miss a descending tape contact.
  for plane in [-RADIUS - 0.04, RADIUS + 0.04]:
   if (previous.z - plane) * (at.z - plane) < 0:
    net_clearance = minf(net_clearance, previous.lerp(at, (previous.z - plane) / (previous.z - at.z)).y)
  if at.y <= VolleyBall.RADIUS:
   break
 return {"landing": at, "net_height": net_height, "net_clearance": net_clearance}

func solve_lifted_hit(start: Vector3, destination: Vector3, apex: float, spin: Vector3) -> Vector3:
 # Low standing contact needs lift, not a downward spike vector. Solve the
 # chosen strength/distance before contact, then leave the free ball alone.
 var launch := solve_launch(start, destination, apex, spin)
 if start.z * destination.z >= 0:
  return launch
 for attempt in range(9):
  var flight := power_serve_flight(start, launch, spin)
  if flight.net_height >= 2.76 and flight.net_clearance >= 2.66:
   break
  apex = minf(apex * 1.45 + 0.20, 8.0)
  launch = solve_launch(start, destination, apex, spin)
 return launch

func power_serve_landing(start: Vector3, velocity: Vector3, spin: Vector3) -> Vector3:
 return power_serve_flight(start, velocity, spin).landing

func solve_power_serve(start: Vector3, destination: Vector3, speed: float, spin: Vector3) -> Vector3:
 # Skill/charge set available pace. A low contact cannot physically deliver
 # maximum pace over a 2.43 m net and still land inside an 18 m court.
 # Ease that pace before contact; never steer or accelerate a ball in flight.
 var horizontal := destination - start
 horizontal.y = 0
 var distance := horizontal.length()
 horizontal = horizontal.normalized()
 var launch := Vector3.ZERO
 for attempt in range(9):
  var low := deg_to_rad(-24.0)
  var high := deg_to_rad(34.0)
  for iteration in range(12):
   var angle := (low + high) * 0.5
   var velocity := (horizontal * cos(angle) + Vector3.UP * sin(angle)) * speed
   var landing := power_serve_landing(start, velocity, spin)
   var travelled := Vector3(landing.x - start.x, 0, landing.z - start.z).dot(horizontal)
   if travelled < distance:
    low = angle
   else:
    high = angle
  var angle := (low + high) * 0.5
  launch = (horizontal * cos(angle) + Vector3.UP * sin(angle)) * speed
  if start.z * destination.z >= 0 or power_serve_flight(start, launch, spin).net_height >= 2.70:
   break
  speed *= 0.94
 return launch

func aero_force(speed: Vector3, spin: Vector3) -> Vector3:
 var area := PI * VolleyBall.RADIUS * VolleyBall.RADIUS
 return (spin.cross(speed) * magnus_coefficient).limit_length(magnus_force_limit) - speed * speed.length() * 0.5 * air_density * drag_coefficient * area

func preview_points() -> PackedVector3Array:
 var points := PackedVector3Array()
 var at := athlete.hold_position()
 var speed := throw_velocity() if aiming_throw() else toss_velocity()
 var spin := FEED_SPIN
 var step := 1.0 / 120.0
 points.append(at)
 for tick in range(360):
  speed += (Vector3.DOWN * 9.81 + aero_force(speed, spin) / mass) * step
  spin *= 1.0 - angular_damp * step
  var next := at + speed * step
  var ray := PhysicsRayQueryParameters3D.create(at, next, 1)
  if next.y <= VolleyBall.RADIUS or not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
   break
  at = next
  if tick % 5 == 4:
   points.append(at)
 return points

func can_pick_up() -> bool:
 return can_pick_up_for(athlete)

func can_pick_up_for(candidate: VolleyAthlete) -> bool:
 if held or (pending_feed and not replica) or (last_velocity if replica else linear_velocity).length() > 3.0:
  return false
 var offset := global_position - candidate.global_position
 if Vector2(offset.x, offset.z).length() > 1.6 or offset.y > 2.0 or offset.y < -0.2:
  return false
 var ray := PhysicsRayQueryParameters3D.create(candidate.global_position + Vector3(0, 1.0, 0), global_position, 1)
 return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func pick_up() -> bool:
 if not can_pick_up():
  athlete.last_result = "Подойдите к медленному мячу (до 1.6 м)"
  return false
 clear_float()
 clear_attack()
 held = true
 if athlete is ContextAthlete:
  athlete.serve_swing_used = false
  athlete.service_attempt_active = false
 held_mode = HeldMode.TOSS
 var forward := -athlete.visual.global_basis.z
 forward.y = 0
 throw_target = athlete.hold_position() + forward.normalized() * 6.0
 throw_target.y = VolleyBall.RADIUS
 toss_yaw = 0
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
 if held and not replica:
  global_position = athlete.hold_position()

func drop() -> void:
 if held:
  feed(athlete.hold_position(), athlete.velocity)

func toss() -> bool:
 if not held:
  athlete.last_result = "Сначала подберите мяч"
  return false
 jump_toss = athlete.technique == VolleyAthlete.Technique.JUMP_SERVE
 if athlete is ContextAthlete:
  athlete.animate_release()
 feed(athlete.hold_position(), toss_velocity())
 if athlete is ContextAthlete:
  athlete.service_attempt_active = true
  athlete.serve_swing_used = false
 athlete.last_result = "Подброс • удержать и отпустить основную кнопку для удара"
 return true

func throw_held() -> bool:
 if not held:
  athlete.last_result = "Бросок: сначала подберите мяч"
  return false
 if athlete is ContextAthlete:
  athlete.animate_release()
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
 linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
 angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
 contact_monitor = true
 max_contacts_reported = 8
 body_entered.connect(_on_body_entered)
 var mat := PhysicsMaterial.new()
 mat.bounce = 0.73
 mat.friction = 0.45
 physics_material_override = mat
 var cs := CollisionShape3D.new()
 var shape := SphereShape3D.new()
 shape.radius = VolleyBall.RADIUS
 cs.shape = shape
 add_child(cs)
 var ball_mesh := VolleyGeometry.sphere(self, Vector3.ZERO, VolleyBall.RADIUS, Color("ffdf79"))
 var shader := Shader.new()
 shader.code = "shader_type spatial; void fragment(){float p=sin(UV.x*18.8496+sin(UV.y*12.566)*0.6); ALBEDO=p>0.25?vec3(0.97,0.96,0.88):(p< -0.25?vec3(0.08,0.27,0.44):vec3(0.98,0.72,0.17)); ROUGHNESS=0.7;}"
 var material := ShaderMaterial.new()
 material.shader = shader
 ball_mesh.material_override = material

func clear_float() -> void:
 float_active = false
 float_age = 0

func _on_body_entered(body: Node) -> void:
 clear_quick()
 clear_float()
 var surface := str(body.get_meta("surface", "world"))
 if surface == "net":
  attack_quality *= 0.8
 else:
  clear_attack()
 surface_contact.emit(surface)

func clear_attack() -> void:
 attack_owner = null
 attack_team = -1
 attack_quality = 0
 attack_kind = -1
 last_duel = {}

static func team_of(actor: ContextAthlete) -> int:
 return actor.court_team if actor.court_team >= 0 else (0 if actor.global_position.z >= 0 else 1)

func attack_for(blocker: ContextAthlete) -> Dictionary:
 if replica or blocker.strike_technique != ContextAthlete.BLOCK or attack_owner == null:
  return {}
 var source: Variant = attack_owner.get_ref()
 if not is_instance_valid(source):
  clear_attack()
  return {}
 if source == blocker or team_of(blocker) == attack_team:
  return {}
 return {"skill": attack_skill, "quality": attack_quality, "kind": attack_kind, "factor": attack_factor}

func remember_contact(actor: ContextAthlete) -> void:
 if replica:
  return
 if actor.strike_technique in [VolleyAthlete.Technique.SPIKE, ContextAthlete.TIP]:
  clear_attack()
  attack_owner = weakref(actor)
  attack_team = team_of(actor)
  attack_skill = actor.style_stats.n("spike")
  attack_factor = actor.style_stats.factor("spike")
  attack_quality = actor.quality
  attack_kind = actor.strike_technique
 elif actor.strike_technique == ContextAthlete.BLOCK and not actor.duel_result.is_empty():
  var result := actor.duel_result.duplicate()
  if result.pierced:
   # A second actual blocker faces a weakened attack, never the original pace.
   attack_quality *= 0.85
  else:
   clear_attack()
  last_duel = result
 else:
  clear_attack()

func launch_float(at: Vector3, speed: Vector3, spin: Vector3, skill: float, seed_value: int) -> void:
 if replica:
  return
 feed(at, speed, spin)
 float_flight.configure(skill, seed_value)
 float_active = true

func feed(at: Vector3, speed: Vector3, spin := FEED_SPIN) -> void:
 clear_quick()
 if replica:
  return
 clear_float()
 clear_attack()
 if athlete is ContextAthlete:
  athlete.service_attempt_active = false
  athlete.serve_swing_used = false
 held = false
 athlete.holding_ball = false
 freeze = false
 collision_mask = 1
 feed_position = at
 feed_velocity = speed
 feed_spin = spin
 pending_feed = true
 sleeping = false
 previous_center_valid = false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
 if replica:
  return
 if pending_feed:
  state.transform = Transform3D(Basis.IDENTITY, feed_position)
  state.linear_velocity = feed_velocity
  state.angular_velocity = feed_spin
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
  if obstacle.is_empty():
   var candidates: Array = contact_athletes if not contact_athletes.is_empty() else [athlete]
   for candidate in candidates:
    if not is_instance_valid(candidate) or (candidate is ContextAthlete and (candidate.lower_serve_active or candidate.float_serve_active)):
     continue
    if candidate is ContextAthlete:
     candidate.contact_incoming_spin = state.angular_velocity
    var delta_v: Vector3 = candidate.try_swept_contact(from, center, state.linear_velocity, attack_for(candidate)) if candidate is ContextAthlete else candidate.try_contact(center, state.linear_velocity)
    if delta_v != Vector3.ZERO:
     if quick_pending:
      quick_active = true
      quick_pending = false
     else:
      clear_quick()
     clear_float()
     state.apply_central_impulse(delta_v * mass)
     state.angular_velocity = candidate.outgoing_spin(state.angular_velocity, delta_v) if candidate is ContextAthlete else (state.angular_velocity + candidate.hand_velocity.cross(delta_v) * 0.12).limit_length(50)
     if candidate is ContextAthlete:
      remember_contact(candidate)
     else:
      clear_attack()
     break
  previous_center = center
  previous_center_valid = true
 if quick_active:
  quick_age += state.step
  if not quick_braked and quick_age >= quick_arrival:
   state.linear_velocity *= 0.035
   state.angular_velocity *= 0.10
   quick_braked = true
   quick_brakes += 1
  if quick_age >= quick_arrival + 0.10:
   clear_quick()
 # Approximate, bounded Magnus force; no target or player tracking.
 state.apply_central_force(aero_force(state.linear_velocity, state.angular_velocity))
 if float_active:
  float_age += state.step
  state.apply_central_force(float_flight.force(state.linear_velocity, state.angular_velocity, float_age))
 acceleration = (state.linear_velocity - last_velocity) / state.step
 last_velocity = state.linear_velocity
