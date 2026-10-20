extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 var folder:=OS.get_environment("VOLLEY_CAPTURE")
 DirAccess.make_dir_recursive_absolute(folder)
 game.frontend.start_solo()
 game.characters.demo=false
 game.athlete.set_character("oikawa")
 game.athlete.court_team=0
 game.athlete.position=Vector3(0,0.02,10.4)
 for i in range(16):await physics_frame
 game.ball.athlete=game.athlete
 game.ball.feed(game.athlete.position+Vector3(0,0.25,0),Vector3.ZERO)
 for i in range(4):await physics_frame
 game.ball.pick_up()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder.path_join("oikawa-button.png"))
 game.super_serve.request()
 var captured:=0
 for i in range(700):
  await physics_frame
  var s: VolleySuperServe=game.super_serve
  if captured==0 and s.clock>1.55:
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(folder.path_join("oikawa-jump.png"))
   captured=1
  elif captured==1 and s.contact_done:
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(folder.path_join("oikawa-contact.png"))
   captured=2
  elif captured==2 and s.landed:
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(folder.path_join("oikawa-floor.png"))
   break
 print("OIKAWA_CAPTURE_READY")
 quit()
