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
func match_level(level: int) -> void:
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 game.athlete.set_physics_process(false)
 game.athlete.position = Vector3(7, 0.02, 11)
 var manager: VolleyGameBots = game.game_bots
 manager.configure({"counts": [3, 3], "difficulty": level})
 manager.human_team = -1
 game.lower_serve.rng.seed = 290001 + level
 game.float_serve.rng.seed = 290101 + level
 manager.solo_match = true
 manager.serve_team = 0
 manager.reset_service(0)
 manager.reset_round()
 for frame in range(30 * 120):
  await physics_frame
 var contacts := [0, 0]
 var skills_ok := true
 for bot in manager.bots.values():
  # Automatic lower/float serves use the same contact counter as humans;
  # bot.contacts only counts the swept-contact override (excludes serves).
  contacts[bot.court_team] += bot.contact_count
  skills_ok = skills_ok and bot.stats.values.speed == VolleyBotDifficulty.SKILLS[level]
 print("LEVEL MATCH ", level, " contacts=", contacts)
 check(contacts[0] >= 2 and contacts[1] >= 2, "Both teams execute physical contacts at level %d" % level)
 check(skills_ok, "Execution does not secretly raise physical stats at level %d" % level)
 game.queue_free()
 for i in range(3):
  await physics_frame
func run() -> void:
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 var manager: VolleyGameBots = game.game_bots
 manager.configure({"counts": [5, 3], "difficulty": 0})
 manager.set_physics_process(false)
 for bot in manager.bots.values():
  bot.set_physics_process(false)
  bot.position = manager.home(bot.court_team, bot.slot)
 var setter: VolleyGameBot = manager.bots[-100]
 var human: ContextAthlete = game.athlete
 human.position = Vector3(2, 0.02, 6)
 human.velocity = Vector3.ZERO
 var aim := manager.tactics.pass_point(human, setter, true)
 check(aim.z < human.position.z - 1.2 and aim.z > 0, "Stationary human gets a forward set for a run-up")
 var poses := []
 var roles := []
 for bot in manager.members(0):
  poses.append(manager.home(0, poses.size()))
  roles.append(manager.role_for(bot))
 manager.advance_service(0, 1)
 check(manager.home(0, 0) != poses[0] and manager.role_for(setter) != roles[0], "Side-out rotates court positions and roles")
 var rotation := manager.rotation_turn.duplicate()
 manager.advance_service(0, 0)
 check(manager.rotation_turn == rotation, "Holding serve does not cause an extra rotation")
 manager.place_team(0)
 var locations := {}
 for actor in manager.members(0):
  locations[str(actor.position)] = true
 check(locations.size() == manager.members(0).size(), "Mixed human/bot rotation has unique court places")
 manager.last_team = 0
 manager.touches = 1
 var counts := {}
 var reserved := true
 for i in range(20):
  manager.tactics.runs.clear()
  manager.tactics.prepare_runs(setter)
  var options: Dictionary = manager.tactics.runs[0]
  counts[options.size()] = true
  for bot in manager.bots.values():
   if options.has(bot.get_instance_id()):
    var run: Dictionary = options[bot.get_instance_id()]
    var start: Vector3 = manager.tactics.support(bot)
    reserved = reserved and start.z > Vector3(run.target).z + 0.9
 check(reserved, "Several attackers stage behind their planned contact for a run-up")
 check(counts.size() > 1, "The number of approach options varies between combinations")
 manager.tactics.runs.clear()
 var safe := true
 for i in range(80):
  setter.serve_aim = Vector3.INF
  var target := manager.tactics.serve_target(setter)
  safe = safe and absf(target.x) < 2.2 and absf(target.z) <= 6.1
 check(safe, "Novice serves aim with enough margin for low Serve accuracy")
 game.queue_free()
 for i in range(3):
  await physics_frame
 for level in range(5):
  await match_level(level)
 print("V29 TESTS PASSED (%d checks)" % checks if failures == 0 else "V29 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
