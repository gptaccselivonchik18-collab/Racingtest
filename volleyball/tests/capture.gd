extends SceneTree

func _initialize() -> void:
 call_deferred("capture")

func capture() -> void:
 var scene := load("res://scenes/Main.tscn") as PackedScene
 var game := scene.instantiate()
 root.add_child(game)
 if OS.get_environment("VOLLEY_CAPTURE_MENU") == "1":
  game.hud.toggle_menu()
 for i in range(180):
  await process_frame
 await RenderingServer.frame_post_draw
 var destination := OS.get_environment("VOLLEY_SCREENSHOT")
 if destination.is_empty():
  destination = "user://volleyball-preview.png"
 root.get_texture().get_image().save_png(destination)
 print("Screenshot: ", destination)
 quit()
