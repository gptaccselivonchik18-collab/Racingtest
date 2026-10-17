extends SceneTree

var game: Node3D
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

func frames(count: int) -> void:
 for i in range(count):
  await physics_frame

func swing(kind: int) -> void:
 var a: ContextAthlete = game.athlete
 a.cancel_input()
 a.action = VolleyAthlete.Action.IDLE
 a.holding_ball = false
 a.begin_action(kind)
 a.charged_for = 0.25
 a.release()
 a.action_time = a.strike_duration * 0.47
 a._update_pose(0)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 await frames(3)
 var a: ContextAthlete = game.athlete
 var ball: VolleyBall = game.ball
 ball.freeze = true
 a.set_physics_process(false)
 var shape: SphereShape3D = ball.get_child(0).shape
 check(is_equal_approx(shape.radius, 0.155) and ball.get_child(1).mesh.radius == shape.radius, "Enlarged visible ball and physical collider share the same radius")
 for height in [0.12, 0.45, 1.0, 1.65, 1.95]:
  swing(1)
  var at := a.visual.to_global(Vector3(0, height, 0.05))
  check(a.try_contact(at, Vector3(0, -5, 4)).length() > 0.1, "Bump accepts whole-body contact at %.2f metres" % height)
  check(a.try_contact(at, Vector3(0, -5, 4)) == Vector3.ZERO, "Whole-body assist never repeats the same action")
 swing(1)
 check(a.try_contact(a.position + Vector3(1.5, 1, 0), Vector3.DOWN) == Vector3.ZERO, "Body reception still requires spatial contact")
 a.action_time = 0
 check(a.try_contact(a.position + Vector3(0, 1, 0), Vector3.DOWN) == Vector3.ZERO, "Body reception cannot happen outside the action window")
 swing(2)
 check(a.try_contact(a.position + Vector3(0, 0.4, 0), Vector3.DOWN) == Vector3.ZERO, "A spike cannot be made with the legs")
 a.position = Vector3(0, 1, -1)
 swing(6)
 game._on_player_touch(a, 1, 6, a.wrists[0], Vector3.UP)
 check(game.feedback_left > 1 and game.feedback_text.contains("ОТБИТ"), "A real block has a persistent visible success cue")
 a.duel_result = {"pierced": true}
 game._on_player_touch(a, 1, 6, a.wrists[0], Vector3.UP)
 check(game.feedback_text.contains("ПРОБИТ"), "A pierced block has distinct visible feedback")
 a.duel_result.clear()
 a.position = Vector3(3.5, 0.02, 8)
 a.action = VolleyAthlete.Action.IDLE
 a.set_physics_process(true)
 ball.freeze = false
 for mode in range(6):
  var side := 1.0 if mode % 2 == 0 else -1.0
  check(game.practice.configure({"enabled": true, "modes": [mode], "anchor": Vector3(0, 0.02, side * 6), "interval": 1.5}), "Coach accepts action %d on either half" % mode)
  var bot: VolleyPracticeBot = game.practice.bot
  var previous := bot.contacts
  ball.feed(Vector3(3, 0.3, 8), Vector3.ZERO)
  for tick in range(600):
   await physics_frame
   if bot.contacts > previous:
    break
  check(bot.contacts == previous + 1 and ball.linear_velocity.length() > 2, "Coach action %d produces a real animated contact and outgoing ball" % mode)
  if mode == 4:
   check(bot.air_attack and bot.position.y > 0.4, "Coach spike is actually airborne")
  var target: Vector3 = game.practice.target_for(mode)
  check(target.z * side > 0 if mode in [0, 2] else target.z * side < 0, "Coach action %d targets the requested side of the net" % mode)
 var bot: VolleyPracticeBot = game.practice.bot
 game.practice.configure({"modes": [1]})
 ball.feed(a.position + Vector3(0, 0.3, 0), Vector3.ZERO)
 await frames(3)
 ball.athlete = a
 check(ball.pick_up(), "Player may take possession during bot practice")
 var cycles := bot.cycles
 await frames(240)
 check(ball.held and bot.cycles == cycles, "Bot never steals a held human ball")
 game.practice.configure({"enabled": false})
 check(not bot.visible and bot not in ball.contact_athletes, "Disabled coach has no visible actor or ball contacts")
 check(game.lan.host_room(24912) == OK and not game.lan.match_active and not game.lan.round_live and not game.rules.strict, "LAN opens directly in unrestricted free play")
 game._on_player_touch(a, 1, 1, Vector3.ZERO, Vector3.UP)
 game._on_surface("floor")
 check(not game.rules.ended and game.lan.scores == [0, 0] and game.lan.round_wait < 0, "Free play ignores floor faults, double touches, score and round restarts")
 a.position = Vector3(6.5, 0.02, 3)
 a.velocity = Vector3.ZERO
 game.lan.ready_seconds = 4
 check(not game.lan.begin_match(), "One host cannot start a match alone")
 game.lan._spawn(999, 1, 0)
 var other: ContextAthlete = game.lan.players[999].actor
 other.set_physics_process(false)
 other.position = Vector3(0, 0.02, -3)
 game.lan._update_readiness(4)
 check(not game.lan.match_active and game.lan.ready_seconds == 0, "Every human must stand in a selection zone")
 other.position = Vector3(6.5, 0.02, 3)
 game.lan._update_readiness(4)
 check(not game.lan.match_active, "A match cannot start with only one occupied team")
 other.position.z = -3
 game.lan._update_readiness(1)
 other.position.x = 0
 game.lan._update_readiness(1)
 check(game.lan.ready_seconds == 0, "Leaving the zone cancels everyone's countdown")
 other.position.x = 6.5
 game.lan._update_readiness(3.1)
 check(game.lan.match_active and game.lan.players[1].team == 0 and game.lan.players[999].team == 1, "All selected humans are assigned by the half they chose")
 check(game.rules.strict and not game.lan.selection_zone.visible, "Only an agreed match enables rules and hides selection zones")
 game.lan.serve_flags[1] = true
 game.lan.owners[1] = "primary"
 game.lan.start_free_play()
 check(not game.lan.match_active and game.lan.selection_zone.visible and not game.rules.strict and not game.lan.serve_flags[1] and game.lan.owners[1].is_empty(), "Returning to free play clears interrupted serve/action state")
 # Replica position advances on render frames between network packets.
 other.replica = true
 other.network_age = -1
 other.accept_network_position(Vector3(0, 0.02, 4))
 other.velocity = Vector3(1, 0, 0)
 other._process(1.0 / 120)
 var first := other.position.x
 other._process(1.0 / 120)
 check(other.position.x > first, "Joined players render continuous motion between 30 Hz snapshots")
 var cap := Engine.max_fps
 game.lan.leave()
 check(Engine.max_fps == cap, "Joining/leaving network state never alters the local FPS preference")
 game.queue_free()
 await frames(3)
 print("V18 TESTS PASSED (%d checks)" % checks if failures == 0 else "V18 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
