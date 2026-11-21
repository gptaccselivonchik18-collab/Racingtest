extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 root.size = Vector2i(1280, 720)
 var game: Node3D = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.hide()
 game.hud.set_process(false)
 game.rig.set_process(false)
 var a: ContextAthlete = game.athlete
 a.set_physics_process(false)
 a.position = Vector3(0, 0.02, 5)
 a.velocity = Vector3.ZERO
 a.tilt = Vector2.ZERO
 a.lean = Vector2.ZERO
 a.visual.rotation = Vector3.ZERO
 game.ball.freeze = true
 game.ball.position = Vector3(0, 3, 3)
 var folder := OS.get_environment("VOLLEY_CAPTURE_DIR")
 DirAccess.make_dir_recursive_absolute(folder)
 for clip in [["eyes", 0.15, -1], ["body", -1.20, -1], ["set", 0.82, 0], ["bump", -0.55, 1], ["held", -0.65, -2]]:
  a.action = VolleyAthlete.Action.IDLE
  a.holding_ball = clip[2] == -2
  if clip[2] >= 0:
   a.begin_action(clip[2])
  for i in range(40):
   a._update_pose(1.0 / 120)
  game.rig.yaw = 0
  game.rig.pitch = clip[1]
  game.rig._process(0)
  if a.holding_ball:
   game.ball.position = a.hold_position()
  for i in range(8):
   await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(folder.path_join("%s.png" % clip[0]))
 print("Captured first-person views")
 quit()
