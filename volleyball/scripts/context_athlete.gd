class_name ContextAthlete
extends VolleyAthlete

# The base resources stay intact; the additive rig refines limbs and poses.
signal touched(kind: int, point: Vector3, outgoing: Vector3)
@export var contact_ball_radius := 0.38
@export var serve_contact_radius := 0.64
var serve_solver: Callable
var power_serve_solver: Callable
var style_stats := VolleyStyleStats.new()
var landing_cooldown := 0.0

func _init() -> void:
 stats = style_stats

func mechanic(kind: int) -> Dictionary:
 return style_stats.profile(Technique.SERVE if lower_serve_active and kind == Technique.UNDERHAND else kind)

@export var air_acceleration := 0.65
var replica := false
var lower_serve_active := false
var approach_armed := false
var jump_windup := 0.0
var attack_ready := false
var approach_kind := Technique.SPIKE
var approach_blend := 0.0
var limb_rig: VolleyLimbRig
var lean := Vector2.ZERO
var landing_load := 0.0
const BLOCK := 6
const DIVE := 7
const JUMP_SET := 8
const TIP := 9
const NAMES := ["Пас", "Приём", "Атака", "Подача", "Подача в прыжке", "Бросок", "Блок", "Подкат", "Пас в прыжке", "Скидка"]
var tilt := Vector2.ZERO
var camera_yaw := 0.0
var camera_pitch := 0.18
var shift_lock := true
var charged_for := 0.0
var dive_time := -1.0
var dive_cooldown := 0.0
var dive_direction := Vector3.FORWARD
var dive_speed := 0.0
var jump_origin := Vector3.ZERO
var pose_ready := false
var last_contact_point := Vector3.ZERO
var release_time := 0.0
var contact_flash := 0.0
var air_attack := false
var takeoff_speed := 0.0
var look_target := Vector3.ZERO
var look_target_valid := false

func hold_position() -> Vector3:
 if pose_ready and is_instance_valid(limb_rig) and limb_rig.motion.initialized:
  return (wrists[0] + wrists[1]) * 0.5 + visual.global_basis * Vector3(0, 0, -0.025)
 return super.hold_position()

func animate_release() -> void:
 release_time = 0.25

func body_tilt() -> Vector2:
 var direction := Basis(Vector3.UP, camera_yaw) * Vector3(tilt.x, 0, tilt.y)
 var local := Basis(Vector3.UP, visual.global_rotation.y).inverse() * direction
 return Vector2(local.x, local.z).limit_length()

func view_basis() -> Basis:
 return Basis(Vector3.UP, camera_yaw) * Basis(Vector3.RIGHT, camera_pitch)

func head_position() -> Vector3:
 var offset := limb_rig.motion.body_offset if is_instance_valid(limb_rig) else Vector3.ZERO
 return visual.to_global(Vector3(0, 1.78, -0.015) + offset)

func eye_transform() -> Transform3D:
 # The view stays just in front of the existing head, with every mesh visible.
 # A fixed face offset avoids looking through the skull/torso when looking down.
 var eyes := head_position() + Basis(Vector3.UP, camera_yaw) * Vector3(0, 0.035, -0.225)
 # Looking down rotates the existing hair cap toward the face. Keep the
 # lens outside that mesh rather than hiding the head or changing cull layers.
 var front := -Basis(Vector3.UP, camera_yaw).z
 var hair_at := head_position() + view_basis() * Vector3(0, 0.09, 0.035)
 if eyes.distance_to(hair_at) < 0.195:
  eyes += front * maxf(0, 0.195 - (eyes - hair_at).dot(front))
 return Transform3D(view_basis(), eyes)

func tilt_affects(kind: int) -> bool:
 return not lower_serve_active and kind in [Technique.OVERHEAD, JUMP_SET, Technique.SERVE, Technique.JUMP_SERVE, Technique.SPIKE, TIP, BLOCK]

func action_tilt(kind: int) -> Vector2:
 return body_tilt() if tilt_affects(kind) else Vector2.ZERO

func is_receive(kind: int) -> bool:
 return not lower_serve_active and kind in [Technique.OVERHEAD, JUMP_SET, Technique.UNDERHAND]

static func receive_power(held_seconds: float) -> float:
 # Short deliberate taps retain maximum strength. After 1.15 seconds the
 # minimum remains stable, so a long hold never cycles into a hard pass.
 return lerpf(1.0, 0.18, smoothstep(0.10, 1.15, held_seconds))

func receive_elevation(kind: int) -> float:
 var angle := rad_to_deg(camera_pitch)
 if kind in [Technique.OVERHEAD, JUMP_SET]:
  angle -= tilt.y * 11.0
 return clampf(angle, -20.0, 84.0)

func receive_speed(kind: int, elevation_degrees: float, strength_input: float) -> float:
 # At 0/30/60/84 degrees a full set is about 14.8/13.0/9.3/7.8 m/s.
 # Horizontal shots trade height for pace; soft holds scale the whole curve.
 var loft := smoothstep(5.0, 78.0, elevation_degrees)
 var maximum := lerpf(15.6 if kind == Technique.UNDERHAND else 14.8, 8.4 if kind == Technique.UNDERHAND else 7.8, loft)
 var p := mechanic(kind)
 maximum *= lerpf(1.0, float(p.lift if kind == Technique.UNDERHAND else p.arc), loft)
 return maximum * lerpf(float(p.soft_floor), 1.0, clampf((strength_input - 0.18) / 0.82, 0, 1))

func serve_target(point: Vector3) -> Vector3:
 var side := 1.0 if global_position.z >= 0 else -1.0
 var input := body_tilt()
 var depth := clampf(lerpf(2.0, float(mechanic(Technique.SERVE).depth), power if action == Action.PREPARE else strike_power) + input.y * 2.8, 1.4, 8.5)
 var forward := -visual.global_basis.z
 var z := -side * depth
 var x := point.x + forward.x / maxf(0.25, absf(forward.z)) * absf(z - point.z) + visual.global_basis.x.x * input.x * 3.7
 return Vector3(x, BALL_RADIUS, z)

func power_serve_speed() -> float:
 # Serve owns delivery/control; Spike contributes only strike efficiency.
 var amount := power if action == Action.PREPARE else strike_power
 return lerpf(17.0, 26.0, amount) * float(mechanic(Technique.JUMP_SERVE).power_speed) * lerpf(0.92, 1.08, style_stats.n("spike")) * (1.0 + minf(takeoff_speed, 5.0) * 0.012)

func power_serve_target(point: Vector3) -> Vector3:
 var aim := serve_target(point)
 var side := 1.0 if global_position.z >= 0 else -1.0
 # A hard baseline serve needs the longer diagonal/deep court to clear the net.
 var amount := power if action == Action.PREPARE else strike_power
 aim.z = -side * clampf(6.6 + amount * 1.5 + body_tilt().y * 1.8, 4.4, 8.8)
 var forward := -visual.global_basis.z
 aim.x = point.x + forward.x / maxf(0.25, absf(forward.z)) * absf(aim.z - point.z) + visual.global_basis.x.x * body_tilt().x * 3.7
 return aim

func serve_apex() -> float:
 var input := body_tilt()
 return ((1.8 if strike_technique == Technique.JUMP_SERVE else 2.7) + maxf(-input.y, 0) * 1.1 - maxf(input.y, 0) * 0.30) * float(mechanic(strike_technique).arc)


func _ready() -> void:
 super._ready()
 pose_ready = true
 limb_rig = VolleyLimbRig.new()
 limb_rig.athlete = self
 add_child(limb_rig)
 last_result = "Выберите упражнение в меню • R — следующий мяч"

func _process(dt: float) -> void:
 if not replica or not pose_ready:
  return
 # Server snapshots remain authoritative; evaluate limb curves every rendered
 # frame so a 30 Hz network update does not freeze arms between packets.
 action_time += dt
 release_time = maxf(0, release_time - dt)
 contact_flash = maxf(0, contact_flash - dt)
 if dive_time >= 0:
  dive_time += dt
 gait += Vector2(velocity.x, velocity.z).length() * dt * 7.6
 _update_pose(dt)

func airborne() -> bool:
 if replica:
  return position.y > 0.06 or velocity.y > 0.1
 return not is_on_floor() or velocity.y > 0.1 or position.y > 0.12

func can_act() -> bool:
 return dive_time < 0 and action == Action.IDLE and not holding_ball and not approach_armed and jump_windup <= 0

func begin_action(kind: int) -> bool:
 if not can_act():
  return false
 technique = kind
 strike_technique = kind
 action = Action.PREPARE
 action_time = 0
 charged_for = 0
 power = receive_power(0) if is_receive(kind) else 0.82
 return true

func prepare() -> void:
 begin_action(technique)

func release() -> void:
 if action != Action.PREPARE or holding_ball:
  return
 strike_technique = technique
 if is_receive(strike_technique):
  power = receive_power(charged_for)
 strike_power = power
 air_attack = strike_technique in [Technique.SPIKE, TIP, Technique.JUMP_SERVE] and airborne()
 if strike_technique == Technique.SPIKE and charged_for < 0.13:
  strike_technique = TIP
 strike_direction = direction_for(strike_technique)
 strike_duration = mechanic(strike_technique).duration
 action = Action.STRIKE
 action_time = 0
 hit_used = false
 strike_count += 1
 last_result = NAMES[strike_technique]

func cancel_input() -> void:
 super.cancel_input()
 tilt = Vector2.ZERO
 charged_for = 0
 approach_armed = false
 jump_windup = 0
 attack_ready = false

func arm_approach(kind := Technique.SPIKE) -> bool:
 if not can_act() or airborne():
  return false
 approach_armed = true
 approach_kind = kind
 technique = kind
 last_result = "Разбег • отпустите на АТАКЕ для прыжка"
 return true

func launch_approach() -> void:
 if not approach_armed or airborne():
  approach_armed = false
  return
 approach_armed = false
 jump_windup = style_stats.movement().plant
 last_result = "Прыжок с замахом • нажмите АТАКА для удара"

func hit_approach() -> bool:
 if not attack_ready or not airborne():
  return false
 attack_ready = false
 charged_for = 0.2
 power = 0.82
 release()
 return action == Action.STRIKE

func jump() -> void:
 if is_on_floor() and dive_time < 0 and landing_cooldown <= 0:
  jump_origin = global_position
  takeoff_speed = Vector2(velocity.x, velocity.z).length()
  velocity.y = sqrt(2.0 * 9.81 * style_stats.movement().jump_height) * lerpf(0.88, 1.0, energy)
  energy = maxf(0, energy - style_stats.movement().jump_cost)

func dive() -> bool:
 if not is_on_floor() or dive_cooldown > 0 or dive_time >= 0 or holding_ball:
  return false
 dive_direction = Vector3(move_axis.x, 0, move_axis.y).normalized()
 cancel_input()
 if dive_direction.length() < 0.1:
  dive_direction = -visual.global_basis.z
 dive_speed = mechanic(DIVE).speed + Vector2(velocity.x, velocity.z).length() * 0.3
 dive_time = 0
 dive_cooldown = mechanic(DIVE).cooldown
 technique = DIVE
 strike_technique = DIVE
 strike_direction = (dive_direction * 0.55 + Vector3.UP * 0.83).normalized()
 strike_power = 0.5
 strike_duration = mechanic(DIVE).duration
 action = Action.STRIKE
 action_time = 0
 hit_used = false
 strike_count += 1
 energy = maxf(0, energy - 0.12)
 last_result = "Подкат"
 return true

func direction_for(kind: int, contact_height := -1.0) -> Vector3:
 var input := action_tilt(kind)
 var forward := -visual.global_basis.z
 forward.y = 0
 forward = forward.normalized()
 var right := visual.global_basis.x
 right.y = 0
 right = right.normalized()
 var horizontal := forward
 var angle := 55.0
 if kind in [Technique.OVERHEAD, JUMP_SET, Technique.UNDERHAND]:
  horizontal = -Basis(Vector3.UP, camera_yaw).z
  if kind in [Technique.OVERHEAD, JUMP_SET] and not lower_serve_active:
   horizontal = horizontal.rotated(Vector3.UP, -tilt.x * deg_to_rad(18))
  angle = receive_elevation(kind)
 elif kind in [Technique.SPIKE, TIP]:
  horizontal = forward.rotated(Vector3.UP, -input.x * deg_to_rad(mechanic(kind).angle))
  # Low contact really is shallow; there is no correction to clear the net.
  var height_factor := clampf(((contact_height if contact_height >= 0 else global_position.y + 2.2) - 2.43) / 0.9, 0, 1)
  angle = lerpf(-6, lerpf(-23, -37, mechanic(kind).weight), height_factor) + input.y * 22
  if kind == TIP:
   angle = 7 + input.y * 15
 elif kind in [Technique.SERVE, Technique.JUMP_SERVE]:
  horizontal = forward.rotated(Vector3.UP, -input.x * deg_to_rad(12))
  angle = (16.0 if kind == Technique.SERVE else 7.0) + input.y * 12
 else:
  angle = clampf(rad_to_deg(camera_pitch), -45, 80) if kind == Technique.THROW else elevation
 return (horizontal * cos(deg_to_rad(angle)) + Vector3.UP * sin(deg_to_rad(angle))).normalized()

func desired_direction() -> Vector3:
 return direction_for(technique)

func contact_active() -> bool:
 if action != Action.STRIKE:
  return false
 var p := mechanic(strike_technique)
 if strike_technique == DIVE:
  return dive_time >= p.contact_from and dive_time <= p.contact_to
 var phase := action_time / strike_duration
 return phase >= p.start and phase <= p.end and (strike_technique != BLOCK or airborne())

func phase_name() -> String:
 if action == Action.PREPARE:
  return "Подготовка" if action_time < 0.06 else "Подведение рук"
 if action == Action.STRIKE:
  return "Контакт" if contact_active() else "Подведение рук" if action_time < strike_duration * 0.18 else "Завершение"
 return "Восстановление" if action == Action.RECOVER else "Готов"

func _physics_process(dt: float) -> void:
 release_time = maxf(0, release_time - dt)
 contact_flash = maxf(0, contact_flash - dt)
 previous_wrists = wrists.duplicate()
 previous_elbows = elbows.duplicate()
 dive_cooldown = maxf(0, dive_cooldown - dt)
 landing_cooldown = maxf(0, landing_cooldown - dt)
 var movement := style_stats.movement()
 if jump_windup > 0:
  jump_windup = maxf(0, jump_windup - dt)
  if jump_windup == 0:
   jump()
   if velocity.y > 0.1:
    action = Action.PREPARE
    technique = approach_kind
    strike_technique = approach_kind
    attack_ready = true
    action_time = 0
 var target_yaw := camera_yaw
 if not shift_lock and move_axis.length() > 0.15:
  target_yaw = atan2(-move_axis.x, -move_axis.y)
 var turn_limit := float(movement.turn) * dt
 if airborne():
  turn_limit *= 0.45
 visual.rotation.y += clampf(angle_difference(visual.rotation.y, target_yaw), -turn_limit, turn_limit)
 if dive_time >= 0:
  dive_time += dt
  var speed := dive_speed * maxf(0, 1.0 - dive_time / float(mechanic(DIVE).travel))
  velocity.x = dive_direction.x * speed
  velocity.z = dive_direction.z * speed
  var dive_yaw := atan2(-dive_direction.x, -dive_direction.z)
  visual.rotation.y += clampf(angle_difference(visual.rotation.y, dive_yaw), -turn_limit, turn_limit)
  var fall := smoothstep(0.0, 0.22, dive_time) * (1.0 - smoothstep(float(mechanic(DIVE).travel), float(mechanic(DIVE).recover_time), dive_time))
  visual.rotation.x = -fall * 1.12
  var shape_node := get_child(0) as CollisionShape3D
  shape_node.shape.height = lerpf(1.75, 0.6, fall)
  shape_node.position.y = shape_node.shape.height * 0.5
  if dive_time >= mechanic(DIVE).recover_time:
   dive_time = -1
   visual.rotation.x = 0
   shape_node.shape.height = 1.75
   shape_node.position.y = 0.875
   action = Action.IDLE
 else:
  var speed := float(movement.speed) * lerpf(0.8, 1.0, energy)
  var horizontal := Vector2(velocity.x, velocity.z)
  if airborne():
   # Keep takeoff momentum; small corrections cannot reverse flight instantly.
   if move_axis.length() > 0.1:
    horizontal = horizontal.move_toward(move_axis * speed, float(movement.air) * dt)
   horizontal *= 1.0 / (1.0 + 0.018 * horizontal.length() * dt)
  else:
   var acceleration := float(movement.acceleration)
   var braking := float(movement.braking)
   if move_axis.length() < 0.1:
    horizontal = horizontal.move_toward(Vector2.ZERO, braking * dt)
   elif horizontal.dot(move_axis) < -0.15:
    horizontal = horizontal.move_toward(Vector2.ZERO, braking * dt)
   else:
    var turn := 1.0 - maxf(0, horizontal.normalized().dot(move_axis.normalized()))
    horizontal = horizontal.move_toward(move_axis * speed, lerpf(acceleration, braking, turn) * dt)
   if jump_windup > 0:
    horizontal *= exp(-1.6 * dt)
  velocity.x = horizontal.x
  velocity.z = horizontal.y
  lean = lean.lerp(Vector2.ZERO if lower_serve_active else body_tilt(), 1.0 - exp(-9.0 * dt))
  visual.rotation.x = lean.y * 0.20
  visual.rotation.z = -lean.x * 0.17
 var fall_speed := velocity.y
 var was_grounded := is_on_floor()
 if not is_on_floor():
  velocity.y -= 9.81 * dt
 move_and_slide()
 if not was_grounded and is_on_floor() and fall_speed < -1:
  landing_load = clampf(-fall_speed / 9.0 * float(movement.landing), 0, 0.7)
  landing_cooldown = float(movement.landing_recovery)
 landing_load = move_toward(landing_load, 0, dt * 2.0)
 visual.position.y = -landing_load * 0.07
 approach_blend = lerpf(approach_blend, 1.0 if approach_armed or jump_windup > 0 else 0.0, 1.0 - exp(-18.0 * dt))
 visual.position.y -= approach_blend * 0.12
 if attack_ready and is_on_floor() and velocity.y <= 0 and jump_windup == 0:
  attack_ready = false
  action = Action.IDLE
 position.x = clampf(position.x, -8, 8)
 position.z = clampf(position.z, -12, 12)
 energy = clampf(energy + dt * (0.13 if move_axis.length() < 0.2 else -float(movement.drain)), 0, 1)
 action_time += dt
 if action == Action.PREPARE and not attack_ready:
  charged_for += dt
  # Predictable, monotonic power control, clamped at the minimum. No cycling.
  power = receive_power(charged_for) if is_receive(technique) else maxf(0.16, 0.82 - maxf(0, charged_for - 0.12) * 0.65)
 if action == Action.STRIKE and action_time >= strike_duration:
  action = Action.RECOVER
  action_time = 0
  if not hit_used:
   last_result = "Промах • R — следующий мяч"
 elif action == Action.RECOVER and action_time > mechanic(strike_technique).recovery and dive_time < 0:
  action = Action.IDLE
 gait += Vector2(velocity.x, velocity.z).length() * dt * 7.6
 _update_pose(dt)

func _update_pose(dt: float) -> void:
 var mode: int = strike_technique if action in [Action.STRIKE, Action.RECOVER] else technique
 if mode in [JUMP_SET, TIP]:
  var old_technique := technique
  var old_strike := strike_technique
  technique = Technique.OVERHEAD if mode == JUMP_SET else Technique.SPIKE
  strike_technique = technique
  super._update_pose(dt)
  _adapt_platform(dt)
  technique = old_technique
  strike_technique = old_strike
  _finish_pose(dt)
  return
 super._update_pose(dt)
 _adapt_platform(dt)
 if mode not in [BLOCK, DIVE] or action == Action.IDLE:
  _finish_pose(dt)
  return
 var blend := 1.0
 if action == Action.PREPARE:
  blend = smoothstep(0, 0.10, action_time)
 elif action == Action.STRIKE:
  blend = smoothstep(0, 0.18, action_time / strike_duration)
 elif action == Action.RECOVER:
  blend = 1.0 - clampf(action_time / 0.2, 0, 1)
 for i in range(2):
  var side := -1.0 if i == 0 else 1.0
  var shoulder := Vector3(side * 0.3, 1.45, 0)
  var e := Vector3(side * 0.31 + tilt.x * 0.08, 1.91, -0.18)
  var w := Vector3(side * float(mechanic(BLOCK).width) + tilt.x * 0.12, 2.35, -0.30 + tilt.y * 0.12)
  if mode == DIVE:
   e = Vector3(side * 0.23, 1.60, -0.32)
   w = Vector3(side * 0.08, 1.87, -0.67)
  e = visual.to_local(elbows[i]).lerp(e, blend)
  w = visual.to_local(wrists[i]).lerp(w, blend)
  VolleyGeometry.segment(arms[i * 2], shoulder, e, 0.075)
  VolleyGeometry.segment(arms[i * 2 + 1], e, w, FOREARM_RADIUS)
  hands[i].position = w
  elbows[i] = visual.to_global(e)
  wrists[i] = visual.to_global(w)
 _finish_pose(dt)

func _finish_pose(dt: float) -> void:
 if is_instance_valid(limb_rig):
  limb_rig.apply_pose(dt)
 if dt > 0:
  hand_velocity = ((wrists[0] + wrists[1]) - (previous_wrists[0] + previous_wrists[1])) * 0.5 / dt

func _adapt_platform(dt: float) -> void:
 if not pose_ready or holding_ball or action not in [Action.PREPARE, Action.STRIKE]:
  return
 var mode: int = strike_technique if action == Action.STRIKE else technique
 if mode not in [Technique.OVERHEAD, Technique.UNDERHAND, JUMP_SET]:
  return
 var approach := smoothstep(0, float(mechanic(mode).windup), action_time) if action == Action.PREPARE else 1.0
 for i in range(2):
  var side := -1.0 if i == 0 else 1.0
  var e := visual.to_local(elbows[i])
  var w := visual.to_local(wrists[i])
  var platform_tilt := action_tilt(mode)
  w += Vector3(platform_tilt.x * 0.05, platform_tilt.x * side * 0.09, platform_tilt.y * 0.06)
  if action == Action.PREPARE:
   e = Vector3(side * 0.36, 1.12, -0.03).lerp(e, approach)
   w = Vector3(side * 0.32, 0.88, -0.08).lerp(w, approach)
  VolleyGeometry.segment(arms[i * 2], Vector3(side * 0.3, 1.45, 0), e, 0.075)
  VolleyGeometry.segment(arms[i * 2 + 1], e, w, FOREARM_RADIUS)
  hands[i].position = w
  elbows[i] = visual.to_global(e)
  wrists[i] = visual.to_global(w)
 if dt > 0:
  hand_velocity = ((wrists[0] + wrists[1]) - (previous_wrists[0] + previous_wrists[1])) * 0.5 / dt

func intersects_ball(center: Vector3) -> bool:
 return overlap_at(center, 1.0)

func effective_contact_radius() -> float:
 return (serve_contact_radius if strike_technique in [Technique.SERVE, Technique.JUMP_SERVE] else contact_ball_radius) * float(mechanic(strike_technique).radius)

func overlap_at(center: Vector3, fraction: float) -> bool:
 for i in range(2):
  if strike_technique in [Technique.SPIKE, Technique.SERVE, Technique.JUMP_SERVE, TIP] and i == 0:
   continue
  var wrist := previous_wrists[i].lerp(wrists[i], fraction)
  if center.distance_to(wrist) <= effective_contact_radius() + HAND_RADIUS and contact_clear(center, wrist):
   return true
  if strike_technique in [Technique.UNDERHAND, DIVE]:
   var elbow := previous_elbows[i].lerp(elbows[i], fraction)
   var closest := Geometry3D.get_closest_point_to_segment(center, elbow, wrist)
   if center.distance_to(closest) <= effective_contact_radius() + FOREARM_RADIUS and contact_clear(center, closest):
    return true
 return false

func contact_clear(center: Vector3, hand: Vector3) -> bool:
 if center.distance_to(hand) < 0.001:
  return true
 var ray := PhysicsRayQueryParameters3D.create(center, hand, 1)
 return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func try_contact(center: Vector3, incoming: Vector3) -> Vector3:
 return try_swept_contact(center, center, incoming)

func try_swept_contact(from: Vector3, center: Vector3, incoming: Vector3) -> Vector3:
 if hit_used or not contact_active():
  return Vector3.ZERO
 var distance := from.distance_to(center)
 distance += maxf(previous_wrists[0].distance_to(wrists[0]), previous_wrists[1].distance_to(wrists[1]))
 var steps := clampi(ceili(distance / 0.025), 1, 160)
 var found := false
 for sample in range(steps + 1):
  var fraction := float(sample) / steps
  var point := from.lerp(center, fraction)
  if overlap_at(point, fraction):
   last_contact_point = point
   found = true
   break
 if not found:
  return Vector3.ZERO
 hit_used = true
 contact_flash = 0.16
 contact_count += 1
 var p := mechanic(strike_technique)
 var phase := action_time / strike_duration
 var timing := clampf(1.0 - absf(phase - 0.47) / 0.47, 0, 1)
 var approach := clampf(1.0 - incoming.length() / float(p.pressure), 0.3, 1)
 quality = clampf((0.45 + timing * 0.55) * lerpf(approach, 1, float(p.control)) * lerpf(0.75, 1, float(p.weight)), 0.15, 1)
 var nearest := 1.0
 for i in range(2):
  nearest = minf(nearest, last_contact_point.distance_to(wrists[i]) / (effective_contact_radius() + HAND_RADIUS))
  if strike_technique in [Technique.UNDERHAND, DIVE]:
   nearest = minf(nearest, VolleyGeometry.distance_to_segment(last_contact_point, elbows[i], wrists[i]) / (effective_contact_radius() + FOREARM_RADIUS))
 quality *= lerpf(1.0, float(p.edge), clampf(nearest, 0, 1))
 var outgoing: Vector3
 if strike_technique == BLOCK:
  var normal := (-visual.global_basis.z + Vector3.UP * (0.18 + tilt.y * float(p.steer)) + visual.global_basis.x * tilt.x * float(p.steer)).normalized()
  normal = normal.rotated(Vector3.UP, deg_to_rad(rng.randf_range(-float(p.accuracy), float(p.accuracy)) * (1.0 - quality)))
  outgoing = incoming.bounce(normal) * float(p.reflect) * lerpf(0.8, 1, quality) + hand_velocity.limit_length(6) * 0.12
  outgoing *= rng.randf_range(1.0 - float(p.stability), 1.0 + float(p.stability))
 else:
  # One sampled angular error and one speed error per contact, never per frame.
  var spread := float(p.accuracy) * (1.3 - quality)
  deviation = rng.randf_range(-spread, spread)
  # Tilt remains live until contact, including after release of the hit button.
  if strike_technique != DIVE:
   strike_direction = direction_for(strike_technique, last_contact_point.y)
  var direction := strike_direction.rotated(Vector3.UP, deg_to_rad(deviation))
  var strength: float = p.strength
  var speed := lerpf(3, 12.5, strike_power)
  match strike_technique:
   Technique.SPIKE: speed = lerpf(16, 31, strike_power)
   TIP: speed = lerpf(4, 7, strike_power)
   Technique.SERVE: speed = lerpf(9, 22, strike_power)
   Technique.JUMP_SERVE: speed = lerpf(13, 29, strike_power)
   DIVE: speed = lerpf(5, 10, strike_power)
  if is_receive(strike_technique):
   speed = receive_speed(strike_technique, receive_elevation(strike_technique), strike_power)
  speed *= strength * (0.7 + quality * 0.3) * rng.randf_range(1.0 - float(p.stability), 1.0 + float(p.stability))
  if strike_technique == Technique.SPIKE and air_attack:
   speed *= 1.07 + minf(takeoff_speed, 5.0) * 0.018
  direction = direction.rotated(visual.global_basis.x, deg_to_rad(rng.randf_range(-spread, spread) * 0.5))
  outgoing = direction * speed + incoming * float(p.carry) + velocity * (0.12 * (1.0 - float(p.control)))
  if is_receive(strike_technique):
   # Controlled receives follow the view. Skill still controls residual drift,
   # impact quality, angular/speed error and absorption of incoming spin.
   var carry := incoming * float(p.carry)
   outgoing = direction * speed + carry * (1.0 - float(p.control)) * 0.12
  elif strike_technique in [Technique.UNDERHAND, DIVE]:
   outgoing.y *= float(p.lift)
 if strike_technique == Technique.JUMP_SERVE and power_serve_solver.is_valid():
  var power_spin := outgoing_spin(Vector3.ZERO, Vector3.ZERO)
  var side := 1.0 if global_position.z >= 0 else -1.0
  var launch: Vector3 = power_serve_solver.call(last_contact_point, power_serve_target(last_contact_point), power_serve_speed() * lerpf(0.84, 1.0, quality), power_spin)
  if strike_direction.z * side < -0.25:
   outgoing = launch.rotated(Vector3.UP, deg_to_rad(deviation)) * rng.randf_range(1.0 - float(p.stability), 1.0 + float(p.stability))
  else:
   outgoing = outgoing.normalized() * power_serve_speed() * lerpf(0.84, 1.0, quality)
  strike_direction = outgoing.normalized()
 elif strike_technique == Technique.SERVE and serve_solver.is_valid():
  var side := 1.0 if global_position.z >= 0 else -1.0
  var horizontal := Vector3(strike_direction.x, 0, strike_direction.z).normalized()
  if horizontal.z * side < -0.25:
   # Choose the landing distance before contact instead of multiplying a
   # fixed fast serve vector that overshoots the whole opponent court.
   var aim := serve_target(last_contact_point)
   var apex := serve_apex()
   var launch: Vector3 = serve_solver.call(last_contact_point, aim, apex)
   outgoing = launch.rotated(Vector3.UP, deg_to_rad(deviation)) * rng.randf_range(1.0 - float(p.stability), 1.0 + float(p.stability))
 last_result = "%s • %d%%" % [NAMES[strike_technique], int(quality * 100)]
 touched.emit(strike_technique, last_contact_point, outgoing)
 return outgoing - incoming

func outgoing_spin(incoming_spin: Vector3, delta_v: Vector3) -> Vector3:
 var p := mechanic(strike_technique)
 if strike_technique == Technique.JUMP_SERVE:
  var amount := power if action == Action.PREPARE else strike_power
  return (-Vector3(strike_direction.x, 0, strike_direction.z).normalized().cross(Vector3.UP) * float(p.topspin) * lerpf(0.65, 1.0, amount)).limit_length(45)
 if strike_technique in [Technique.SPIKE, TIP]:
  return (incoming_spin * float(p.spin) - Vector3(strike_direction.x, 0, strike_direction.z).normalized().cross(Vector3.UP) * float(p.topspin) * strike_power * (1.15 if air_attack else 0.75)).limit_length(50)
 # A cleaner platform absorbs incoming rotation rather than adding random spin.
 return (incoming_spin * float(p.spin) + hand_velocity.cross(delta_v) * (0.025 * (1.0 - float(p.control)))).limit_length(50)
