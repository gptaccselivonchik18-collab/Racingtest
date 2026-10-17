extends SceneTree
var game: Node3D
var folder := ""
func _initialize() -> void:
 call_deferred("run")
func shot(label: String) -> void:
 for i in range(16):
  await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder.path_join("VolleyballSimulator-0.22-" + label + ".png"))
func run() -> void:
 folder = OS.get_environment("VOLLEY_CAPTURE_DIR")
 root.size = Vector2i(1280, 720)
 root.content_scale_size = root.size
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 for key in game.hud.stat_sliders:
  game.hud.stat_sliders[key].set_value_no_signal(65)
 game.game_bots.configure({"counts": [2, 3]})
 game.hud.toggle_menu()
 game.hud.tabs.current_tab = 6
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 await shot("bots-desktop")
 root.size = Vector2i(844, 390)
 root.content_scale_size = root.size
 game.hud.tabs.current_tab = 3
 await shot("player-phone")
 game.hud.tabs.current_tab = 6
 await shot("bots-phone")
 game.hud.tabs.current_tab = 1
 await shot("controls-phone")
 print("V22 VISUAL CAPTURE PASSED")
 quit()
