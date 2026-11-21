extends SceneTree

func _initialize() -> void:
 call_deferred("capture")

func capture() -> void:
 var scene := load("res://scenes/Main.tscn") as PackedScene
 var game := scene.instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 if OS.get_environment("VOLLEY_CAPTURE_SERVE") == "1":
  game.training.selected = 5
  game.start_drill()
  for i in range(20):
   await physics_frame
  game.ball.pick_up()
  game.athlete.set_physics_process(false)
  game.athlete._update_pose(0)
  game.ball.aim_toss(Vector2(35, 45))
  game.rig.distance = 3.8
  game.rig.yaw = -0.85
  game.rig.pitch = 0.05
  if OS.get_environment("VOLLEY_CAPTURE_THROW") == "1":
   game.ball.toggle_held_mode()
   game.ball.throw_target = Vector3(1.2, VolleyBall.RADIUS, 6.7)
 if OS.get_environment("VOLLEY_CAPTURE_COMBO") == "1":
  for i in range(20):
   await physics_frame
  game.hud._touch_down(90, game.hud.left_center + Vector2(0, -game.hud.radius))
  for i in range(60):
   await physics_frame
  game.begin_primary()
  game.finish_action("primary")
  for i in range(30):
   await physics_frame
  game.athlete.set_physics_process(false)
  game.rig.distance = 3.8
  game.rig.yaw = 0.9
  game.rig.pitch = -0.15
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
