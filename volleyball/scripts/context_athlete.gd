class_name ContextAthlete
extends VolleyAthlete

# The base resources stay intact; the additive rig refines limbs and poses.
signal touched(kind: int, point: Vector3, outgoing: Vector3)
@export var contact_ball_radius := 0.26
@export var air_acceleration := 0.65
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
var camera_pitch := -0.24
var shift_lock := true
var charged_for := 0.0
var dive_time := -1.0
var dive_cooldown := 0.0
var dive_direction := Vector3.FORWARD
var dive_speed := 0.0
var jump_origin := Vector3.ZERO
var pose_ready := false
var last_contact_point := Vector3.ZERO

func _ready() -> void:
 super._ready()
 pose_ready = true
 limb_rig = VolleyLimbRig.new()
 limb_rig.athlete = self
 add_child(limb_rig)
 last_result = "Выберите упражнение в меню • R — следующий мяч"

func airborne() -> bool:
 return not is_on_floor() or velocity.y > 0.1

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
 power = 0.82
 return true

func prepare() -> void:
 begin_action(technique)

func release() -> void:
 if action != Action.PREPARE or holding_ball:
  return
 strike_technique = technique
 strike_power = power
 if strike_technique == Technique.SPIKE and charged_for < 0.13:
  strike_technique = TIP
 strike_direction = direction_for(strike_technique)
 strike_duration = lerpf(0.34, 0.23, stats.n("reaction"))
 if strike_technique == BLOCK:
  strike_duration = 0.46
 elif strike_technique == JUMP_SET:
  strike_duration = 0.24
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
 jump_windup = 0.10
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
 if is_on_floor() and dive_time < 0:
  jump_origin = global_position
  velocity.y = lerpf(3.5, 5.9, stats.n("jump")) * lerpf(0.88, 1.0, energy)
  energy = maxf(0, energy - 0.075 * (1.3 - stats.n("stamina")))

func dive() -> bool:
 if not is_on_floor() or dive_cooldown > 0 or dive_time >= 0 or holding_ball:
  return false
 dive_direction = Vector3(move_axis.x, 0, move_axis.y).normalized()
 cancel_input()
 if dive_direction.length() < 0.1:
  dive_direction = -visual.global_basis.z
 dive_speed = lerpf(5.0, 8.5, stats.n("agility")) + Vector2(velocity.x, velocity.z).length() * 0.3
 dive_time = 0
 dive_cooldown = lerpf(2.0, 1.25, stats.n("agility"))
 technique = DIVE
 strike_technique = DIVE
 strike_direction = (dive_direction * 0.55 + Vector3.UP * 0.83).normalized()
 strike_power = 0.5
 strike_duration = 0.55
 action = Action.STRIKE
 action_time = 0
 hit_used = false
 strike_count += 1
 energy = maxf(0, energy - 0.12)
 last_result = "Подкат"
 return true

func direction_for(kind: int) -> Vector3:
 var forward := -visual.global_basis.z
 forward.y = 0
 forward = forward.normalized()
 var right := visual.global_basis.x
 right.y = 0
 right = right.normalized()
 var horizontal := forward
 var angle := 55.0
 if kind in [Technique.OVERHEAD, JUMP_SET, Technique.UNDERHAND]:
  if tilt.length() > 0.18:
   horizontal = (forward * -tilt.y + right * tilt.x).normalized()
  angle = lerpf(74, 43, power) if kind != Technique.UNDERHAND else lerpf(67, 41, power)
 elif kind in [Technique.SPIKE, TIP]:
  horizontal = forward.rotated(Vector3.UP, -tilt.x * deg_to_rad(50))
  # Low contact really is shallow; there is no correction to clear the net.
  var height_factor := clampf((global_position.y + 2.2 - 2.43) / 0.9, 0, 1)
  angle = lerpf(-6, -30, height_factor) + tilt.y * 28
  if kind == TIP:
   angle = 7 + tilt.y * 15
 elif kind in [Technique.SERVE, Technique.JUMP_SERVE]:
  horizontal = forward.rotated(Vector3.UP, -tilt.x * deg_to_rad(25))
  angle = (16.0 if kind == Technique.SERVE else 7.0) + tilt.y * 12
 else:
  angle = clampf(rad_to_deg(camera_pitch), -45, 80) if kind == Technique.THROW else elevation
 return (horizontal * cos(deg_to_rad(angle)) + Vector3.UP * sin(deg_to_rad(angle))).normalized()

func desired_direction() -> Vector3:
 return direction_for(technique)

func contact_active() -> bool:
 if action != Action.STRIKE:
  return false
 if strike_technique == DIVE:
  return dive_time >= 0.10 and dive_time <= 0.56
 var phase := action_time / strike_duration
 if strike_technique == BLOCK:
  return phase >= 0.20 and phase <= 0.92 and airborne()
 return phase >= 0.12 and phase <= 0.90

func phase_name() -> String:
 if action == Action.PREPARE:
  return "Подготовка" if action_time < 0.06 else "Подведение рук"
 if action == Action.STRIKE:
  return "Контакт" if contact_active() else "Подведение рук" if action_time < strike_duration * 0.18 else "Завершение"
 return "Восстановление" if action == Action.RECOVER else "Готов"

func _physics_process(dt: float) -> void:
 previous_wrists = wrists.duplicate()
 previous_elbows = elbows.duplicate()
 dive_cooldown = maxf(0, dive_cooldown - dt)
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
 var turn_limit := lerpf(2.5, 5.5, stats.n("coordination")) * dt
 if airborne():
  turn_limit *= 0.45
 visual.rotation.y += clampf(angle_difference(visual.rotation.y, target_yaw), -turn_limit, turn_limit)
 if dive_time >= 0:
  dive_time += dt
  var speed := dive_speed * maxf(0, 1.0 - dive_time / 0.68)
  velocity.x = dive_direction.x * speed
  velocity.z = dive_direction.z * speed
  var dive_yaw := atan2(-dive_direction.x, -dive_direction.z)
  visual.rotation.y += clampf(angle_difference(visual.rotation.y, dive_yaw), -turn_limit, turn_limit)
  var fall := smoothstep(0.0, 0.22, dive_time) * (1.0 - smoothstep(0.72, 1.12, dive_time))
  visual.rotation.x = -fall * 1.12
  var shape_node := get_child(0) as CollisionShape3D
  shape_node.shape.height = lerpf(1.75, 0.6, fall)
  shape_node.position.y = shape_node.shape.height * 0.5
  if dive_time >= 1.12:
   dive_time = -1
   visual.rotation.x = 0
   shape_node.shape.height = 1.75
   shape_node.position.y = 0.875
   action = Action.IDLE
 else:
  var speed := lerpf(2.8, 6.2, stats.n("speed")) * lerpf(0.8, 1.0, energy)
  var horizontal := Vector2(velocity.x, velocity.z)
  if airborne():
   # Keep takeoff momentum; small corrections cannot reverse flight instantly.
   if move_axis.length() > 0.1:
    horizontal = horizontal.move_toward(move_axis * speed, air_acceleration * dt)
   horizontal *= 1.0 / (1.0 + 0.018 * horizontal.length() * dt)
  else:
   var acceleration := lerpf(8.0, 13.0, stats.n("agility"))
   var braking := lerpf(16.0, 22.0, stats.n("agility"))
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
  lean = lean.lerp(tilt if not holding_ball else Vector2.ZERO, 1.0 - exp(-9.0 * dt))
  visual.rotation.x = lean.y * 0.20
  visual.rotation.z = -lean.x * 0.17
 var fall_speed := velocity.y
 var was_grounded := is_on_floor()
 if not is_on_floor():
  velocity.y -= 9.81 * dt
 move_and_slide()
 if not was_grounded and is_on_floor() and fall_speed < -1:
  landing_load = clampf(-fall_speed / 9.0, 0, 0.7)
 landing_load = move_toward(landing_load, 0, dt * 2.0)
 visual.position.y = -landing_load * 0.07
 approach_blend = lerpf(approach_blend, 1.0 if approach_armed or jump_windup > 0 else 0.0, 1.0 - exp(-18.0 * dt))
 visual.position.y -= approach_blend * 0.12
 if attack_ready and is_on_floor() and velocity.y <= 0 and jump_windup == 0:
  attack_ready = false
  action = Action.IDLE
 position.x = clampf(position.x, -8, 8)
 position.z = clampf(position.z, -12, 12)
 energy = clampf(energy + dt * (0.13 if move_axis.length() < 0.2 else -0.018 * (1.2 - stats.n("stamina"))), 0, 1)
 action_time += dt
 if action == Action.PREPARE and not attack_ready:
  charged_for += dt
  # Predictable, monotonic power control, clamped at the minimum. No cycling.
  power = maxf(0.16, 0.82 - maxf(0, charged_for - 0.12) * 0.65)
 if action == Action.STRIKE and action_time >= strike_duration:
  action = Action.RECOVER
  action_time = 0
  if not hit_used:
   last_result = "Промах • R — следующий мяч"
 elif action == Action.RECOVER and action_time > 0.20 and dive_time < 0:
  action = Action.IDLE
 gait += Vector2(velocity.x, velocity.z).length() * dt * 2.5
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
  var w := Vector3(side * 0.20 + tilt.x * 0.12, 2.35, -0.30 + tilt.y * 0.12)
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
  limb_rig.apply_pose()
 if dt > 0:
  hand_velocity = ((wrists[0] + wrists[1]) - (previous_wrists[0] + previous_wrists[1])) * 0.5 / dt

func _adapt_platform(dt: float) -> void:
 if not pose_ready or holding_ball or action not in [Action.PREPARE, Action.STRIKE]:
  return
 var mode: int = strike_technique if action == Action.STRIKE else technique
 if mode not in [Technique.OVERHEAD, Technique.UNDERHAND, JUMP_SET]:
  return
 var approach := smoothstep(0, 0.10, action_time) if action == Action.PREPARE else 1.0
 for i in range(2):
  var side := -1.0 if i == 0 else 1.0
  var e := visual.to_local(elbows[i])
  var w := visual.to_local(wrists[i])
  w += Vector3(tilt.x * 0.05, tilt.x * side * 0.09, tilt.y * 0.06)
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

func overlap_at(center: Vector3, fraction: float) -> bool:
 for i in range(2):
  if strike_technique in [Technique.SPIKE, Technique.SERVE, Technique.JUMP_SERVE, TIP] and i == 0:
   continue
  var wrist := previous_wrists[i].lerp(wrists[i], fraction)
  if center.distance_to(wrist) <= contact_ball_radius + HAND_RADIUS and contact_clear(center, wrist):
   return true
  if strike_technique in [Technique.UNDERHAND, DIVE]:
   var elbow := previous_elbows[i].lerp(elbows[i], fraction)
   var closest := Geometry3D.get_closest_point_to_segment(center, elbow, wrist)
   if center.distance_to(closest) <= contact_ball_radius + FOREARM_RADIUS and contact_clear(center, closest):
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
 contact_count += 1
 var phase := action_time / strike_duration
 var timing := clampf(1.0 - absf(phase - 0.47) / 0.47, 0, 1)
 var approach := clampf(1.0 - incoming.length() / 65.0, 0.3, 1)
 quality = clampf((0.45 + timing * 0.55) * lerpf(approach, 1, stats.n("control")) * lerpf(0.75, 1, stats.n("coordination")), 0.15, 1)
 var nearest := 1.0
 for i in range(2):
  nearest = minf(nearest, last_contact_point.distance_to(wrists[i]) / (contact_ball_radius + HAND_RADIUS))
  if strike_technique in [Technique.UNDERHAND, DIVE]:
   nearest = minf(nearest, VolleyGeometry.distance_to_segment(last_contact_point, elbows[i], wrists[i]) / (contact_ball_radius + FOREARM_RADIUS))
 quality *= lerpf(1.0, 0.65, clampf(nearest, 0, 1))
 var outgoing: Vector3
 if strike_technique == BLOCK:
  var normal := (-visual.global_basis.z + Vector3.UP * (0.18 + tilt.y * 0.55) + visual.global_basis.x * tilt.x * 0.3).normalized()
  outgoing = incoming.bounce(normal) * lerpf(0.65, 0.94, stats.n("control")) * lerpf(0.8, 1, quality) + hand_velocity.limit_length(6) * 0.12
 else:
  # One sampled angular error and one speed error per contact, never per frame.
  var spread := lerpf(7.0, 0.3, stats.n("accuracy")) * (1.3 - quality)
  deviation = rng.randf_range(-spread, spread)
  # Tilt remains live until contact, including after release of the hit button.
  if strike_technique != DIVE:
   strike_direction = direction_for(strike_technique)
  var direction := strike_direction.rotated(Vector3.UP, deg_to_rad(deviation))
  var strength := lerpf(0.75, 1.18, stats.n("strength"))
  var speed := lerpf(3, 12.5, strike_power)
  match strike_technique:
   Technique.SPIKE: speed = lerpf(16, 31, strike_power)
   TIP: speed = lerpf(4, 7, strike_power)
   Technique.SERVE: speed = lerpf(9, 22, strike_power)
   Technique.JUMP_SERVE: speed = lerpf(13, 29, strike_power)
   DIVE: speed = lerpf(5, 10, strike_power)
  speed *= strength * (0.7 + quality * 0.3) * rng.randf_range(0.98, 1.02)
  outgoing = direction * speed + incoming * (0.025 + (1 - stats.n("control")) * 0.13) + velocity * 0.12
 last_result = "%s • %d%%" % [NAMES[strike_technique], int(quality * 100)]
 touched.emit(strike_technique, last_contact_point, outgoing)
 return outgoing - incoming
