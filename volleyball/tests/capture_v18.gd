extends SceneTree
var folder := ""

func _initialize() -> void:
 call_deferred("run")

func capture(label: String) -> void:
 for frame in range(6):
  await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func run() -> void:
 folder = OS.get_environment("VOLLEY_CAPTURE_DIR")
 DirAccess.make_dir_recursive_absolute(folder)
 root.size = Vector2i(1280, 720)
 root.content_scale_size = root.size
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.lan.host_room(24914)
 game.practice.configure({"enabled": true, "modes": [1, 3, 4], "anchor": Vector3(-2, 0.02, -5)})
 game.rig.set_process(false)
 game.camera.position = Vector3(12, 15, 17)
 game.camera.look_at(Vector3(0, 0.5, 0))
 game.ball.feed(Vector3(0, 2.2, 3), Vector3.ZERO)
 game.ball.freeze = true
 await capture("practice-court")
 game.hud.menu.show()
 game.hud.menu_blocker.show()
 game.hud.tabs.current_tab = 4
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 await capture("bot-settings")
 root.size = Vector2i(844, 390)
 root.content_scale_size = root.size
 await capture("bot-phone")
 game.hud.menu.hide()
 game.hud.menu_blocker.hide()
 game.show_feedback("БЛОК! МЯЧ ОТБИТ", false)
 await capture("block-phone")
 print("V18 VISUAL CAPTURE PASSED")
 quit()
