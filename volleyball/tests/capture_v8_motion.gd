extends SceneTree

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 root.size = Vector2i(600, 480)
 root.content_scale_size = Vector2i(600, 480)
 var game: Node3D = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.frontend.hide()
 game.hud.hide()
 game.hud.set_process(false)
 game.rig.set_process(false)
 var a: ContextAthlete = game.athlete
 a.set_physics_process(false)
 a.set_process(false)
 game.ball.freeze = true
 game.ball.visible = false
 var layer := CanvasLayer.new()
 root.add_child(layer)
 var label := Label.new()
 label.position = Vector2(18, 15)
 label.add_theme_font_size_override("font_size", 23)
 label.add_theme_color_override("font_color", Color("ffe3a0"))
 layer.add_child(label)
 var subtitle := Label.new()
 subtitle.position = Vector2(18, 49)
 subtitle.text = "VOLLEY / LAB 0.8 • движения замедлены"
 subtitle.add_theme_font_size_override("font_size", 14)
 layer.add_child(subtitle)
 var folder := OS.get_environment("VOLLEY_CAPTURE_DIR")
 DirAccess.make_dir_recursive_absolute(folder)
 var clips := [[-1, "БЕГ / ПОСТАНОВКА СТОП"], [1, "НИЖНИЙ ПРИЁМ"], [0, "ВЕРХНИЙ ПАС"], [2, "АТАКА С МЕСТА"], [12, "АТАКА В ПРЫЖКЕ"], [3, "ПОДАЧА"], [4, "ПОДАЧА В ПРЫЖКЕ"], [8, "ПАС В ПРЫЖКЕ"], [6, "БЛОК"], [7, "ПОДКАТ / ПОДЪЁМ"], [-2, "МЯЧ В РУКАХ / ПОДБРОС"], [5, "БРОСОК"], [9, "СКИДКА"]]
 var number := 0
 for clip in clips:
  label.text = clip[1]
  a.position = Vector3(0, 0.02, 5)
  a.velocity = Vector3.ZERO
  a.move_axis = Vector2.ZERO
  a.visual.rotation = Vector3.ZERO
  a.camera_yaw = 0
  a.tilt = Vector2.ZERO
  a.lean = Vector2.ZERO
  a.energy = 1
  a.landing_cooldown = 0
  a.dive_cooldown = 0
  a.dive_time = -1
  a.action = VolleyAthlete.Action.IDLE
  a.holding_ball = false
  a.release_time = 0
  a.air_attack = false
  a.limb_rig.motion.stance = [false, false]
  a.limb_rig.motion.previous_state = ""
  a.limb_rig.motion.origins.clear()
  a._update_pose(0)
  a._physics_process(1.0 / 120)
  var count := 42 if clip[0] == 7 else 30
  for frame in range(count):
   for substep in range(4):
    var time := float(frame * 4 + substep) / 120
    if clip[0] == -1:
     a.move_axis = Vector2.RIGHT if time < 0.65 else Vector2.ZERO
    elif clip[0] == -2:
     a.holding_ball = time < 0.55
     if frame == 16 and substep == 0:
      a.holding_ball = false
      a.animate_release()
    elif clip[0] == 7:
     if frame == 0 and substep == 0:
      a.move_axis = Vector2(0, -1)
      a.dive()
    else:
     if frame == 0 and substep == 0:
      if clip[0] in [4, 6, 8, 12]:
       a.jump()
      a.begin_action(2 if clip[0] == 12 else clip[0])
     if frame == 7 and substep == 0:
      a.charged_for = 0.20
      a.release()
     a.tilt = Vector2(0.25, -0.15)
    a._physics_process(1.0 / 120)
   game.ball.visible = a.holding_ball
   if a.holding_ball:
    game.ball.position = a.hold_position()
   var base := Vector3(a.position.x, a.position.y * 0.75, a.position.z)
   game.camera.position = base + Vector3(2.7, 2.05, -3.2)
   game.camera.look_at(base + Vector3(0, 1.15, 0))
   await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(folder.path_join("%04d.png" % number))
   number += 1
 print("Captured animation frames: ", number)
 quit()
