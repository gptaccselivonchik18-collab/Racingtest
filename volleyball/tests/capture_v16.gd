extends SceneTree
func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 root.size = Vector2i(900, 600)
 root.content_scale_size = root.size
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.frontend.hide()
 game.hud.hide()
 game.hud.set_process(false)
 game.rig.set_process(false)
 game.ball.freeze = true
 game.ball.hide()
 var a: ContextAthlete = game.athlete
 a.set_physics_process(false)
 a.set_process(false)
 var folder := OS.get_environment("VOLLEY_CAPTURE_DIR")
 DirAccess.make_dir_recursive_absolute(folder)
 var layer := CanvasLayer.new()
 root.add_child(layer)
 var label := Label.new()
 label.position = Vector2(24, 20)
 label.add_theme_font_size_override("font_size", 24)
 layer.add_child(label)
 var number := 0
 for view in ["side", "body"]:
  a.position = Vector3(0, 0.02, 6)
  a.velocity = Vector3.ZERO
  a.move_axis = Vector2.ZERO
  a.visual.rotation = Vector3.ZERO
  a.camera_yaw = 0
  a.energy = 1
  a.landing_cooldown = 0
  a.gait = 0
  for frame in range(120):
   var time := frame / 30.0
   label.text = "VOLLEY / LAB 0.16 · обычная скорость\n" + ("Бег → прыжок → приземление" if view == "side" else "Вид от первого лица")
   for step in range(4):
    a.move_axis = Vector2(0, -0.8) if time > 0.4 and time < 3.0 else Vector2.ZERO
    if frame == 42 and step == 0:
     a.jump()
    a._physics_process(1.0 / 120)
   if view == "side":
    game.camera.position = a.position + Vector3(2.8, 1.7, -3.3)
    game.camera.look_at(a.position + Vector3(0, 1.05, 0))
   else:
    game.rig.yaw = 0
    game.rig.pitch = -1.1
    game.rig._process(0)
   await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(folder.path_join("%04d.png" % number))
   number += 1
 print("Captured normal-speed animation frames: ", number)
 quit()
