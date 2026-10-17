class_name VolleyStrikePreview
extends VolleyTossPreview

var title: Label3D
var game: Node3D

func _ready() -> void:
 super._ready()
 title = Label3D.new()
 title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 title.font_size = 32
 title.pixel_size = 0.007
 add_child(title)

func _physics_process(dt: float) -> void:
 if not is_instance_valid(viewer):
  hide()
  elapsed = 1
  return
 var a: ContextAthlete = viewer
 var kind: int = a.technique if a.action == VolleyAthlete.Action.PREPARE else a.strike_technique
 visible = not a.float_serve_active and not ball.held and a.action in [VolleyAthlete.Action.PREPARE, VolleyAthlete.Action.STRIKE] and (a.action == VolleyAthlete.Action.PREPARE or not a.hit_used) and kind in [0, 1, 2, 3, 4, 8, 9]
 if not visible:
  elapsed = 1
  return
 elapsed += dt
 if elapsed < 0.10:
  return
 elapsed = 0
 var at := a.wrists[1]
 var strength: float = a.mechanic(kind).strength
 var power: float = a.power if a.action == VolleyAthlete.Action.PREPARE else a.strike_power
 var direction := a.direction_for(kind, at.y)
 var speed := direction * lerpf(16, 31, power) * strength * 0.97 + ball.last_velocity * float(a.mechanic(kind).carry)
 if kind == 2 and (a.airborne() if a.action == VolleyAthlete.Action.PREPARE else a.air_attack):
  speed *= 1.07 + minf(a.takeoff_speed, 5.0) * 0.018
 var spin := -Vector3(direction.x, 0, direction.z).normalized().cross(Vector3.UP) * float(a.mechanic(kind).topspin) * power if kind in [2, 9] else VolleyBall.FEED_SPIN
 if kind == 4:
  spin = a.outgoing_spin(Vector3.ZERO, Vector3.ZERO)
  speed = direction * a.power_serve_speed() * 0.97
  if direction.z * (1.0 if a.position.z >= 0 else -1.0) < -0.25:
   speed = ball.solve_power_serve(at, a.power_serve_target(at), a.power_serve_speed() * 0.97, spin)
 elif kind == 3:
  speed = ball.solve_launch(at, a.serve_target(at), a.serve_apex())
 if a.is_receive(kind):
  speed = direction * a.receive_speed(kind, a.receive_elevation(kind), power) * strength * 0.97
  spin = Vector3.ZERO
 var points: Array[Vector3] = [at]
 var landed := false
 for tick in range(240):
  speed += (Vector3.DOWN * 9.81 + ball.aero_force(speed, spin) / ball.mass) / 60.0
  spin *= 1.0 - ball.angular_damp / 60.0
  var next := at + speed / 60.0
  var ray := PhysicsRayQueryParameters3D.create(at, next, 1)
  var hit := get_world_3d().direct_space_state.intersect_ray(ray)
  at = next
  if not hit.is_empty() or at.y <= VolleyBall.RADIUS:
   landed = at.y < 0.20 or (not hit.is_empty() and hit.collider.get_meta("surface", "") == "floor")
   break
  if tick % 4 == 0:
   points.append(at)
 landing.visible = landed
 title.visible = landed
 if landed:
  landing.global_position = Vector3(at.x, 0.055, at.z)
  title.global_position = landing.global_position + Vector3.UP * 0.25
  title.text = "ПОДАЧА" if kind in [3, 4] else "ПАС" if kind in [0, 8] else "ПРИЁМ" if kind == 1 else "АТАКА"
  if absf(at.x) > 4.5 or absf(at.z) > 9:
   title.text += " • АУТ"
  title.modulate = Color("f4cf77") if absf(at.x) <= 4.5 and absf(at.z) <= 9 else Color("f29981")
 for i in range(dots.size()):
  dots[i].visible = i < points.size()
  if i < points.size():
   dots[i].global_position = points[i]
