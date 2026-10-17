class_name VolleyShotModel
extends RefCounted

# The contact and its private preview share this entire launch calculation.
# Accuracy errors are sampled once at contact; preview uses their centre.
static func spin_for(a: ContextAthlete, kind: int, incoming: Vector3, delta: Vector3, direction: Vector3, amount: float) -> Vector3:
 var p := a.mechanic(kind)
 var horizontal := Vector3(direction.x, 0, direction.z).normalized()
 if kind == VolleyAthlete.Technique.JUMP_SERVE:
  return (-horizontal.cross(Vector3.UP) * float(p.topspin) * lerpf(0.65, 1.0, amount)).limit_length(45)
 if kind in [VolleyAthlete.Technique.SPIKE, ContextAthlete.TIP]:
  var powerful_jump := a.air_attack if a.action != VolleyAthlete.Action.PREPARE else a.airborne() and a.approach_jump
  var factor := 0.25 if kind == ContextAthlete.TIP else 1.15 if powerful_jump else 0.75
  return (incoming * float(p.spin) - horizontal.cross(Vector3.UP) * float(p.topspin) * amount * factor).limit_length(50)
 return (incoming * float(p.spin) + a.hand_velocity.cross(delta) * (0.025 * (1.0 - float(p.control)))).limit_length(50)

static func standing_target(a: ContextAthlete, at: Vector3, amount: float, quality: float) -> Vector3:
 var direction := a.direction_for(VolleyAthlete.Technique.SPIKE, at.y)
 var horizontal := Vector3(direction.x, 0, direction.z).normalized()
 var force := clampf((amount - 0.16) / 0.66, 0, 1)
 var side := 1.0 if a.global_position.z >= 0 else -1.0
 var depth := lerpf(0.7, 8.0, force) * lerpf(0.83, 1.12, a.style_stats.n("spike")) * lerpf(0.84, 1.0, quality)
 depth += a.body_tilt().y * 2.5
 var distance := lerpf(2, 13, force)
 if horizontal.z * side < -0.20:
  distance = absf(at.z + side * maxf(0.35, depth)) / maxf(0.20, absf(horizontal.z))
 return Vector3(at.x + horizontal.x * distance, VolleyBall.RADIUS, at.z + horizontal.z * distance)

static func solve(a: ContextAthlete, kind: int, at: Vector3, incoming: Vector3, incoming_spin: Vector3, quality: float, amount: float, angular_error := Vector2.ZERO, pace_scale := 1.0) -> Dictionary:
 var p := a.mechanic(kind)
 var direction := a.strike_direction if kind == ContextAthlete.DIVE else a.direction_for(kind, at.y)
 var nominal_direction := direction
 direction = direction.rotated(Vector3.UP, deg_to_rad(angular_error.x))
 direction = direction.rotated(a.visual.global_basis.x, deg_to_rad(angular_error.y))
 var speed := lerpf(3, 12.5, amount)
 match kind:
  VolleyAthlete.Technique.SPIKE: speed = lerpf(16, 31, amount)
  ContextAthlete.TIP: speed = lerpf(4.8, 9.0, clampf((amount - 0.16) / 0.66, 0, 1))
  VolleyAthlete.Technique.SERVE: speed = lerpf(9, 22, amount)
  VolleyAthlete.Technique.JUMP_SERVE: speed = lerpf(13, 29, amount)
  ContextAthlete.DIVE: speed = lerpf(5, 10, amount)
 if a.is_receive(kind):
  speed = a.receive_speed(kind, a.receive_elevation(kind), amount)
 speed *= float(p.strength) * (0.7 + quality * 0.3) * pace_scale
 var powerful_jump := a.air_attack if a.action != VolleyAthlete.Action.PREPARE else a.airborne() and a.approach_jump
 if kind == VolleyAthlete.Technique.SPIKE and powerful_jump:
  speed *= 1.07 + minf(a.takeoff_speed, 5.0) * 0.018
 var outgoing := direction * speed + incoming * float(p.carry) + a.velocity * (0.12 * (1.0 - float(p.control)))
 if a.is_receive(kind):
  outgoing = direction * speed + incoming * float(p.carry) * (1.0 - float(p.control)) * 0.12
 elif kind in [VolleyAthlete.Technique.UNDERHAND, ContextAthlete.DIVE]:
  outgoing.y *= float(p.lift)
 var spin := spin_for(a, kind, incoming_spin, outgoing - incoming, nominal_direction, amount)
 if kind == VolleyAthlete.Technique.SPIKE and not powerful_jump and a.lifted_attack_solver.is_valid():
  var target := standing_target(a, at, amount, quality)
  var apex := 0.85 + maxf(0, a.body_tilt().y) * 1.2
  outgoing = a.lifted_attack_solver.call(at, target, apex, spin)
  outgoing = outgoing.rotated(Vector3.UP, deg_to_rad(angular_error.x)).rotated(a.visual.global_basis.x, deg_to_rad(angular_error.y)) * pace_scale
 elif kind == VolleyAthlete.Technique.JUMP_SERVE and a.power_serve_solver.is_valid():
  var side := 1.0 if a.global_position.z >= 0 else -1.0
  if nominal_direction.z * side < -0.25:
   outgoing = a.power_serve_solver.call(at, a.power_serve_target(at), a.power_serve_speed() * lerpf(0.84, 1.0, quality), spin)
   outgoing = outgoing.rotated(Vector3.UP, deg_to_rad(angular_error.x)) * pace_scale
  else:
   outgoing = outgoing.normalized() * a.power_serve_speed() * lerpf(0.84, 1.0, quality)
 elif kind == VolleyAthlete.Technique.SERVE and a.serve_solver.is_valid():
  var side := 1.0 if a.global_position.z >= 0 else -1.0
  if nominal_direction.z * side < -0.25:
   outgoing = a.serve_solver.call(at, a.serve_target(at), a.serve_apex())
   outgoing = outgoing.rotated(Vector3.UP, deg_to_rad(angular_error.x)) * pace_scale
 return {"velocity": outgoing, "spin": spin, "direction": nominal_direction}
