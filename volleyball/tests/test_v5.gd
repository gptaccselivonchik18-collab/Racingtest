extends SceneTree

var game: Node3D
var a: ContextAthlete
var b: VolleyBall
var ui: VolleyHUD
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func frames(n: int) -> void:
 for i in range(n):
  await physics_frame

func check(ok: bool, note: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", note)
 else:
  failures += 1
  push_error("FAIL: " + note)

func reset() -> void:
 ui._cancel()
 game.reset_player()
 game.serving = false
 a.energy = 1
 b.feed(Vector3(3, 0.2, 6), Vector3.ZERO)
 await frames(8)
 ui._process(0)

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 a = game.athlete
 b = game.ball
 ui = game.hud
 ui.set_process(false)
 await frames(20)
 ui.settings.layout.clear()
 ui.settings.button_scale = 1
 ui._layout()
 await reset()
 var primary: Vector2 = ui.buttons.primary.rect.get_center()
 var secondary: Vector2 = ui.buttons.secondary.rect.get_center()
 ui._touch_down(1, primary)
 ui._touch_move(1, secondary, secondary - primary)
 check(game.action_owner == "secondary" and a.technique == VolleyAthlete.Technique.OVERHEAD, "Sliding between action buttons transfers capture without lifting")
 var before := a.strike_count
 ui._touch_up(1)
 check(a.strike_count == before + 1 and ui.role_owners.is_empty(), "Transferred finger releases exactly one swing and all holds")
 await reset()
 ui._touch_down(2, primary)
 ui._touch_down(2, secondary)
 check(game.action_owner == "secondary" and ui.fingers[2] == "secondary", "Reused OS touch index cancels stale capture")
 ui._touch_up(2, true)
 check(a.action == VolleyAthlete.Action.IDLE and game.action_owner.is_empty(), "OS cancellation clears gameplay owner as well as HUD")
 var edge: Vector2 = ui.buttons.primary.rect.position + Vector2(-8, 40)
 ui._touch_down(3, edge)
 check(game.action_owner == "primary", "Near-edge taps within eight pixels register")
 ui._touch_move(3, Vector2(600, 200))
 before = a.strike_count
 ui._touch_up(3)
 check(a.strike_count == before and a.action == VolleyAthlete.Action.IDLE, "Dragging away cancels instead of firing an unintended hit")
 ui._touch_down(4, primary)
 ui._press("primary", -123)
 ui._release("primary", -123)
 check(game.action_owner == "primary" and a.action == VolleyAthlete.Action.PREPARE, "Keyboard release cannot release a touch-owned button")
 ui._touch_up(4, true)
 check(ui.fingers.is_empty() and ui.role_owners.is_empty(), "Mixed input sources leave no stale ownership")
 a.action = VolleyAthlete.Action.RECOVER
 a.action_time = 0.16
 before = a.strike_count
 ui._touch_down(5, primary)
 ui._touch_up(5)
 check(ui.queued.has("primary"), "Tap near end of recovery is buffered")
 await frames(7)
 ui._process(0.06)
 check(a.strike_count == before + 1 and ui.queued.is_empty(), "Released buffered tap fires exactly once when ready")
 await reset()
 a.action = VolleyAthlete.Action.RECOVER
 a.action_time = 0.16
 ui._touch_down(6, primary)
 before = a.strike_count
 ui._touch_up(6, true)
 await frames(7)
 ui._process(0.06)
 check(a.strike_count == before and ui.queued.is_empty(), "Canceled buffered touch never fires later")
 ui._touch_down(7, primary)
 ui._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
 check(ui.fingers.is_empty() and ui.role_owners.is_empty() and game.action_owner.is_empty(), "Phone suspension releases every input source")
 await reset()
 ui._touch_down(8, Vector2(600, 180))
 ui._touch_move(8, primary, primary - Vector2(600, 180))
 check(game.action_owner == "primary" and ui.camera_id == -1, "Free-screen finger can slide onto an action button")
 ui._touch_up(8, true)
 await reset()
 ui._touch_down(10, ui.left_center + Vector2(0, -ui.radius))
 await frames(60)
 ui._process(0)
 check(ui.buttons.primary.text == "АТАКА" and game.running_approach(), "Ground running changes primary to Attack")
 ui._touch_move(10, primary, primary - ui.left_center)
 check(ui.fingers[10] == "approach" and a.approach_armed, "Run-stick finger transfers into approach gesture")
 before = a.strike_count
 ui._touch_up(10)
 check(a.jump_windup > 0 and ui.move_id == -1, "Releasing over Attack plants for an approach jump")
 await frames(25)
 check(a.airborne() and a.attack_ready and a.wrists[1].y > a.position.y + 1.7, "Approach jump raises the striking arm before contact")
 check(a.strike_count == before, "Jump and windup do not hit automatically")
 ui._touch_down(11, primary)
 check(a.action == VolleyAthlete.Action.STRIKE and a.strike_technique == VolleyAthlete.Technique.SPIKE, "Next Attack press executes a full spike immediately")
 ui._touch_up(11)
 check(a.strike_count == before + 1, "Releasing the second tap does not duplicate the spike")
 await reset()
 ui._touch_down(12, ui.left_center + Vector2(0, -ui.radius))
 await frames(50)
 ui._touch_down(13, primary)
 ui._touch_up(13)
 await frames(16)
 check(a.attack_ready and ui.move_id == 12, "A second finger can trigger the same approach without releasing run")
 ui._cancel()
 await reset()
 ui._touch_down(30, ui.left_center + Vector2(0, -ui.radius))
 await frames(50)
 ui._touch_move(30, primary)
 ui._touch_up(30, true)
 await frames(20)
 check(not a.airborne() and not a.approach_armed and a.jump_windup == 0, "Canceled approach gesture never launches a delayed jump")
 ui._touch_down(31, ui.left_center + Vector2(0, -ui.radius))
 await frames(50)
 ui._touch_move(31, primary)
 ui._touch_move(31, Vector2(600, 180))
 ui._touch_up(31)
 await frames(20)
 check(not a.airborne() and game.action_owner.is_empty(), "Releasing approach outside Attack cancels the combination")
 await reset()
 a.action = VolleyAthlete.Action.RECOVER
 a.action_time = 0
 before = a.strike_count
 ui._touch_down(32, primary)
 ui._touch_up(32)
 ui._process(0.17)
 await frames(30)
 ui._process(0)
 check(a.strike_count == before and ui.queued.is_empty(), "An expired buffered tap cannot fire much later")
 await reset()
 ui._touch_down(14, ui.left_center + Vector2(0, -ui.radius))
 await frames(60)
 var start := a.position
 ui._touch_up(14)
 await frames(60)
 var stop_distance := Vector2(a.position.x - start.x, a.position.z - start.z).length()
 check(stop_distance > 0.15 and stop_distance < 0.85 and Vector2(a.velocity.x, a.velocity.z).length() < 0.05, "Running stops in a short natural step rather than sliding on ice")
 await reset()
 b.feed(a.position + Vector3(0.1, 0.25, -0.4), Vector3.ZERO)
 await frames(4)
 check(b.pick_up(), "Pickup enters held-ball context")
 ui._process(0)
 check(not ui.buttons.dive.visible and not ui.buttons.jump_set.visible and ui.buttons.jump.visible, "Held context removes dive and jump set but retains jump")
 var low := ui.height_rect.position + Vector2(16, 25)
 ui._touch_down(20, low)
 ui._process(0)
 check(ui.fingers.get(20) == "height", "New height capture survives the first held-context frame")
 var low_speed := b.toss_velocity().y
 ui._touch_move(20, ui.height_rect.end - Vector2(16, 25))
 check(b.release_height() > 3.2 and b.toss_velocity().y > low_speed + 3, "Height slider changes upward launch speed independently of direction")
 ui._touch_up(20)
 b.set_release_height(0.7)
 var low_points := b.preview_points()
 var low_apex := low_points[0].y
 for point in low_points:
  low_apex = maxf(low_apex, point.y)
 b.set_release_height(2.8)
 var high_points := b.preview_points()
 var high_apex := high_points[0].y
 for point in high_points:
  high_apex = maxf(high_apex, point.y)
 check(high_apex - low_apex > 1.9 and absf(high_apex - high_points[0].y - 2.8) < 0.12, "Shown apex agrees with chosen height in real metres")
 ui._touch_down(33, ui.left_center + Vector2(0, -30))
 ui._touch_down(21, secondary)
 ui._touch_up(21)
 ui._process(0)
 check(b.aiming_throw() and b.held and ui.buttons.primary.text == "БРОСИТЬ", "Throw mode selects aim without unintentionally releasing the ball")
 check(ui.move_id == 33, "Held-mode toggle preserves the movement finger")
 ui._touch_up(33)
 game.rig._process(1)
 var target := Vector3(1.6, VolleyAthlete.BALL_RADIUS, 1.8)
 var screen: Vector2 = game.camera.unproject_position(target)
 ui._touch_down(22, screen)
 ui._touch_up(22)
 check(b.throw_target.distance_to(target) < 0.05, "Tapping the court selects the actual world landing point")
 b.set_release_height(1.0)
 var destination := b.throw_target
 ui._touch_down(23, primary)
 ui._touch_up(23)
 check(not b.held and b.pending_feed, "One primary tap launches the configured throw")
 var landed := false
 for tick in range(240):
  await physics_frame
  if not b.pending_feed and b.position.y < 0.15 and b.linear_velocity.y < 0:
   landed = true
   break
 check(landed and Vector2(b.position.x - destination.x, b.position.z - destination.z).length() < 0.25, "Unguided physical throw lands within 25 cm of the chosen point")
 ui._process(0)
 check(ui.buttons.dive.visible and ui.role_owners.is_empty(), "Releasing the ball restores controls without stuck held buttons")
 game.queue_free()
 await process_frame
 print("V5 TESTS PASSED (%d checks)" % checks if failures == 0 else "V5 TESTS FAILED %d" % failures)
 quit(0 if failures == 0 else 1)
