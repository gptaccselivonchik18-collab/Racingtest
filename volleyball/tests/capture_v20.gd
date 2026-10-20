extends SceneTree

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 root.size = Vector2i(844, 390)
 root.content_scale_size = root.size
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.set_process(false)
 game.set_physics_process(false)
 game.rig.set_process(false)
 game.athlete.set_physics_process(false)
 game.athlete.cancel_input()
 game.athlete.action = VolleyAthlete.Action.IDLE
 game.athlete.position = Vector3(0, 0.65, 1.1)
 game.athlete.velocity = Vector3.ZERO
 game.athlete.camera_yaw = 0
 game.athlete.camera_pitch = 0.02
 game.athlete.visual.rotation = Vector3.ZERO
 game.athlete.begin_action(ContextAthlete.BLOCK)
 game.athlete.action_time = 0.35
 game.athlete.tilt = Vector2(0, -0.6)
 game.athlete._update_pose(0)
 game.camera.global_transform = game.athlete.eye_transform()
 game.ball.feed(Vector3(0.25, 3.1, 0.4), Vector3.ZERO)
 game.ball.freeze = true
 game.show_feedback("", false)
 game.hud._process(0)
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 for frame in range(10):
  await process_frame
 await RenderingServer.frame_post_draw
 var folder := OS.get_environment("VOLLEY_CAPTURE_DIR")
 root.get_texture().get_image().save_png(folder.path_join("VolleyballSimulator-0.20-block-phone.png"))
 print("V20 VISUAL CAPTURE PASSED")
 quit()
