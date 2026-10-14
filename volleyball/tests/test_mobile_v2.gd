extends SceneTree

var checks := 0
var failures := 0
var saved_config := ""
var had_config := false

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, label: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", label)
 else:
  failures += 1
  push_error("FAIL: " + label)

func frames(n: int) -> void:
 for i in range(n):
  await physics_frame

func click(pos: Vector2) -> void:
 var event := InputEventMouseButton.new()
 event.device = InputEvent.DEVICE_ID_EMULATION
 event.position = pos
 event.global_position = pos
 event.button_index = MOUSE_BUTTON_LEFT
 event.pressed = true
 root.push_input(event, true)
 await process_frame
 event = event.duplicate()
 event.pressed = false
 root.push_input(event, true)
 await process_frame

func run() -> void:
 had_config = FileAccess.file_exists("user://controls.cfg")
 if had_config:
  saved_config = FileAccess.get_file_as_string("user://controls.cfg")
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 await frames(25)
 var a: VolleyAthlete = game.athlete
 var b: VolleyBall = game.ball
 var ui: VolleyHUD = game.hud
 check(ProjectSettings.get_setting("display/window/handheld/orientation") == 6, "iOS permits runtime orientation changes")
 check(Input.emulate_mouse_from_touch, "Native menu receives touch mouse events")
 ui._orientation(0)
 check(ui.config.orientation == 0, "Manual landscape side 1")
 ui._orientation(2)
 check(ui.config.orientation == 2, "Manual landscape side 2")
 ui._orientation(4)
 check(ui.config.orientation == 4, "Automatic landscape restored")
 a.power = 0.7
 ui._aim(Vector2(0.01, 0))
 ui._aim(Vector2(1, -1))
 ui._aim(Vector2.ZERO)
 check(is_equal_approx(a.power, 0.7), "Aim magnitude and return to center never change power")
 ui._touch_down(71, ui.power_rect.position + Vector2(20 + (ui.power_rect.size.x - 40) * 0.35, 46))
 ui._touch_down(72, ui.left_center + Vector2(35, 0))
 ui._touch_down(73, ui.right_center + Vector2(0, -55))
 check(is_equal_approx(a.power, 0.35) and ui.move_id == 72 and ui.aim_id == 73, "Power slider and two sticks accept independent fingers")
 ui._touch_up(71)
 var cfg := ConfigFile.new()
 cfg.load("user://controls.cfg")
 check(is_equal_approx(float(cfg.get_value("controls", "power")), 35), "Power setting persisted on release")
 ui._cancel()
 check(ui.buttons.jump.rect.get_center().x > ui.size.x * 0.65, "Jump is on right side")
 var jump_rect: Rect2 = ui.buttons.jump.rect
 check(not jump_rect.intersects(Rect2(ui.right_center - Vector2.ONE * ui.radius, Vector2.ONE * ui.radius * 2)), "Jump does not overlap aiming stick")
 ui.toggle_menu()
 await process_frame
 await process_frame
 var old_speed: float = a.stats.values.speed
 var slider: HSlider = ui.stat_sliders.speed
 await click(slider.global_position + Vector2(slider.size.x * 0.2, slider.size.y * 0.5))
 check(a.stats.values.speed != old_speed, "Native GUI slider changes stat through emulated finger click while paused")
 var resume: Button = ui.menu.find_child("Resume", true, false)
 await click(resume.global_position + resume.size * 0.5)
 check(not paused and not ui.menu.visible, "Native menu Resume button works while paused")
 # Restore stats for the physics checks and never persist test settings.
 a.stats = AthleteStats.new()
 a.power = 0.65
 a.action = VolleyAthlete.Action.IDLE
 b.feed(Vector3(5, 0.2, 4), Vector3.ZERO)
 await frames(4)
 check(not b.pick_up(), "Cannot remotely pick up ball")
 b.feed(a.position + Vector3(0.3, 0.15, -0.5), Vector3.ZERO)
 await frames(5)
 check(b.pick_up(), "Nearby slow ball can be picked up")
 await frames(2)
 check(b.held and b.freeze and a.holding_ball, "Held ball is explicitly attached and physics frozen")
 a.position.x += 0.4
 await frames(3)
 check(b.position.distance_to(a.hold_position()) < 0.02, "Held ball follows animated holding position")
 a.select_technique(VolleyAthlete.Technique.THROW)
 a.aim = Vector2(1, 0)
 a.elevation = 35
 a.power = 0.5
 game.release_action()
 check(not b.held and not b.freeze and not a.holding_ball, "Throw releases hold and restores physics")
 check(b.feed_velocity.x > 4 and b.feed_velocity.y > 2, "Throw uses freely chosen direction and elevation")
 await frames(5)
 check(b.linear_velocity.x > 4, "Thrown ball moves in actual physics")
 a.action = VolleyAthlete.Action.IDLE
 a.prepare()
 game.release_action()
 check(a.action == VolleyAthlete.Action.IDLE, "Empty throw does not leave stuck preparation")
 b.feed(a.position + Vector3(0.2, 0.2, -0.5), Vector3(6, 0, 0))
 await frames(3)
 check(not b.pick_up(), "Cannot catch fast airborne ball as pickup")
 for mode in [VolleyAthlete.Technique.SPIKE, VolleyAthlete.Technique.SERVE, VolleyAthlete.Technique.JUMP_SERVE]:
  a.position = Vector3(0, 1, 4)
  a.velocity = Vector3.ZERO
  await frames(2)
  a.action = VolleyAthlete.Action.IDLE
  a.select_technique(mode)
  a.aim = Vector2(0, -1)
  a.visual.rotation = Vector3.ZERO
  a.prepare()
  a.release()
  check(a.action == VolleyAthlete.Action.STRIKE, "Technique %d immediately swings without ball" % mode)
  a.action_time = a.strike_duration * 0.48
  a._update_pose(1.0 / 120.0)
  check(a.try_contact(a.wrists[1] + Vector3(0.5, 0, 0), Vector3.ZERO) == Vector3.ZERO, "Technique %d cannot correct miss" % mode)
  var impulse := a.try_contact(a.wrists[1], Vector3.ZERO)
  check(impulse.length() > 1, "Technique %d hitting palm transfers impulse" % mode)
  if mode == VolleyAthlete.Technique.SPIKE:
   check(impulse.y < 0, "Attack can direct ball downward")
  check(a.try_contact(a.wrists[1], Vector3.ZERO) == Vector3.ZERO, "Technique %d only hits once" % mode)
 game.serve_start()
 await frames(20)
 check(a.position.z > 9, "Serve setup places player behind baseline")
 check(b.pick_up(), "Serve setup ball can be picked up")
 a.select_technique(VolleyAthlete.Technique.SERVE)
 check(b.toss(), "Serve has explicit independent toss")
 await frames(5)
 check(not b.held and b.linear_velocity.y > 4, "Toss is free physical upward trajectory")
 a.select_technique(VolleyAthlete.Technique.JUMP_SERVE)
 a.prepare()
 var previous := a.strike_count
 a.release()
 check(a.strike_count == previous, "Jump serve cannot hit while grounded")
 a.jump()
 await frames(3)
 a.prepare()
 a.release()
 check(a.strike_count == previous + 1, "Jump serve can strike after player jumps")
 # End-to-end serving: only pickup, toss, jump and timed release, no moving
 # the ball to a contact point. These also catch unreachable animation paths.
 for mode in [VolleyAthlete.Technique.SERVE, VolleyAthlete.Technique.JUMP_SERVE]:
  game.serve_start()
  a.stats = AthleteStats.new()
  await frames(20)
  b.pick_up()
  a.select_technique(mode)
  await frames(4)
  b.toss()
  a.prepare()
  var count_before := a.contact_count
  if mode == VolleyAthlete.Technique.JUMP_SERVE:
   await frames(60)
   a.jump()
   await frames(24)
  else:
   await frames(78)
  a.release()
  await frames(40)
  check(a.contact_count == count_before + 1, "Complete physical serve %d connects after independent toss" % mode)
 if paused:
  paused = false
 game.queue_free()
 await process_frame
 if had_config:
  var file := FileAccess.open("user://controls.cfg", FileAccess.WRITE)
  file.store_string(saved_config)
  file.close()
 else:
  DirAccess.remove_absolute("user://controls.cfg")
 print("V2 TESTS PASSED (%d checks)" % checks if failures == 0 else "V2 FAILED: %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
