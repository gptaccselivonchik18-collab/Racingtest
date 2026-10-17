extends SceneTree

var game: Node3D
var a: ContextAthlete
var preview: VolleyStrikePreview
var checks := 0
var failures := 0
var landed := false
var floor_at := Vector3.ZERO

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

func pose(kind: int, at: Vector3, side := 1.0, combo := false, held := 0.2, lean := Vector2.ZERO) -> void:
 a.cancel_input()
 a.action = VolleyAthlete.Action.IDLE
 a.position = at
 if at.y < 0.1:
  a.velocity = Vector3.DOWN * 6
  a.move_and_slide()
 a.jump_origin = Vector3(at.x, 0, at.z)
 a.velocity = Vector3.ZERO
 a.dive_time = -1
 a.holding_ball = false
 a.release_time = 0
 a.visual.rotation = Vector3(0, 0 if side > 0 else PI, 0)
 a.camera_yaw = a.visual.rotation.y
 a.camera_pitch = deg_to_rad(35)
 a.approach_jump = combo
 a.begin_action(kind)
 a.charged_for = held
 a.power = maxf(0.16, 0.82 - maxf(0, held - 0.12) * 0.65)
 a.tilt = lean
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
 game.rig.set_process(false)
 game.set_physics_process(false)
 await frames(5)
 a = game.athlete
 a.set_physics_process(false)
 preview = game.get_node("StrikePreview")
 preview.set_physics_process(false)
 game.ball.surface_contact.connect(func(surface: String):
  if surface == "floor" and not landed:
   landed = true
   floor_at = game.ball.global_position)
 a.style_stats.reset_all()
 for side in [1.0, -1.0]:
  for distance in [0.75, 1.5, 4.0]:
   pose(2, Vector3(0, 0.02, side * distance), side, false, 0)
   var point := a.wrists[1]
   var out := a.try_contact(point, Vector3.ZERO)
   var spin := a.outgoing_spin(Vector3.ZERO, out)
   var flight: Dictionary = game.ball.power_serve_flight(point, out, spin)
   print("Standing near net: side=%s distance=%s speed=%s net=%s landing=%s" % [side, distance, out.length(), flight.net_height, flight.landing])
   check(a.strike_technique == 2 and out.length() > 4, "A quick grounded tap is a real standing attack, not a weak tip")
   check(flight.net_height >= 2.61 and flight.landing.z * side < 0 and absf(flight.landing.z) <= 9.16, "Standing attack lifts over the real net and lands on the opposite court")
 pose(2, Vector3(0, 0.02, 2), 1, false, 0)
 var hard := a.try_contact(a.wrists[1], Vector3.ZERO)
 var hard_flight: Dictionary = game.ball.power_serve_flight(a.last_contact_point, hard, a.outgoing_spin(Vector3.ZERO, hard))
 pose(2, Vector3(0, 0.02, 2), 1, false, 1.3)
 var soft := a.try_contact(a.wrists[1], Vector3.ZERO)
 var soft_flight: Dictionary = game.ball.power_serve_flight(a.last_contact_point, soft, a.outgoing_spin(Vector3.ZERO, soft))
 check(absf(hard_flight.landing.z) > absf(soft_flight.landing.z) + 3 and hard.length() > soft.length(), "Holding a standing attack softens its pace and shortens its actual landing")
 for held in [0.0, 0.25, 1.3]:
  pose(2, Vector3(0, 1.1, 2), 1, false, held)
  var feint := a.try_contact(a.wrists[1], Vector3.ZERO)
  check(a.strike_technique == ContextAthlete.TIP and not a.air_attack and feint.length() < 12, "An ordinary jump plus attack stays a controlled feint at every hold duration")
 pose(2, Vector3(0, 1.1, 2), 1, true)
 var power := a.try_contact(a.wrists[1], Vector3.ZERO)
 check(a.strike_technique == 2 and a.air_attack and power.length() > 20 and power.y < 0, "Approach jump plus the second attack preserves a hard downward spike")
 # Predict every shot at its actual contact point, including input spin and
 # a changing Tilt. High skill isolates the model from intended shot scatter.
 for key in VolleyStyleStats.KEYS:
  a.style_stats.set_stat(key, 900)
 for kind in [0, 1, 2, 3, 4, 8, 9]:
  for side in [1.0, -1.0]:
   var origin := Vector3(0, 1.0 if kind in [4, 8, 9] else 0.02, side * (9.7 if kind in [3, 4] else 3.0))
   pose(kind, origin, side, false, 0.25, Vector2(0.15, 0.10))
   a.contact_incoming_spin = Vector3(3, 2, -1)
   var incoming := Vector3(0.6, -2, side * 2)
   var point := a.wrists[1]
   var before_rng := a.rng.state
   var predicted := preview.prediction(point, incoming, a.contact_incoming_spin)
   check(before_rng == a.rng.state and not a.hit_used, "Prediction never consumes contact randomness or triggers a hit")
   var out := incoming + a.try_contact(point, incoming)
   var spin := a.outgoing_spin(a.contact_incoming_spin, out - incoming)
   check(out.normalized().dot(predicted.velocity.normalized()) > 0.999 and absf(out.length() - predicted.velocity.length()) < 0.25, "Preview and actual shot agree on direction and pace for kind %d / side %d" % [kind, int(side)])
   check(spin.distance_to(predicted.spin) < 0.01, "Preview uses the actual shot's spin for kind %d" % kind)
 for held in [0.0, 0.25, 1.2]:
  pose(2, Vector3(0, 1.2, 2), 1, true, held, Vector2(-0.25, -0.15))
  a.contact_incoming_spin = Vector3(2, -1, 4)
  var point := a.wrists[1]
  var predicted := preview.prediction(point, Vector3.ZERO, a.contact_incoming_spin)
  var out := a.try_contact(point, Vector3.ZERO)
  var spin := a.outgoing_spin(a.contact_incoming_spin, out)
  check(predicted.kind == 2 and out.normalized().dot(predicted.velocity.normalized()) > 0.999 and absf(out.length() - predicted.velocity.length()) < 0.25 and spin.distance_to(predicted.spin) < 0.01, "The powerful approach spike shares the preview's pace, direction and topspin")
 var stopped := preview.sample_path(Vector3(0, 2.0, 2), Vector3(0, 0, -15), Vector3.ZERO)
 check(not stopped.landed and absf(stopped.landing.z) < 0.3, "A predicted net collision stops at the ball's surface without a false landing marker")
 # Compare the displayed landing with the real rigid body and net collision.
 for held in [0.0, 1.2]:
  pose(2, Vector3(0, 0.02, 1.5), 1, false, held)
  var point := a.wrists[1]
  a.contact_incoming_spin = Vector3.ZERO
  var predicted := preview.prediction(point, Vector3.ZERO, Vector3.ZERO)
  var path := preview.sample_path(point, predicted.velocity, predicted.spin)
  var out := a.try_contact(point, Vector3.ZERO)
  var spin := a.outgoing_spin(Vector3.ZERO, out)
  landed = false
  game.ball.feed(point, out, spin)
  while game.ball.pending_feed:
   await physics_frame
  for i in range(550):
   await physics_frame
   if landed:
    break
  print("Preview vs rigid body: held=%s predicted=%s actual=%s" % [held, path.landing, floor_at])
  check(path.landed and landed and floor_at.distance_to(path.landing) < 0.35, "The displayed landing matches an actual ball flight with drag, spin and net geometry")
 a.style_stats.reset_all()
 pose(2, Vector3(0, 1.2, 2), 1, false)
 a.action = VolleyAthlete.Action.PREPARE
 check(preview.prediction(a.wrists[1], Vector3.ZERO, Vector3.ZERO).kind == ContextAthlete.TIP, "During wind-up the ordinary-jump indicator already predicts the feint")
 a.approach_jump = true
 check(preview.prediction(a.wrists[1], Vector3.ZERO, Vector3.ZERO).kind == 2, "During wind-up the approach indicator already predicts the power attack")
 game.hud._process(0)
 check(game.hud.buttons.primary.text == "АТАКА", "The approach jump keeps the attack button label")
 a.approach_jump = false
 game.hud._process(0)
 check(game.hud.buttons.primary.text == "ФИНТ", "The ordinary jump shows its contextual feint button")
 # Exercise the real movement + attack gesture rather than setting its flag.
 a.cancel_input()
 a.action = VolleyAthlete.Action.IDLE
 a.position = Vector3(0, 0.02, 5)
 a.velocity = Vector3.ZERO
 a.set_physics_process(true)
 await frames(30)
 a.move_axis = Vector2(0, -1)
 await frames(45)
 check(game.begin_primary() and a.approach_armed, "Running attack press arms the existing approach gesture")
 game.finish_action("primary")
 for i in range(35):
  await physics_frame
  if a.attack_ready:
   break
 check(a.approach_jump and a.attack_ready and a.airborne(), "Releasing the moving attack starts a real approach jump")
 check(game.begin_primary() and a.air_attack and a.strike_technique == 2, "The next attack press launches the existing powerful spike")
 var pose_data: Array = game.lan.pack_actor(a, 1)
 var remote := ContextAthlete.new()
 game.add_child(remote)
 remote.replica = true
 remote.set_physics_process(false)
 game.lan.apply_actor_pose(remote, pose_data)
 check(remote.approach_jump and remote.air_attack, "Network pose preserves the difference between approach and ordinary jump")
 game.hud._cancel()
 game.queue_free()
 await frames(3)
 print("V21 TESTS PASSED (%d checks)" % checks if failures == 0 else "V21 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
