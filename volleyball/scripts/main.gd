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
 ball_shadow.position = Vector3(ball.position.x, 0.037, ball.position.z)
 if ball.position.y < -3 or ball.position.length() > 45:
  ball.feed(Vector3(0, 0.3, 1), Vector3.ZERO)

func _physics_process(_dt: float) -> void:
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

func _on_touch(kind: int, _point: Vector3, _outgoing: Vector3) -> void:
 var side := 0 if athlete.position.z >= 0 else 1
 rules.touch(side, 0, kind, athlete.strike_count)
 if kind in [VolleyAthlete.Technique.SERVE, VolleyAthlete.Technique.JUMP_SERVE]:
  rules.serve_contact(athlete.jump_origin if kind == VolleyAthlete.Technique.JUMP_SERVE else athlete.position)
  serving = false

func _on_surface(surface: String) -> void:
 if surface == "floor":
  rules.floor_contact(ball.global_position)
 elif surface == "antenna":
  rules.net_contact(false, true)

func repeat_drill() -> void:
 action_owner = ""
 athlete.cancel_input()
 athlete.action = VolleyAthlete.Action.IDLE
 serving = training.selected in [5, 6]
 rules.reset(serving)
 previous_ball_valid = false
 training.launch(ball, athlete)

func start_drill() -> void:
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

func begin_primary() -> void:
 if not action_owner.is_empty():
  return
 if ball.held:
  athlete.technique = VolleyAthlete.Technique.JUMP_SERVE if training.selected == 6 else VolleyAthlete.Technique.SERVE
  ball.toss()
  serving = true
  rules.reset(true)
  return
 var kind := VolleyAthlete.Technique.SPIKE if athlete.airborne() else VolleyAthlete.Technique.UNDERHAND
 if serving:
  kind = VolleyAthlete.Technique.JUMP_SERVE if athlete.airborne() else VolleyAthlete.Technique.SERVE
 if athlete.begin_action(kind):
  action_owner = "primary"

func begin_secondary() -> void:
 if not action_owner.is_empty():
  return
 if ball.held:
  athlete.technique = VolleyAthlete.Technique.THROW
  athlete.action = VolleyAthlete.Action.PREPARE
  athlete.action_time = 0
  athlete.charged_for = 0
  athlete.power = 0.82
  action_owner = "secondary"
 elif athlete.begin_action(ContextAthlete.BLOCK if athlete.airborne() else VolleyAthlete.Technique.OVERHEAD):
  action_owner = "secondary"

func begin_jump_set() -> void:
 if action_owner.is_empty() and athlete.airborne() and athlete.begin_action(ContextAthlete.JUMP_SET):
  action_owner = "jump_set"

func finish_action(role: String) -> void:
 if action_owner != role:
  return
 if ball.held and role == "secondary":
  ball.throw_held()
 elif athlete.action == VolleyAthlete.Action.PREPARE:
  if role == "primary":
   athlete.technique = (VolleyAthlete.Technique.JUMP_SERVE if athlete.airborne() else VolleyAthlete.Technique.SERVE) if serving else (VolleyAthlete.Technique.SPIKE if athlete.airborne() else VolleyAthlete.Technique.UNDERHAND)
  elif role == "secondary":
   athlete.technique = ContextAthlete.BLOCK if athlete.airborne() else VolleyAthlete.Technique.OVERHEAD
  athlete.release()
 action_owner = ""

func cancel_action(role: String) -> void:
 if role.is_empty() or role == action_owner:
  athlete.cancel_input()
  action_owner = ""

func pickup_or_drop() -> void:
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
