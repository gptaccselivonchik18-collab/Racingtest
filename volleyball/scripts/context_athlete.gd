class_name ContextAthlete
extends VolleyAthlete

# The base resources stay intact; the additive rig refines limbs and poses.
signal touched(kind: int, point: Vector3, outgoing: Vector3)
signal block_missed
signal jump_started(player: ContextAthlete)
var character_id := "kageyama"
var instance_uid := ""
var height_cm := 181.9
var physical_scale := 1.0
var special_set := ""
var special_yaw := 0.0
var locked_yaw := 0.0
var special_recipient: WeakRef
var ability_solver: Callable
var resolving_contact := false
var air_swing_used := false
var jump_in_progress := false
var serve_swing_used := false
var service_attempt_active := false
var volley_role := "S"
var rotation_slot := 0
var starting_rotation_slot := 0
var formation_revision := 0
var lineup_index := -1
var benched := false
var strict_positions := false
var designated_libero := false
var rolling_active := false
var tactical_state := VolleyRoles.State.COVER
var last_ground_feet: Array[Vector3] = []

func finish_service_attempt() -> void:
 service_attempt_active = false
 serve_swing_used = false

func set_character(id: String) -> bool:
 if not VolleyCharacterDatabase.valid(id):
  return false
 character_id = id
 volley_role = VolleyRoles.default_role(id)
 height_cm = float(VolleyCharacterDatabase.get_character(id).height_cm)
 (style_stats as VolleyCharacterStats).install(id)
 if is_instance_valid(visual):
  cancel_input()
  reset_dive()
  action = Action.IDLE
  VolleyCharacterPhysicalProfile.apply(self)
  _update_pose(0)
 return true

func natural_reach() -> float:
 return 2.2 * physical_scale

@export var contact_ball_radius := 0.50
@export var serve_contact_radius := 0.76
var serve_solver: Callable
var power_serve_solver: Callable
var lifted_attack_solver: Callable
var approach_jump := false
var contact_incoming_spin := Vector3.ZERO
var style_stats := VolleyStyleStats.new()
var landing_cooldown := 0.0
var cinema_time := -1.0
var cinema_pose: Callable
var execution_level := 2
var bot_execution := false
var fatigue_enabled := true
var contact_error: Dictionary = {}

func stamina() -> float:
 return energy if fatigue_enabled else 1.0

func direction_pace(axis: Vector2) -> float:
 if axis.length_squared()<0.0001:return 1.0
 var local := Basis(Vector3.UP,visual.global_rotation.y).inverse()*Vector3(axis.x,0,axis.y).normalized()
 var longitudinal := 1.0 if local.z<=0 else 0.60
 return 1.0/sqrt(pow(local.x/0.76,2)+pow(local.z/longitudinal,2))

func effective_speed() -> float:
 return float(style_stats.movement().speed)*lerpf(0.8,1.0,stamina())

func speed_toward(axis: Vector2) -> float:
 return effective_speed()*direction_pace(axis)

func effective_jump_height() -> float:
 return float(style_stats.movement().jump_height) * pow(lerpf(0.88, 1.0, stamina()), 2)

func _init() -> void:
 style_stats = VolleyCharacterStats.new()
 (style_stats as VolleyCharacterStats).install(character_id)
 stats = style_stats

func mechanic(kind: int) -> Dictionary:
 var result: Dictionary = style_stats.profile(Technique.SERVE if lower_serve_active and kind == Technique.UNDERHAND and VolleyRules.in_service_zone(service_origin()) else kind)
 if rolling_active and kind == DIVE:
  result = result.duplicate()
  result.recover_time = float(result.travel)+(float(result.recover_time)-float(result.travel))*0.65
  result.accuracy *= 0.80
 return result

func defense_dive_profile() -> Dictionary:
 var result := mechanic(DIVE).duplicate()
 if character_id == "yu_nishinoya":
  result.speed *= 1.30
 return result

@export var air_acceleration := 0.65
var replica := false
var network_position := Vector3.ZERO
var network_age := -1.0
var network_pose_time := 0.0
var network_motion := VolleyReplicaMotion.new()
var network_rotation := Vector3.ZERO

func accept_network_position(at: Vector3, stamp := -1.0) -> bool:
 if stamp >= 0:
  if not network_motion.push(at, velocity, stamp):
   return false
  position = network_motion.position
 else:
  network_motion.reset()
  if network_age < 0 or position.distance_to(at) > 2.0:
   position = at
 network_position = at
 network_age = 0
 return true

var lower_serve_active := false
var float_serve_active := false
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
var court_team := -1
var duel_result: Dictionary = {}
var block_held := false
var block_contact_cooldown := 0.0

func service_origin() -> Vector3:
 return jump_origin if airborne() else global_position

func delivery_kind(jumping := false) -> int:
 if VolleyRules.in_service_zone(service_origin()):
  return Technique.JUMP_SERVE if jumping else Technique.SERVE
 return Technique.SPIKE

func end_block() -> void:
 if not block_held:
  return
 block_held = false
 action = Action.RECOVER
 action_time = 0
 last_result = ""

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
 return not lower_serve_active and not float_serve_active and kind in [Technique.OVERHEAD, JUMP_SET, Technique.SERVE, Technique.JUMP_SERVE, Technique.SPIKE, TIP, BLOCK]

func action_tilt(kind: int) -> Vector2:
 return body_tilt() if tilt_affects(kind) else Vector2.ZERO

func is_receive(kind: int) -> bool:
 return not lower_serve_active and not float_serve_active and kind in [Technique.OVERHEAD, JUMP_SET, Technique.UNDERHAND]

static func receive_power(held_seconds: float) -> float:
 # Short deliberate taps retain maximum strength. After 1.15 seconds the
 # minimum remains stable, so a long hold never cycles into a hard pass.
 return lerpf(1.0, 0.18, smoothstep(0.10, 1.15, held_seconds))

func receive_elevation(kind: int) -> float:
 # A platform always lifts the ball; the view chooses only its horizontal
 # bearing. Hold duration controls speed, so both apex and distance change.
 if kind == Technique.UNDERHAND and not lower_serve_active:
  return 62.0
 var angle := rad_to_deg(camera_pitch)
 if kind in [Technique.OVERHEAD, JUMP_SET]:
  # A small, smooth assist (at most eight degrees) preserves flat passes and
  # the existing range while making a high set easier to see and aim.
  angle += 8.0 * sin(PI * clampf(angle / 84.0, 0, 1))
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
 var depth := maxf(1.4, lerpf(2.0, float(mechanic(Technique.SERVE).depth), power if action == Action.PREPARE else strike_power) + input.y * 2.8)
 var forward := -visual.global_basis.z
 var z := -side * depth
 var x := point.x + forward.x / maxf(0.25, absf(forward.z)) * absf(z - point.z) + visual.global_basis.x.x * input.x * 3.7
 return Vector3(x, VolleyBall.RADIUS, z)

func power_serve_speed() -> float:
 # Serve owns delivery/control; Spike contributes only strike efficiency.
 var amount := power if action == Action.PREPARE else strike_power
 return lerpf(17.0, 26.0, amount) * float(mechanic(Technique.JUMP_SERVE).power_speed) * lerpf(0.92, 1.08, style_stats.n("spike")) * (1.0 + minf(takeoff_speed, 5.0) * 0.012)

func power_serve_target(point: Vector3) -> Vector3:
 var aim := serve_target(point)
 var side := 1.0 if global_position.z >= 0 else -1.0
 # A hard baseline serve needs the longer diagonal/deep court to clear the net.
 var amount := power if action == Action.PREPARE else strike_power
 aim.z = -side * clampf(6.6 + amount * 1.5 + body_tilt().y * 1.8, 4.4, 8.8) * style_stats.factor("serve")
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
 instance_uid = "actor-%d" % get_instance_id()
 VolleyCharacterPhysicalProfile.apply(self)
 last_result = "Выберите упражнение в меню • R — следующий мяч"

func _process(dt: float) -> void:
 if cinema_time >= 0 and not replica:
  return
 if not replica or not pose_ready:
  return
 if network_motion.active:
  position = network_motion.advance(dt)
  for axis in range(3):
   visual.rotation[axis] = lerp_angle(visual.rotation[axis], network_rotation[axis], 1.0 - exp(-18.0 * dt))
 elif network_age >= 0:
  network_age += dt
  # Integrate between packets, then correct error. Chasing a stationary
  # 30 Hz target alone repeatedly slows and accelerates a 120 Hz camera.
  if network_age <= 0.12:
   position += velocity * dt
  var target := network_position + velocity * minf(network_age, 0.12)
  position = position.lerp(target, 1.0 - exp(-10.0 * dt))
 # Server snapshots remain authoritative; evaluate limb curves every rendered
 # frame so a 30 Hz network update does not freeze arms between packets.
 action_time += dt
 release_time = maxf(0, release_time - dt)
 contact_flash = maxf(0, contact_flash - dt)
 if dive_time >= 0:
  dive_time += dt
 update_rolling_visual()
 advance_gait(dt)
 _update_pose(dt)

func airborne() -> bool:
 if replica:
  return position.y > 0.06 or velocity.y > 0.1
 return not is_on_floor() or velocity.y > 0.1 or position.y > 0.12

func can_act() -> bool:
 return not benched and dive_time < 0 and action == Action.IDLE and not holding_ball and not approach_armed and jump_windup <= 0

func begin_action(kind: int) -> bool:
 if (kind == BLOCK and not VolleyRoles.can_block(self)) or (kind in [Technique.SERVE,Technique.JUMP_SERVE] and not VolleyRoles.can_serve(self)):
  return false
 if not can_act():
  return false
 if kind in [Technique.SPIKE, TIP, Technique.SERVE, Technique.JUMP_SERVE] and ((airborne() and air_swing_used) or (service_attempt_active and serve_swing_used)):
  return false
 technique = kind
 strike_technique = kind
 block_held = false
 action = Action.PREPARE
 action_time = 0
 charged_for = 0
 power = receive_power(0) if is_receive(kind) else 0.82
 if kind == BLOCK:
  block_held = true
  action = Action.STRIKE
  strike_duration = mechanic(BLOCK).duration
  power = 0
  strike_power = 0
  hit_used = false
  block_contact_cooldown = 0
  strike_count += 1
  last_result = ""
 return true

func prepare() -> void:
 begin_action(technique)

func release() -> void:
 if block_held:
  end_block()
  return
 if action != Action.PREPARE or holding_ball:
  return
 strike_technique = planned_technique()
 if is_receive(strike_technique):
  power = receive_power(charged_for)
 if strike_technique in [Technique.SPIKE, TIP, Technique.SERVE, Technique.JUMP_SERVE]:
  if (airborne() and air_swing_used) or (service_attempt_active and serve_swing_used):
   cancel_input()
   return
  if airborne():
   air_swing_used = true
  if service_attempt_active:
   serve_swing_used = true
 strike_power = power
 air_attack = airborne() and (strike_technique == Technique.JUMP_SERVE or (strike_technique == Technique.SPIKE and approach_jump))
 strike_direction = direction_for(strike_technique)
 strike_duration = mechanic(strike_technique).duration
 action = Action.STRIKE
 action_time = 0
 hit_used = false
 strike_count += 1
 last_result = NAMES[strike_technique]

func planned_technique() -> int:
 if technique in [Technique.SERVE, Technique.JUMP_SERVE]:
  var delivery := delivery_kind(technique == Technique.JUMP_SERVE)
  if delivery != Technique.SPIKE:
   return delivery
 if technique == Technique.SPIKE or technique in [Technique.SERVE, Technique.JUMP_SERVE]:
  return TIP if airborne() and not approach_jump else Technique.SPIKE
 return technique

func cancel_input() -> void:
 var was_blocking := block_held
 end_block()
 super.cancel_input()
 if was_blocking:
  action = Action.IDLE
 tilt = Vector2.ZERO
 special_set = ""
 special_recipient = null
 charged_for = 0
 approach_armed = false
 jump_windup = 0
 attack_ready = false
 approach_jump = false

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

func jump(from_approach := false) -> void:
 if benched:
  return
 if is_on_floor() and velocity.y <= 0.1 and dive_time < 0 and landing_cooldown <= 0:
  air_swing_used = false
  jump_in_progress = true
  jump_origin = global_position
  approach_jump = from_approach
  takeoff_speed = Vector2(velocity.x, velocity.z).length()
  velocity.y = sqrt(2.0 * 9.81 * style_stats.movement().jump_height) * lerpf(0.88, 1.0, stamina())
  if from_approach and absf(global_position.z) < 5.0:
   # Plant before taking off: keep a useful approach without carrying the
   # torso into the net for the whole ballistic flight.
   var side := signf(global_position.z)
   var duration := 2.0 * velocity.y / 9.81
   var toward_net := -velocity.z * side
   var available := maxf(0, absf(global_position.z) - 0.65)
   if toward_net > available / duration:
    velocity.z = -side * available / duration
  if fatigue_enabled:energy = maxf(0,energy-style_stats.movement().jump_cost)
  jump_started.emit(self)

func dive(rolling := false) -> bool:
 if benched or not is_on_floor() or dive_cooldown > 0 or dive_time >= 0 or holding_ball or (rolling and character_id != "yu_nishinoya"):
  return false
 rolling_active = rolling
 dive_direction = Vector3(move_axis.x, 0, move_axis.y).normalized()
 cancel_input()
 if dive_direction.length() < 0.1:
  dive_direction = -visual.global_basis.z
 dive_speed = mechanic(DIVE).speed + Vector2(velocity.x, velocity.z).length() * 0.3
 if rolling_active:
  dive_speed *= 1.30
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
 if fatigue_enabled:energy = maxf(0,energy-0.12)
 last_result = "Rolling Thunder" if rolling_active else "Подкат"
 return true

func defensive_dive() -> bool:
 return dive(character_id == "yu_nishinoya")

func reset_dive() -> void:
 dive_time = -1
 rolling_active = false
 dive_cooldown = 0
 if not is_instance_valid(visual):
  return
 visual.rotation.x = 0
 visual.position = Vector3.ZERO
 var shape := get_child(0) as CollisionShape3D
 if shape and shape.shape is CapsuleShape3D:
  shape.shape.height = 1.75*physical_scale
  shape.position.y = shape.shape.height*0.5

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
  horizontal = -Basis(Vector3.UP, special_yaw if not special_set.is_empty() else camera_yaw).z
  if kind in [Technique.OVERHEAD, JUMP_SET] and not lower_serve_active:
   horizontal = horizontal.rotated(Vector3.UP, -tilt.x * deg_to_rad(18))
  angle = receive_elevation(kind)
 elif kind in [Technique.SPIKE, TIP]:
  horizontal = forward.rotated(Vector3.UP, -input.x * deg_to_rad(mechanic(kind).angle))
  var height_factor := clampf(((contact_height if contact_height >= 0 else global_position.y + natural_reach()) - 2.43) / 0.9, 0, 1)
  angle = lerpf(-6, lerpf(-23, -37, mechanic(kind).weight), height_factor) + input.y * 22
  if kind == TIP:
   angle = 22 + input.y * 17
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
 if strike_technique == BLOCK:
  return block_held and airborne() and action_time >= float(p.windup)
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
 if benched:
  velocity = Vector3.ZERO
  move_axis = Vector2.ZERO
  _update_pose(dt)
  return
 if cinema_time >= 0:
  return
 block_contact_cooldown = maxf(0, block_contact_cooldown - dt)
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
   jump(true)
   if velocity.y > 0.1:
    action = Action.PREPARE
    technique = approach_kind
    strike_technique = approach_kind
    attack_ready = true
    action_time = 0
 var target_yaw := locked_yaw if not special_set.is_empty() else camera_yaw
 if special_set.is_empty() and not shift_lock and move_axis.length() > 0.15:
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
  shape_node.shape.height = lerpf(1.75, 0.6, fall) * physical_scale
  shape_node.position.y = shape_node.shape.height * 0.5
  if dive_time >= mechanic(DIVE).recover_time:
   dive_time = -1
   rolling_active = false
   visual.rotation.x = 0
   shape_node.shape.height = 1.75 * physical_scale
   shape_node.position.y = 0.875 * physical_scale
   action = Action.IDLE
 else:
  var speed := speed_toward(move_axis)
  var horizontal := Vector2(velocity.x, velocity.z)
  if airborne():
   # Keep takeoff momentum; small corrections cannot reverse flight instantly.
   if move_axis.length() > 0.1:
    horizontal = horizontal.move_toward(move_axis * speed, float(movement.air) * dt)
   horizontal *= 1.0 / (1.0 + 0.018 * horizontal.length() * dt)
  else:
   var acceleration := float(movement.acceleration)
   var braking := float(movement.braking)
   if character_id == "hinata" and jump_windup <= 0:
    horizontal = move_axis * speed
   elif move_axis.length() < 0.1:
    horizontal = horizontal.move_toward(Vector2.ZERO, braking * dt)
   elif horizontal.dot(move_axis) < -0.15:
    horizontal = horizontal.move_toward(Vector2.ZERO, braking * dt)
   else:
    var turn := 1.0 - maxf(0, horizontal.normalized().dot(move_axis.normalized()))
    horizontal = horizontal.move_toward(move_axis * speed, lerpf(acceleration, braking, turn) * dt)
   if jump_windup > 0:
    horizontal *= exp(-6.0 * dt)
  velocity.x = horizontal.x
  velocity.z = horizontal.y
  lean = lean.lerp(Vector2.ZERO if lower_serve_active or float_serve_active else body_tilt(), 1.0 - exp(-9.0 * dt))
  visual.rotation.x = lean.y * 0.20
  visual.rotation.z = -lean.x * 0.17
 var fall_speed := velocity.y
 var was_grounded := is_on_floor()
 if not is_on_floor():
  velocity.y -= 9.81 * dt
 move_and_slide()
 if not was_grounded and is_on_floor() and fall_speed < -1:
  jump_in_progress = false
  air_swing_used = false
  approach_jump = false
  landing_load = clampf(-fall_speed / 9.0 * float(movement.landing), 0, 0.7)
  landing_cooldown = float(movement.landing_recovery)
 landing_load = move_toward(landing_load, 0, dt * 2.0)
 if is_on_floor() and velocity.y <= 0:
  jump_in_progress = false
 visual.position.y = -landing_load * 0.07
 approach_blend = lerpf(approach_blend, 1.0 if approach_armed or jump_windup > 0 else 0.0, 1.0 - exp(-18.0 * dt))
 visual.position.y -= approach_blend * 0.12
 update_rolling_visual()
 if attack_ready and is_on_floor() and velocity.y <= 0 and jump_windup == 0:
  attack_ready = false
  action = Action.IDLE
 position.x = clampf(position.x, -8, 8)
 position.z = clampf(position.z, -12, 12)
 energy = clampf(energy+dt*(0.13 if move_axis.length()<0.2 else -float(movement.drain)),0,1) if fatigue_enabled else 1.0
 action_time += dt
 if block_held and not airborne():
  end_block()
 if action == Action.PREPARE and not attack_ready:
  charged_for += dt
  # Predictable, monotonic power control, clamped at the minimum. No cycling.
  power = receive_power(charged_for) if is_receive(technique) else maxf(0.16, 0.82 - maxf(0, charged_for - 0.12) * 0.65)
 if action == Action.STRIKE and not block_held and action_time >= strike_duration:
  action = Action.RECOVER
  action_time = 0
  if not hit_used:
   last_result = "Промах • R — следующий мяч"
   if strike_technique == BLOCK:
    block_missed.emit()
 elif action == Action.RECOVER and action_time > mechanic(strike_technique).recovery and dive_time < 0:
  action = Action.IDLE
  special_set = ""
  special_recipient = null
 advance_gait(dt)
 _update_pose(dt)
 if is_on_floor():
  last_ground_feet.clear()
  if is_instance_valid(limb_rig) and limb_rig.motion.feet.size() == 2:
   for foot in limb_rig.motion.feet:
    last_ground_feet.append(visual.to_global(foot))
  else:
   last_ground_feet = [position+Vector3(-0.16,0,0),position+Vector3(0.16,0,0)]

func update_rolling_visual() -> void:
 if rolling_active and dive_time>=float(mechanic(DIVE).contact_to):
  var p := mechanic(DIVE)
  var roll := smoothstep(float(p.contact_to),float(p.recover_time)-0.04,dive_time)
  var angle := -TAU*roll
  var fall := smoothstep(0,0.22,dive_time)*(1.0-smoothstep(float(p.travel),float(p.recover_time),dive_time))
  visual.rotation.x = -fall*1.12+angle
  var pivot := Vector3.UP*physical_scale
  visual.position = Basis(Vector3.UP,visual.rotation.y)*(pivot-Basis(Vector3.RIGHT,angle)*pivot)
  # Rotate the tucked body over the shoulder, keeping the head above the
  # floor; the root/collider still follows the same physical dive path.
  visual.position.y=maxf(visual.position.y,(-cos(visual.rotation.x)*2.04+0.10)*physical_scale)
 else:
  visual.position = Vector3(0,-landing_load*0.07-approach_blend*0.12,0)

func _update_pose(dt: float) -> void:
 var mode: int = strike_technique if action in [Action.STRIKE, Action.RECOVER] else planned_technique() if action == Action.PREPARE else technique
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
  blend = smoothstep(0, float(mechanic(BLOCK).windup), action_time) if mode == BLOCK else smoothstep(0, 0.18, action_time / strike_duration)
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

func advance_gait(dt: float) -> void:
 # One phase revolution is a complete left/right stride, not a single step.
 # Keep take-off momentum without continuing to cycle limbs in mid-air.
 var speed := Vector2(velocity.x, velocity.z).length()
 if speed > 0.12 and not airborne() and dive_time < 0:
  gait = fposmod(gait + dt * TAU * VolleyMotion.stride_frequency(speed), TAU)

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
 # Bump/dive use the whole moving body: feet, legs, chest and head. The
 # action window and world occlusion still apply; this is not an auto-hit.
 if strike_technique in [Technique.UNDERHAND, DIVE] and character_id != "yu_nishinoya":
  var local := visual.to_local(center)
  var spine := Vector3(0, clampf(local.y, 0.20, 1.65), 0)
  var anchor := visual.to_global(spine)
  if center.distance_to(anchor) <= 0.32 + effective_contact_radius() and contact_clear(center, anchor):
   return true
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

func quality_at(kind: int, point: Vector3, incoming: Vector3, phase := 0.47) -> float:
 var p := mechanic(kind)
 var timing := clampf(1.0 - absf(phase - 0.47) / 0.47, 0, 1)
 if kind == BLOCK:
  timing = smoothstep(float(p.windup), float(p.windup) + 0.10, action_time)
 var approach := clampf(1.0 - incoming.length() / float(p.pressure), 0.3, 1)
 var result := clampf((0.45 + timing * 0.55) * lerpf(approach, 1, float(p.control)) * lerpf(0.75, 1, float(p.weight)), 0.15, 1)
 var nearest := 1.0
 for i in range(2):
  nearest = minf(nearest, point.distance_to(wrists[i]) / ((serve_contact_radius if kind in [Technique.SERVE, Technique.JUMP_SERVE] else contact_ball_radius) * float(p.radius) + HAND_RADIUS))
  if kind in [Technique.UNDERHAND, DIVE]:
   nearest = minf(nearest, VolleyGeometry.distance_to_segment(point, elbows[i], wrists[i]) / ((serve_contact_radius if kind in [Technique.SERVE, Technique.JUMP_SERVE] else contact_ball_radius) * float(p.radius) + FOREARM_RADIUS))
 result *= lerpf(1.0, float(p.edge), clampf(nearest, 0, 1))
 if kind in [Technique.UNDERHAND,DIVE]:
  var moving_loss := clampf(Vector2(velocity.x,velocity.z).length()/maxf(1,effective_speed()),0,1)*0.10
  result *= 1.0-moving_loss*(0.80 if character_id == "yu_nishinoya" else 1.0)
 if kind in [Technique.OVERHEAD, JUMP_SET]:
  var motion_loss := clampf(Vector2(velocity.x, velocity.z).length() / maxf(1, effective_speed()), 0, 1) * 0.08
  var body_loss := body_tilt().length() * 0.06
  result *= 1.0 - (motion_loss + body_loss) * (0.60 if character_id == "kageyama" else 1.0)
 return result

func try_contact(center: Vector3, incoming: Vector3, attack: Dictionary = {}) -> Vector3:
 return try_swept_contact(center, center, incoming, attack)

func try_swept_contact(from: Vector3, center: Vector3, incoming: Vector3, attack: Dictionary = {}) -> Vector3:
 if benched:
  return Vector3.ZERO
 if block_held and hit_used:
  # The same overlapping ball cannot reroll a duel on successive frames.
  # A held block can meet a genuinely returning ball after it leaves the hands.
  if block_contact_cooldown <= 0 and not overlap_at(center, 1.0) and not overlap_at(from, 0.0):
   hit_used = false
  return Vector3.ZERO
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
 duel_result = {}
 hit_used = true
 contact_flash = 0.16
 contact_count += 1
 var p := mechanic(strike_technique)
 quality = quality_at(strike_technique, last_contact_point, incoming, action_time / strike_duration)
 var outgoing: Vector3
 if strike_technique == BLOCK:
  block_contact_cooldown = 0.16
  var input := body_tilt()
  var forward := -Basis(Vector3.UP, visual.global_rotation.y).z
  var right := Basis(Vector3.UP, visual.global_rotation.y).x
  var normal := VolleyBlockDuel.hand_normal(forward, right, input, style_stats.n("block"))
  var edge_error := float(p.accuracy) * (1.0 - quality) * float(VolleyBotDifficulty.execution(execution_level,bot_execution).scatter)
  normal = normal.rotated(Vector3.UP, deg_to_rad(rng.randf_range(-edge_error, edge_error)))
  outgoing = VolleyBlockDuel.reflection(incoming, normal, quality)
  if not attack.is_empty():
   duel_result = VolleyBlockDuel.resolve(attack, style_stats.n("block"), quality, incoming, normal, rng, input.y, style_stats.factor("block"))
   if duel_result.pierced:
    outgoing = duel_result.velocity
 else:
  contact_error = VolleyBotDifficulty.contact_error(rng, execution_level, quality, float(p.accuracy), float(p.stability),bot_execution)
  deviation = Vector2(contact_error.angle).x
  resolving_contact = true
  var solution := VolleyShotModel.solve(self, strike_technique, last_contact_point, incoming, contact_incoming_spin, quality, strike_power, contact_error.angle, contact_error.pace)
  resolving_contact = false
  outgoing = solution.velocity
  strike_direction = solution.direction
 last_result = "" if strike_technique == BLOCK else "%s • %d%%" % [NAMES[strike_technique], int(quality * 100)]
 touched.emit(strike_technique, last_contact_point, outgoing)
 return outgoing - incoming

func outgoing_spin(incoming_spin: Vector3, delta_v: Vector3) -> Vector3:
 var p := mechanic(strike_technique)
 if strike_technique == BLOCK and bool(duel_result.get("pierced", false)):
  return incoming_spin * lerpf(0.75, 0.50, float(p.control))
 return VolleyShotModel.spin_for(self, strike_technique, incoming_spin, delta_v, strike_direction, strike_power)
