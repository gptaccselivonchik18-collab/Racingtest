extends Node3D

var athlete: ContextAthlete
var ball: VolleyBall
var training := VolleyTraining.new()
var camera: Camera3D
var rig: VolleyCameraRig
var rules := VolleyRules.new()
var serving := false
var action_owner := ""
var previous_ball := Vector3.ZERO
var previous_ball_valid := false
var hud: VolleyHUD
var ball_shadow: MeshInstance3D
var lan: VolleyLAN
var frontend: VolleyFrontend
var lower_serve: VolleyLowerServe

func _ready() -> void:
 if OS.get_name() in ["iOS", "Android"]:
  DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
 _court()
 athlete = ContextAthlete.new()
 athlete.name = "Athlete"
 add_child(athlete)
 athlete.position = Vector3(0, 0.02, 4)
 ball = VolleyBall.new()
 ball.athlete = athlete
 add_child(ball)
 ball.position = Vector3(0, 0.2, 1)
 athlete.serve_solver = ball.solve_launch
 var preview := VolleyTossPreview.new()
 preview.ball = ball
 add_child(preview)
 var strike_preview := VolleyStrikePreview.new()
 strike_preview.game = self
 strike_preview.ball = ball
 add_child(strike_preview)
 athlete.touched.connect(_on_touch)
 ball.surface_contact.connect(_on_surface)
 ball_shadow = VolleyGeometry.sphere(self, Vector3.ZERO, 0.16, Color("143c42"))
 ball_shadow.scale.y = 0.02
 rig = VolleyCameraRig.new()
 rig.athlete = athlete
 rig.ball = ball
 add_child(rig)
 camera = rig.camera
 var layer := CanvasLayer.new()
 add_child(layer)
 hud = VolleyHUD.new()
 hud.game = self
 layer.add_child(hud)
 lan = VolleyLAN.new()
 lan.game = self
 add_child(lan)
 lower_serve = VolleyLowerServe.new()
 lower_serve.game = self
 layer.add_child(lower_serve)
 frontend = VolleyFrontend.new()
 frontend.game = self
 layer.add_child(frontend)

func _court() -> void:
 var world := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color("101e32")
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color("b7cde0")
 env.ambient_light_energy = 0.35
 env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
 world.environment = env
 add_child(world)
 var sun := DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-48, -30, 0)
 sun.light_energy = 0.85
 sun.shadow_enabled = true
 add_child(sun)
 VolleyGeometry.box(self, Vector3(0, -0.21, 0), Vector3(40, 0.4, 40), Color("1b3042"))
 VolleyGeometry.collider(self, Vector3(0, -0.2, 0), Vector3(40, 0.4, 40)).set_meta("surface", "floor")
 VolleyGeometry.box(self, Vector3(0, 0.005, 0), Vector3(13, 0.01, 22), Color("2c686b"))
 VolleyGeometry.box(self, Vector3(0, 0.015, 0), Vector3(9, 0.01, 18), Color("b66b4a"))
 for z in [-9.0, -3.0, 0.0, 3.0, 9.0]:
  VolleyGeometry.box(self, Vector3(0, 0.024, z), Vector3(9.05, 0.012, 0.05), Color("f6e9c9"))
 for x in [-4.5, 4.5]:
  VolleyGeometry.box(self, Vector3(x, 0.024, 0), Vector3(0.05, 0.012, 18.05), Color("f6e9c9"))
 # Net: continuous thin collision sheet (cord mesh visually), top at 2.43 m.
 VolleyGeometry.collider(self, Vector3(0, 1.93, 0), Vector3(9.7, 1.0, 0.035)).set_meta("surface", "net")
 VolleyGeometry.collider(self, Vector3(0, 2.43, 0), Vector3(9.8, 0.06, 0.045)).set_meta("surface", "net")
 for x in [-4.5, 4.5]:
  VolleyGeometry.box(self, Vector3(x, 2.68, 0), Vector3(0.025, 1.3, 0.025), Color("f1a993"))
  VolleyGeometry.collider(self, Vector3(x, 2.68, 0), Vector3(0.025, 1.3, 0.025)).set_meta("surface", "antenna")
 for i in range(49):
  VolleyGeometry.box(self, Vector3(-4.8 + i * 0.2, 1.93, 0), Vector3(0.012, 1, 0.012), Color("9daeb5"))
 for i in range(6):
  VolleyGeometry.box(self, Vector3(0, 1.43 + i * 0.2, 0), Vector3(9.6, 0.012, 0.012), Color("9daeb5"))
 VolleyGeometry.box(self, Vector3(0, 2.43, 0), Vector3(9.8, 0.06, 0.045), Color("f8f2df"))
 for x in [-4.9, 4.9]:
  VolleyGeometry.box(self, Vector3(x, 1.3, 0), Vector3(0.12, 2.6, 0.12), Color("d9ac54"))
  VolleyGeometry.collider(self, Vector3(x, 1.3, 0), Vector3(0.12, 2.6, 0.12))
 for side in [-1, 1]:
  for row in range(3):
   VolleyGeometry.box(self, Vector3(side * (8 + row * 0.8), 0.4 + row * 0.4, 0), Vector3(0.75, 0.6, 19), Color("263d53"))
 for x in [-9, 9]:
  for z in [-10, 10]:
   VolleyGeometry.box(self, Vector3(x, 3, z), Vector3(0.15, 6, 0.15), Color("3c5369"))
   VolleyGeometry.box(self, Vector3(x, 6, z), Vector3(1.4, 0.12, 0.4), Color("f2e7ca"))
 var sign_text := Label3D.new()
 sign_text.text = "V O L L E Y   /   L A B"
 sign_text.font_size = 80
 sign_text.pixel_size = 0.012
 sign_text.position = Vector3(0, 3.2, -11)
 sign_text.modulate = Color("f6d279")
 add_child(sign_text)

func _process(_dt: float) -> void:
 for entry in ([athlete] if not lan.active else lan.players.values().map(func(p: Dictionary): return p.actor)):
  entry.look_target = ball.global_position
  entry.look_target_valid = true
 ball_shadow.position = Vector3(ball.position.x, 0.037, ball.position.z)
 if (not lan.active or lan.hosting) and (ball.position.y < -3 or ball.position.length() > 45):
  ball.feed(Vector3(0, 0.3, 1), Vector3.ZERO)

func _physics_process(_dt: float) -> void:
 if lan.active and not lan.hosting:
  return
 if not ball.held and not ball.pending_feed:
  if previous_ball_valid:
   rules.crossing(previous_ball, ball.global_position)
  previous_ball = ball.global_position
  previous_ball_valid = true
 else:
  previous_ball_valid = false
 if athlete.action != VolleyAthlete.Action.IDLE and not rules.ended:
  for index in range(athlete.get_slide_collision_count()):
   var collision := athlete.get_slide_collision(index)
   if collision.get_collider().get_meta("surface", "") == "net":
    rules.net_contact(true)
  for wrist in athlete.wrists:
   if absf(wrist.z) < VolleyAthlete.HAND_RADIUS + 0.025 and absf(wrist.x) < 4.5 and wrist.y >= 1.43 and wrist.y <= 2.49:
    rules.net_contact(true)

func _on_touch(kind: int, point: Vector3, outgoing: Vector3) -> void:
 _on_player_touch(athlete, lan.player_id(athlete), kind, point, outgoing)

func _on_player_touch(actor: ContextAthlete, id: int, kind: int, _point: Vector3, _outgoing: Vector3) -> void:
 var side: int = lan.players[id].team if lan.active and lan.players.has(id) else (0 if actor.position.z >= 0 else 1)
 rules.touch(side, id, kind, actor.strike_count)
 if lan.active:
  lan.last_touch_team = side
  lan.round_live = true
 if kind in [VolleyAthlete.Technique.SERVE, VolleyAthlete.Technique.JUMP_SERVE]:
  rules.serve_contact(actor.jump_origin if kind == VolleyAthlete.Technique.JUMP_SERVE else actor.position)
  serving = false

func holding_ball() -> bool:
 return ball.held and ball.athlete == athlete

func begin_bump() -> bool:
 if not action_owner.is_empty() or holding_ball():
  return false
 if athlete.begin_action(VolleyAthlete.Technique.UNDERHAND):
  action_owner = "bump"
  return true
 return false

func _on_surface(surface: String) -> void:
 if lan.active and not lan.hosting:
  return
 if surface == "floor":
  rules.floor_contact(ball.global_position)
  if lan.active and lan.round_live:
   lan.award_floor(ball.global_position)
 elif surface == "antenna":
  rules.net_contact(false, true)

func repeat_drill() -> void:
 if lan.active:
  lan.local_action("next")
  return
 lower_serve.cancel_sequence()
 action_owner = ""
 athlete.cancel_input()
 athlete.action = VolleyAthlete.Action.IDLE
 serving = training.selected in [5, 6]
 ball.jump_toss = training.selected == 6
 rules.reset(serving)
 previous_ball_valid = false
 training.launch(ball, athlete)

func start_drill() -> void:
 if lan.active:
  repeat_drill()
  return
 athlete.dive_time = -1
 athlete.dive_cooldown = 0
 athlete.visual.rotation.x = 0
 var shape_node := athlete.get_child(0) as CollisionShape3D
 shape_node.shape.height = 1.75
 shape_node.position.y = 0.875
 athlete.velocity = Vector3.ZERO
 athlete.position = training.start_position()
 athlete.visual.rotation.y = 0
 rig.yaw = 0
 rig.pitch = -0.24
 rig.rendered_yaw = 0
 rig.rendered_pitch = -0.24
 rig.followed = athlete.position + Vector3.UP * 1.45
 repeat_drill()

func reset_player() -> void:
 if lan.active:
  return
 athlete.position = Vector3(0, 0.02, 4)
 athlete.velocity = Vector3.ZERO
 athlete.visual.rotation = Vector3.ZERO
 athlete.cancel_input()
 athlete.dive_time = -1
 athlete.visual.rotation.x = 0
 var shape_node := athlete.get_child(0) as CollisionShape3D
 shape_node.shape.height = 1.75
 shape_node.position.y = 0.875
 athlete.action = VolleyAthlete.Action.IDLE
 action_owner = ""

func running_approach() -> bool:
 return not holding_ball() and not athlete.airborne() and athlete.move_axis.length() > 0.65 and Vector2(athlete.velocity.x, athlete.velocity.z).length() > 1.0

func begin_approach() -> bool:
 if lan.active and not lan.executing:
  return lan.local_action("approach")
 if not action_owner.is_empty() or ball.held or not athlete.arm_approach(VolleyAthlete.Technique.JUMP_SERVE if serving else VolleyAthlete.Technique.SPIKE):
  return false
 action_owner = "approach"
 return true

func begin_primary() -> bool:
 if not action_owner.is_empty():
  return false
 if ball.held:
  if ball.held_mode == VolleyBall.HeldMode.THROW:
   ball.throw_held()
   return true
  athlete.technique = VolleyAthlete.Technique.JUMP_SERVE if training.selected == 6 else VolleyAthlete.Technique.SERVE
  ball.toss()
  serving = true
  rules.reset(true)
  return true
 if athlete.attack_ready:
  return athlete.hit_approach()
 if running_approach() and athlete.arm_approach(VolleyAthlete.Technique.JUMP_SERVE if serving else VolleyAthlete.Technique.SPIKE):
  action_owner = "primary"
  return true
 var kind := VolleyAthlete.Technique.SPIKE
 if serving:
  kind = VolleyAthlete.Technique.JUMP_SERVE if athlete.airborne() else VolleyAthlete.Technique.SERVE
 if athlete.begin_action(kind):
  action_owner = "primary"
  return true
 return false

func begin_secondary() -> bool:
 if not action_owner.is_empty():
  return false
 if ball.held:
  ball.toggle_held_mode()
  return true
 elif athlete.begin_action(ContextAthlete.BLOCK if athlete.airborne() else VolleyAthlete.Technique.OVERHEAD):
  action_owner = "secondary"
  return true
 return false

func begin_jump_set() -> bool:
 if action_owner.is_empty() and athlete.airborne() and athlete.begin_action(ContextAthlete.JUMP_SET):
  action_owner = "jump_set"
  return true
 return false

func finish_action(role: String) -> void:
 if lan.active and not lan.executing:
  lan.local_action(role, "release")
  return
 if action_owner != role:
  return
 if athlete.approach_armed:
  athlete.launch_approach()
  action_owner = ""
  return
 if ball.held and role == "secondary":
  ball.throw_held()
 elif athlete.action == VolleyAthlete.Action.PREPARE:
  if role == "primary":
   athlete.technique = (VolleyAthlete.Technique.JUMP_SERVE if athlete.airborne() else VolleyAthlete.Technique.SERVE) if serving else (VolleyAthlete.Technique.SPIKE)
  elif role == "secondary":
   athlete.technique = ContextAthlete.BLOCK if athlete.airborne() else VolleyAthlete.Technique.OVERHEAD
  athlete.release()
 action_owner = ""

func cancel_action(role: String) -> void:
 if is_instance_valid(lan) and lan.active and not lan.executing:
  lan.local_action("cancel" if role.is_empty() else role, "cancel")
  return
 if role.is_empty() or role == action_owner:
  athlete.cancel_input()
  action_owner = ""

func pickup_or_drop() -> void:
 cancel_action("")
 if ball.held:
  ball.drop()
 else:
  ball.pick_up()

func serve_start() -> void:
 # Explicit training reset, never part of an automatic contact or pickup.
 athlete.position = Vector3(0, 0.02, 9.6)
 athlete.velocity = Vector3.ZERO
 athlete.aim = Vector2(0, -1)
 athlete.visual.rotation = Vector3.ZERO
 athlete.action = VolleyAthlete.Action.IDLE
 ball.feed(Vector3(0.3, 0.2, 9), Vector3.ZERO)
 rules.reset(true)
 serving = true
 athlete.last_result = "Подберите мяч • основная кнопка — подброс"
