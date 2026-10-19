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
 check(s.begin(game.athlete, 0), "Prototype can be started without a charge meter or held ball")
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
 check(game.athlete.cinema_time < 0 and game.camera.current and game.hud.visible and not game.ball.freeze and game.athlete.position.distance_to(original) < 0.01, "Normal controls, eye camera, position and ball physics restore")
 var good := 0
 var valid := true
 s.random.seed = 32000
 for i in range(1000):
  var choice := s.choose_target(Vector3(0, 0, 9.5 if i % 2 == 0 else -9.5))
  good += int(choice.inside)
  valid = valid and absf(choice.target.x) < 3.2 and (absf(choice.target.z) <= 9.155 if choice.inside else absf(choice.target.z) > 9.155)
 check(valid and good > 420 and good < 580, "Seeded 50/50 outcomes vary around both opposite back lines")
 s.set_process(true)
 await physics_frame
 check(s.begin(game.athlete, 0), "The ability can be replayed immediately after finishing")
 for i in range(560):
  await physics_frame
 check(not s.active and game.athlete.cinema_time < 0 and game.camera.current, "The full four-second scene ends automatically")
 game.queue_free()
 await process_frame
 print("SUPER SERVE PASSED (%d checks)" % checks if failures == 0 else "SUPER SERVE FAILED")
 quit(0 if failures == 0 else 1)
