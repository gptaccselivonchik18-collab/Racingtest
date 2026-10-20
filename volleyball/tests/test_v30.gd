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
func run() -> void:
 var random := RandomNumberGenerator.new()
 var previous_faults := 20000
 var previous_spread := INF
 for level in range(5):
  random.seed = 300001
  var faults := 0
  var spread := 0.0
  for sample in range(12000):
   var error := VolleyBotDifficulty.contact_error(random, level, 0.8, 3.0, 0.04)
   faults += int(error.fault)
   spread += Vector2(error.angle).length()
  check(faults < previous_faults and faults > 0, "Execution faults decrease at grade %d without becoming impossible" % level)
  check(spread < previous_spread, "Routine touch dispersion decreases at grade %d" % level)
  previous_faults = faults
  previous_spread = spread
  if level > 0:
   var profile := VolleyBotDifficulty.profile(level)
   var lower := VolleyBotDifficulty.profile(level - 1)
   check(profile.lookahead > lower.lookahead and profile.scan < lower.scan and profile.reaction < lower.reaction and profile.uncertainty < lower.uncertainty, "Anticipation horizon, observation and reaction improve at grade %d" % level)
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 var manager: VolleyGameBots = game.game_bots
 manager.configure({"counts": [1, 1], "difficulty": 4})
 manager.set_physics_process(false)
 for bot in manager.bots.values():
  bot.set_physics_process(false)
 check(game.athlete.execution_level == 2, "Human keeps club execution baseline with professional bots")
 var guest := ContextAthlete.new()
 check(guest.execution_level == 2, "New network athlete also defaults to club execution baseline")
 guest.free()
 var bot: VolleyGameBot = manager.bots[-100]
 bot.energy = 0
 check(bot.effective_speed() < float(bot.style_stats.movement().speed) and bot.effective_jump_height() < float(bot.style_stats.movement().jump_height), "Reach prediction uses actual fatigued running and jumping")
 for rally in range(40):
  manager.clock = 3600.0 + rally * 30.0
  bot.energy = 0.01
  bot.noticed_touch = manager.last_touch_time
  bot.reaction_until = manager.clock + 5
  bot.dive_time = 0.3
  bot.move_axis = Vector2.ONE
  manager.reset_rally()
  if rally == 39:
   check(bot.energy == 1 and bot.dive_time < 0 and bot.reaction_until == 0 and bot.noticed_touch == -INF and bot.move_axis == Vector2.ZERO, "Forty late-session rallies clear fatigue and stale movement/reaction state")
 # A fresh reaction delay must expire rather than be charged again in every
 # interception scan. Compare identical visible balls at early/late clocks.
 game.athlete.set_physics_process(false)
 game.athlete.position = Vector3(7, 0.02, 11)
 bot.position = Vector3(0, 0.02, 5)
 bot.velocity = Vector3.ZERO
 manager.human_team = -1
 manager.last_team = 1
 manager.last_kind = 1
 manager.last_actor = manager.bots[-106]
 var targets: Array[Vector3] = []
 for time in [1.0, 8000.0]:
  manager.clock = time
  manager.last_touch_time = time - 1.0
  bot.noticed_touch = manager.last_touch_time
  bot.reaction_until = time - 0.5
  game.ball.feed(Vector3(0, 4, 4.8), Vector3(0, -2, 0))
  await physics_frame
  manager.predict()
  check(manager.receivers[0] == bot.bot_id, "Reachable ball gets a receiver at clock %.0f" % time)
  targets.append(manager.intercepts[0])
 check(targets[0].distance_to(targets[1]) < 0.06, "Long-running clock does not degrade a fresh reachable interception")
 game.queue_free()
 await process_frame
 print("V30 TESTS PASSED (%d checks)" % checks if failures == 0 else "V30 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
