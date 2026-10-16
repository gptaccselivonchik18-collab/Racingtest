class_name VolleyMotion
extends RefCounted

# Keyed movement phases drive the visible hands used by contact physics.
# This layer also preserves actual stance feet in world space.
var athlete: ContextAthlete
var clock := 0.0
var body_offset := Vector3.ZERO
var torso_basis := Basis.IDENTITY
var wrists: Array[Vector3] = []
var poles: Array[Vector3] = []
var feet: Array[Vector3] = []
var previous_state := ""
var transition := 0.0
var origins: Array[Vector3] = []
var planted: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var stance := [false, false]
var initialized := false
var last_velocity := Vector3.ZERO
var torso_origin := Basis.IDENTITY
var offset_origin := Vector3.ZERO
var acceleration := Vector3.ZERO
var previous_feet: Array[Vector3] = []
var previous_poles: Array[Vector3] = []
var air_blend := 0.0
var run_blend := 0.0

static func stride_frequency(speed: float) -> float:
 return clampf(1.15 + speed * 0.23, 1.15, 2.80)

func shoulder(index: int) -> Vector3:
 return Vector3(0, 1.23, 0) + body_offset + torso_basis * Vector3(-0.3 if index == 0 else 0.3, 0.22, 0)

static func arc(a: Vector3, b: Vector3, c: Vector3, phase: float) -> Vector3:
 if phase <= 0.47:
  return a.lerp(b, smoothstep(0.0, 0.47, phase))
 return b.lerp(c, smoothstep(0.47, 1.0, phase))

func update(dt: float) -> void:
 var a := athlete
 clock += dt
 if dt > 0:
  acceleration = acceleration.lerp((a.velocity - last_velocity) / dt, 1.0 - exp(-12.0 * dt))
 last_velocity = a.velocity
 var kind: int = a.strike_technique if a.action in [VolleyAthlete.Action.STRIKE, VolleyAthlete.Action.RECOVER] else a.technique
 var speed := Vector2(a.velocity.x, a.velocity.z).length()
 var air := a.airborne()
 var blend := 1.0 - exp(-14.0 * dt) if dt > 0 else 1.0
 air_blend = lerpf(air_blend, 1.0 if air else 0.0, blend)
 run_blend = lerpf(run_blend, clampf(speed / 4.0, 0, 1) * (1.0 - air_blend), blend)
 var aim := a.action_tilt(kind)
 var phase := clampf(a.action_time / maxf(a.strike_duration, 0.01), 0, 1)
 var jumping_spike := kind in [2, 4] and (air if a.action == VolleyAthlete.Action.PREPARE else a.air_attack)
 var state := "%d:%d:%s:%s:%s:%s" % [a.action, kind, a.holding_ball, a.approach_armed, a.attack_ready, jumping_spike]
 if state != previous_state:
  origins = wrists.duplicate()
  torso_origin = torso_basis
  offset_origin = body_offset
  transition = 0
  previous_state = state
 transition += dt
 var windup := float(a.mechanic(kind).windup)
 var coordination := float(a.mechanic(kind).get("coordination", 1.0)) if kind == 4 else 1.0
 var twist := 0.0
 var bend := 0.0
 var crouch := 0.055 + a.landing_load * 0.19 + a.approach_blend * 0.12
 var readiness := clampf(speed / maxf(0.1, float(a.style_stats.movement().speed)), 0, 1)
 bend = -0.035 - readiness * 0.035
 if kind in [2, 3, 4, 9] and a.action != VolleyAthlete.Action.IDLE and not a.holding_ball:
  twist = -0.22 if a.action == VolleyAthlete.Action.PREPARE else lerpf(-0.22, 0.18, smoothstep(0, 0.70, phase))
  bend = -0.055 if a.action == VolleyAthlete.Action.PREPARE else sin(phase * PI) * 0.07
  if a.action == VolleyAthlete.Action.RECOVER:
   var recovery := 1.0 - smoothstep(0, float(a.mechanic(kind).recovery), a.action_time)
   twist = 0.18 * recovery
   bend *= recovery
  if kind in [2, 4]:
   var load := 1.0 if a.action == VolleyAthlete.Action.PREPARE else 1.0 - smoothstep(0, float(a.mechanic(kind).recovery), a.action_time) if a.action == VolleyAthlete.Action.RECOVER else 1.0
   twist = (-0.38 if a.action == VolleyAthlete.Action.PREPARE else lerpf(-0.38, 0.30, smoothstep(0, 0.72, phase))) * load if jumping_spike else (-0.10 if a.action == VolleyAthlete.Action.PREPARE else lerpf(-0.10, 0.12, phase)) * load
   bend = (-0.16 if a.action == VolleyAthlete.Action.PREPARE else lerpf(-0.16, 0.20, smoothstep(0, 0.65, phase))) * load if jumping_spike else bend * 0.45
 elif kind == 1 and a.action != VolleyAthlete.Action.IDLE:
  crouch += 0.055
  bend = 0.055
 var local_accel := a.visual.global_basis.inverse() * acceleration.limit_length(20)
 bend += clampf(-local_accel.z * 0.002, -0.025, 0.025)
 body_offset = Vector3(0, -crouch + sin(clock * 2.0) * 0.002, 0)
 torso_basis = Basis.from_euler(Vector3(bend, twist * coordination + aim.x * 0.04, 0))
 if dt > 0:
  torso_basis = torso_origin.slerp(torso_basis, smoothstep(0, 0.10, transition))
  body_offset = offset_origin.lerp(body_offset, smoothstep(0, 0.10, transition))
 wrists.clear()
 previous_poles = poles.duplicate()
 previous_feet = feet.duplicate()
 poles.clear()
 feet.clear()
 for i in range(2):
  var side := -1.0 if i == 0 else 1.0
  var run_swing := cos(a.gait + i * PI) * 0.18 * run_blend
  var idle := Vector3(side * lerpf(0.28, 0.31, readiness), 1.08 - run_blend * 0.04, -0.28 + run_blend * 0.13 + run_swing)
  # Elbows descend beside the ribs, behind the wrists. A lateral pole used
  # to fold both arms outward into an inverted-looking chicken-wing pose.
  var pole := Vector3(side * 0.30, 1.02, 0.24)
  var jump_hands := Vector3(side * 0.30, 1.17, -0.24)
  idle = idle.lerp(jump_hands, air_blend)
  var draw := idle
  var contact := idle
  var follow := idle
  match kind:
   0, 8:
    draw = Vector3(side * 0.14, 1.96, -0.32)
    contact = Vector3(side * 0.12, 2.20, -0.36)
    follow = Vector3(side * 0.18, 2.15, -0.43)
    pole = Vector3(side * 0.43, 1.64, -0.26)
   1:
    draw = Vector3(side * 0.075, 0.93, -0.63)
    contact = Vector3(side * 0.075, 1.23, -0.69)
    follow = Vector3(side * 0.08, 1.42, -0.60)
    pole = Vector3(side * 0.23, 1.17, -0.30)
   2, 3, 4, 9:
    if i == 1:
     draw = Vector3(0.30, 2.04, 0.16)
     contact = Vector3(0.22, 2.23, -0.30)
     follow = Vector3(0.04, 1.48, -0.72)
     pole = Vector3(0.42, 1.72, 0.14).lerp(Vector3(0.40, 1.64, -0.28), smoothstep(0, 0.7, phase))
     if kind == 9:
      follow = Vector3(0.18, 2.10, -0.43)
    else:
     draw = Vector3(-0.23, 1.72, -0.38)
     contact = Vector3(-0.34, 1.43, -0.12)
     follow = Vector3(-0.37, 1.12, 0.02)
     pole = Vector3(-0.40, 1.46, -0.19)
    if kind in [2, 4]:
     if jumping_spike:
      if i == 1:
       draw = Vector3(0.43, 2.05, 0.27)
       contact = Vector3(0.22, 2.25, -0.30)
       follow = Vector3(-0.10, 1.36, -0.67)
       if kind == 4:
        draw = Vector3(0.42, 2.02, 0.29)
        contact = Vector3(0.24, 2.27, -0.42)
        follow = Vector3(-0.22, 1.20, -0.58)
       pole = Vector3(0.47, 1.79, 0.24).lerp(Vector3(0.39, 1.63, -0.35), smoothstep(0.15, 0.8, phase))
      else:
       draw = Vector3(-0.20, 1.91, -0.40)
       contact = Vector3(-0.36, 1.30, -0.12)
       follow = Vector3(-0.39, 1.04, 0.15)
     elif i == 1:
      draw = Vector3(0.38, 1.77, 0.13)
      contact = Vector3(0.22, 1.98, -0.41)
      follow = Vector3(0.08, 1.32, -0.61)
   6:
    var width := float(a.mechanic(6).width)
    draw = Vector3(side * width, 2.22, -0.19)
    contact = Vector3(side * width, 2.28, -0.32)
    follow = Vector3(side * width, 2.20, -0.37)
    pole = Vector3(side * 0.35, 1.91, -0.14)
   7:
    draw = Vector3(side * 0.12, 1.73, -0.57)
    contact = Vector3(side * 0.08, 1.87, -0.67)
    follow = Vector3(side * 0.12, 1.78, -0.55)
    pole = Vector3(side * 0.23, 1.60, -0.32)
   5:
    draw = Vector3(0.18 + side * 0.1, 1.30, -0.50)
    contact = Vector3(side * 0.13, 1.57, -0.66)
    follow = Vector3(side * 0.17, 1.71, -0.60)
  if a.float_serve_active and i == 1:
   draw = Vector3(0.34, 1.99, 0.08)
   contact = Vector3(0.22, 2.18, -0.39)
   follow = Vector3(0.22, 1.98, -0.54)
  var wrist := idle
  if a.action == VolleyAthlete.Action.PREPARE:
   wrist = draw
  elif a.action == VolleyAthlete.Action.STRIKE:
   wrist = arc(draw, contact, follow, phase)
  elif a.action == VolleyAthlete.Action.RECOVER:
   wrist = origins[i].lerp(idle, smoothstep(0, float(a.mechanic(kind).recovery), a.action_time)) if origins.size() == 2 else idle
  if a.action != VolleyAthlete.Action.IDLE:
   wrist += Vector3(aim.x * 0.07, aim.x * side * 0.035, aim.y * 0.055)
  if a.action == VolleyAthlete.Action.IDLE:
   pole = Vector3(side * 0.30, 1.02, 0.24)
  elif a.action == VolleyAthlete.Action.RECOVER:
   pole = pole.lerp(Vector3(side * 0.30, 1.02, 0.24), smoothstep(0, float(a.mechanic(kind).recovery), a.action_time))
  if a.holding_ball:
   wrist = Vector3(0.18 + side * 0.105, 1.30, -0.50)
   pole = Vector3(side * 0.35, 1.20, -0.15)
  elif a.release_time > 0:
   var release_phase := 1.0 - a.release_time / 0.25
   var released_wrist := Vector3(0.18 + side * 0.1, 1.30, -0.50).lerp(Vector3(side * 0.16, 1.70, -0.58), smoothstep(0, 0.65, release_phase))
   wrist = released_wrist.lerp(wrist, smoothstep(0.65, 1, release_phase))
  elif a.approach_armed or a.jump_windup > 0:
   wrist = idle.lerp(Vector3(side * 0.35, 1.02, 0.26), a.approach_blend)
  # Zero-time evaluation is used by pose/contact sampling and editors.
  if dt == 0 and a.action == VolleyAthlete.Action.PREPARE and not a.holding_ball:
   wrist = draw
  var chest := Vector3(0, 1.23, 0)
  if a.action != VolleyAthlete.Action.RECOVER and not a.holding_ball:
   wrist = chest + body_offset + torso_basis * (wrist - chest)
  if origins.size() == 2 and (a.holding_ball or a.action in [VolleyAthlete.Action.IDLE, VolleyAthlete.Action.PREPARE]):
   wrist = origins[i].lerp(wrist, smoothstep(0, 0.16 if a.holding_ball else windup, transition))
  wrists.append(wrist)
  var posed_pole := chest + body_offset + torso_basis * (pole - chest)
  if previous_poles.size() == 2 and dt > 0:
   posed_pole = previous_poles[i].lerp(posed_pole, 1.0 - exp(-20.0 * dt))
  poles.append(posed_pole)
  var local_motion := a.visual.global_basis.inverse() * Vector3(a.velocity.x, 0, a.velocity.z)
  var travel := local_motion.normalized() if speed > 0.1 else Vector3.FORWARD
  var walk_phase := fposmod((a.gait + i * PI) / TAU, 1.0)
  var frequency := stride_frequency(speed)
  # At running speed the foot stays down for a short support phase. Keep
  # stride reach within leg length rather than vibrating short steps.
  var support := minf(0.32, 0.72 * frequency / maxf(speed, 0.1))
  var reach := minf(0.36, speed / frequency * support * 0.5)
  var swing_phase := clampf((walk_phase - support) / (1.0 - support), 0, 1)
  var along := lerpf(reach, -reach, walk_phase / support) if walk_phase < support else lerpf(-reach, reach, smoothstep(0, 1, swing_phase))
  var lift := sin(swing_phase * PI) * minf(0.15, speed * 0.035)
  var foot := Vector3(side * lerpf(0.20, 0.15, readiness), 0.11 + lift, side * 0.045 * (1.0 - readiness)) + travel * along
  var on_stance := walk_phase < support and not air and a.dive_time < 0 and speed > 0.25
  if on_stance:
   if not stance[i] or not initialized:
    if previous_feet.size() == 2 and dt > 0:
     foot = previous_feet[i].lerp(foot, 1.0 - exp(-22.0 * dt))
    planted[i] = a.visual.to_global(foot)
    planted[i].y = a.global_position.y + 0.10
   foot = a.visual.to_local(planted[i])
  elif not air and a.dive_time < 0:
   var world_foot := a.visual.to_global(foot)
   world_foot.y = a.global_position.y + 0.10 + lift
   foot = a.visual.to_local(world_foot)
  if air:
   foot = Vector3(side * 0.16, 0.22 + maxf(0, a.velocity.y) * 0.012, 0.14 + side * 0.045)
   foot = foot.lerp(Vector3(side * 0.17, 0.14, -0.04), smoothstep(0, 4, -a.velocity.y))
   if jumping_spike:
    var air_windup := 1.0 if a.action == VolleyAthlete.Action.PREPARE else 1.0 - smoothstep(0.3, 1.0, phase)
    foot = foot.lerp(Vector3(side * 0.17, 0.35 if i == 1 else 0.22, 0.30 if i == 1 else -0.08), air_windup)
  if a.dive_time >= 0:
   foot = Vector3(side * 0.19, 0.13, 0.15 + side * 0.05)
  if previous_feet.size() == 2 and dt > 0 and not on_stance:
   foot = previous_feet[i].lerp(foot, 1.0 - exp(-22.0 * dt))
  stance[i] = on_stance
  feet.append(foot)
 initialized = true
