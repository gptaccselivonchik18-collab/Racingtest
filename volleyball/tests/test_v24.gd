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
 root.size = Vector2i(844, 390)
 root.content_scale_size = root.size
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 game.set_physics_process(false)
 var a: ContextAthlete = game.athlete
 a.set_physics_process(false)
 a.style_stats.reset_all()
 await frames(5)
 check(VolleySettings.clean_nickname("  Alexey.24  ") == "Alexey.24", "Nickname keeps dots and trims surrounding spaces")
 check(VolleySettings.clean_nickname("Алексей🏐") == "Алексей🏐", "Russian letters and emoji survive nickname editing")
 check(VolleySettings.clean_nickname("\n\t") == "Игрок" and VolleySettings.clean_nickname("a\nb") == "ab", "Empty and multiline names become a usable single-line nickname")
 check(VolleySettings.clean_nickname("X".repeat(80)).length() == 24, "Names have a readable 24-character display length")
 var settings_name: String = game.hud.settings.nickname
 game.hud.settings.nickname = "Alexey.24"
 check(game.lan.host_room(24784) == OK, "A local room starts for identity and service tests")
 game.lan._spawn(2, 1, 0)
 game.lan.players[2].nickname = "Друг🏐"
 game.lan.refresh_name(2)
 var remote: ContextAthlete = game.lan.players[2].actor
 check(not a.get_node("TeamTag").visible, "The local player never sees their own overhead name")
 check(remote.get_node("TeamTag").visible and remote.get_node("TeamTag").text == "Друг🏐", "Other players have visible personal names in free play")
 game.lan.rename_local("Selivonchyk")
 check(game.lan.players[1].nickname == "Selivonchyk" and not a.get_node("TeamTag").visible, "Changing a room nickname updates the roster while keeping the own tag hidden")
 game.game_bots.configure({"counts": [2, 2], "difficulty": 4})
 var manager: VolleyGameBots = game.game_bots
 manager.set_physics_process(false)
 for bot in manager.bots.values():
  bot.set_physics_process(false)
 game.lan.match_active = true
 a.court_team = 0
 remote.court_team = 1
 manager.reset_service(0)
 check(manager.serving_actor(0) == a, "Humans participate in the serving order even when teammates are bots")
 manager.advance_service(0, 0)
 check(manager.serving_actor(0) == a, "Winning a point on your serve keeps the same server")
 manager.advance_service(1, 0)
 check(manager.serving_actor(1) == remote, "The receiving team's first side-out gives its human the serve")
 manager.advance_service(0, 1)
 check(manager.serving_actor(0) is VolleyGameBot, "The next side-out rotates to the next teammate")
 manager.advance_service(1, 0)
 manager.advance_service(0, 1)
 check(manager.serving_actor(0) == manager.bots[-101], "Further side-outs cycle through the complete team")
 manager.advance_service(0, 1)
 check(manager.serving_actor(0) == a, "The service order eventually returns to the human")
 manager.reset_service(0)
 game.lan.serve_team = 0
 game.lan.reset_round()
 check(manager.current_server == a and a.position.z > 9 and not manager.bots[-100].is_server, "The real round reset positions the human server instead of always selecting a bot")
 manager.samples = [{"at": Vector3(0, 1.35, 4), "v": Vector3(0, -2, 0), "time": 0.6}]
 manager.last_team = 0
 manager.last_kind = VolleyAthlete.Technique.SERVE
 manager.receivers = [0, 0]
 manager.tactics.choose_receivers()
 check(manager.receivers[0] == 0, "Teammates yield their own outgoing serve even if it passes within reach")
 manager.last_kind = VolleyAthlete.Technique.SPIKE
 manager.touches = 3
 manager.receivers = [0, 0]
 manager.tactics.choose_receivers()
 check(manager.receivers[0] == 0, "Teammates yield their outgoing third touch rather than intercepting a fourth")
 game.lan.match_active = false
 game.lan.leave()
 game.hud.settings.nickname = settings_name
 await frames(4)
 # Each automatic delivery shares the same inside-the-roof camera and mapping.
 a.set_physics_process(false)
 for controller: VolleyLowerServe in [game.lower_serve, game.float_serve]:
  for side in [1.0, -1.0]:
   a.position = Vector3(0, 0.02, side * 9.7)
   a.velocity = Vector3.DOWN * 6
   a.move_and_slide()
   a.velocity = Vector3.ZERO
   game.ball.athlete = a
   game.ball.held = true
   a.holding_ball = true
   check(controller.open(), "The delivery opens while the local player holds the ball")
   for i in range(3):
    await process_frame
   check(controller.panel.get_global_rect().end.y < 390 and controller.panel.position.y >= 0, "The height dialog fits an actual landscape phone viewport")
   controller.choose_target()
   check(controller.top_camera.position.y < VolleyCourt.ROOF and get_root().get_camera_3d() == controller.top_camera, "The opposite-court camera is current and below the opaque roof")
   for x in [-3.5, 0.0, 3.5]:
    var target := Vector3(x, VolleyBall.RADIUS, -side * 5)
    var pixel := controller.top_camera.unproject_position(target)
    var mapped: Variant = controller.target_from_screen(pixel)
    check(mapped is Vector3 and mapped.distance_to(target) < 0.01 and mapped.z * side < 0, "A court tap maps to the opposite half on both serving sides")
   controller.close()
 game.ball.held = false
 a.holding_ball = false
 game.rules.reset()
 game.rules.strict = true
 game.rules.touches = 1
 a.action = VolleyAthlete.Action.STRIKE
 a.wrists = [Vector3(0, 2, 0.12), Vector3(0.3, 2, 0.12)]
 check(not game.player_touches_net(a), "An assisted contact radius near the net is not mistaken for a palm touching it")
 a.wrists = [Vector3(0, 2, 0.02), Vector3(0.3, 2, 0.02)]
 game.check_net_contact(a, 1.0 / 120)
 check(not game.rules.ended, "A single animated frame grazing the net does not end the rally")
 for i in range(12):
  game.check_net_contact(a, 1.0 / 120)
 check(game.rules.ended and "сетки" in game.rules.message, "Sustained actual palm contact still produces a net fault")
 game.rules.reset()
 # A moving replica advances every render frame, including between packets.
 var replica := ContextAthlete.new()
 game.add_child(replica)
 replica.replica = true
 replica.set_process(false)
 replica.set_physics_process(false)
 replica.position = Vector3.ZERO
 replica.velocity = Vector3(0, 0, 5)
 replica.accept_network_position(Vector3.ZERO)
 var error := 0.0
 var minimum := INF
 var maximum := -INF
 for frame in range(240):
  if frame % 4 == 0:
   replica.accept_network_position(Vector3(0, 0, frame * 5.0 / 120))
  var before := replica.position
  replica._process(1.0 / 120)
  if frame > 24:
   var step := replica.position.z - before.z
   minimum = minf(minimum, step)
   maximum = maxf(maximum, step)
   error = maxf(error, absf(step - 5.0 / 120))
 print("REPLICA_STEP min=", minimum, " max=", maximum, " max_error=", error)
 check(error < 0.001 and maximum - minimum < 0.001, "30 Hz snapshots produce steady 120 Hz movement without periodic slowdowns")
 replica.queue_free()
 # A fast human approach plants before the net, then follows a real jump.
 a.cancel_input()
 a.action = VolleyAthlete.Action.IDLE
 a.position = Vector3(0, 0.02, 1.8)
 a.velocity = Vector3(0, -6, 0)
 a.move_and_slide()
 a.velocity = Vector3(0, 0, -5.5)
 a.landing_cooldown = 0
 a.jump(true)
 check(a.velocity.y > 0 and absf(a.velocity.z) < 2.0, "An approach close to the net converts its run-up into a controlled takeoff")
 a.move_axis = Vector2.ZERO
 a.set_physics_process(true)
 await frames(150)
 check(a.position.z > 0.55, "The planted approach lands on its own side instead of carrying the torso into the net")
 a.set_physics_process(false)
 # Test real closed-loop navigation at the fastest difficulty.
 var manager2: VolleyGameBots = game.game_bots
 manager2.configure({"counts": [1, 0], "difficulty": 4, "human_team": 1})
 manager2.set_physics_process(false)
 var defender: VolleyGameBot = manager2.bots[-100]
 defender.position = Vector3(0, 0.02, 8)
 defender.velocity = Vector3.ZERO
 a.position = Vector3(0, 0.02, -9)
 game.ball.athlete = a
 game.ball.held = true
 var closest_depth := INF
 for i in range(360):
  await physics_frame
  closest_depth = minf(closest_depth, defender.position.z)
 check(absf(defender.position.z - 4.2) < 0.35 and Vector2(defender.velocity.x, defender.velocity.z).length() < 0.5, "The fastest defender brakes and settles at its real support position")
 check(closest_depth > 3.7, "High Speed no longer makes a bot run far past its defensive lane")
 game.queue_free()
 await frames(3)
 print("V24 TESTS PASSED (%d checks)" % checks if failures == 0 else "V24 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
