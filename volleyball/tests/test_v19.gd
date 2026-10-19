extends SceneTree
var game: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")
func frames(n: int) -> void:
 for i in range(n):
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
 var original_stats: Dictionary = game.athlete.stats.values.duplicate()
 game.hud.set_process(false)
 game.athlete.position = Vector3(-7.5, 0.02, 11)
 await frames(4)
 var manager: VolleyGameBots = game.game_bots
 var ball: VolleyBall = game.ball
 check(manager.configure({"counts": [6, 6]}), "Both bot teams can be filled independently")
 check(manager.bots.size() == 12 and ball.contact_athletes.size() == 13, "Twelve game bots join physical ball contacts")
 for team in range(2):
  for slot in range(6):
   var bot: VolleyGameBot = manager.bots[VolleyGameBots.bot_id(team, slot)]
   check(bot.court_team == team and bot.slot == slot and not bot.replica and bot.is_physics_processing(), "Bot %d/%d has an authoritative team and physical actor" % [team, slot])
 check(not manager.configure({"counts": [7, 1]}) and not manager.configure({"counts": [-1, 1]}) and not manager.configure({"counts": [1.5, 2]}), "Invalid counts cannot overflow the bot roster")
 check(not manager.configure({"level": NAN}), "Nonfinite skill values are rejected")
 manager.configure({"level": 130})
 check(manager.bots[-100].stats.values.serve == 130 and manager.bots[-106].stats.values.block == 130, "All eight bot skills use the same character system")
 manager.configure({"level": 65, "counts": [3, 3]})
 game.practice.configure({"enabled": true, "modes": [1], "interval": 12})
 check(game.practice.bot in ball.contact_athletes and manager.bots.size() == 6 and ball.contact_athletes.size() == 8, "Training bot and game bots coexist in free play")
 game.practice.configure({"enabled": false})
 ball.feed(Vector3(1, 4, 5), Vector3(0, -2, -2))
 var bumps := 0
 var diving_receives := 0
 var sets := 0
 var spikes := 0
 var jumps := 0
 var both_teams := [0, 0]
 for tick in range(4800):
  await physics_frame
 for bot in manager.bots.values():
  bumps += int(bot.contact_kinds.get(1, 0))
  diving_receives += int(bot.contact_kinds.get(ContextAthlete.DIVE, 0))
  sets += int(bot.contact_kinds.get(0, 0))
  spikes += int(bot.contact_kinds.get(2, 0))
  jumps += bot.jumps
  both_teams[bot.court_team] += bot.contact_count
 print("BOT RALLY: bump=%d dive=%d set=%d spike=%d jumps=%d contacts=%s" % [bumps, diving_receives, sets, spikes, jumps, str(both_teams)])
 check(bumps + diving_receives >= 2, "Autonomous bots run to and receive freely moving balls with standing or diving saves")
 check(sets >= 1 and spikes >= 1 and jumps >= 1, "Autonomous play combines reception, set and a real jump attack")
 check(both_teams[0] > 0 and both_teams[1] > 0, "Both teams participate without human commands")
 check(not game.rules.ended, "Solo free play has no match faults or forced restarts")
 manager.configure({"counts": [0, 1]})
 game.lower_serve.cancel_sequence()
 game.float_serve.cancel_sequence()
 if ball.held:
  ball.drop()
 var server: VolleyGameBot = manager.bots[-106]
 server.reset_plan()
 server.position = Vector3(0, 0.02, -5)
 ball.feed(Vector3(0.4, 0.25, -5), Vector3.ZERO)
 var picked_up := false
 var crossed := false
 var possession_safe := false
 for tick in range(2100):
  await physics_frame
  picked_up = picked_up or (ball.held and ball.athlete == server)
  if ball.held and ball.athlete == server:
   possession_safe = not game.begin_primary() and not game.begin_secondary()
   game.pickup_or_drop()
   possession_safe = possession_safe and ball.held and ball.athlete == server
  crossed = crossed or (server.serves > 0 and ball.position.z > 0 and not ball.held)
  if crossed:
   break
 check(picked_up, "A bot retrieves a resting real ball, without teleporting it into a rally")
 check(possession_safe, "Human attack/pass/pickup buttons cannot toss or drop a bot's held ball")
 check(server.serves > 0 and server.contact_count > 0, "After retrieval a bot walks behind the line and performs a real serve")
 check(crossed, "An autonomous serve crosses into the opposing half")
 game.lower_serve.cancel_sequence()
 game.float_serve.cancel_sequence()
 server.serves = 3
 # Risky jump serves are now selected only at strong/pro tactical levels.
 # Keep the physical skill fixture unchanged while enabling that decision.
 manager.difficulty = 3
 server.prepare_serve()
 for tick in range(800):
  await physics_frame
  if int(server.contact_kinds.get(4, 0)) > 0:
   break
 check(int(server.contact_kinds.get(4, 0)) > 0 and server.air_attack, "Bot jump serve uses its own toss, takeoff and actual hand contact")
 game.lower_serve.cancel_sequence()
 game.float_serve.cancel_sequence()
 if ball.held:
  ball.drop()
 manager.reset_rally()
 server.position = Vector3(0, 0.02, -0.7)
 server.velocity = Vector3.ZERO
 await frames(5)
 manager.last_team = 0
 manager.last_kind = VolleyAthlete.Technique.SPIKE
 var previous_jumps := server.jumps
 game.athlete.strike_technique = VolleyAthlete.Technique.SPIKE
 game.athlete.quality = 0.9
 ball.feed(Vector3(0, 3.2, 1.2), Vector3(0, -0.3, -6))
 await frames(2)
 ball.remember_contact(game.athlete)
 await frames(90)
 print("BOT BLOCK: jumps=%d previous=%d kinds=%s" % [server.jumps, previous_jumps, str(server.contact_kinds)])
 check(server.jumps > previous_jumps and int(server.contact_kinds.get(6, 0)) > 0, "Front-row bot jumps and makes a real block against an opposing spike")
 manager.reset_rally()
 manager.set_physics_process(false)
 game.lower_serve.cancel_sequence()
 game.float_serve.cancel_sequence()
 if ball.held:
  ball.drop()
 server.position = Vector3(0, 0.02, -4)
 server.velocity = Vector3.ZERO
 server.set_physics_process(false)
 ball.feed(Vector3(1.8, 0.9, -4), Vector3(-1, -1, 0))
 await frames(4)
 server.set_physics_process(true)
 manager.last_team = 0
 manager.receivers[1] = server.bot_id
 manager.intercepts[1] = Vector3(1.4, 0.02, -4)
 manager.arrival[1] = manager.clock + 0.1
 server.noticed_touch = manager.last_touch_time
 server.reaction_until = manager.clock
 await frames(70)
 print("BOT DIVE: attempts=%d kinds=%s state=%s" % [server.dives, str(server.contact_kinds), server.state])
 check(server.dives > 0 and int(server.contact_kinds.get(7, 0)) > 0, "Bot chooses a real diving save for a low ball beyond standing reach")
 manager.set_physics_process(true)
 manager.reset_rally()
 if ball.held:
  ball.drop()
 game.athlete.position = Vector3(0, 0.02, 6)
 game.athlete.velocity = Vector3.ZERO
 ball.feed(Vector3(0, 0.25, 6), Vector3.ZERO)
 await frames(4)
 ball.athlete = game.athlete
 check(ball.pick_up(), "Human can hold the shared ball with game bots enabled")
 var served := server.serves
 await frames(180)
 check(ball.held and ball.athlete == game.athlete and server.serves == served, "Game bots never steal a human-held ball")
 ball.drop()
 manager.configure({"counts": [0, 0]})
 check(manager.bots.is_empty() and ball.contact_athletes == [game.athlete], "Removing bots removes their collision and prediction participants")
 # Every solid boundary is tested with a fast live rigid body, including roof.
 for velocity in [Vector3(45, 3, 0), Vector3(-45, 3, 0), Vector3(0, 3, 45), Vector3(0, 3, -45), Vector3(0, 48, 0)]:
  ball.feed(Vector3(0, 2, 4), velocity)
  var contained := true
  for tick in range(240):
   await physics_frame
   contained = contained and absf(ball.position.x) < 8.21 and absf(ball.position.z) < 12.21 and ball.position.y < VolleyCourt.ROOF + 0.01
  check(contained, "Hall contains a fast ball launched %s" % str(velocity))
 game.athlete.position = Vector3(7.3, 0.02, 10.7)
 game.athlete.velocity = Vector3.ZERO
 ball.feed(Vector3(7.98, 0.25, 11.4), Vector3.ZERO)
 await frames(5)
 check(ball.can_pick_up_for(game.athlete), "A ball stopped beside the boundary remains reachable for pickup")
 manager.configure({"counts": [1, 1]})
 check(manager.start_solo() and manager.solo_match and game.rules.strict, "A scored solo team match can start with bots")
 # The human now serves first. Select the next rotation slot to exercise
 # the bot's physical pickup and missed-toss recovery below.
 manager.serving_turn[manager.serve_team] = 1
 manager.reset_round()
 check(manager.bots[-100].is_server, "A bot can be selected as the formal match server")
 var match_server: VolleyGameBot = manager.bots[-100]
 for tick in range(120):
  await physics_frame
  if ball.held and ball.athlete == match_server:
   break
 check(ball.held and match_server.is_server, "A nominated server retains its role after physically picking up the ball")
 game.lower_serve.cancel_sequence()
 game.float_serve.cancel_sequence()
 ball.drop()
 ball.feed(match_server.position + Vector3(0, 0.25, -0.5), Vector3.ZERO)
 game.rules.reset(true)
 game.rules.floor_contact(ball.feed_position)
 var previous_contacts := match_server.contact_count
 for tick in range(1200):
  await physics_frame
  if match_server.contact_count > previous_contacts:
   break
 check(match_server.contact_count > previous_contacts and not match_server.is_server, "A missed first toss is retrieved and served again without stalling the match")
 manager.last_team = 0
 manager.on_floor(Vector3(0, VolleyBall.RADIUS, -4))
 check(manager.scores == [1, 0] and manager.round_wait > 0, "Solo bot matches award points and schedule a new rally")
 manager.on_floor(Vector3(0, VolleyBall.RADIUS, -4))
 check(manager.scores == [1, 0], "A resting ball cannot award repeated points")
 manager.end_solo()
 game.lan.host_room(24923)
 manager.configure({"counts": [1, 1]})
 game.athlete.position = Vector3(6.5, 0.02, 3)
 game.athlete.velocity = Vector3.ZERO
 game.lan._spawn(999, 1, 0)
 var guest: ContextAthlete = game.lan.players[999].actor
 guest.set_physics_process(false)
 guest.position = Vector3(0, 0.02, -4)
 game.lan.ready_seconds = 4
 check(not game.lan.begin_match(), "Bots cannot replace the consent of a human outside the selection zone")
 guest.position = Vector3(6.5, 0.02, -3)
 game.lan.ready_seconds = 4
 var ready: Dictionary = game.lan.readiness()
 check(ready.totals == [2, 2] and game.lan.begin_match(), "Consenting humans and bots form two mixed teams")
 check(manager.current_server == game.athlete and not manager.bots[-100].is_server, "LAN rounds include the human first instead of always selecting a bot server")
 manager.configure({"counts": [2, 2]})
 check(not game.lan.match_active, "Changing bot composition returns a running room to free play for fresh consent")
 game.lan.leave()
 check(manager.bots.is_empty(), "Leaving a room removes shared bots and stale references")
 # Mobile menu has a single category selector and direct controls in cards.
 root.size = Vector2i(844, 390)
 root.content_scale_size = root.size
 await process_frame
 game.hud._layout()
 check(game.hud.category_picker.item_count == 8 and game.hud.tabs.get_tab_title(7) == "Звук" and not game.hud.tabs.tabs_visible, "All settings categories, including sound, are reachable from a compact selector")
 check(game.hud.stat_grid.columns == 2, "Landscape phones show two stat cards per row")
 game.hud.stat_sliders["set"].value = 143
 game.hud.stat_sliders.bump.value = -12
 check(game.athlete.stats.values["set"] == 143 and game.athlete.stats.values.bump == -12, "New stat cards preserve unrestricted experimentation")
 for key in original_stats:
  game.athlete.stats.set_stat(key, original_stats[key])
 game.hud.settings.save(game.athlete)
 game.queue_free()
 await frames(3)
 print("V19 TESTS PASSED (%d checks)" % checks if failures == 0 else "V19 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
