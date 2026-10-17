extends SceneTree

var game: Node3D
var a: ContextAthlete
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

func reset_actor(at := Vector3(0, 1.3, 3)) -> void:
 a.cancel_input()
 a.action = VolleyAthlete.Action.IDLE
 a.dive_time = -1
 a.position = at
 if at.y < 0.1:
  a.velocity = Vector3.DOWN * 6
  a.move_and_slide()
 a.jump_origin = Vector3(at.x, 0, at.z)
 a.velocity = Vector3.ZERO
 a.visual.rotation = Vector3.ZERO
 a.camera_yaw = 0
 a.tilt = Vector2.ZERO
 a.holding_ball = false
 a.lower_serve_active = false
 a.float_serve_active = false
 a.release_time = 0
 game.action_owner = ""
 game.ball.held = false

func block(lean: Vector2, incoming := Vector3(0, -7, 20), attack: Dictionary = {}, seed_value := 42) -> Vector3:
 reset_actor()
 a.begin_action(ContextAthlete.BLOCK)
 a.tilt = lean
 a.action_time = 0.25
 a._update_pose(0)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()
 a.reset_seed(seed_value)
 return incoming + a.try_contact(a.wrists[1], incoming, attack)

func hit(z: float, serve_value: float, spike_value: float) -> Vector3:
 reset_actor(Vector3(0, 0.02, z))
 a.style_stats.set_stat("serve", serve_value)
 a.style_stats.set_stat("spike", spike_value)
 a.begin_action(VolleyAthlete.Technique.SERVE)
 a.charged_for = 0.25
 a.power = 0.8
 a.release()
 a.action_time = a.strike_duration * 0.47
 a._update_pose(0)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()
 a.reset_seed(2020)
 return a.try_contact(a.wrists[1], Vector3.ZERO)

func auto_sample(controller: VolleyLowerServe, z: float, serving_skill: float, other: float) -> Dictionary:
 reset_actor(Vector3(0, 0.02, z))
 a.style_stats.set_stat("serve", serving_skill)
 a.style_stats.set_stat("bump", other)
 a.style_stats.set_stat("spike", other)
 game.ball.held = true
 game.ball.freeze = true
 game.ball.athlete = a
 a.holding_ball = true
 controller.rng.seed = 20020
 var accepted := controller.launch(a, Vector3(1, VolleyBall.RADIUS, -6), 3.8)
 var sample: Dictionary = controller.delivery.duplicate() if controller is VolleyFloatServe else {"target": controller.target, "slip": controller.slipped}
 sample.accepted = accepted
 controller.cancel_sequence()
 return sample

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 game.set_physics_process(false)
 await frames(3)
 a = game.athlete
 a.style_stats.reset_all()
 a.set_physics_process(false)
 var incoming := Vector3(0, -7, 20)
 var neutral := block(Vector2.ZERO, incoming)
 var pressed := block(Vector2(0, -1), incoming)
 var opened := block(Vector2(0, 1), incoming)
 check(neutral.z < 0 and pressed.z < 0 and opened.z < 0, "All three successful hand planes return the attack to the opponent")
 check(pressed.y < neutral.y - 8 and opened.y > neutral.y + 8, "Forward palms press down, neutral goes deep, withdrawn palms loft the return")
 for output in [neutral, pressed, opened]:
  check(output.length() >= incoming.length() * 0.969 and output.length() <= incoming.length() * 1.001, "Passive block retains incoming pace without adding energy")
 var lateral := block(Vector2(1, 0), incoming)
 check(absf(lateral.x) > 8, "Side Tilt creates a real lateral ricochet and permits block-out")
 a.power = 0.01
 a.strike_power = 0.01
 a.hit_used = false
 a.reset_seed(42)
 var weak := incoming + a.try_contact(a.wrists[1], incoming)
 a.power = 1
 a.strike_power = 1
 a.hit_used = false
 a.reset_seed(42)
 var strong := incoming + a.try_contact(a.wrists[1], incoming)
 check(weak.is_equal_approx(strong), "Legacy strength values cannot change a block's velocity")
 var attacked := {"skill": 0.9, "quality": 0.95, "kind": 2}
 for tilt in [Vector2.ZERO, Vector2(0, -1), Vector2(0, 1)]:
  var pierced := Vector3.ZERO
  var found := false
  for seed_value in range(50):
   pierced = block(tilt, incoming, attacked, seed_value)
   if a.duel_result.pierced:
    found = true
    break
  check(found, "A strong real attack can pierce each tilted block")
  if tilt.y <= 0:
   check(pierced.normalized().dot(incoming.normalized()) > 0.99999, "Pierced square or pressed hands preserve the original attack direction")
  else:
   check(pierced.z > 0 and pierced.y > 10, "Pierced withdrawn hands loft the ball deep toward the blocking side")
 var previous := a.contact_count
 for i in range(60):
  a.try_contact(a.wrists[1], incoming, attacked)
 check(a.contact_count == previous, "A ball still touching held hands cannot reroll the block outcome")
 reset_actor(Vector3(0, 4, 3))
 a.set_physics_process(true)
 check(game.begin_secondary() and a.block_held and a.action == VolleyAthlete.Action.STRIKE, "Airborne secondary raises an active block on press")
 await frames(90)
 check(a.block_held and a.contact_active() and a.power == 0 and a.strike_power == 0, "Held block survives beyond a swing duration and has no charged strength")
 game.finish_action("secondary")
 check(not a.block_held and not a.contact_active(), "Releasing the button immediately removes the block contact surface")
 await frames(30)
 reset_actor(Vector3(0, 2, 3))
 game.begin_secondary()
 game.cancel_action("")
 check(not a.block_held and a.action == VolleyAthlete.Action.IDLE, "Input cancellation clears held block without a stuck action")
 reset_actor(Vector3(0, 0.1, 3))
 a.velocity.y = 1
 game.begin_secondary()
 await frames(70)
 check(not a.block_held and not a.contact_active(), "Landing lowers the block even if a finger stays down")
 a.set_physics_process(false)
 a.style_stats.reset_all()
 neutral = block(Vector2.ZERO)
 game._on_player_touch(a, 0, ContextAthlete.BLOCK, a.wrists[1], neutral)
 check(game.feedback_left > 0 and game.feedback_text.is_empty() and a.last_result.is_empty(), "A block contact flashes briefly with no toast or percentage text")
 game.feedback_left = 0
 game._on_block_missed(a, 0)
 check(game.feedback_left == 0, "A missed block does not display a false contact flash")
 for z in [-9.6, 9.6]:
  for x in [-7.7, 0.0, 7.7]:
   var rules := VolleyRules.new()
   rules.reset(true)
   rules.serve_contact(Vector3(x, 0, z))
   check(not rules.ended, "Wide rear runoff is a legal serving zone on either side")
 var low := hit(4, -250, 65)
 var high := hit(4, 400, 65)
 check(low.is_equal_approx(high) and a.strike_technique == VolleyAthlete.Technique.SPIKE, "Delivery from inside court ignores Serve and becomes a normal hit")
 var skilled_hit := hit(4, 65, 300)
 var skilled_flight: Dictionary = game.ball.power_serve_flight(a.last_contact_point, skilled_hit, a.outgoing_spin(Vector3.ZERO, skilled_hit))
 var novice_hit := hit(4, 65, -200)
 var novice_flight: Dictionary = game.ball.power_serve_flight(a.last_contact_point, novice_hit, a.outgoing_spin(Vector3.ZERO, novice_hit))
 check(absf(skilled_flight.landing.z) > absf(novice_flight.landing.z) + 1, "Inside-court standing delivery gains depth and control from Spike skill")
 check(not hit(9.6, -200, 65).is_equal_approx(hit(9.6, 300, 65)), "Rear-zone delivery responds to Serve skill")
 reset_actor(Vector3(0, 1.2, 8.6))
 a.jump_origin.z = 9.7
 a.begin_action(VolleyAthlete.Technique.JUMP_SERVE)
 a.charged_for = 0.2
 a.release()
 check(a.strike_technique == VolleyAthlete.Technique.JUMP_SERVE, "Jump service remains legal after take-off behind the baseline")
 reset_actor(Vector3(0, 1.2, 9.7))
 a.jump_origin.z = 8.6
 a.begin_action(VolleyAthlete.Technique.JUMP_SERVE)
 a.charged_for = 0.2
 a.release()
 check(a.strike_technique == ContextAthlete.TIP, "An ordinary jump from inside court stays a feint and cannot acquire Serve bonuses")
 for controller in [game.lower_serve, game.float_serve]:
  low = Vector3.ZERO
  var first := auto_sample(controller, 4, -200, 65)
  var second := auto_sample(controller, 4, 300, 65)
  var skilled := auto_sample(controller, 4, 65, 300)
  check(first.accepted and second.accepted and first.target == second.target, "Automatic delivery inside court ignores Serve: " + controller.network_role())
  check(skilled.target != first.target, "Automatic delivery uses its Bump or Spike skill inside court: " + controller.network_role())
  reset_actor(Vector3(0, 0.02, 4))
  game.ball.athlete = a
  game.ball.held = true
  game.ball.freeze = true
  a.holding_ball = true
  a.set_physics_process(true)
  var before := a.contact_count
  check(controller.launch(a, Vector3(0, VolleyBall.RADIUS, -6), 3.8), "Inside-court automatic contact starts")
  await frames(150)
  check(a.contact_count > before and not game.rules.serving, "Inside-court automatic swing meets a free toss without being recorded as a serve")
  controller.cancel_sequence()
  a.set_physics_process(false)
 var rules := VolleyRules.new()
 rules.strict = true
 rules.touch(0, 1, 3, 1)
 check(not rules.touch(1, 2, 6, 2) and rules.message == "Блок подачи", "Formal match forbids blocking an incoming serve")
 rules.reset()
 rules.touch(0, 1, 3, 1)
 check(not rules.touch(1, 2, 2, 2, 3.2), "Formal match forbids attacking a serve above the net")
 rules.reset()
 rules.touch(0, 1, 3, 1)
 check(rules.touch(1, 2, 1, 2) and rules.touch(1, 3, 0, 3) and rules.touch(1, 4, 2, 4, 3.2), "A received serve supports the normal receive-set-spike sequence")
 rules.reset()
 rules.touch(0, 1, 6, 1)
 check(rules.touch(0, 1, 1, 2) and rules.touches == 1, "A blocker may receive next and still has three team touches")
 var points := [24, 24]
 var sets := [0, 0]
 check(VolleyMatchScore.point(points, sets, 0) < 0 and points == [25, 24] and sets == [0, 0], "A set requires a two-point lead")
 VolleyMatchScore.point(points, sets, 0)
 check(points == [0, 0] and sets == [1, 0], "Winning a set starts the next set with a fresh point score")
 points = [14, 14]
 sets = [2, 2]
 VolleyMatchScore.point(points, sets, 1)
 check(points == [14, 15] and sets == [2, 2], "Deciding fifth set also requires a two-point lead")
 check(VolleyMatchScore.point(points, sets, 1) == 1 and sets == [2, 3], "A team winning its third set wins the match")
 reset_actor()
 game.rules.reset()
 check(game.lan.host_room(24932) == OK, "A room opens in free play for rules verification")
 for i in range(5):
  game._on_player_touch(a, 1, 1, Vector3.ZERO, Vector3.UP)
 game._on_surface("boundary")
 game._on_surface("floor")
 check(not game.rules.ended and game.lan.scores == [0, 0], "Free play allows repeated touches, walls and floor without scoring")
 game.lan.match_active = true
 game.lan.round_live = true
 game.lan.last_touch_team = 0
 game.rules.strict = true
 game._on_surface("boundary")
 game.lan._process(0.01)
 check(game.lan.scores == [0, 1], "A formal block-out awards the opponent when the last toucher hit the boundary")
 game.lan.start_free_play()
 game.lan.match_active = true
 game.lan.round_live = true
 game.lan.last_touch_team = 1
 game._on_surface("boundary")
 game.lan._process(0.01)
 check(game.lan.scores == [1, 0], "Block-out scoring is symmetric for the opposite team")
 game.lan.start_free_play()
 reset_actor(Vector3(3.4, 1.3, 1.5))
 a.style_stats.reset_all()
 a.court_team = 0
 a.tilt = Vector2(1, 0)
 a.begin_action(ContextAthlete.BLOCK)
 a.action_time = 0.25
 a._update_pose(0)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()
 var before := a.contact_count
 game.ball.contact_athletes = [a]
 game.lan.match_active = true
 game.lan.round_live = true
 game.lan.last_touch_team = 1
 game.rules.strict = true
 game.ball.feed(a.wrists[1] - incoming.normalized() * 0.25, incoming, Vector3.ZERO)
 for i in range(180):
  await physics_frame
  if game.lan.round_wait >= 0:
   break
 check(a.contact_count == before + 1, "A real fast ball physically strikes the tilted held block exactly once")
 check(game.lan.last_touch_team == 0 and game.lan.scores == [0, 1], "Real block deflection reaches the outside boundary and awards block-out against the blocker")
 game.lan.start_free_play()
 game.lan.match_active = true
 game.lan.round_live = true
 game.lan.last_touch_team = 0
 game.rules.strict = true
 game.rules.reset(true)
 game.ball.position = Vector3(0, VolleyBall.RADIUS, -3)
 game._on_surface("floor")
 check(game.lan.scores == [0, 1], "An invalid uncrossed serve cannot score merely by reaching the opponent floor")
 for z in [2.9, 3.1]:
  game.rules.reset()
  a.position.z = z
  game._on_player_touch(a, 1, 2, Vector3(0, 3.4, z), Vector3.FORWARD)
  check(not game.rules.ended, "An ordinary high attack has no three-metre-line restriction")
 game.lan.leave()
 game.queue_free()
 await frames(3)
 print("V20 TESTS PASSED (%d checks)" % checks if failures == 0 else "V20 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
