extends Node3D

var athlete: VolleyAthlete
var ball: VolleyBall
var training := VolleyTraining.new()
var camera: Camera3D
var hud: VolleyHUD
var guide: Array[MeshInstance3D] = []
var ball_shadow: MeshInstance3D

func _ready() -> void:
 _court()
 athlete = VolleyAthlete.new()
 add_child(athlete)
 athlete.position = Vector3(0, 0.02, 4)
 ball = VolleyBall.new()
 ball.athlete = athlete
 add_child(ball)
 ball.position = Vector3(0, 0.2, 1)
 ball_shadow = VolleyGeometry.sphere(self, Vector3.ZERO, 0.16, Color("143c42"))
 ball_shadow.scale.y = 0.02
 camera = Camera3D.new()
 camera.fov = 66
 add_child(camera)
 camera.position = Vector3(0, 5.0, 10.8)
 camera.look_at(Vector3(0, 1.2, 0))
 camera.current = true
 for i in range(16):
  var dash := VolleyGeometry.sphere(self, Vector3.ZERO, 0.035 if i % 2 else 0.055, Color("ffdb7e"))
  dash.visible = false
  guide.append(dash)
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
 env.ambient_light_energy = 0.65
 env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 world.environment = env
 add_child(world)
 var sun := DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-48, -30, 0)
 sun.light_energy = 1.6
 sun.shadow_enabled = true
 add_child(sun)
 VolleyGeometry.box(self, Vector3(0, -0.21, 0), Vector3(40, 0.4, 40), Color("1b3042"))
 VolleyGeometry.collider(self, Vector3(0, -0.2, 0), Vector3(40, 0.4, 40))
 VolleyGeometry.box(self, Vector3(0, 0.005, 0), Vector3(13, 0.01, 22), Color("2c686b"))
 VolleyGeometry.box(self, Vector3(0, 0.015, 0), Vector3(9, 0.01, 18), Color("b66b4a"))
 for z in [-9.0, -3.0, 0.0, 3.0, 9.0]:
  VolleyGeometry.box(self, Vector3(0, 0.024, z), Vector3(9.05, 0.012, 0.05), Color("f6e9c9"))
 for x in [-4.5, 4.5]:
  VolleyGeometry.box(self, Vector3(x, 0.024, 0), Vector3(0.05, 0.012, 18.05), Color("f6e9c9"))
 # Net: continuous thin collision sheet (cord mesh visually), top at 2.43 m.
 VolleyGeometry.collider(self, Vector3(0, 1.93, 0), Vector3(9.7, 1.0, 0.035))
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

func _process(dt: float) -> void:
 var target := athlete.position + Vector3(0, 4.8, 6.8)
 target.x *= 0.6
 camera.position = camera.position.lerp(target, 1.0 - exp(-4.0 * dt))
 camera.look_at(athlete.position + Vector3(0, 1.3, -3.7))
 for i in range(guide.size()):
  guide[i].visible = athlete.action == VolleyAthlete.Action.PREPARE
  guide[i].position = athlete.position + Vector3(0, 1.65, -0.25) + athlete.desired_direction() * (0.3 + i * 0.23)
 ball_shadow.position = Vector3(ball.position.x, 0.037, ball.position.z)
 if ball.position.y < -3 or ball.position.length() > 45:
  ball.feed(Vector3(0, 0.3, 1), Vector3.ZERO)

func repeat_drill() -> void:
 training.launch(ball, athlete)

func reset_player() -> void:
 athlete.position = Vector3(0, 0.02, 4)
 athlete.velocity = Vector3.ZERO
 athlete.visual.rotation = Vector3.ZERO
 athlete.cancel_input()
