extends SceneTree
var game: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func frames(count: int) -> void:
 for tick in range(count):
  await physics_frame

func check(ok: bool, note: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", note)
 else:
  failures += 1
  push_error("FAIL: " + note)

func distribution(skill: float) -> Dictionary:
 var result := {"error": 0.0, "slips": 0, "out": 0, "close": 0, "spin": 0.0}
 var aim := Vector3(0, VolleyBall.RADIUS, -5)
 game.float_serve.rng.seed = 11011
 for i in range(2000):
  var sample: Dictionary = game.float_serve.sample_delivery(aim, skill)
  result.error += sample.target.distance_to(aim)
  result.spin += sample.spin.length()
  if sample.mishit:
   result.slips += 1
  if absf(sample.target.x) > 4.605 or absf(sample.target.z) > 9.105 or sample.target.z > 0:
   result.out += 1
  elif sample.target.distance_to(aim) < 1:
   result.close += 1
 result.error /= 2000
 result.spin /= 2000
 return result

func trial(side: float, seed_value: int) -> Dictionary:
 var a: ContextAthlete = game.athlete
 game.float_serve.cancel_sequence()
 game.hud._cancel()
 a.position = Vector3(0, 0.02, side * 9.6)
 a.velocity = Vector3.ZERO
 a.landing_load = 0
 a.energy = 1
 a.visual.rotation = Vector3(0, 0 if side > 0 else PI, 0)
 a.camera_yaw = a.visual.rotation.y
 a.tilt = Vector2.ZERO
 a.action = VolleyAthlete.Action.IDLE
 a._update_pose(0.2)
 game.ball.feed(a.position + Vector3(0, 0.3, -side * 0.5), Vector3.ZERO)
 await frames(20)
 if not game.ball.pick_up():
  return {"hit": false}
 game.float_serve.rng.seed = seed_value
 var before: int = a.contact_count
 if not game.float_serve.launch(a, Vector3(0, VolleyBall.RADIUS, -side * 5), 1.8):
  return {"hit": false}
 var active := false
 var spin := 99.0
 var landing := Vector3.ZERO
 for tick in range(500):
  await physics_frame
  if game.ball.float_active and not game.ball.pending_feed:
   active = true
   spin = minf(spin, game.ball.angular_velocity.length())
  if a.contact_count > before and game.ball.position.y < 0.16:
   landing = game.ball.position
   break
 await frames(140)
 return {"hit": a.contact_count == before + 1, "active": active, "spin": spin, "landing": landing, "crossed": game.rules.serve_crossed}

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 await frames(20)
 check(VolleyRoomDiscovery.private_ipv4("10.42.0.1"), "Private 10/8 discovery still works after the protocol version bump")
 check(not VolleyRoomDiscovery.private_ipv4("11.42.0.1"), "Public 11/8 is not mistaken for a local hotspot subnet")
 game.athlete.style_stats.reset_all()
 game.hud.settings.layout.clear()
 game.hud._layout()
 game.hud._process(0)
 check(not game.hud.buttons.float_serve.visible, "Float button is hidden without possession")
 check(not game.float_serve.open(), "Float wizard requires the player's held ball")
 game.ball.feed(game.athlete.position + Vector3(0, 0.3, -0.5), Vector3.ZERO)
 await frames(18)
 check(game.ball.pick_up(), "A slow nearby ball can be picked up for the float serve")
 game.hud._process(0)
 check(game.hud.buttons.float_serve.visible and game.hud.buttons.lower_serve.visible, "Float and lower serve have separate buttons during possession")
 var float_rect: Rect2 = game.hud.buttons.float_serve.rect
 var lower_rect: Rect2 = game.hud.buttons.lower_serve.rect
 check(not float_rect.intersects(lower_rect) and absf(float_rect.get_center().y - lower_rect.get_center().y) < 1 and float_rect.get_center().distance_to(lower_rect.get_center()) < 125, "Float button sits next to lower serve without overlap")
 check(game.hud._press("float_serve", 501) and game.float_serve.visible and not game.hud.visible, "Float button opens the height wizard and cancels old touch owners")
 check(game.float_serve.stage == 0 and game.float_serve.serve_title() == "ПОДАЧА ПЛАНЕР", "Float wizard has its own title and starts with height")
 game.float_serve.choose_target()
 check(game.frontend.blocks_input() and game.float_serve.top_camera.current, "Opponent targeting blocks ordinary game inputs")
 for side in [1.0, -1.0]:
  game.float_serve.close()
  game.athlete.position.z = side * 9.6
  game.float_serve.open()
  game.float_serve.choose_target()
  var point := Vector3(1.2, VolleyBall.RADIUS, -side * 5.5)
  var selected: Variant = game.float_serve.target_from_screen(game.float_serve.top_camera.unproject_position(point))
  check(selected is Vector3 and selected.distance_to(point) < 0.01 and game.float_serve.top_camera.position.z * side < 0, "Top view selects the opposite court on side %.0f" % side)
  check(not game.float_serve.opposite_target(Vector3(0, 0, side * 5), side), "Float targeting rejects the player's own half on side %.0f" % side)
 game.float_serve.close()
 var low := distribution(0.03)
 var normal := distribution(0.5)
 var high := distribution(0.97)
 print("Float distribution low=", low, " normal=", normal, " high=", high)
 check(high.error < low.error * 0.5 and high.close > low.close * 2, "Serve substantially improves target accuracy")
 check(low.slips > high.slips * 3 and high.spin < low.spin * 0.3, "Serve improves contact cleanliness and suppresses unintended rotation")
 check(normal.close > 50 and normal.out > 30 and normal.close + normal.out < 1900, "Normal float serves include target hits, other areas and out balls")
 check(high.out > 0 and high.close < 1900, "High Serve retains risk rather than guaranteeing the selected destination")
 var lower_error := 0.0
 game.lower_serve.rng.seed = 11011
 for i in range(2000):
  lower_error += game.lower_serve.sample_error(Vector3(0, VolleyBall.RADIUS, -5), 0.5).target.distance_to(Vector3(0, VolleyBall.RADIUS, -5))
 check(normal.error > lower_error / 2000 * 2.3, "Float target spread is several times harder than lower serve")
 var flight := VolleyFloatFlight.new()
 flight.configure(0.5, 1135)
 var v := Vector3(0, 1, -15)
 var f1 := flight.force(v, Vector3.ZERO, 0.1)
 var f2 := flight.force(v, Vector3.ZERO, 0.5)
 check(f1.distance_to(f2) > 0.08 and f1.length() <= 0.48, "Wake force changes continuously over flight and remains bounded")
 check(absf(f1.dot(v)) < 0.0001, "Float wake acts across the flight rather than injecting forward speed")
 check(f1.length() > flight.force(v, Vector3(30, 0, 0), 0.1).length() * 20, "Fast rotation suppresses the float effect")
 check(flight.force(Vector3(0, 0, -2), Vector3.ZERO, 1).is_zero_approx(), "Slow balls cannot keep floating after the serve")
 var duplicate := VolleyFloatFlight.new()
 duplicate.configure(0.5, 1135)
 check(f1.is_equal_approx(duplicate.force(v, Vector3.ZERO, 0.1)), "Seeded forces reproduce independently of rendering frame rate")
 duplicate.configure(0.5, 1136)
 check(f1.distance_to(duplicate.force(v, Vector3.ZERO, 0.1)) > 0.02, "Different serves have different wake trajectories")
 duplicate.configure(0.97, 1135)
 check(duplicate.force(v, Vector3.ZERO, 0.1).length() < f1.length(), "Serve reduces wake uncertainty without removing it")
 for side in [1.0, -1.0]:
  var result: Dictionary = await trial(side, 42)
  print("Float actual flight ", side, " ", result)
  check(result.hit and result.get("active", false), "Automatic float makes exactly one overhead contact on side %.0f" % side)
  check(result.get("spin", 99) < 1 and result.get("crossed", false), "Actual low-spin float crosses the net on side %.0f" % side)
  check(not game.ball.held and not game.automatic_serve_busy() and not game.athlete.float_serve_active, "Float sequence releases possession and ends on side %.0f" % side)
 game.ball.launch_float(Vector3(0, 3, 4), Vector3(0, 1, -14), Vector3.ZERO, 0.5, 1)
 game.ball.feed(Vector3(0, 3, 4), Vector3.ZERO)
 check(not game.ball.float_active, "A new feed clears float forces from the previous ball")
 var a: ContextAthlete = game.athlete
 a.action = VolleyAthlete.Action.IDLE
 a.float_serve_active = false
 a.begin_action(0)
 a.release()
 a.action_time = a.strike_duration * 0.47
 a._update_pose(0)
 game.ball.launch_float(a.wrists[1], Vector3.ZERO, Vector3.ZERO, 0.5, 2)
 await frames(5)
 check(a.hit_used and not game.ball.float_active, "An actual ordinary receive clears the float wake instead of contaminating the pass")
 game.athlete.float_serve_active = true
 game.float_serve.busy_actor = game.athlete
 game.float_serve.cancel_sequence()
 check(not game.athlete.float_serve_active and not game.automatic_serve_busy(), "Cancellation clears automatic float state")
 game.hud._cancel()
 game.queue_free()
 await frames(2)
 print("V11 TESTS PASSED (%d checks)" % checks if failures == 0 else "V11 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
