extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
 call_deferred("run")
func check(ok: bool, text: String) -> void:
 checks += 1
 print("PASS: " if ok else "FAIL: ", text)
 if not ok:
  failures += 1
  push_error(text)
func run() -> void:
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 for i in range(12):
  await physics_frame
 var s: VolleySuperServe = game.super_serve
 var original: Vector3 = game.athlete.position
 check(not s.begin(game.athlete, 0) and s.percent(0) == 0, "Super serve requires personal charge")
 for i in range(7):
  s.note_contact(game.athlete, 0, 2)
  s.record_floor(Vector3(0, 0.155, -5))
  s.record_floor(Vector3(0, 0.155, -5))
 check(s.ready_for(0) and s.percent(0) == 100 and int(s.charges[0]) == 7, "Seven personal scores fill the bar; repeated bounces do not count")
 var other := ContextAthlete.new()
 game.add_child(other)
 other.set_physics_process(false)
 other.position = Vector3(2, 0.02, 5)
 s.note_contact(other, 42, 2)
 s.record_floor(Vector3(0, 0.155, -5))
 check(int(s.charges.get(42, 0)) == 1 and int(s.charges[0]) == 7, "Another player's score charges only that player")
 other.position.z = -5
 s.charges[0] = 0
 s.note_contact(game.athlete, 0, 2)
 s.note_contact(other, 42, 1)
 s.record_floor(Vector3(0, 0.155, -5))
 check(int(s.charges[0]) == 1 and int(s.charges[42]) == 1, "A failed opponent receive still credits the player who scored")
 s.charges[0] = 7
 other.queue_free()
 check(s.begin(game.athlete, 0) and s.percent(0) == 0, "Starting the skill consumes the personal charge")
 check(not s.begin(game.athlete, 0), "A second press cannot overlap two cinematic sequences")
 s.set_process(false)
 s.elapsed = 2.86
 s._sample()
 var distance: float = game.athlete.wrists[1].distance_to(game.ball.position)
 print("SUPER CONTACT DISTANCE ", distance)
 check(distance < 0.27, "The animated hand actually reaches the ball at impact")
 s.elapsed = VolleySuperServe.HIT + s.flight
 s._sample()
 check(s.camera.position.y < 0.8 and game.ball.position.distance_to(s.target) < 0.1, "The floor camera frames the actual landing target")
 s.finish(true)
 check(game.athlete.cinema_time < 0 and game.camera.current and game.hud.visible and not game.ball.freeze and game.athlete.position.distance_to(s.ground_at(4.3)) < 0.01 and game.athlete.position.z < original.z - 0.5, "Run-up position, normal controls, eye camera and physics restore")
 var good := 0
 var valid := true
 s.random.seed = 32000
 for i in range(1000):
  var choice := s.choose_target(Vector3(0, 0, 9.5 if i % 2 == 0 else -9.5))
  good += int(choice.inside)
  valid = valid and absf(choice.target.x) < 4.2 and (absf(choice.target.z) <= 9.155 if choice.inside else absf(choice.target.z) > 9.155)
 check(valid and good > 420 and good < 580, "Seeded 50/50 outcomes vary around both opposite back lines")
 s.set_process(true)
 await physics_frame
 check(not s.begin(game.athlete, 0), "A spent skill cannot be repeated before recharging")
 s.charges[0] = 7
 s.begin(game.athlete, 0)
 for i in range(560):
  await physics_frame
 check(not s.active and game.athlete.cinema_time < 0 and game.camera.current, "The full four-second scene ends automatically")
 game.game_bots.configure({"counts": [0, 3], "difficulty": 2})
 var safe := true
 for bot in game.game_bots.bots.values():
  bot.set_physics_process(false)
  bot.position = Vector3((bot.slot - 1) * 2.5, 0.02, -8.2)
 for i in range(8):
  var choice := s.choose_target(Vector3(0, 0, 9.5))
  for bot in game.game_bots.bots.values():
   safe = safe and Vector2(choice.target.x - bot.position.x, choice.target.z - bot.position.z).length() > 1.15
 check(safe, "Landing choices avoid the back-row opponents rather than hit their bodies")
 game.queue_free()
 await process_frame
 print("SUPER SERVE PASSED (%d checks)" % checks if failures == 0 else "SUPER SERVE FAILED")
 quit(0 if failures == 0 else 1)
