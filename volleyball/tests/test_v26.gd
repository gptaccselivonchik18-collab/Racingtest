extends SceneTree
var checks := 0
var failures := 0
var game: Node3D
var manager: VolleyGameBots

func _initialize() -> void:
 call_deferred("run")
func check(ok: bool, note: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", note)
 else:
  failures += 1
  push_error("FAIL: " + note)
func freeze() -> void:
 manager.set_physics_process(false)
 for bot in manager.bots.values():
  bot.set_physics_process(false)
  bot.velocity = Vector3.ZERO
 game.athlete.set_physics_process(false)
 game.athlete.velocity = Vector3.ZERO
func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 game.set_physics_process(false)
 manager = game.game_bots
 manager.configure({"counts": [1, 3], "difficulty": 4, "human_team": 1})
 freeze()
 var server: VolleyGameBot = manager.bots[-100]
 server.position = Vector3(0, 0.02, 9.7)
 var opponents := manager.members(1)
 for i in range(opponents.size()):
  opponents[i].position = Vector3(-2.5, 0.02, -2.5 - i * 1.6)
 var qualities := []
 for difficulty in [0, 4]:
  manager.difficulty = difficulty
  server.rng.seed = 26026
  server.serve_history.clear()
  var quality := 0.0
  var right := 0
  var legal := true
  var zones: Dictionary = {}
  for i in range(180):
   server.serve_aim = Vector3.INF
   var aim := manager.tactics.serve_target(server)
   quality += manager.tactics.coverage_at(aim + Vector3(0, 0, 0.8), opponents, 1.0)
   right += int(aim.x > 1)
   zones[str(aim)] = true
   legal = legal and game.lower_serve.opposite_target(aim, 1.0) and absf(aim.x) <= 3.3 and absf(aim.z) <= 7.7
  qualities.append(quality / 180)
  print("SERVE THINKING level=", difficulty, " open_space=", quality / 180, " right=", right, " zones=", zones.size())
  check(legal, "All planned deliveries stay safely inside the opposite court at level %d" % difficulty)
  check(zones.size() >= 4, "Serving changes both lane and depth instead of locking one target at level %d" % difficulty)
  if difficulty == 4:
   check(right > 140, "Expert serves exploit the unguarded right half")
 check(float(qualities[1]) > float(qualities[0]) + 0.6, "Expert placement outthinks novice placement with exactly the same physical skills")
 check(server.stats.values.serve == 140, "The decision comparison does not improve physical stats between runs")
 manager.difficulty = 4
 server.serve_history.clear()
 server.serve_aim = Vector3.INF
 server.rng.seed = 1234
 var before := manager.tactics.serve_target(server)
 for opponent in opponents:
  opponent.position.x = 2.5
 check(manager.tactics.serve_target(server) == before, "The committed target cannot follow a moving receiver during the toss")
 server.serve_aim = Vector3.INF
 server.serve_history.clear()
 server.rng.seed = 1234
 var after := manager.tactics.serve_target(server)
 check(before.x > 1 and after.x < -1, "The next serve reacts to a changed receiving formation")
 var human: ContextAthlete = game.athlete
 var other: ContextAthlete = manager.bots[-106]
 human.position = Vector3(-3, 0.02, -5)
 other.position = Vector3(3, 0.02, -5)
 server.serve_aim = Vector3.INF
 server.serve_history.clear()
 server.rng.seed = 35
 before = manager.tactics.serve_target(server)
 var saved := human.position
 human.position = other.position
 other.position = saved
 server.serve_aim = Vector3.INF
 server.serve_history.clear()
 server.rng.seed = 35
 check(manager.tactics.serve_target(server) == before, "Swapping human and bot identities cannot change serving priority")
 server.serve_history.clear()
 for i in range(15):
  server.serve_aim = Vector3.INF
  manager.tactics.serve_target(server)
 check(server.serve_history.size() == 3, "Serve memory stays bounded across long matches")
 server.court_team = 1
 server.position.z = -9.7
 server.serve_aim = Vector3.INF
 check(manager.tactics.serve_target(server).z > 0, "Serving also targets the correct half from the opposite baseline")
 server.court_team = 0
 manager.configure({"counts": [3, 3], "difficulty": 4, "human_team": 0})
 freeze()
 var setter: VolleyGameBot = manager.bots[-100]
 var near: VolleyGameBot = manager.bots[-101]
 var wing: VolleyGameBot = manager.bots[-102]
 setter.position = Vector3(0, 0.02, 3)
 near.position = Vector3(0, 0.02, 3.4)
 wing.position = Vector3(-2.1, 0.02, 1.8)
 human.position = Vector3(7, 0.02, 10)
 for opponent in manager.members(1):
  opponent.position = Vector3(2.1, 0.02, -1)
 manager.last_team = 0
 manager.touches = 1
 manager.last_touch_time = 10
 manager.difficulty = 0
 manager.tactics.plans.clear()
 check(manager.tactics.pass_plan(setter, 0).recipient == near, "A novice chooses the nearby available teammate")
 manager.difficulty = 4
 manager.tactics.plans.clear()
 check(manager.tactics.pass_plan(setter, 0).recipient == wing, "An expert chooses the ready attacker in the less-blocked lane")
 check(setter.stats.values.set == 140, "Pass choice differs with intelligence alone, not stronger Set")
 var plan := manager.tactics.pass_plan(setter, 0)
 near.position = Vector3(-3, 0.02, 1.5)
 check(manager.tactics.pass_plan(setter, 0).recipient == plan.recipient, "A selected attacker remains reserved for the ongoing combination")
 manager.tactics.plans.clear()
 manager.last_team = 1
 manager.last_kind = 0
 manager.touches = 2
 game.ball.held = false
 game.ball.position = Vector3(0, 3.1, -1.5)
 game.ball.linear_velocity = Vector3(0, -1, 0)
 setter.position = Vector3(0, 0.02, 0.7)
 near.position = Vector3(4, 0.02, 7)
 wing.position = Vector3(-4, 0.02, 7)
 var attacker: ContextAthlete = manager.bots[-106]
 attacker.position = Vector3(0, 0.6, -1.5)
 attacker.action = VolleyAthlete.Action.PREPARE
 attacker.technique = VolleyAthlete.Technique.SPIKE
 manager.difficulty = 0
 check(manager.tactics.block_plan(setter).is_empty(), "Novice blockers do not read the opponent's preparation like professionals")
 manager.difficulty = 4
 check(not manager.tactics.block_plan(setter).is_empty(), "Expert blockers prepare while an opponent visibly winds up")
 setter.block_held = true
 manager.difficulty = 0
 var basic := manager.tactics.support(wing)
 manager.difficulty = 4
 var advanced := manager.tactics.support(wing)
 check(advanced.distance_to(basic) > 0.25, "Expert defenders cover around a teammate's block instead of only staying home")
 check(advanced.z > 0 and absf(advanced.x) < 4, "Defensive coverage preserves its own half and court bounds")
 var lane := Vector3(0, VolleyBall.RADIUS, -7)
 attacker.position = Vector3(0, 0.7, -0.7)
 attacker.block_held = true
 check(manager.tactics.block_obstruction(Vector3(0, 3, 1.5), lane, [attacker]) > manager.tactics.block_obstruction(Vector3(0, 3, 1.5), Vector3(3.3, VolleyBall.RADIUS, -3.2), [attacker]), "Attack planning distinguishes a visible blocking lane from an open diagonal")
 var previous := -1.0
 for level in range(5):
  var profile := VolleyBotDifficulty.profile(level)
  check(float(profile.court_read) > previous and float(profile.lookahead) >= 0.9, "Each difficulty has a distinct tactical reading level %d" % level)
  previous = float(profile.court_read)
 game.queue_free()
 await process_frame
 print("V26 TESTS PASSED (%d checks)" % checks if failures == 0 else "V26 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
