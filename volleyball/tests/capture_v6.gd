extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var game: Node3D = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 var args := OS.get_cmdline_user_args()
 var mode := args[0] if args.size() > 0 else "home"
 if mode == "room":
  game.lan.host_room(24693)
  game.frontend.show_room()
 elif mode != "home":
  game.frontend.start_solo()
  game.training.selected = 5
  game.start_drill()
  for i in range(30):
   await physics_frame
  game.ball.pick_up()
  if mode in ["height", "target"]:
   game.lower_serve.open()
   if mode == "target":
    game.lower_serve.choose_target()
 for i in range(80):
  await process_frame
 await RenderingServer.frame_post_draw
 var path := OS.get_environment("VOLLEY_SCREENSHOT")
 root.get_texture().get_image().save_png(path)
 print("Screenshot: ", path)
 quit()
