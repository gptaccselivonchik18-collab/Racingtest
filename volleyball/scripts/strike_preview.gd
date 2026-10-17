class_name VolleyStrikePreview
extends VolleyTossPreview

var title: Label3D
var game: Node3D
var predicted_launch: Dictionary = {}

func _ready() -> void:
 super._ready()
 title = Label3D.new()
 title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 title.font_size = 32
 title.pixel_size = 0.007
 add_child(title)

func prediction(at: Vector3, incoming: Vector3, spin: Vector3) -> Dictionary:
 var a := viewer
 var kind := a.planned_technique() if a.action == VolleyAthlete.Action.PREPARE else a.strike_technique
 var amount := a.power if a.action == VolleyAthlete.Action.PREPARE else a.strike_power
 var phase := 0.47 if a.action == VolleyAthlete.Action.PREPARE else a.action_time / maxf(0.01, a.strike_duration)
 var quality := a.quality_at(kind, at, incoming, phase)
 var result := VolleyShotModel.solve(a, kind, at, incoming, spin, quality, amount)
 result.kind = kind
 result.point = at
 return result

func sample_path(start: Vector3, speed: Vector3, spin: Vector3) -> Dictionary:
 var at := start
 var points: Array[Vector3] = [at]
 var landed := false
 var query := PhysicsShapeQueryParameters3D.new()
 var shape := SphereShape3D.new()
 shape.radius = VolleyBall.RADIUS
 query.shape = shape
 query.collision_mask = 1
 query.margin = 0.001
 for tick in range(600):
  speed += (Vector3.DOWN * 9.81 + ball.aero_force(speed, spin) / ball.mass) / 120.0
  spin *= 1.0 - ball.angular_damp / 120.0
  var next := at + speed / 120.0
  query.transform = Transform3D(Basis.IDENTITY, at)
  query.motion = next - at
  var fractions := get_world_3d().direct_space_state.cast_motion(query)
  if fractions[0] < 1.0 or next.y <= VolleyBall.RADIUS:
   at = at.lerp(next, fractions[0])
   landed = at.y <= VolleyBall.RADIUS + 0.06
   points.append(at)
   break
  at = next
  if tick % 8 == 0:
   points.append(at)
 return {"points": points, "landed": landed, "landing": at}

func _physics_process(dt: float) -> void:
 if not is_instance_valid(viewer):
  hide()
  elapsed = 1
  return
 var a := viewer
 var kind := a.planned_technique() if a.action == VolleyAthlete.Action.PREPARE else a.strike_technique
 var just_hit := a.contact_flash > 0 and a.action == VolleyAthlete.Action.STRIKE
 visible = not a.float_serve_active and not a.lower_serve_active and not ball.held and a.action in [VolleyAthlete.Action.PREPARE, VolleyAthlete.Action.STRIKE] and (not a.hit_used or just_hit) and kind in [0, 1, 2, 3, 4, 8, 9]
 if not visible:
  elapsed = 1
  return
 elapsed += dt
 if elapsed < 0.05:
  return
 elapsed = 0
 var at := a.wrists[1]
 if ball.global_position.distance_to(at) < a.effective_contact_radius() + 0.8:
  at = ball.global_position
 var incoming := ball.last_velocity if ball.replica else ball.linear_velocity
 predicted_launch = {"point": ball.global_position, "velocity": incoming, "spin": ball.angular_velocity, "kind": kind} if just_hit else prediction(at, incoming, ball.angular_velocity)
 var flight := sample_path(predicted_launch.point, predicted_launch.velocity, predicted_launch.spin)
 var points: Array = flight.points
 landing.visible = flight.landed
 title.visible = flight.landed
 if flight.landed:
  var finish: Vector3 = flight.landing
  landing.global_position = Vector3(finish.x, 0.055, finish.z)
  title.global_position = landing.global_position + Vector3.UP * 0.25
  title.text = "ПОДАЧА" if kind in [3, 4] else "ПАС" if kind in [0, 8] else "ПРИЁМ" if kind == 1 else "ФИНТ" if kind == 9 else "АТАКА"
  var outside := absf(finish.x) > 4.5 + VolleyBall.RADIUS or absf(finish.z) > 9 + VolleyBall.RADIUS
  if outside:
   title.text += " • АУТ"
  title.modulate = Color("f29981") if outside else Color("f4cf77")
 for i in range(dots.size()):
  dots[i].visible = i < points.size()
  if i < points.size():
   dots[i].global_position = points[i]
