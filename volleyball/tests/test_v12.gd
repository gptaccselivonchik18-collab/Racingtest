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

func reset() -> void:
 game.hud._cancel()
 a.cancel_input()
 a.action = VolleyAthlete.Action.IDLE
 a.position = Vector3(0, 0.02, 5)
 a.velocity = Vector3.ZERO
 a.visual.rotation = Vector3.ZERO
 a.dive_time = -1
 a.holding_ball = false
 a.lower_serve_active = false
 a.float_serve_active = false
 game.rig.yaw = 0
 game.rig.pitch = 0
 game.rig._process(0)

func sample(kind: int, hold: float, pitch: float, yaw := 0.0, tilt := Vector2.ZERO, incoming := Vector3.ZERO) -> Vector3:
 reset()
 a.position.y = 1.2 if kind == 8 else 0.02
 a.camera_yaw = yaw
 a.camera_pitch = deg_to_rad(pitch)
 a.tilt = tilt
 a.begin_action(kind)
 a.charged_for = hold
 a.release()
 a.action_time = a.strike_duration * 0.47
 a._update_pose(0)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()
 a.reset_seed(1212)
 return a.try_contact(a.wrists[0], incoming) + incoming

func flight(hold: float) -> Vector2:
 var velocity := sample(1, hold, -80, PI * 0.5)
 var start: Vector3 = a.wrists[0]
 game.ball.feed(start, velocity)
 while game.ball.pending_feed:
  await physics_frame
 var apex := start.y
 for tick in range(600):
  await physics_frame
  apex = maxf(apex, game.ball.position.y)
  if game.ball.position.y < 0.16:
   return Vector2(apex, Vector2(game.ball.position.x - start.x, game.ball.position.z - start.z).length())
 return Vector2(-1, -1)

func drag(id: int, at: Vector2, delta: Vector2) -> void:
 var event := InputEventScreenDrag.new()
 event.index = id
 event.position = at
 event.relative = delta
 game.hud._input(event)

func touch(id: int, at: Vector2, down: bool, canceled := false) -> void:
 var event := InputEventScreenTouch.new()
 event.index = id
 event.position = at
 event.pressed = down
 event.canceled = canceled
 game.hud._input(event)

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 a = game.athlete
 a.set_physics_process(false)
 a.replica = true
 a.style_stats.reset_all()
 var baseline := sample(1, 0.35, 0)
 for pitch in [-84.0, -45.0, 0.0, 45.0, 84.0]:
  var out := sample(1, 0.35, pitch)
  check(out.is_equal_approx(baseline) and out.y > 0, "Actual lower contact ignores camera pitch %.0f" % pitch)
 for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
  var out := sample(1, 0.35, -84, yaw, Vector2.ZERO, Vector3(3, -25, 2))
  var bearing := -Basis(Vector3.UP, yaw).z
  check(out.y > 0 and Vector3(out.x, 0, out.z).normalized().dot(bearing) > 0.99, "Lower receive rises along yaw %.2f even against a fast descending ball" % yaw)
 var no_tilt := sample(1, 0.5, 0, 0.4)
 check(sample(1, 0.5, 70, 0.4, Vector2(1, -1)).is_equal_approx(no_tilt), "Tilt and camera pitch cannot redirect the platform")
 var strong := await flight(0.03)
 var medium := await flight(0.6)
 var soft := await flight(1.3)
 print("Lower receive actual apex/range: ", strong, " / ", medium, " / ", soft)
 check(strong.x > medium.x + 0.5 and medium.x > soft.x + 0.3, "Holding reduces actual apex monotonically")
 check(strong.y > medium.y + 1 and medium.y > soft.y + 0.5, "Holding reduces actual travel distance monotonically")
 for kind in [0, 8]:
  var smooth_curve := true
  var previous := -100.0
  for pitch in range(-84, 85):
   a.camera_pitch = deg_to_rad(pitch)
   a.tilt = Vector2.ZERO
   var angle := a.receive_elevation(kind)
   smooth_curve = smooth_curve and angle >= previous and absf(angle - clampf(pitch, -20, 84)) <= 8.001
   previous = angle
  check(smooth_curve, "Set assist is smooth, monotonic and limited to eight degrees: %d" % kind)
  a.camera_pitch = deg_to_rad(45)
  check(a.receive_elevation(kind) > 52 and a.receive_elevation(kind) < 54, "A moderate view angle now gives a higher pass: %d" % kind)
  a.camera_pitch = 0
  check(is_zero_approx(a.receive_elevation(kind)), "Flat pass remains flat: %d" % kind)
  a.camera_pitch = deg_to_rad(45)
  a.tilt = Vector2(0, -1)
  var high := a.receive_elevation(kind)
  a.tilt.y = 1
  check(absf(high - a.receive_elevation(kind) - 22) < 0.001, "Set Tilt keeps its vertical range: %d" % kind)
 reset()
 var ui: VolleyHUD = game.hud
 ui.settings.layout.clear()
 ui.settings.button_scale = 1
 ui._layout()
 ui._process(0)
 var free := Vector2(600, 180)
 var primary: Vector2 = ui.buttons.primary.rect.get_center()
 var secondary: Vector2 = ui.buttons.secondary.rect.get_center()
 var bump: Vector2 = ui.buttons.bump.rect.get_center()
 var before := a.strike_count
 touch(90, free, true)
 for role in ["primary", "secondary", "jump", "dive", "bump"]:
  drag(90, ui.buttons[role].rect.get_center(), Vector2(20, 0))
 check(ui.fingers.get(90) == "camera" and ui.role_owners.is_empty() and game.action_owner.is_empty(), "Camera finger crossing five buttons stays a camera finger")
 touch(90, bump, false)
 check(a.strike_count == before, "Ending camera swipe on a button never fires an action")
 reset()
 touch(91, secondary, true)
 var yaw_before: float = game.rig.yaw
 drag(91, primary, Vector2(65, -30))
 check(game.action_owner == "secondary" and ui.fingers.get(91) == "secondary", "A held pass cannot become an attack while dragging")
 check(game.rig.yaw < yaw_before and game.rig.pitch > 0 and ui.camera_id == 91, "Held pass finger rotates both camera axes")
 before = a.strike_count
 touch(91, free, false)
 check(a.strike_count == before + 1 and a.strike_technique == 0 and ui.role_owners.is_empty() and ui.camera_id == -1, "Release outside button executes exactly the held pass and clears look capture")
 touch(91, free, false)
 check(a.strike_count == before + 1, "Duplicate release cannot repeat the pass")
 reset()
 touch(92, bump, true)
 drag(92, free, Vector2(-30, 20))
 before = a.strike_count
 touch(92, free, false, true)
 check(a.strike_count == before and ui.fingers.is_empty() and ui.role_owners.is_empty() and ui.camera_id == -1 and game.action_owner.is_empty(), "OS cancellation after aiming never performs a receive or leaves capture")
 reset()
 touch(93, free, true)
 touch(94, secondary, true)
 yaw_before = game.rig.yaw
 drag(94, primary, Vector2(80, 0))
 check(is_equal_approx(game.rig.yaw, yaw_before) and ui.camera_id == 93, "Dedicated camera finger prevents double look from an action finger")
 drag(93, bump, Vector2(40, 0))
 check(game.rig.yaw < yaw_before and game.action_owner == "secondary", "Independent camera still aims a held pass across other buttons")
 touch(93, bump, false)
 yaw_before = game.rig.yaw
 drag(94, free, Vector2(20, 0))
 check(game.rig.yaw < yaw_before and ui.camera_id == 94, "Held button takes over camera after the separate look finger lifts")
 ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
 check(ui.fingers.is_empty() and ui.role_owners.is_empty() and ui.camera_id == -1 and game.action_owner.is_empty(), "Focus loss cancels both held action and camera")
 reset()
 touch(95, ui.left_center, true)
 drag(95, primary, Vector2(300, 0))
 check(ui.fingers.get(95) == "move" and ui.move_id == 95 and game.action_owner.is_empty() and not a.approach_armed, "Joystick crossing an action button never starts an attack")
 touch(95, primary, false)
 check(ui.move_id == -1 and ui.move_value == Vector2.ZERO, "Crossing buttons does not stick the movement joystick")
 reset()
 var low := sample(1, 0.4, 0)
 a.style_stats.set_stat("bump", 220)
 var high := sample(1, 0.4, 0)
 check(high.length() > low.length() * 1.2 and high.y > low.y, "Bump stat still improves lift and contact strength")
 a.style_stats.reset_all()
 game.hud._cancel()
 game.queue_free()
 await process_frame
 print("V12 TESTS PASSED (%d checks)" % checks if failures == 0 else "V12 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
