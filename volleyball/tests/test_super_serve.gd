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
 game.athlete.position = Vector3(0, 0.02, 10.5)
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
 game.athlete.position.z = 8.5
 check(not s.begin(game.athlete, 0) and s.percent(0) == 100, "A foot-fault start is refused without spending charge")
 game.athlete.position = original
 check(s.begin(game.athlete, 0) and s.percent(0) == 0, "Starting the skill consumes the personal charge")
 check(not s.begin(game.athlete, 0), "A second press cannot overlap two cinematic sequences")
 s.set_process(false)
 var legal := true
 for step in range(23):
  s.elapsed = step * 0.05
  s._sample()
  for shoe in game.athlete.limb_rig.shoes:
   legal = legal and shoe.global_position.z - 0.15 > 9.0
 check(legal, "Every planted approach frame keeps the shoe toes behind the back line")
 s.elapsed = VolleySuperServe.HIT
 s._sample()
 var distance: float = game.athlete.wrists[1].distance_to(game.ball.position)
 print("SUPER CONTACT DISTANCE ", distance)
 check(distance < 0.27, "The animated hand actually reaches the ball at impact")
 s.elapsed = VolleySuperServe.HIT + VolleySuperServe.PALM_HOLD * 0.5
 s._sample()
 var pressure := (s.target - s.hit_point()).normalized()
 check(absf(s.ball_visual.global_basis.determinant() - 1.0) < 0.01 and (s.ball_visual.global_basis.inverse() * pressure).length() > 1.2 and game.athlete.wrists[1].distance_to(game.ball.position) < 0.27, "The hand close-up holds a volume-preserving compression against the palm")
 var middle := s.flight_position(s.release_point(), s.target, 0.5)
 check(absf(middle.y - s.release_point().lerp(s.target, 0.5).y) < 0.25 and middle.y > 2.43, "The fast shot follows a shallow curve that clears the net")
 s.elapsed = VolleySuperServe.RELEASE + s.flight
 s._sample()
 check(s.camera.position.y < 0.8 and game.ball.position.distance_to(s.target) < 0.1, "The floor camera frames the actual landing target")
 s.elapsed += VolleySuperServe.FLOOR_HOLD * 0.5
 s._sample()
 check(absf((s.ball_visual.global_basis.transposed() * Vector3.UP).length() - 0.66) < 0.01 and absf(game.ball.position.y - VolleyBall.RADIUS * 0.66) < 0.01, "The floor close-up shows compression with the ball underside on the floor")
 var rebound := s.rebound_state(VolleySuperServe.RELEASE + s.flight + 1.2)
 check(Vector2(rebound.position.x - s.target.x, rebound.position.z - s.target.z).length() > 1.5 and Vector2(rebound.velocity.x, rebound.velocity.z).length() > 3, "The ball rebounds forward with residual momentum instead of hopping in place")
 s.finish(true)
 check(game.athlete.cinema_time < 0 and game.camera.current and game.hud.visible and not game.ball.freeze and game.athlete.position.distance_to(s.ground_at(VolleySuperServe.END)) < 0.01 and game.athlete.position.z < original.z - 0.5 and s.ball_visual.transform.is_equal_approx(s.ball_visual_rest) and game.ball.feed_velocity.distance_to(s.rebound_state(VolleySuperServe.END).velocity) < 0.01, "Run-up position, controls, camera, round shape and physical rebound momentum restore")
 var good := 0
 var valid := true
 s.random.seed = 32000
 for i in range(1000):
  var choice := s.choose_target(Vector3(0, 0, 9.5 if i % 2 == 0 else -9.5))
  good += int(choice.inside)
  valid = valid and absf(choice.target.x) < 4.2 and (absf(choice.target.z) <= 9.155 if choice.inside else absf(choice.target.z) > 9.155)
 check(valid and good > 860 and good < 940, "Seeded 90/10 outcomes vary around both opposite back lines")
 s.set_process(true)
 await physics_frame
 check(not s.begin(game.athlete, 0), "A spent skill cannot be repeated before recharging")
 s.charges[0] = 7
 game.athlete.position = original
 var restarted := s.begin(game.athlete, 0)
 for i in range(ceil(VolleySuperServe.END * 120) + 30):
  await physics_frame
 check(restarted and not s.active and game.athlete.cinema_time < 0 and game.camera.current, "The extended seven-second scene ends automatically")
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
