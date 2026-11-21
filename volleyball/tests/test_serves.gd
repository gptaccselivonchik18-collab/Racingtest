extends SceneTree
var game: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func frames(n: int) -> void:
 for i in range(n):
  await physics_frame

func check(ok: bool, text: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", text)
 else:
  failures += 1
  push_error("FAIL: " + text)

func trial(jumping: bool, timing: int, side: float) -> Dictionary:
 game.hud._cancel()
 game.training.selected = 6 if jumping else 5
 game.start_drill()
 var a: ContextAthlete = game.athlete
 a.position.z = side * 9.6
 a.visual.rotation.y = 0 if side > 0 else PI
 a.camera_yaw = a.visual.rotation.y
 game.rig.yaw = a.camera_yaw
 a.reset_seed(6000 + timing)
 game.ball.feed(a.position + Vector3(0, 0.2, -side * 0.5), Vector3.ZERO)
 await frames(18)
 if not game.ball.pick_up():
  return {"hit": false, "in": false}
 var contacts: int = a.contact_count
 game.begin_primary()
 var hit := false
 for frame in range(550):
  if jumping and frame == 34:
   a.jump()
  if frame == maxi(0, timing - 18):
   game.begin_primary()
  if frame == timing:
   game.finish_action("primary")
  await physics_frame
  hit = a.contact_count > contacts
  if hit and game.ball.position.y <= VolleyBall.RADIUS + 0.035:
   var at: Vector3 = game.ball.position
   print("Serve jump=%s timing=%d side=%d landed=%s" % [jumping, timing, int(side), at])
   return {"hit": true, "in": at.z * side < -0.15 and absf(at.x) <= 4.5 + VolleyBall.RADIUS and absf(at.z) <= 9 + VolleyBall.RADIUS and game.rules.serve_crossed}
  if not hit and frame > 155:
   return {"hit": false, "in": false}
 return {"hit": hit, "in": false}

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 await frames(20)
 var a: ContextAthlete = game.athlete
 a.action = VolleyAthlete.Action.STRIKE
 a.strike_technique = VolleyAthlete.Technique.SERVE
 a.action_time = a.strike_duration * 0.03
 check(a.contact_active() and a.effective_contact_radius() >= 0.6, "Serve has an early contact window and a forgiving contact area")
 a.action_time = a.strike_duration * 0.97
 check(a.contact_active(), "Serve contact remains available near the end of the swing")
 var attempts := 0
 var hits := 0
 var inside := 0
 for jumping in [false, true]:
  for timing in ([58, 66, 74, 82, 90] if jumping else [26, 38, 50, 62, 74, 86, 98]):
   var result: Dictionary = await trial(jumping, timing, 1.0)
   attempts += 1
   if result.hit:
    hits += 1
   if result.get("in"):
    inside += 1
 check(hits >= 8, "At least 8 of 12 varied serve timings make contact (%d/12)" % hits)
 check(inside == hits and hits > 0, "Every contacted neutral serve lands on the opponent court (%d/%d)" % [inside, hits])
 var reverse: Dictionary = await trial(false, 74, -1.0)
 check(reverse.hit and reverse.get("in"), "Manual serve also lands in court from the reverse side")
 game.queue_free()
 await frames(3)
 print("SERVE TESTS PASSED (%d checks)" % checks if failures == 0 else "SERVE TESTS FAILED: %d" % failures)
 quit(0 if failures == 0 else 1)
