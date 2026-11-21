extends SceneTree
var checks := 0
var failures := 0
var game: Node3D

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, note: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", note)
 else:
  failures += 1
  push_error("FAIL: " + note)

func frames(n: int) -> void:
 for i in range(n):
  await physics_frame

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 check(game.frontend.visible and not game.hud.visible, "Main menu is shown at startup")
 game.frontend.start_solo()
 await frames(20)
 check(not game.frontend.visible and game.hud.visible and not game.lan.active, "Solo remains available from the main menu")
 game.hud.set_process(false)
 game.hud.settings.layout.clear()
 game.hud._layout()
 game.hud._process(0)
 check(game.hud.buttons.bump.visible and not game.hud.buttons.lower_serve.visible, "Lower receive has a dedicated visible button")
 game.athlete.move_axis = Vector2(0, -1)
 game.athlete.velocity = Vector3(0, 0, -3)
 check(game.begin_bump() and game.action_owner == "bump" and game.athlete.technique == VolleyAthlete.Technique.UNDERHAND, "Lower receive stays a lower receive while running")
 game.finish_action("bump")
 check(game.athlete.strike_technique == VolleyAthlete.Technique.UNDERHAND, "Releasing lower receive cannot turn into a spike")
 await frames(80)
 game.reset_player()
 game.ball.feed(game.athlete.position + Vector3(0, 0.3, -0.5), Vector3.ZERO)
 await frames(15)
 check(game.ball.pick_up(), "Ball can be picked up for lower serve")
 game.hud._process(0)
 check(game.hud.buttons.lower_serve.visible and not game.hud.buttons.bump.visible, "Possession shows lower serve in the unused dive position")
 check(game.lower_serve.open() and game.lower_serve.stage == 0, "Lower serve opens height selection first")
 game.lower_serve.choose_target()
 check(game.lower_serve.top_camera.current and game.lower_serve.top_camera.position.z < 0, "Positive-z server sees the opposite negative-z half from above")
 var screen: Vector2 = game.lower_serve.top_camera.unproject_position(Vector3(0, 0.105, -5))
 var point: Variant = game.lower_serve.target_from_screen(screen)
 check(point is Vector3 and point.z < 0 and absf(point.z + 5) < 0.01, "Top-view tap projects onto the actual opponent court")
 check(not game.lower_serve.opposite_target(Vector3(0, 0, 5), 1), "Own half is rejected rather than silently mirrored")
 game.lower_serve.close()
 game.athlete.position.z = -9.6
 game.lower_serve.open()
 game.lower_serve.choose_target()
 check(game.lower_serve.top_camera.position.z > 0, "Negative-z server sees the opposite positive-z half")
 check(game.lower_serve.opposite_target(Vector3(4, 0, 8), -1) and not game.lower_serve.opposite_target(Vector3(0, 0, -8), -1), "Opponent selection works from both sides")
 game.lower_serve.close()
 var slip_count := 0
 var scatter_count := 0
 game.lower_serve.rng.seed = 6006
 for i in range(300):
  var sample: Dictionary = game.lower_serve.sample_error(Vector3(0, 0, -5), 0.5)
  if sample.slip:
   slip_count += 1
  if sample.target.distance_to(Vector3(0, 0, -5)) > 0.2:
   scatter_count += 1
 check(slip_count > 0 and slip_count < 60 and scatter_count > 200, "Seeded serves include both normal scatter and rare slips")
 for side in [1.0, -1.0]:
  game.lower_serve.cancel_sequence()
  game.reset_player()
  game.athlete.position = Vector3(0, 0.02, side * 9.6)
  game.athlete.visual.rotation.y = 0 if side > 0 else PI
  game.athlete.camera_yaw = game.athlete.visual.rotation.y
  game.ball.feed(game.athlete.position + Vector3(0, 0.3, -side * 0.5), Vector3.ZERO)
  await frames(18)
  check(game.ball.pick_up(), "Pickup before automatic serve on side %d" % int(side))
  game.lower_serve.rng.seed = 42
  var contacts: int = game.athlete.contact_count
  check(game.lower_serve.launch(game.athlete, Vector3(0, 0.105, -side * 5), 3.5), "Automatic lower serve starts on side %d" % int(side))
  await frames(130)
  check(game.athlete.contact_count == contacts + 1, "Automatic lower swing makes exactly one real platform contact on side %d" % int(side))
  check(game.ball.position.z * side < side * side * 9.0, "Served ball travels toward the opponent on side %d" % int(side))
  check(not game.ball.held and not is_instance_valid(game.lower_serve.busy_actor), "Automatic serve releases possession and finishes")
  await frames(200)
  check(game.rules.serve_crossed, "Normal-height lower serve physically clears the net on side %d" % int(side))
 check(game.lan.host_room(24691) == OK and game.lan.players.size() == 1, "A local room can be hosted without internet")
 game.frontend.enter_court()
 game.hud.toggle_menu()
 check(not paused and game.lan.hosting, "Opening settings never pauses the shared server")
 game.hud.toggle_menu()
 game.lan.leave()
 check(not game.lan.active and not game.ball.replica and game.athlete.is_physics_processing(), "Leaving restores standalone physics")
 game.queue_free()
 await frames(3)
 print("V6 TESTS PASSED (%d checks)" % checks if failures == 0 else "V6 TESTS FAILED: %d" % failures)
 quit(0 if failures == 0 else 1)
