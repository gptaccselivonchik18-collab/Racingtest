extends SceneTree
var game: Node3D
var a: ContextAthlete
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, label: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", label)
 else:
  failures += 1
  push_error("FAIL: " + label)

func frames(count: int) -> void:
 for i in range(count):
  await physics_frame

func sample(kind: int, value: float, incoming := Vector3(16, -24, 30)) -> Dictionary:
 a.stats.set_stat(a.style_stats.skill_for(kind), value)
 a.action = VolleyAthlete.Action.IDLE
 a.dive_time = -1
 a.holding_ball = false
 a.velocity = Vector3(0, 2, 0) if kind == ContextAthlete.BLOCK else Vector3.ZERO
 a.position.y = 1.2 if kind == 2 else 0.02
 a.approach_jump = kind == 2
 a.position.z = 9.6 if kind == 3 else 5.0
 a.jump_origin = Vector3(0, 0, a.position.z)
 a.begin_action(kind)
 a.charged_for = 0.2
 a.power = 0.82
 if kind != ContextAthlete.BLOCK:
  a.release()
 a.action_time = a.strike_duration * 0.47
 if kind == ContextAthlete.DIVE:
  a.dive_time = 0.3
 a._update_pose(0)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()
 var point := a.wrists[1]
 var outgoing := a.try_contact(point, incoming) + incoming
 return {"velocity": outgoing, "quality": a.quality, "spin": a.outgoing_spin(Vector3(18, 15, -22), outgoing - incoming), "duration": a.strike_duration, "radius": a.effective_contact_radius()}

func reset_actor() -> void:
 game.hud._cancel()
 a.set_physics_process(true)
 a.action = VolleyAthlete.Action.IDLE
 a.dive_time = -1
 a.dive_cooldown = 0
 a.landing_cooldown = 0
 a.energy = 1
 a.position = Vector3(0, 0.02, 6)
 a.velocity = Vector3.ZERO
 a.visual.rotation = Vector3.ZERO
 a.tilt = Vector2.ZERO
 a.move_axis = Vector2.ZERO
 game.ball.feed(Vector3(5, 0.2, 10), Vector3.ZERO)
 await frames(20)

func run() -> void:
 var old_settings := FileAccess.get_file_as_bytes(VolleySettings.PATH) if FileAccess.file_exists(VolleySettings.PATH) else PackedByteArray()
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 a = game.athlete
 a.style_stats.reset_all()
 await frames(20)
 a.set_physics_process(false)
 check(a.stats.values.size() == 8 and game.hud.stat_sliders.size() == 8, "Exactly eight independent style characteristics have editable controls")
 game.hud.stat_sliders.set.value = -125
 game.hud.stat_sliders.spike.value = 270
 check(a.stats.values.set == -125 and a.stats.values.spike == 270, "Numeric inputs accept negative values and values above 100 independently")
 game.hud.stat_sliders.set.get_parent().get_child(2).pressed.emit()
 check(a.stats.values.set == -115 and a.stats.values.spike == 270, "Large plus button changes only its own characteristic")
 game.hud.stat_sliders.set.get_parent().get_child(0).pressed.emit()
 check(a.stats.values.set == -125 and a.stats.values.spike == 270, "Large minus button changes only its own characteristic")
 var loaded := ContextAthlete.new()
 VolleySettings.new().load_settings(loaded)
 check(loaded.stats.values.set == -125 and loaded.stats.values.spike == 270, "Unrestricted style values persist separately from legacy settings")
 loaded.free()
 a.style_stats.reset_all()
 a.stats.set_stat("set", INF)
 check(a.stats.values.set == 65, "Non-finite values cannot poison physics")
 for kind in [0, 1, 2, 3, ContextAthlete.BLOCK, ContextAthlete.DIVE]:
  a.reset_seed(40)
  var low := sample(kind, -150)
  a.reset_seed(40)
  var high := sample(kind, 250)
  check(high.quality > low.quality + 0.12, "Cleaner difficult contact at high " + a.style_stats.skill_for(kind))
  check(high.radius > low.radius and high.duration > low.duration, "Larger forgiving contact and timing window at high " + a.style_stats.skill_for(kind))
  if kind in [0, 1, ContextAthlete.DIVE]:
   check(absf(high.velocity.x) < absf(low.velocity.x) * 0.6 and high.spin.length() < low.spin.length() * 0.5, "Platform absorbs lateral incoming velocity and spin: " + a.style_stats.skill_for(kind))
  if kind == 2:
   check(high.velocity.length() > low.velocity.length() * 1.2, "High Spike increases actual outgoing speed")
   a.stats.set_stat("spike", -150)
   var weak_spin := a.outgoing_spin(Vector3.ZERO, Vector3.ZERO).length()
   a.stats.set_stat("spike", 250)
   check(a.outgoing_spin(Vector3.ZERO, Vector3.ZERO).length() > weak_spin * 2, "High Spike creates stronger downward topspin")
  if kind == ContextAthlete.BLOCK:
   check(high.velocity.length() >= low.velocity.length() * 0.99 and high.velocity.length() <= Vector3(16, -24, 30).length() * 1.001, "Block controls the rebound without creating extra momentum")
 a.dive_time = -1
 var variances := []
 for value in [-150.0, 250.0]:
  a.reset_seed(92)
  var samples: Array[Vector3] = []
  var mean := Vector3.ZERO
  for i in range(80):
   var out: Vector3 = sample(0, value, Vector3(0, -8, 0)).velocity
   samples.append(out)
   mean += out / 80.0
  var variance := 0.0
  for out in samples:
   variance += out.distance_squared_to(mean) / 80.0
  variances.append(variance)
 check(variances[1] < variances[0] * 0.2, "High Set produces measurably more stable and accurate passes over 80 contacts")
 a.reset_seed(32)
 var unchanged: Vector3 = sample(2, 65).velocity
 a.stats.set_stat("set", 999)
 a.reset_seed(32)
 check(sample(2, 65).velocity.is_equal_approx(unchanged), "Changing Set does not secretly increase Spike")
 var slips := []
 var errors := []
 for value in [-150.0, 250.0]:
  a.stats.set_stat("serve", value)
  game.lower_serve.rng.seed = 800
  var slip_count := 0
  var error_sum := 0.0
  for i in range(400):
   var error: Dictionary = game.lower_serve.sample_error(Vector3.ZERO, a.style_stats.n("serve"))
   slip_count += int(error.slip)
   error_sum += error.target.length_squared()
  slips.append(slip_count)
  errors.append(error_sum)
 check(slips[1] < slips[0] * 0.5 and errors[1] < errors[0] * 0.15, "High Serve reduces real target scatter and slip frequency over 400 serves")
 a.style_stats.reset_all()
 var speeds := []
 var distances := []
 var heights := []
 for value in [-150.0, 250.0]:
  await reset_actor()
  a.stats.set_stat("speed", value)
  a.move_axis = Vector2.RIGHT
  await frames(30)
  speeds.append(a.velocity.x)
  a.move_axis = Vector2.ZERO
  var begin := a.position.x
  await frames(90)
  distances.append(a.position.x - begin)
 check(speeds[1] > speeds[0] * 1.8, "Speed changes acceleration and achieved running speed in actual physics")
 for value in [-150.0, 250.0]:
  await reset_actor()
  a.stats.set_stat("jump", value)
  a.jump()
  var apex := 0.0
  for i in range(180):
   await physics_frame
   apex = maxf(apex, a.position.y)
  heights.append(apex)
 check(heights[1] > heights[0] * 2, "Jump changes the measured ballistic apex")
 var dive_distances := []
 for value in [-150.0, 250.0]:
  await reset_actor()
  a.stats.set_stat("dive", value)
  a.move_axis = Vector2.RIGHT
  a.dive()
  await frames(180)
  dive_distances.append(a.position.x)
 check(dive_distances[1] > dive_distances[0] * 1.7, "Dive changes actual sliding rescue distance")
 await reset_actor()
 var ui: VolleyHUD = game.hud
 ui._touch_down(71, ui.left_center + Vector2(ui.radius, 0))
 ui._touch_move(71, ui.left_center + Vector2(-ui.radius * 3, 0))
 check(ui.move_value.x < -0.95, "A finger dragged far outside the stick can reverse direction without freezing")
 var up := InputEventScreenTouch.new()
 up.index = 71
 up.position = ui.buttons.primary.rect.get_center()
 ui._input(up)
 check(ui.move_id == -1 and a.move_axis == Vector2.ZERO and not a.approach_armed, "Release cannot invent a new approach or leave a running stick held")
 ui.move_value = Vector2.ONE
 ui.move_id = 72
 ui._sync_axes()
 check(a.move_axis == Vector2.ZERO, "Lost pointer ownership clears stale movement")
 Input.action_press("volley_forward")
 ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
 check(not Input.is_action_pressed("volley_forward"), "Focus loss clears keyboard movement as well as touch movement")
 game.ball.feed(a.position + Vector3(0, 0.25, -0.4), Vector3.ZERO)
 await frames(5)
 game.ball.pick_up()
 ui._sync_held_state()
 game.ball.set_release_height(1.5)
 var knob_x: float = ui.height_rect.position.x + 16 + (1.5 - 0.35) / 3.15 * (ui.height_rect.size.x - 32)
 var knob := Vector2(knob_x, ui.height_rect.get_center().y)
 ui._touch_down(73, knob + Vector2(12, 0))
 check(is_equal_approx(game.ball.release_height(), 1.5), "Grabbing the edge of the height knob does not jump its value")
 ui._touch_move(73, Vector2(ui.height_rect.end.x + 12, knob.y + 200))
 check(is_equal_approx(game.ball.release_height(), 3.5), "Horizontal slider sets a realistic 3.5 m apex while ignoring vertical drift")
 ui._look_or_aim(Vector2(30, 200))
 check(is_equal_approx(game.ball.release_height(), 3.5), "Aiming swipe cannot fight the height slider")
 up.index = 73
 up.position = Vector2.ZERO
 ui._input(up)
 check(is_equal_approx(game.ball.release_height(), 3.5) and not ui.fingers.has(73), "An unreliable touch-up coordinate cannot reset toss height")
 game.ball.drop()
 await frames(5)
 await reset_actor()
 check(game.begin_primary() and a.technique == VolleyAthlete.Technique.SPIKE, "Ground Attack stays Attack rather than switching to receive")
 game.cancel_action("primary")
 check(game.begin_bump() and a.technique == VolleyAthlete.Technique.UNDERHAND, "Receive remains a separate explicit action")
 ui._cancel()
 if old_settings.is_empty():
  DirAccess.remove_absolute(VolleySettings.PATH)
 else:
  var settings_file := FileAccess.open(VolleySettings.PATH, FileAccess.WRITE)
  settings_file.store_buffer(old_settings)
  settings_file.close()
 print("V7 TESTS PASSED (%d checks)" % checks if failures == 0 else "V7 TESTS FAILED %d / %d" % [failures, checks])
 game.queue_free()
 await process_frame
 quit(0 if failures == 0 else 1)
