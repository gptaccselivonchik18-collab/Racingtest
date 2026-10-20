extends SceneTree
var folder := ""
func _initialize() -> void:
 call_deferred("run")
func capture(label: String) -> void:
 for frame in range(8):
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
 game.athlete.stats.reset_all()
 for key in game.hud.stat_sliders:
  game.hud.stat_sliders[key].set_value_no_signal(65)
 game.game_bots.configure({"counts": [5, 6]})
 game.practice.configure({"enabled": true, "modes": [1, 3, 4], "anchor": Vector3(-3, 0.02, -7)})
 game.rig.set_process(false)
 game.camera.position = Vector3(7.7, 10.8, 11.6)
 game.camera.look_at(Vector3(0, 0.8, 0))
 game.ball.feed(Vector3(0, 2.2, 3), Vector3.ZERO)
 await capture("VolleyballSimulator-0.19-court")
 game.hud.toggle_menu()
 game.hud.tabs.current_tab = 6
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 await capture("VolleyballSimulator-0.19-bots")
 root.size = Vector2i(844, 390)
 root.content_scale_size = root.size
 game.hud.tabs.current_tab = 3
 await capture("VolleyballSimulator-0.19-player-phone")
 game.hud.tabs.current_tab = 6
 await capture("VolleyballSimulator-0.19-bots-phone")
 print("V19 VISUAL CAPTURE PASSED")
 quit()
