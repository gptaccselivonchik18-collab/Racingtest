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
 var boot = load("res://scenes/Boot.tscn").instantiate()
 root.add_child(boot)
 boot.set_process(false)
 boot.bar.value = 65
 await capture("loading")
 # Now exercise the actual threaded startup and scene hand-off.
 boot.begun = Time.get_ticks_msec()
 boot.set_process(true)
 await create_timer(1.5).timeout
 var game = current_scene
 if game == null or not is_instance_valid(game.frontend):
  push_error("Boot did not open the main menu")
  quit(1)
  return
 await capture("menu-desktop")
 root.size = Vector2i(844, 390)
 root.content_scale_size = root.size
 await capture("menu-phone")
 game.frontend.show_network()
 await capture("network-phone")
 game.frontend._set_manual(true)
 await capture("ip-phone")
 root.size = Vector2i(1280, 720)
 root.content_scale_size = root.size
 game.frontend.show_home()
 await capture("menu-final")
 print("V17 BOOT AND MENU CAPTURE PASSED")
 quit()
