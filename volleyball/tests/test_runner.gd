extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error("FAIL: " + message)
 else:
  print("PASS: " + message)

func frames(count: int) -> void:
 for i in range(count):
  await physics_frame

func run() -> void:
 var scene := load("res://scenes/Main.tscn") as PackedScene
 check(scene != null, "Main scene loads")
 var game := scene.instantiate()
 root.add_child(game)
 await frames(20)
 var a: VolleyAthlete = game.athlete
 var b: VolleyBall = game.ball
 var ui: VolleyHUD = game.hud
 check(a.is_on_floor(), "Athlete stands on court")
 check(game.camera.current, "Third person camera active")
 # Empty release must execute, finish, and report a miss without changing ball.
 a.prepare()
 a.release()
 check(a.action == VolleyAthlete.Action.STRIKE and a.strike_count == 1, "Release starts empty swing immediately")
 await frames(70)
 check(a.action == VolleyAthlete.Action.IDLE and not a.hit_used, "Empty swing finishes as miss")
 check(a.contact_count == 0, "No phantom impulse")
 # Test real contact geometry and debounce with known ball centers.
 a.prepare()
 a.release()
 a.action_time = a.strike_duration * 0.48
 a._update_pose(1.0 / 120.0)
 var incoming := Vector3(0, -4, 2)
 check(a.try_contact(a.wrists[0] + Vector3(0.5, 0, 0), incoming) == Vector3.ZERO, "Spatial miss never assisted")
 var delta := a.try_contact(a.wrists[0], incoming)
 check(delta.length() > 0.1, "Overhead hand overlap transfers impulse")
 check(a.try_contact(a.wrists[0], incoming) == Vector3.ZERO, "Only one impulse per swing")
 a.action = VolleyAthlete.Action.IDLE
 a.technique = VolleyAthlete.Technique.UNDERHAND
 a.prepare()
 a.release()
 a.action_time = a.strike_duration * 0.48
 a._update_pose(1.0 / 120.0)
 var forearm := (a.elbows[0] + a.wrists[0]) * 0.5
 check(a.try_contact(forearm, incoming).length() > 0, "Underhand forearm overlap transfers impulse")
 a.hit_used = false
 a.action_time = 0
 check(a.try_contact(a.wrists[0], incoming) == Vector3.ZERO, "Overlap outside active stroke does not hit")
 # Seed reproduces both direction and power, given the same physical input.
 a.action_time = a.strike_duration * 0.48
 a.reset_seed(12345)
 var first := a.try_contact(a.wrists[0], incoming)
 a.hit_used = false
 a.reset_seed(12345)
 var second := a.try_contact(a.wrists[0], incoming)
 check(first.is_equal_approx(second), "Seed reproduces contact randomness")
 a.action = VolleyAthlete.Action.IDLE
 # Multitouch routing: releasing aim must not release movement or sprint.
 ui._touch_down(11, ui.left_center + Vector2(30, 0))
 ui._touch_down(22, ui.right_center + Vector2(0, -60))
 ui._touch_down(33, ui.buttons.sprint.rect.get_center())
 check(ui.move_id == 11 and ui.aim_id == 22 and ui.mobile_sprint, "Three simultaneous fingers independently captured")
 var swings_before := a.strike_count
 ui._touch_up(22)
 check(a.strike_count == swings_before + 1, "Aim finger release triggers stroke")
 check(ui.move_id == 11 and ui.mobile_sprint, "Aim release preserves other fingers")
 ui._touch_up(11)
 ui._touch_up(33)
 check(ui.move_value == Vector2.ZERO and not ui.mobile_sprint, "Movement and sprint release reset state")
 a.action = VolleyAthlete.Action.IDLE
 ui._touch_down(44, ui.right_center)
 ui._cancel()
 check(a.action == VolleyAthlete.Action.IDLE and ui.aim_id == -1, "Focus/menu cancellation cannot leave held input")
 # All feeds are fixed world trajectories; moving athlete does not move launcher.
 for i in range(6):
  game.training.selected = i
  game.training.launch(b, a)
  var origin: Vector3 = b.feed_position
  var velocity: Vector3 = b.feed_velocity
  a.position.x = 3
  game.training.launch(b, a)
  check(b.feed_position == origin and b.feed_velocity == velocity, "Drill %d fixed launch independent of athlete" % i)
  await frames(3)
  check(not b.pending_feed and b.linear_velocity.length() > 0.1, "Drill %d enters physics simulation" % i)
 a.position = Vector3(0, 0.02, 4)
 # Actual engine integration: a falling ball bounces from the ground.
 b.feed(Vector3(2, 0.3, 4), Vector3(0, -3, 0))
 await frames(3)
 var bounced := false
 for i in range(35):
  await physics_frame
  if b.linear_velocity.y > 1:
   bounced = true
 check(bounced, "Rigid ball bounces from court")
 b.feed(Vector3(2, 1.9, -0.5), Vector3(0, 0, 6))
 await frames(3)
 var net_bounce := false
 for i in range(20):
  await physics_frame
  if b.linear_velocity.z < -0.5:
   net_bounce = true
 check(net_bounce, "Net physically rejects incoming ball")
 # Integrator path, not merely direct try_contact calls.
 a.action = VolleyAthlete.Action.IDLE
 a.technique = VolleyAthlete.Technique.OVERHEAD
 a.prepare()
 a.release()
 a.action_time = a.strike_duration * 0.35
 a._update_pose(1.0 / 120.0)
 var count_before := a.contact_count
 b.feed(a.wrists[0], Vector3(0, -1, 0))
 await frames(5)
 check(a.contact_count == count_before + 1, "Live physics integrator produces exactly one hand contact")
 # Motion/attribute changes: compare actual jump velocities and sprint stamina.
 a.position = Vector3(0, 0.01, 4)
 a.velocity = Vector3.ZERO
 await frames(15)
 a.stats.set_stat("jump", 1)
 a.jump()
 var low_jump := a.velocity.y
 a.stats.set_stat("jump", 100)
 a.jump()
 check(a.velocity.y > low_jump, "Jump stat changes launch velocity")
 for key in a.stats.values:
  a.stats.set_stat(key, 500)
  check(a.stats.values[key] == 100, "Stat bound: " + key)
 ui.toggle_menu()
 check(paused, "Menu pauses physics")
 ui.toggle_menu()
 check(not paused, "Menu resumes physics")
 if failures == 0:
  print("ALL TESTS PASSED (%d checks)" % checks)
 else:
  print("FAILED: %d / %d" % [failures, checks])
 game.queue_free()
 await process_frame
 quit(0 if failures == 0 else 1)
