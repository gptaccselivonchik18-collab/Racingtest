extends SceneTree

var game: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, text: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(text)
 print("PASS: " if ok else "FAIL: ", text)

func ready_actor(a: ContextAthlete, at := Vector3(0,0.02,9.7)) -> void:
 a.set_physics_process(false)
 a.position = at
 a.velocity = Vector3.DOWN
 a.cancel_input()
 a.action = VolleyAthlete.Action.IDLE
 a.air_swing_used = false
 a.jump_in_progress = false
 for i in range(8):
  a._physics_process(1.0/120)
 a._update_pose(0)

func start_toss(a: ContextAthlete) -> bool:
 ready_actor(a)
 game.ball.athlete = a
 game.ball.held = true
 a.holding_ball = true
 a.technique = VolleyAthlete.Technique.SERVE
 var tossed: bool = game.ball.toss()
 game.serving = a == game.athlete
 return tossed

func swing(a: ContextAthlete) -> bool:
 if not a.begin_action(VolleyAthlete.Technique.SERVE):
  return false
 a.release()
 return a.action == VolleyAthlete.Action.STRIKE

func attack_works(a: ContextAthlete) -> bool:
 ready_actor(a, Vector3(0,0.02,4))
 game.action_owner = ""
 var accepted: bool = game.begin_primary()
 if accepted:
  game.finish_action("primary")
 return accepted and a.action == VolleyAthlete.Action.STRIKE and a.strike_technique in [VolleyAthlete.Technique.SPIKE,ContextAthlete.TIP]

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.characters.set_physics_process(false)
 game.game_bots.set_physics_process(false)
 game.set_physics_process(false)
 game.set_process(false)
 var roster: Array = game.characters.default_teams()
 roster[1][0] = {"kind":"bot","character":"hinata","human":0}
 check(game.characters.apply_teams(roster,1,false), "Configure a human and a bot without changing saved rosters")
 var human: ContextAthlete = game.athlete
 var bot: ContextAthlete = game.game_bots.bots[-106]
 bot.set_physics_process(false)
 var floor := StaticBody3D.new()
 floor.set_meta("surface","floor")
 root.add_child(floor)
 for cycle in range(24):
  check(start_toss(human) and swing(human), "Human toss and swing in rally %d" % cycle)
  human.action = VolleyAthlete.Action.IDLE
  check(not human.begin_action(VolleyAthlete.Technique.SERVE), "No second swing before this toss resolves (%d)" % cycle)
  if cycle % 3 == 0:
   # A bot/other LAN player's input can change ball.athlete before the floor.
   game.ball.athlete = bot
   game.ball._on_body_entered(floor)
  elif cycle % 3 == 1:
   # Resolve an actual hand contact, including the normal gameplay callback.
   human.action = VolleyAthlete.Action.STRIKE
   human.action_time = human.strike_duration*0.47
   human._update_pose(0)
   human.previous_wrists = human.wrists.duplicate()
   human.previous_elbows = human.elbows.duplicate()
   var impulse := human.try_contact(human.wrists[1],Vector3.DOWN)
   check(impulse != Vector3.ZERO, "The human physically hits their serve (%d)" % cycle)
   game.ball.remember_contact(human)
  else:
   game.ball.athlete = bot
   game.ball.feed(bot.position+Vector3.UP,Vector3.ZERO)
  check(not human.service_attempt_active and not human.serve_swing_used and not game.serving, "Toss state and HUD mode close on contact, missed floor or another server (%d)" % cycle)
  check(attack_works(human), "Attack remains usable after resolved serve (%d)" % cycle)
 check(start_toss(human) and swing(human), "Prepare a stale serve at round boundary")
 game.ball.athlete = bot
 game.game_bots.reset_rally()
 check(attack_works(human), "Rally reset unlocks every participant, including the previous server")
 check(start_toss(human) and swing(human), "Prepare a missed training serve")
 game.training.selected = 6
 game.repeat_drill()
 check(game.serving and not human.service_attempt_active and not human.serve_swing_used, "Repeating a serve drill preserves the new drill mode and clears the old attempt")
 ready_actor(human,Vector3(2,0.02,5))
 game.ball.athlete = human
 game.ball.pending_feed = false
 game.ball.held = false
 game.ball.linear_velocity = Vector3.ZERO
 game.ball.position = human.position+Vector3(0,1,-0.5)
 check(game.ball.pick_up(), "The human really picks up a slow ball")
 game.ball.athlete = bot
 game.ball.feed(bot.position+Vector3.UP,Vector3.ZERO)
 check(not human.holding_ball and attack_works(human), "A different round server releases the previous holder instead of permanently locking attacks")
 ready_actor(human,Vector3(0,1.2,4))
 human.air_swing_used = true
 human.finish_service_attempt()
 check(not human.begin_action(VolleyAthlete.Technique.SPIKE), "Closing a service attempt never permits a second swing in the same jump")
 floor.queue_free()
 game.queue_free()
 await process_frame
 print("SERVICE LIFECYCLE PASSED (%d checks)" % checks if failures == 0 else "SERVICE LIFECYCLE FAILED (%d)" % failures)
 quit(0 if failures == 0 else 1)
