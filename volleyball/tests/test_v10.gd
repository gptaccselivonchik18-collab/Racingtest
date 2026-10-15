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

func sample(kind: int, height := 2.0, tilt := Vector2.ZERO, strength := 0.82, yaw := 0.0) -> Vector3:
 a.position = Vector3(0, height, 9.6)
 a.jump_origin = Vector3(0, 0, 9.6)
 a.velocity = Vector3.ZERO
 a.takeoff_speed = 0
 a.action = VolleyAthlete.Action.IDLE
 a.visual.rotation = Vector3(0, yaw, 0)
 a.camera_yaw = yaw
 a.tilt = tilt
 a.lean = Vector2.ZERO
 a.holding_ball = false
 a.release_time = 0
 a.landing_load = 0
 a.begin_action(kind)
 a.power = strength
 a.release()
 a.action_time = a.strike_duration * 0.47
 a._update_pose(0)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()
 a.reset_seed(940)
 return a.try_contact(a.wrists[1], Vector3.ZERO)

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 a = game.athlete
 for tick in range(3):
  await physics_frame
 a.set_physics_process(false)
 a.style_stats.reset_all()
 var standing := sample(3, 0.02)
 var power := sample(4, 2.0)
 check(power.length() > standing.length() * 1.5, "Air serve delivers substantially more pace than the standing serve")
 check(power.normalized().y < standing.normalized().y * 0.5, "Power serve has a flatter attack trajectory")
 var spin := a.outgoing_spin(Vector3.ZERO, Vector3.ZERO)
 check(spin.length() > 20 and spin.cross(power).y < 0, "Power serve produces downward Magnus force from topspin")
 for height in [2.8, 3.2, 3.8, 4.3]:
  for side in [-1.0, 1.0]:
   var origin := Vector3(0, height, side * 9.1)
   var target := Vector3(0, VolleyAthlete.BALL_RADIUS, -side * 7.8)
   var rotation := Vector3(-side * 24, 0, 0)
   var launch: Vector3 = game.ball.solve_power_serve(origin, target, 24, rotation)
   var flight: Dictionary = game.ball.power_serve_flight(origin, launch, rotation)
   check(flight.net_height >= 2.69 and flight.landing.distance_to(target) < 0.25, "Height-aware power serve clears the net and reaches the opposite court: %.1f / %.0f" % [height, side])
 check(sample(4, 2.0, Vector2.ZERO, 0.82, PI).z > 0, "A backward-facing power serve is not redirected toward the opponent automatically")
 var low_contact: Vector3 = game.ball.solve_power_serve(Vector3(0, 2.8, 9.1), Vector3(0, 0.105, -7.8), 24, Vector3(-24, 0, 0))
 var high_contact: Vector3 = game.ball.solve_power_serve(Vector3(0, 4.3, 9.1), Vector3(0, 0.105, -7.8), 24, Vector3(-24, 0, 0))
 check(high_contact.length() > low_contact.length() * 1.1, "Higher jump/contact permits more real pace within the same court")
 a.style_stats.set_stat("serve", -100)
 var low_serve := sample(4)
 var low_spin := a.outgoing_spin(Vector3.ZERO, Vector3.ZERO).length()
 a.style_stats.set_stat("serve", 250)
 var high_serve := sample(4)
 check(high_serve.length() > low_serve.length() * 1.1, "Serve changes actual power-serve velocity")
 check(a.outgoing_spin(Vector3.ZERO, Vector3.ZERO).length() > low_spin * 1.8, "Serve changes actual topspin as well as accuracy and contact control")
 a.style_stats.reset_all()
 a.style_stats.set_stat("spike", -100)
 var low_spike := sample(4, 2.4)
 var standing_low := sample(3, 0.02)
 a.style_stats.set_stat("spike", 250)
 var high_spike := sample(4, 2.4)
 var standing_high := sample(3, 0.02)
 check(high_spike.length() > low_spike.length() * 1.08, "Spike contributes strike efficiency to airborne power serve")
 check(standing_low.is_equal_approx(standing_high), "Standing serve remains independent of Spike and its new air mechanics")
 a.style_stats.reset_all()
 for key in ["set", "bump"]:
  var kind := 0 if key == "set" else 1
  a.style_stats.set_stat(key, -100)
  var low_arc := a.receive_speed(kind, 78, 1)
  var low_ratio := a.receive_speed(kind, 78, 0.18) / low_arc
  a.style_stats.set_stat(key, 250)
  check(a.receive_speed(kind, 78, 1) > low_arc * 1.1, "%s changes loft control" % key)
  check(a.receive_speed(kind, 78, 0.18) / a.receive_speed(kind, 78, 1) < low_ratio - 0.08, "%s improves the range of soft touches" % key)
 a.style_stats.reset_all()
 var left := sample(4, 2.0, Vector2(-0.65, 0))
 var left_at: Vector3 = game.ball.power_serve_landing(a.last_contact_point, left, a.outgoing_spin(Vector3.ZERO, Vector3.ZERO))
 var right := sample(4, 2.0, Vector2(0.65, 0))
 var right_at: Vector3 = game.ball.power_serve_landing(a.last_contact_point, right, a.outgoing_spin(Vector3.ZERO, Vector3.ZERO))
 check(right_at.x - left_at.x > 3.0, "Tilt steers the power-serve landing laterally")
 sample(4, 2.0, Vector2(0, -0.7))
 var near := a.power_serve_target(a.last_contact_point)
 sample(4, 2.0, Vector2(0, 0.7))
 check(absf(a.power_serve_target(a.last_contact_point).z) > absf(near.z) + 1.5, "Tilt changes power-serve depth")
 a.position.y = 0.02
 for tick in range(8):
  a._physics_process(1.0 / 120.0)
 a.velocity = Vector3.ZERO
 a.action = VolleyAthlete.Action.IDLE
 a.technique = 4
 a.tilt = Vector2.ZERO
 a.limb_rig.motion.previous_state = ""
 a.limb_rig.motion.origins.clear()
 a._update_pose(0.2)
 var motion: VolleyMotion = a.limb_rig.motion
 check(motion.feet[1].x - motion.feet[0].x > 0.36 and motion.body_offset.y < -0.04, "Ready stance plants feet apart with flexed hips/knees")
 check(motion.wrists[1].z < -0.20 and motion.wrists[1].y > 1, "Ready hands stay relaxed in front of the body")
 a.begin_action(4)
 a._update_pose(0.2)
 a.power = 0.82
 a.release()
 a.air_attack = true
 a.position.y = 1.2
 a.action_time = a.strike_duration * 0.85
 a._update_pose(0)
 check(motion.wrists[1].x < 0 and motion.wrists[1].z < -0.4, "Jump-serve follow-through crosses the body after the overhead strike")
 check(motion.feet[1].z > motion.feet[0].z, "Air serve has an asymmetric leg counterbalance")
 game.serving = true
 game.lan.active = true
 game.lan.serve_flags[1] = true
 game._on_player_touch(a, 1, 4, a.position, Vector3.ZERO)
 check(not game.serving and not game.lan.serve_flags[1], "Serve contact clears both solo and per-player LAN serve context")
 game.lan.serve_flags[1] = true
 game.serving = true
 game.lan.hosting = true
 game.lan.players[1] = {"actor": a, "team": 0}
 game.lan.reset_round()
 check(not game.serving and not game.lan.serve_flags[1], "Resetting a round also clears an interrupted/missed serve context")
 game.lan.hosting = false
 game.lan.players.clear()
 game.lan.active = false
 game.hud._cancel()
 game.queue_free()
 await process_frame
 print("V10 TESTS PASSED (%d checks)" % checks if failures == 0 else "V10 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
