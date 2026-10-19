extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
 call_deferred("run")
func check(ok: bool, note: String) -> void:
 checks += 1
 print("PASS: " if ok else "FAIL: ", note)
 if not ok:
  failures += 1
  push_error(note)
func frames(count: int) -> void:
 for i in range(count):
  await physics_frame
func run() -> void:
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 var sound: VolleySound = game.sound
 sound.master = 1
 sound.effects = 1
 sound.interface = 1
 sound.apply_volumes()
 for key in VolleySound.CLIPS:
  var stream: AudioStreamWAV = sound.clips[key]
  check(stream != null and stream.get_length() > 0.025 and stream.get_length() < 0.6 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Short non-looping effect loads: " + key)
 check(sound.world_voices.size() == 24 and sound.ui_voices.size() == 4, "Audio voice count is bounded for a full multiplayer court")
 await frames(15)
 var prior := int(sound.played.get("spike", 0))
 sound.contact(2, game.athlete.position + Vector3.UP, Vector3(0, 2, -20), game.athlete)
 check(int(sound.played.get("spike", 0)) == prior + 1, "Real contact mapping plays the attack sound once")
 var bump_before := int(sound.played.get("bump", 0))
 sound.contact(1, game.athlete.position + Vector3.UP, Vector3(0, 4, -2), game.athlete)
 check(int(sound.played.get("bump", 0)) == bump_before + 1, "Lower receive has its own distinct contact sound")
 game.ball.last_velocity = Vector3(0, -7, 0)
 sound.surface("floor")
 var floor_count := int(sound.played.get("ball_floor", 0))
 sound.surface("floor")
 check(floor_count > 0 and int(sound.played.get("ball_floor", 0)) == floor_count, "Collision chatter does not duplicate an impact")
 await frames(15)
 game.ball.last_velocity = Vector3(2, 0.1, 0)
 sound.surface("floor")
 check(int(sound.played.get("ball_floor", 0)) == floor_count, "A ball rolling along the floor stays silent")
 game.ball.last_velocity = Vector3(0, 1, 12)
 sound.surface("net")
 check(int(sound.played.get("ball_net", 0)) > 0, "The net has a separate impact sound")
 var at: Vector3 = game.athlete.position
 sound._play_world("set", at + Vector3(3, 1, 0), 0.7)
 var spatial := false
 for player in sound.world_voices:
  if player.stream == sound.clips.set and player.position.x > at.x + 2:
   spatial = player.bus == VolleySound.COURT_BUS and player.max_distance == 32
 check(spatial, "Court audio retains world position and distance attenuation")
 var actor: ContextAthlete = game.athlete
 game.ball.feed(Vector3(7, 0.3, -10), Vector3.ZERO)
 actor.position = Vector3(0, 0.02, 5)
 await frames(20)
 var jumps := int(sound.played.get("jump", 0))
 var lands := int(sound.played.get("land", 0))
 actor.jump()
 await frames(180)
 check(int(sound.played.get("jump", 0)) == jumps + 1 and int(sound.played.get("land", 0)) == lands + 1, "One physical jump produces one takeoff and landing sound")
 actor.move_axis = Vector2.RIGHT
 await frames(90)
 var steps := 0
 for key in ["step_1", "step_2", "step_3"]:
  steps += int(sound.played.get(key, 0))
 check(steps > 0, "Moving feet produce distance-based footsteps")
 actor.move_axis = Vector2.ZERO
 await frames(100)
 steps = int(sound.played.get("step_1", 0)) + int(sound.played.get("step_2", 0)) + int(sound.played.get("step_3", 0))
 await frames(90)
 check(steps == int(sound.played.get("step_1", 0)) + int(sound.played.get("step_2", 0)) + int(sound.played.get("step_3", 0)), "A stationary player cannot emit phantom footsteps")
 for i in range(80):
  sound.world("bump", actor.position, 0.4)
 check(sound.world_voices.size() == 24 and sound.get_child_count() == 28, "Repeated rallies cannot accumulate audio players")
 sound.master = 0
 sound.apply_volumes()
 prior = int(sound.played.get("spike", 0))
 sound.contact(2, actor.position, Vector3(0, 2, -20), actor)
 check(int(sound.played.get("spike", 0)) == prior and AudioServer.is_bus_mute(AudioServer.get_bus_index(VolleySound.COURT_BUS)) and AudioServer.is_bus_mute(AudioServer.get_bus_index(VolleySound.UI_BUS)), "Master zero mutes both court and interface")
 sound.master = 0.73
 sound.effects = 0.42
 sound.interface = 0.21
 check(sound.save_preferences("user://test_audio.cfg") == OK, "Volume preferences can be saved")
 sound.master = 0
 sound.load_preferences("user://test_audio.cfg")
 check(is_equal_approx(sound.master, 0.73) and is_equal_approx(sound.effects, 0.42) and is_equal_approx(sound.interface, 0.21), "All three volume settings restore independently")
 DirAccess.remove_absolute("user://test_audio.cfg")
 sound.clock += 0.2
 var ui_before := int(sound.played.get("ui_tap", 0))
 var button: Button = game.hud._native_button(game.hud.tabs, "Audio test", func(): pass)
 await process_frame
 button.pressed.emit()
 check(int(sound.played.get("ui_tap", 0)) == ui_before + 1, "Dynamically created menu buttons receive one UI sound hook")
 button.queue_free()
 game.queue_free()
 await process_frame
 print("V31 TESTS PASSED (%d checks)" % checks if failures == 0 else "V31 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
