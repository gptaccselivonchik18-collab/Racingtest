extends SceneTree
var game: Node3D
var manager: VolleyGameBots
var a: ContextAthlete
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
func freeze_bots() -> void:
 manager.set_physics_process(false)
 for bot in manager.bots.values():
  bot.set_physics_process(false)
func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 game.set_physics_process(false)
 a = game.athlete
 a.set_physics_process(false)
 manager = game.game_bots
 manager.configure({"counts": [2, 2]})
 freeze_bots()
 for bot in manager.bots.values():
  bot.position = Vector3(3, 0.02, -6)
 a.position = Vector3(0, 0.02, 6)
 game.ball.athlete = manager.bots[-106]
 game.ball.feed(Vector3(0.2, 0.25, 6), Vector3.ZERO)
 await frames(5)
 check(game.ball.can_pick_up_for(a) and not game.ball.can_pick_up(), "Reproduce a lit human pickup button with the last bot still bound to the ball")
 game.ball.replica = true
 game.ball.pending_feed = true
 game.ball.last_velocity = Vector3.ZERO
 check(game.ball.can_pick_up_for(a), "A network replica ignores a stale local feed when displaying human pickup availability")
 game.ball.replica = false
 game.ball.pending_feed = false
 game.pickup_or_drop()
 check(game.holding_ball() and game.ball.athlete == a and a.holding_ball, "The actual human button picks up the ball after a bot's turn")
 check(not manager.bots[-106].holding_ball, "Pickup transfers ownership without giving the old bot a held flag")
 game.ball.drop()
 await frames(5)
 check(manager.tactics.human_pickup_near(), "Bots recognize a slow ball already within human pickup reach")
 manager.bots[-100].position = Vector3(0.5, 0.02, 6)
 manager.bots[-100].decide(0.01)
 check(not game.ball.held and manager.bots[-100].state != "retrieve", "A teammate yields a resting nearby ball to the human")
 # All eight skills and decision timings follow one difficulty choice.
 var previous := -INF
 for difficulty in range(5):
  check(manager.configure({"difficulty": difficulty}), "Difficulty preset %d is accepted" % difficulty)
  var bot: VolleyGameBot = manager.bots[-100]
  check(bot.stats.values.spike > previous and bot.stats.values.spike == VolleyBotDifficulty.SKILLS[difficulty], "Increasing difficulty raises the bot's real character skills")
  previous = bot.stats.values.spike
  for key in VolleyStyleStats.KEYS:
   check(bot.stats.values[key] == VolleyBotDifficulty.SKILLS[difficulty], "Preset controls " + key)
  var state := manager.settings_state()
  check(state.difficulty == difficulty and manager.configure(state, false) and bot.stats.values.spike == previous, "Difficulty and its derived skills survive network settings round-trip")
 check(not manager.configure({"difficulty": -1}) and not manager.configure({"difficulty": 5}) and not manager.configure({"difficulty": 1.5}), "Invalid difficulty values cannot corrupt the roster")
 check(VolleyBotDifficulty.profile(4).reaction < VolleyBotDifficulty.profile(0).reaction and VolleyBotDifficulty.profile(4).anticipation > VolleyBotDifficulty.profile(0).anticipation, "Higher levels react sooner and anticipate reachable balls farther ahead")
 manager.configure({"counts": [2, 0], "difficulty": 2})
 freeze_bots()
 manager.reset_rally()
 a.position = Vector3(7, 0.02, 10)
 var first: VolleyGameBot = manager.bots[-100]
 var second: VolleyGameBot = manager.bots[-101]
 first.position = Vector3(0, 0.02, 4)
 second.position = first.position
 var one := manager.tactics.spaced_axis(first, Vector2.ZERO)
 var two := manager.tactics.spaced_axis(second, Vector2.ZERO)
 check(one.dot(two) < -0.5, "Even exactly overlapping bots choose opposite escape directions")
 second.position.x = 0.7
 one = manager.tactics.spaced_axis(first, Vector2.ZERO)
 two = manager.tactics.spaced_axis(second, Vector2.ZERO)
 check(one.x < 0 and two.x > 0, "Nearby teammates repel within their personal space")
 a.position = Vector3(-0.6, 0.02, 4)
 one = manager.tactics.spaced_axis(first, Vector2.ZERO)
 check(one.x > -0.2, "Bot spacing also accounts for human teammates")
 a.position = Vector3(7, 0.02, 10)
 manager.last_team = 1
 manager.clock = 10
 manager.samples = [{"at": Vector3(0.1, 1.35, 3.6), "v": Vector3(0, -2, 0), "time": 0.6}]
 manager.receivers = [0, 0]
 manager.tactics.choose_receivers()
 var receiver: int = manager.receivers[0]
 check(receiver in [first.bot_id, second.bot_id], "Exactly one bot claims a reception corridor")
 for i in range(8):
  first.position.x += 0.015
  second.position.x -= 0.015
  manager.clock += 0.04
  manager.tactics.choose_receivers()
  check(manager.receivers[0] == receiver, "Tiny prediction changes do not alternate the receiving bot")
 first.reaction_until = 0
 second.reaction_until = 0
 first.noticed_touch = manager.last_touch_time
 second.noticed_touch = manager.last_touch_time
 game.ball.feed(Vector3(0.1, 2, 3.6), Vector3(0, -2, 0))
 await frames(3)
 first.decide(0.01)
 second.decide(0.01)
 check(int(first.state == "intercept") + int(second.state == "intercept") == 1, "Only the assigned receiver chases the ball; the other covers")
 # Real people participate in reception and attacking plans.
 manager.configure({"counts": [1, 0], "difficulty": 4})
 freeze_bots()
 manager.reset_rally()
 first = manager.bots[-100]
 first.position = Vector3(0, 0.02, 4)
 a.position = Vector3(2, 0.02, 5)
 a.velocity = Vector3(1.5, 0, -0.8)
 manager.arrival[0] = manager.clock + 0.6
 var reception := manager.target_for(first, VolleyAthlete.Technique.UNDERHAND)
 check(reception.z > 0 and reception.y > 1.8, "A lone bot receives a serve into a comfortable human setup on its own side")
 check(reception.x > a.position.x and reception.z < a.position.z, "Pass lead uses the human's measured movement")
 check(manager.tactics.pass_plan(first, 1).recipient == a, "A real human is a full participant in teammate selection")
 # Check the actual contact and rigid body reach the planned receive height.
 a.velocity = Vector3.ZERO
 manager.tactics.plans.clear()
 first.cancel_input()
 first.action = VolleyAthlete.Action.IDLE
 first.camera_yaw = 0
 first.visual.rotation = Vector3.ZERO
 first.begin_action(1)
 first.charged_for = 0.2
 first.release()
 first.action_time = first.strike_duration * 0.47
 first._update_pose(0)
 first.previous_wrists = first.wrists.duplicate()
 first.previous_elbows = first.elbows.duplicate()
 var target := manager.target_for(first, 1)
 var point := first.wrists[1]
 var incoming := Vector3(0, -2, 1)
 var outgoing := incoming + first.try_contact(point, incoming)
 var spin := first.outgoing_spin(Vector3.ZERO, outgoing - incoming)
 check(first.hit_used and first.strike_technique == 1 and outgoing.y > 0, "Reception remains a physical lower contact, not an automatic serve over the net")
 game.ball.feed(point, outgoing, spin)
 var near := INF
 var own_side := true
 for i in range(360):
  await physics_frame
  own_side = own_side and game.ball.position.z > 0
  if game.ball.linear_velocity.y < 0:
   near = minf(near, game.ball.position.distance_to(target))
  if game.ball.position.y < 0.3:
   break
 check(own_side and near < 0.55, "A real received ball descends within human reach at the intended hand height")
 # Pick an attacker before the setter touches, using court space, not distance.
 manager.configure({"counts": [3, 1], "difficulty": 2})
 freeze_bots()
 manager.reset_rally()
 first = manager.bots[-100]
 second = manager.bots[-101]
 var third: VolleyGameBot = manager.bots[-102]
 first.position = Vector3(0, 0.02, 3)
 second.position = Vector3(0, 0.02, 7)
 third.position = Vector3(3, 0.02, 6)
 manager.bots[-106].position = Vector3(3, 0.02, -1.2)
 a.position = Vector3(-3, 0.02, 2.8)
 a.velocity = Vector3(-0.5, 0, -0.5)
 manager.last_team = 0
 manager.touches = 1
 manager.last_touch_time = 12
 manager.arrival[0] = manager.clock + 0.5
 var attack := manager.tactics.pass_plan(first, 0)
 check(attack.recipient == a and attack.target.x < -3, "The setter selects the well-positioned moving human attacker in an open lane")
 check(Vector3(attack.target).z > 0 and Vector3(attack.target).y > 2.5, "An attacking set offers a high own-side contact")
 third.position = Vector3(-2.8, 0.02, 1.8)
 check(manager.tactics.pass_plan(first, 0).recipient == a, "The selected attacker stays reserved while the ball is flying toward the setter")
 manager.tactics.plans.clear()
 a.position = Vector3(4, 0.02, 9)
 a.velocity = Vector3.ZERO
 attack = manager.tactics.pass_plan(first, 0)
 check(attack.recipient == third, "A better-positioned bot is selected when the human is too deep to attack")
 # Human input and proximity reserve live balls too.
 manager.reset_rally()
 a.position = Vector3(0, 0.02, 4)
 first.position = Vector3(0.3, 0.02, 4)
 second.position = Vector3(3, 0.02, 7)
 third.position = Vector3(-3, 0.02, 7)
 manager.samples = [{"at": Vector3(0, 1.4, 4), "v": Vector3(0, -2, 0), "time": 0.4}]
 manager.tactics.choose_receivers()
 check(manager.receivers[0] == 1, "A reachable human gets the reception instead of a bot taking the same ball")
 root.size = Vector2i(844, 390)
 root.content_scale_size = root.size
 game.hud.toggle_menu()
 await process_frame
 game.hud._layout()
 for i in range(game.hud.tabs.get_tab_count()):
  game.hud.nav_buttons[i].pressed.emit()
  check(game.hud.tabs.current_tab == i, "Visible sidebar opens settings category %d" % i)
 check(game.hud.menu.get_global_rect().end.x <= 844 and game.hud.menu.get_global_rect().end.y <= 390, "The redesigned menu fits a landscape phone")
 check(manager.difficulty_picker.item_count == 5 and not game.hud.category_picker.visible, "Difficulty uses named choices and navigation no longer requires a dropdown")
 game.hud.toggle_menu()
 manager.configure({"counts": [0, 0]})
 game.queue_free()
 await frames(3)
 print("V22 TESTS PASSED (%d checks)" % checks if failures == 0 else "V22 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
