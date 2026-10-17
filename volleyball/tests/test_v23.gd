extends SceneTree
var game: Node3D
var checks := 0
var failures := 0
func _initialize() -> void:
 call_deferred("run")
func frames(count: int) -> void:
 for i in range(count):
  await physics_frame
func check(ok: bool, note: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", note)
 else:
  failures += 1
  push_error("FAIL: " + note)
func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 game.athlete.set_physics_process(false)
 game.athlete.position = Vector3(-7, 0.02, -10)
 var stats := VolleyStyleStats.new()
 for key in VolleyStyleStats.KEYS:
  var previous := 0.0
  for value in [100.0, 150.0, 999.0, 9999.0]:
   stats.set_stat(key, value)
   var gain := stats.factor(key)
   check(gain > previous and stats.values[key] == value, "%s keeps its number and grows beyond 100/150/999: %.0f" % [key, value])
   previous = gain
  stats.reset_all()
 # All skills have a real physical effect beyond the former asymptote.
 for kind in [0, 1, 2, 3, 6, 7]:
  var key := stats.skill_for(kind)
  stats.set_stat(key, 150)
  var lower := stats.profile(kind).duplicate()
  stats.set_stat(key, 999)
  var upper := stats.profile(kind)
  check(upper.strength > lower.strength * 4 and upper.radius > lower.radius * 2, "Extreme " + key + " changes actual contact strength and reach")
  check(upper.accuracy < lower.accuracy and upper.recovery < lower.recovery, "Extreme " + key + " keeps improving precision and recovery")
  stats.reset_all()
 stats.set_stat("speed", 150)
 var movement := stats.movement()
 stats.set_stat("speed", 999)
 check(stats.movement().speed > movement.speed * 4 and stats.movement().acceleration > movement.acceleration * 4, "999 Speed really runs and accelerates much faster than 150")
 stats.reset_all()
 stats.set_stat("jump", 150)
 var jump := stats.movement()
 stats.set_stat("jump", 999)
 check(stats.movement().jump_height > jump.jump_height * 4, "999 Jump has a much higher ballistic apex than 150")
 stats.set_stat("jump", -999)
 check(stats.movement().jump_height > 0 and stats.movement().jump_height < 0.1, "Negative experiments weaken the mechanic without negative jump heights")
 var rng := RandomNumberGenerator.new()
 rng.seed = 2300
 var attack := {"skill": 0.9, "quality": 1.0, "kind": 2, "factor": 10.34}
 var normal := Vector3(0, 0.2, 1).normalized()
 var strong_attack := VolleyBlockDuel.resolve(attack, 0.9, 1.0, Vector3(0, -4, -20), normal, rng, 0, 1.85)
 var strong_block := VolleyBlockDuel.resolve(attack, 0.9, 1.0, Vector3(0, -4, -20), normal, rng, 0, 100.34)
 check(strong_attack.pierce_chance > strong_block.pierce_chance + 0.5, "Block/Spike contest uses unlimited physical ratings, not only normalized accuracy")
 # Compare actual launch calculations, including the formerly court-limited
 # jump serve, rather than only inspecting profile fields.
 var athlete: ContextAthlete = game.athlete
 athlete.position = Vector3(0, 0.02, 9.7)
 athlete.visual.rotation.y = 0
 athlete.camera_yaw = 0
 athlete.camera_pitch = deg_to_rad(35)
 for kind in [0, 1, 2, 3, 4, 8, 9]:
  athlete.cancel_input()
  athlete.action = VolleyAthlete.Action.IDLE
  athlete.begin_action(kind)
  athlete.release()
  # This is a launch-model fixture, independent of the service-zone/input
  # context that can deliberately convert a requested serve into an attack.
  athlete.strike_technique = kind
  athlete.action = VolleyAthlete.Action.STRIKE
  athlete.strike_power = 0.82
  var key := athlete.style_stats.skill_for(kind)
  athlete.style_stats.set_stat(key, 150)
  var lower := VolleyShotModel.solve(athlete, kind, Vector3(0, 2.5, 9.7), Vector3.ZERO, Vector3.ZERO, 1, 0.82)
  athlete.style_stats.set_stat(key, 999)
  var upper := VolleyShotModel.solve(athlete, kind, Vector3(0, 2.5, 9.7), Vector3.ZERO, Vector3.ZERO, 1, 0.82)
  check(Vector3(upper.velocity).is_finite() and Vector3(upper.velocity).length() > Vector3(lower.velocity).length() * 1.3, "999 skill increases the actual launch beyond 150 for kind %d" % kind)
  athlete.style_stats.reset_all()
 athlete.cancel_input()
 athlete.action = VolleyAthlete.Action.IDLE
 var manager: VolleyGameBots = game.game_bots
 manager.configure({"counts": [1, 0], "difficulty": 2, "human_team": 1})
 var bot: VolleyGameBot = manager.bots[-100]
 game.athlete.position = Vector3(2, 0.02, -5.5)
 bot.position = Vector3(0, 0.02, 4)
 await frames(20)
 bot.set_physics_process(false)
 manager.set_physics_process(false)
 # Most serves deliberately offer humans the first contact, rotating LAN recipients.
 var offered := 0
 for i in range(12):
  bot.reset_plan()
  bot.serves = i
  var aim := manager.target_for(bot, 3)
  if i % 4 != 3:
   offered += int(absf(aim.x - game.athlete.position.x) < 0.6 and aim.z < 0)
  check(aim.is_equal_approx(manager.target_for(bot, 4)), "Serve aim survives toss/strike and jump-serve technique changes")
 check(offered == 9, "Nine of twelve serves offer a reachable reception to the human instead of avoiding them")
 # The receiver selector itself admits a save that cannot be reached on foot.
 game.athlete.position = Vector3(-7, 0.02, -10)
 bot.position = Vector3(0, 0.02, 4)
 bot.velocity = Vector3.ZERO
 bot.reset_plan()
 manager.reset_rally()
 manager.last_team = 1
 manager.samples = [{"at": Vector3(2.1, 0.45, 4), "v": Vector3(0, -4, 0), "time": 0.46}]
 manager.tactics.choose_receivers()
 check(manager.receivers[0] == bot.bot_id and manager.receive_dives[0], "An otherwise unreachable low ball is assigned to a real diving save")
 # Full predictor + autonomous controller + real rigid ball, with no forced assignment.
 manager.reset_rally()
 bot.position = Vector3(0, 0.02, 4)
 bot.velocity = Vector3.ZERO
 bot.reset_plan()
 bot.set_physics_process(true)
 await frames(5)
 manager.last_team = 1
 manager.last_kind = 2
 manager.last_touch_time = manager.clock
 manager.set_physics_process(true)
 game.ball.feed(Vector3(2.2, 2.6, 4), Vector3(0, -1, 0), Vector3.ZERO)
 await frames(2)
 manager.predict()
 var before := bot.dives
 var touched := int(bot.contact_kinds.get(7, 0))
 for i in range(180):
  await physics_frame
  if int(bot.contact_kinds.get(7, 0)) > touched:
   break
 print("AUTONOMOUS DIVE attempts=", bot.dives - before, " contacts=", int(bot.contact_kinds.get(7, 0)) - touched)
 check(bot.dives > before, "The autonomous bot actually dives without a test assigning its receiver or destination")
 check(int(bot.contact_kinds.get(7, 0)) > touched, "The autonomous dive makes a physical contact on the falling ball")
 await frames(160)
 # Prepare the block before an opponent's strike, from the regular front position.
 game.lower_serve.cancel_sequence()
 game.float_serve.cancel_sequence()
 manager.reset_rally()
 bot.position = Vector3(0, 0.02, 2.7)
 bot.velocity = Vector3.ZERO
 bot.landing_cooldown = 0
 game.athlete.position = Vector3(0, 0.8, -1.3)
 game.athlete.velocity = Vector3.ZERO
 game.athlete.cancel_input()
 game.athlete.action = VolleyAthlete.Action.IDLE
 game.athlete.approach_jump = true
 game.athlete.begin_action(2)
 game.ball.pending_feed = false
 game.ball.held = false
 game.ball.freeze = true
 game.ball.position = Vector3(0, 3.2, -1.4)
 game.ball.linear_velocity = Vector3.ZERO
 manager.last_team = 1
 manager.last_kind = 0
 manager.touches = 2
 manager.last_touch_time = manager.clock
 var initial_depth := bot.position.z
 before = bot.jumps
 for i in range(120):
  await physics_frame
  if bot.block_held:
   break
 check(bot.position.z < initial_depth - 0.8, "A normal front-row bot moves to the net while the opponent winds up")
 check(bot.jumps > before and bot.block_held and bot.airborne(), "The bot jumps with raised blocking hands before the spike is struck")
 bot.end_block()
 bot.reset_plan()
 bot.position = Vector3(0, 0.02, 0.7)
 bot.velocity = Vector3.ZERO
 manager.last_kind = 4
 manager.touches = 1
 game.athlete.cancel_input()
 game.athlete.action = VolleyAthlete.Action.IDLE
 game.ball.position = Vector3(0, 3.2, -2)
 game.ball.linear_velocity = Vector3(0, -1, 9)
 check(manager.tactics.block_plan(bot).is_empty(), "A jump serve does not trigger an illegal block")
 manager.configure({"counts": [0, 0]})
 game.queue_free()
 await frames(3)
 print("V23 TESTS PASSED (%d checks)" % checks if failures == 0 else "V23 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)

