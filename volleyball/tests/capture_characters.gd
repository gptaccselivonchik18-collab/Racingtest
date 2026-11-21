extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 var folder := OS.get_environment("VOLLEY_CAPTURE")
 DirAccess.make_dir_recursive_absolute(folder)
 for i in range(6):
  await process_frame
 game.characters.ui.open_characters()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder.path_join("characters.png"))
 game.characters.ui.open_teams()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder.path_join("teams.png"))
 game.characters.ui.close()
 game.frontend.start_solo()
 var teams: Array = game.characters.default_teams()
 teams[0][0] = {"kind":"bot","character":"kageyama","human":0}
 teams[0][1] = {"kind":"bot","character":"hinata","human":0}
 teams[1][0] = {"kind":"human","character":"hinata","human":0}
 game.characters.apply_teams(teams,2,false)
 game.characters.start_demo()
 for i in range(150):
  await physics_frame
  if game.ball.quick_braked:
   break
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder.path_join("demo.png"))
 print("CHARACTER_CAPTURE_READY")
 quit()
