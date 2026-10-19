extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.athlete.position = Vector3(0.7, 0.02, 9.5)
 for i in range(12):
  await physics_frame
 var s: VolleySuperServe = game.super_serve
 s.random.seed = 32024
 s.charges[0] = 7
 s.begin(game.athlete, 0)
 s.set_process(false)
 var folder := OS.get_environment("VOLLEY_CAPTURE")
 DirAccess.make_dir_recursive_absolute(folder)
 for i in range(108):
  s.elapsed = i / 25.0
  s._sample()
  await RenderingServer.frame_post_draw
  var image := root.get_texture().get_image()
  image.save_png(folder.path_join("%04d.png" % i))
 s.finish(true)
 print("SUPER_CAPTURE_READY")
 quit()
