extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func save_frame(folder: String, name_value: String) -> void:
 for tick in range(5):
  await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder.path_join(name_value + ".png"))
func run() -> void:
 root.size = Vector2i(1280, 720)
 var game: Node3D = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.settings.layout.clear()
 game.hud._layout()
 game.athlete.position = Vector3(0, 0.02, 9.6)
 game.athlete.visual.rotation.y = 0
 game.athlete.camera_yaw = 0
 game.rig.yaw = 0
 game.rig.pitch = -0.35
 game.ball.feed(Vector3(0, 0.3, 9.1), Vector3.ZERO)
 for tick in range(20):
  await physics_frame
 game.ball.pick_up()
 var folder := OS.get_environment("VOLLEY_CAPTURE_DIR")
 DirAccess.make_dir_recursive_absolute(folder)
 await save_frame(folder, "held")
 game.float_serve.open()
 await save_frame(folder, "height")
 game.float_serve.choose_target()
 await save_frame(folder, "target")
 game.float_serve.close()
 print("Captured float serve controls and targeting")
 quit()
