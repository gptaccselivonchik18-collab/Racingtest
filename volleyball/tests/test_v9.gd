extends SceneTree
var game: Node3D
var a: ContextAthlete
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, note: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", note)
 else:
  failures += 1
  push_error("FAIL: " + note)

func sample(kind: int, held: float, elevation: float, yaw := 0.0, tilt := Vector2.ZERO, incoming := Vector3.ZERO) -> Vector3:
 a.action = VolleyAthlete.Action.IDLE
 a.position = Vector3(0, 1.2 if kind == 8 else 0.02, 5)
 a.velocity = Vector3.ZERO
 a.dive_time = -1
 a.visual.rotation = Vector3.ZERO
 a.holding_ball = false
 a.release_time = 0
 a.lower_serve_active = false
 a.camera_yaw = yaw
 a.camera_pitch = deg_to_rad(elevation)
 a.tilt = tilt
 a.begin_action(kind)
 a.charged_for = held
 a.release()
 a.action_time = a.strike_duration * 0.47
 a._update_pose(0)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()
 a.reset_seed(652)
 return a.try_contact(a.wrists[1], incoming) + incoming

func flight(held: float, elevation: float) -> Vector3:
 var velocity := sample(0, held, elevation)
 # Test the actual RigidBody with gravity, aerodynamic drag and collisions.
 game.ball.feed(a.wrists[1], velocity)
 while game.ball.pending_feed:
  await physics_frame
 var apex: float = game.ball.position.y
 for i in range(600):
  await physics_frame
  apex = maxf(apex, game.ball.position.y)
  if game.ball.position.y < 0.16:
   return Vector3(game.ball.position.x, apex, game.ball.position.z)
 return Vector3(99, 99, 99)

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 a = game.athlete
 a.set_physics_process(false)
 a.style_stats.reset_all()
 a.position = Vector3(0, 0.02, 5)
 game.rig.yaw = 0
 game.rig.pitch = 0
 a._update_pose(0.1)
 game.rig._process(0)
 check(game.camera.global_position.distance_to(a.eye_transform().origin) < 0.001 and game.camera.global_position.distance_to(a.head_position()) < 0.24, "First-person camera is at the eyes with no orbit distance")
 check(absf(game.camera.position.y - 1.835) < 0.04, "Standing eye height is anatomically aligned with the head")
 var all_visible := true
 for node in a.visual.get_children():
  if node is GeometryInstance3D:
   all_visible = all_visible and node.visible and (node.layers & game.camera.cull_mask) != 0
 for node in a.limb_rig.get_children():
  if node is GeometryInstance3D:
   all_visible = all_visible and node.visible and (node.layers & game.camera.cull_mask) != 0
 check(all_visible and a.arms.size() == 4 and a.legs.size() == 2, "Head, hair, torso, hands and legs remain visible on camera layers")
 game.rig.look(Vector2(120, -260))
 game.rig._process(0)
 var head := a.visual.get_child(2) as MeshInstance3D
 check((-head.global_basis.z).dot(-game.camera.global_basis.z) > 0.999, "Head rotates with camera pitch and yaw")
 check(absf(game.camera.global_rotation.x) > 0.6, "Looking up changes camera pitch without a delayed chase")
 game.rig.look(Vector2(0, 3000))
 game.rig._process(0)
 check(game.camera.global_position.distance_to(a.visual.get_child(3).global_position) > 0.18, "Looking down keeps the lens outside the hair without hiding the head")
 var shoe: Vector3 = a.limb_rig.shoes[0].global_position
 check(not game.camera.is_position_behind(shoe) and root.get_visible_rect().has_point(game.camera.unproject_position(shoe)), "Looking down places the existing feet inside the viewport")
 game.rig.pitch = 0.2
 game.rig.yaw = 0
 game.rig._process(0)
 var view_direction: Vector3 = -game.camera.global_basis.z
 a.tilt = Vector2(0.8, -0.5)
 a._physics_process(0.15)
 game.rig._process(0)
 check(Vector2(a.visual.rotation.x, a.visual.rotation.z).length() > 0.08 and (-game.camera.global_basis.z).dot(view_direction) > 0.999, "Tilt leans the body while the eye view remains upright")
 a.tilt = Vector2.ZERO
 a.lean = Vector2.ZERO
 a.visual.rotation = Vector3.ZERO
 var previous := 2.0
 var monotonic := true
 for i in range(201):
  var value := ContextAthlete.receive_power(float(i) / 100)
  monotonic = monotonic and value <= previous + 0.00001
  previous = value
 check(monotonic and is_equal_approx(ContextAthlete.receive_power(0), 1.0) and is_equal_approx(ContextAthlete.receive_power(30), 0.18), "Holding weakens smoothly from maximum to a stable minimum without cycling")
 for kind in [0, 8, 1]:
  var tap := sample(kind, 0.03, 35)
  var medium := sample(kind, 0.6, 35)
  var soft := sample(kind, 1.3, 35)
  check(tap.length() > medium.length() * 1.3 and medium.length() > soft.length() * 1.4, "Actual contact strength follows hold duration for action %d" % kind)
  var flat := sample(kind, 0.03, 5)
  var loft := sample(kind, 0.03, 75)
  check(flat.length() > loft.length() * 1.6 and loft.y > flat.y * 3, "Higher camera angle trades speed for a higher arc for action %d" % kind)
  var previous_speed := 100.0
  var smooth_curve := true
  for angle in range(0, 81, 5):
   var velocity := sample(kind, 0.03, angle)
   smooth_curve = smooth_curve and velocity.length() <= previous_speed + 0.05
   previous_speed = velocity.length()
  check(smooth_curve, "Angle-to-speed distribution has no discontinuities for action %d" % kind)
  for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
   var out := sample(kind, 0.2, 35, yaw, Vector2.ZERO, Vector3(0, -10, 0))
   var desired := -Basis(Vector3.UP, yaw).z
   check(Vector3(out.x, 0, out.z).normalized().dot(desired) > 0.995, "Receive follows the view while body stays facing forward: %d / %.1f" % [kind, yaw])
 for kind in [0, 8, 3, 4, 2]:
  a.camera_yaw = 0
  a.camera_pitch = 0.6
  a.visual.rotation = Vector3.ZERO
  a.tilt = Vector2(-0.6, 0)
  var left := a.direction_for(kind, 3.2)
  a.tilt = Vector2(0.6, 0)
  var right := a.direction_for(kind, 3.2)
  check(right.x - left.x > 0.15, "Tilt remains active for pass/serve/spike action %d" % kind)
 var no_tilt := sample(1, 0.4, 35, 0.7, Vector2.ZERO, Vector3(4, -9, 2))
 var full_tilt := sample(1, 0.4, 35, 0.7, Vector2(0.7, -0.6), Vector3(4, -9, 2))
 check(no_tilt.is_equal_approx(full_tilt), "Tilt does not change actual lower receive speed or direction")
 a.lower_serve_active = true
 check(not a.tilt_affects(1) and not a.is_receive(1), "Automatic lower serve remains independent of manual pass hold/angle controls")
 a.lower_serve_active = false
 check(not a.tilt_affects(7), "Dive excludes Tilt steering")
 var low := await flight(0.03, 8)
 var high := await flight(0.03, 72)
 check(high.y > low.y + 1.5, "Real free ball flight produces a higher apex when looking up")
 var strong := await flight(0.03, 38)
 var weak := await flight(1.3, 38)
 check(absf(strong.z - 5) > absf(weak.z - 5) + 2.0, "Real free ball flight travels farther after a short hold")
 game.hud._cancel()
 game.queue_free()
 await process_frame
 print("V9 TESTS PASSED (%d checks)" % checks if failures == 0 else "V9 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
