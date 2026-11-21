extends SceneTree
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
func trial(level: int, setting: bool) -> void:
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 game.athlete.set_physics_process(false)
 game.athlete.position = Vector3(3, 0.02, 4)
 var manager: VolleyGameBots = game.game_bots
 manager.configure({"counts": [1, 0], "difficulty": level, "human_team": 0})
 var bot: VolleyGameBot = manager.bots[-100]
 bot.position = Vector3(0, 0.02, 1.8 if setting else 5)
 bot.velocity = Vector3.ZERO
 for i in range(5):
  await physics_frame
 manager.reset_rally()
 if setting:
  manager.note_touch(game.athlete, 1)
 game.ball.feed(Vector3(0, 4.8, 1.6 if setting else 4.8), Vector3(0, -1, 0))
 for i in range(170):
  await physics_frame
  if bot.contacts > 0:
   break
 print("CONTROL level=%d set=%s contacts=%d kind=%d jumps=%d" % [level, setting, bot.contacts, bot.strike_technique, bot.jumps])
 check(bot.contacts > 0, "Reachable descending ball is physically touched at level %d / set %s" % [level, setting])
 if setting and level >= 2:
  check(bot.contact_kinds.has(ContextAthlete.JUMP_SET) and bot.jumps > 0, "High second touch uses an actual jump set")
 if setting and level < 2:
  check(bot.contact_kinds.has(0) and bot.jumps == 0, "Beginner keeps a simple grounded set")
 game.queue_free()
 for i in range(3):
  await physics_frame
func run() -> void:
 for level in range(5):
  await trial(level, false)
  await trial(level, true)
 print("V28 TESTS PASSED (%d checks)" % checks if failures == 0 else "V28 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
