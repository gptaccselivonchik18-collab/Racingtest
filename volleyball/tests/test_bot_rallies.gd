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
func match_scenario(count: int, seconds: int) -> void:
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 # Fix delivery scatter as well as player RNG, so CI replays the same match.
 game.lower_serve.rng.seed = 260001 + count
 game.float_serve.rng.seed = 260101 + count
 game.hud.set_process(false)
 game.rig.set_process(false)
 game.athlete.set_physics_process(false)
 game.athlete.position = Vector3(7, 0.02, 11)
 var manager: VolleyGameBots = game.game_bots
 manager.configure({"counts": [count, count], "difficulty": 4})
 # An all-bot scrimmage isolates decision quality from an idle test human.
 manager.human_team = -1
 manager.solo_match = true
 manager.serve_team = 0
 manager.reset_service(0)
 manager.reset_round()
 var prior := [0, 0]
 var previous_contacts := 0
 var rally_contacts := 0
 var longest := 0
 var net_faults := 0
 var double_faults := 0
 for frame in range(seconds * 120):
  await physics_frame
  var contacts := 0
  for bot in manager.bots.values():
   contacts += bot.contact_count
   check_finite(bot)
  rally_contacts += contacts - previous_contacts
  previous_contacts = contacts
  if manager.scores != prior:
   longest = maxi(longest, rally_contacts)
   rally_contacts = 0
   prior = manager.scores.duplicate()
   net_faults += int("Касание сетки" in game.rules.message)
   double_faults += int("Двойное" in game.rules.message or "Четыре" in game.rules.message or "своей подачи" in game.rules.message)
 longest = maxi(longest, rally_contacts)
 var team_contacts := [0, 0]
 var kinds: Dictionary = {}
 var active := 0
 var jumps := 0
 var dives := 0
 for bot in manager.bots.values():
  team_contacts[bot.court_team] += bot.contact_count
  active += int(bot.contact_count > 0)
  jumps += bot.jumps
  dives += bot.dives
  for kind in bot.contact_kinds:
   kinds[kind] = int(kinds.get(kind, 0)) + int(bot.contact_kinds[kind])
 print("SCRIMMAGE %dv%d contacts=%s longest=%d net_faults=%d rule_faults=%d kinds=%s jumps=%d dives=%d" % [count, count, team_contacts, longest, net_faults, double_faults, kinds, jumps, dives])
 check(team_contacts[0] >= 3 and team_contacts[1] >= 3, "Both teams sustain real physical play in %dv%d at maximum difficulty" % [count, count])
 check(longest >= (6 if count > 1 else 4), "Both teams complete multi-touch rallies instead of losing every first return")
 check(net_faults <= 2 and double_faults <= 2, "Bot rallies are not repeatedly ended by net collisions or illegal team contacts")
 if count > 1:
  check(active >= 5, "Front and rear teammates participate rather than leaving most bots idle")
  check(int(kinds.get(0, 0)) + int(kinds.get(ContextAthlete.JUMP_SET, 0)) >= 4 and int(kinds.get(2, 0)) >= 4, "Teams repeatedly construct grounded/jump sets followed by genuine attacks")
  # Better court coverage can remove every need to dive in a seeded rally.
  # Dedicated v19/v23 tests still require an actual physical diving save.
  check(jumps >= 4, "Blocking/attacking jumps occur during an unassisted match")
 else:
  check(int(kinds.get(2, 0)) > 0, "A lone bot attacks legal high balls instead of only exchanging lower receives forever")
 game.queue_free()
 for i in range(4):
  await physics_frame
func check_finite(bot: VolleyGameBot) -> void:
 if not bot.position.is_finite() or not bot.velocity.is_finite():
  push_error("Bot physics became non-finite during an autonomous scrimmage")
  quit(1)
func run() -> void:
 await match_scenario(3, 60)
 await match_scenario(1, 60)
 await match_scenario(6, 90)
 print("BOT RALLIES PASSED (%d checks)" % checks if failures == 0 else "BOT RALLIES FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
