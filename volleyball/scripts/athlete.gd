class_name VolleyAthlete
extends CharacterBody3D

enum Technique { OVERHEAD, UNDERHAND, SPIKE, SERVE, JUMP_SERVE, THROW }
const TECHNIQUE_NAMES := ["Верхний пас", "Нижний пас", "Нападение", "Подача", "Подача в прыжке", "Бросок"]
const DEFAULT_ANGLES := [58.0, 48.0, -22.0, 18.0, 12.0, 55.0]
enum Action { IDLE, PREPARE, STRIKE, RECOVER }
const BALL_RADIUS := 0.105
const HAND_RADIUS := 0.085
const FOREARM_RADIUS := 0.07
var stats := AthleteStats.new()
var technique := Technique.OVERHEAD
var strike_technique := Technique.OVERHEAD
var action := Action.IDLE
var move_axis := Vector2.ZERO
var sprint := false
var aim := Vector2(0, -1)
var power := 0.65
var elevation := 58.0
var strike_direction := Vector3.FORWARD
var strike_power := 0.65
var action_time := 0.0
var strike_duration := 0.24
var hit_used := false
var strike_count := 0
var contact_count := 0
var energy := 1.0
var quality := 0.0
var deviation := 0.0
var last_result := "Запустите мяч • R"
var rng := RandomNumberGenerator.new()
var random_seed := 20261014
var visual: Node3D
var arms: Array[MeshInstance3D] = []
var hands: Array[MeshInstance3D] = []
var legs: Array[MeshInstance3D] = []
var elbows: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var wrists: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var previous_elbows: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var previous_wrists: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var hand_velocity := Vector3.ZERO
var gait := 0.0
var holding_ball := false

func select_technique(value: int) -> void:
 technique = clampi(value, 0, Technique.THROW)
 elevation = DEFAULT_ANGLES[technique]
 if action == Action.PREPARE:
  action_time = 0.0

func hold_position() -> Vector3:
 return visual.to_global(Vector3(0.18, 1.3, -0.5))

func _ready() -> void:
 reset_seed(random_seed)
 collision_layer = 2
 collision_mask = 1
 var shape := CapsuleShape3D.new()
 shape.radius = 0.27
 shape.height = 1.75
 var cs := CollisionShape3D.new()
 cs.shape = shape
 cs.position.y = 0.875
 add_child(cs)
 visual = Node3D.new()
 add_child(visual)
 VolleyGeometry.box(visual, Vector3(0, 1.23, 0), Vector3(0.52, 0.6, 0.31), Color("e6bd58"))
 VolleyGeometry.box(visual, Vector3(0, 0.86, 0), Vector3(0.47, 0.22, 0.32), Color("172c45"))
 VolleyGeometry.sphere(visual, Vector3(0, 1.78, -0.015), 0.2, Color("c28d6b"))
 VolleyGeometry.sphere(visual, Vector3(0, 1.87, 0.02), 0.17, Color("29283a"))
 var number := Label3D.new()
 number.text = "07"
 number.font_size = 64
 number.pixel_size = 0.004
 number.position = Vector3(0, 1.25, 0.16)
 visual.add_child(number)
 for i in range(4):
  arms.append(VolleyGeometry.limb(visual, Color("c28d6b")))
 for i in range(2):
  hands.append(VolleyGeometry.sphere(visual, Vector3.ZERO, HAND_RADIUS, Color("e3b193")))
  legs.append(VolleyGeometry.limb(visual, Color("243952")))
 _update_pose(0.0)
 previous_wrists = wrists.duplicate()
 previous_elbows = elbows.duplicate()

func reset_seed(value: int) -> void:
 random_seed = value
 rng.seed = value

func prepare() -> void:
 if action != Action.STRIKE:
  action = Action.PREPARE
  action_time = 0.0

func release() -> void:
 # No ball lookup here: an empty swing is a complete, immediate action.
 if action != Action.PREPARE:
  return
 if holding_ball:
  last_result = "Сначала ПОДБРОС или выберите БРОСОК"
  action = Action.IDLE
  return
 if technique == Technique.JUMP_SERVE and is_on_floor() and velocity.y <= 0:
  last_result = "Подача в прыжке: сначала ПРЫЖОК"
  action = Action.IDLE
  return
 strike_technique = technique
 strike_direction = desired_direction()
 strike_power = power
 strike_duration = lerpf(0.32, 0.18, stats.n("reaction"))
 action = Action.STRIKE
 action_time = 0.0
 hit_used = false
 strike_count += 1
 last_result = "Движение рук"

func cancel_input() -> void:
 move_axis = Vector2.ZERO
 sprint = false
 if action == Action.PREPARE:
  action = Action.IDLE

func jump() -> void:
 if is_on_floor():
  velocity.y = lerpf(3.0, 5.6, stats.n("jump"))

func desired_direction() -> Vector3:
 var horizontal := Vector3(aim.x, 0, aim.y).normalized()
 var angle := deg_to_rad(elevation)
 return horizontal * cos(angle) + Vector3.UP * sin(angle)

func contact_active() -> bool:
 if action != Action.STRIKE:
  return false
 var phase := action_time / strike_duration
 return phase >= 0.12 and phase <= 0.86

func _physics_process(dt: float) -> void:
 previous_wrists = wrists.duplicate()
 previous_elbows = elbows.duplicate()
 var running := sprint and energy > 0.05 and move_axis.length() > 0.1
 var max_speed := lerpf(2.3, 5.4, stats.n("speed")) * (1.55 if running else 1.0)
 energy = clampf(energy + dt * ((-0.32 + 0.22 * stats.n("stamina")) if running else 0.14), 0, 1)
 var acceleration := lerpf(7.0, 22.0, stats.n("agility"))
 velocity.x = move_toward(velocity.x, move_axis.x * max_speed, acceleration * dt)
 velocity.z = move_toward(velocity.z, move_axis.y * max_speed, acceleration * dt)
 if not is_on_floor():
  velocity.y -= 9.81 * dt
 move_and_slide()
 position.x = clampf(position.x, -6.5, 6.5)
 position.z = clampf(position.z, -10.5, 10.5)
 if action == Action.PREPARE:
  var target_yaw := atan2(-aim.x, -aim.y)
  visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, minf(1, dt * lerpf(3, 12, stats.n("coordination"))))
 action_time += dt
 if action == Action.STRIKE and action_time >= strike_duration:
  action = Action.RECOVER
  action_time = 0
  if not hit_used:
   last_result = "ПРОМАХ • мяча в руках не было"
 elif action == Action.RECOVER and action_time > 0.25:
  action = Action.IDLE
 gait += Vector2(velocity.x, velocity.z).length() * dt * 2.5
 _update_pose(dt)

func _update_pose(dt: float) -> void:
 var t := clampf(action_time / strike_duration, 0, 1)
 var mode: int = strike_technique if action == Action.STRIKE or action == Action.RECOVER else technique
 var blend := 0.0
 if action == Action.PREPARE:
  blend = 1.0
 elif action == Action.STRIKE:
  blend = 1.0
 elif action == Action.RECOVER:
  blend = 1.0 - clampf(action_time / 0.25, 0, 1)
 for i in range(2):
  var side := -1.0 if i == 0 else 1.0
  var shoulder := Vector3(side * 0.3, 1.45, 0)
  var elbow := Vector3(side * 0.36, 1.12, -0.03)
  var wrist := Vector3(side * 0.32, 0.88, -0.08)
  var e: Vector3
  var w: Vector3
  if mode == Technique.OVERHEAD:
   e = Vector3(side * 0.36, 1.55, -0.24)
   w = Vector3(side * 0.13, 1.96, -0.32)
   if action == Action.STRIKE:
    e += Vector3(0, 0.18 * t, -0.18 * t)
    w += Vector3(0, 0.35 * sin(t * PI * 0.5), -0.35 * t)
  elif mode == Technique.UNDERHAND:
   e = Vector3(side * 0.22, 1.12, -0.28)
   w = Vector3(side * 0.075, 0.93, -0.63)
   if action == Action.STRIKE:
    e += Vector3(0, 0.18 * t, -0.08 * t)
    w += Vector3(0, 0.49 * t, -0.12 * t)
  else:
   # Attack/serve: one striking palm, drawn and tested at the same location.
   if i == 1:
    e = Vector3(0.35, 1.65, 0.12)
    w = Vector3(0.22, 2.05, 0.12)
    if action == Action.STRIKE:
     e = e.lerp(Vector3(0.3, 1.7, -0.35), t)
     w = Vector3(0.2, 2.05 + sin(t * PI) * 0.25, 0.12 - t * 1.15)
   else:
    e = Vector3(-0.3, 1.4, -0.15)
    w = Vector3(-0.2, 1.7, -0.35)
  if holding_ball:
   e = Vector3(side * 0.3, 1.2, -0.2)
   w = Vector3(0.18 + side * 0.1, 1.3, -0.5)
   blend = 1.0
  elbow = elbow.lerp(e, blend)
  wrist = wrist.lerp(w, blend)
  VolleyGeometry.segment(arms[i * 2], shoulder, elbow, 0.075)
  VolleyGeometry.segment(arms[i * 2 + 1], elbow, wrist, FOREARM_RADIUS)
  hands[i].position = wrist
  elbows[i] = visual.to_global(elbow)
  wrists[i] = visual.to_global(wrist)
  var step := sin(gait + i * PI) * minf(0.22, Vector2(velocity.x, velocity.z).length() * 0.05)
  VolleyGeometry.segment(legs[i], Vector3(side * 0.14, 0.83, 0), Vector3(side * 0.15, 0.12, step), 0.105)
 if dt > 0:
  hand_velocity = ((wrists[0] + wrists[1]) - (previous_wrists[0] + previous_wrists[1])) * 0.5 / dt

func intersects_ball(center: Vector3) -> bool:
 for i in range(2):
  if strike_technique >= Technique.SPIKE and i == 0:
   continue
  if center.distance_to(wrists[i]) <= BALL_RADIUS + HAND_RADIUS:
   return true
  if strike_technique == Technique.UNDERHAND and VolleyGeometry.distance_to_segment(center, elbows[i], wrists[i]) <= BALL_RADIUS + FOREARM_RADIUS:
   return true
 return false

func try_contact(center: Vector3, incoming: Vector3) -> Vector3:
 # Strict overlap against the SAME joint positions used to draw the limbs.
 # 120 Hz + CCD on the ball; no attraction, snapping, or late-hit grace period.
 if hit_used or not contact_active() or not intersects_ball(center):
  return Vector3.ZERO
 hit_used = true
 contact_count += 1
 var forward := -visual.global_basis.z
 var align := clampf(forward.dot(Vector3(strike_direction.x, 0, strike_direction.z).normalized()), 0, 1)
 var timing := 1.0 - absf(action_time / strike_duration - 0.48) / 0.48
 quality = clampf((0.55 + 0.45 * timing) * (0.65 + 0.35 * align), 0.15, 1)
 var spread := lerpf(8.0, 0.4, stats.n("accuracy")) * (1.45 - quality) / (0.6 + 0.4 * stats.n("coordination"))
 deviation = rng.randf_range(-spread, spread)
 var direction := strike_direction.rotated(Vector3.UP, deg_to_rad(deviation))
 direction = direction.rotated(Vector3.RIGHT, deg_to_rad(rng.randf_range(-spread, spread) * 0.5)).normalized()
 var control := stats.n("control")
 var magnitude := lerpf(2.0, 12.5, strike_power) * lerpf(0.65, 1.2, stats.n("strength"))
 if strike_technique == Technique.SPIKE:
  magnitude *= 1.8
 elif strike_technique == Technique.SERVE:
  magnitude *= 1.55
 elif strike_technique == Technique.JUMP_SERVE:
  magnitude *= 1.9
 magnitude *= rng.randf_range(1.0 - 0.18 * (1 - control), 1.0 + 0.18 * (1 - control))
 magnitude *= quality * (0.9 if strike_technique == Technique.UNDERHAND else 1.0)
 var hand_speed := maxf(0, hand_velocity.dot(direction))
 # A passive rebound and active hand work both contribute. Bad control retains
 # more incoming lateral velocity; stats never bypass the overlap test above.
 var rebound := incoming.bounce(direction) * lerpf(0.4, 0.12, control)
 var outgoing := direction * (magnitude + hand_speed * 0.28) + rebound + velocity * 0.15
 last_result = "КАСАНИЕ • %d%%" % int(quality * 100)
 return outgoing - incoming
