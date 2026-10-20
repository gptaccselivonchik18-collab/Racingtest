class_name VolleyCourt
extends RefCounted

# Ball centre limits. The run-off area is accessible to every player.
const INNER_X := 8.2 - VolleyBall.RADIUS
const INNER_Z := 12.2 - VolleyBall.RADIUS
const ROOF := 12.0

static func build(root: Node3D) -> void:
 var hall := Node3D.new()
 hall.name = "CourtHall"
 root.add_child(hall)
 var world := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color("172e43")
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color("d0e3eb")
 env.ambient_light_energy = 0.62
 env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
 world.environment = env
 hall.add_child(world)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-63, -22, 0)
 light.light_energy = 0.95
 # Even indoor light, without an expensive shadow map for 12 moving bodies.
 light.shadow_enabled = false
 hall.add_child(light)
 VolleyGeometry.box(hall, Vector3(0, -0.21, 0), Vector3(17, 0.4, 25), Color("b89b70"))
 VolleyGeometry.collider(hall, Vector3(0, -0.20, 0), Vector3(17, 0.4, 25)).set_meta("surface", "floor")
 # Low-cost wood boards and coloured competition floor, 9 by 18 metres.
 for stripe in range(17):
  VolleyGeometry.box(hall, Vector3(-8 + stripe, 0.003, 0), Vector3(0.018, 0.006, 24.4), Color("997b55"))
 VolleyGeometry.box(hall, Vector3(0, 0.008, 0), Vector3(10.2, 0.008, 19.2), Color("193c53"))
 for side in [-1, 1]:
  VolleyGeometry.box(hall, Vector3(0, 0.015, side * 4.5), Vector3(9, 0.01, 9), Color("247988") if side > 0 else Color("d77c54"))
  VolleyGeometry.box(hall, Vector3(0, 0.022, side * 1.5), Vector3(9, 0.006, 3), Color("2a8791") if side > 0 else Color("e18a5e"))
 for z in [-9.0, -3.0, 0.0, 3.0, 9.0]:
  VolleyGeometry.box(hall, Vector3(0, 0.029, z), Vector3(9.05, 0.012, 0.05), Color("fff3dd"))
 for x in [-4.5, 4.5]:
  VolleyGeometry.box(hall, Vector3(x, 0.029, 0), Vector3(0.05, 0.012, 18.05), Color("fff3dd"))
 # Closed sports hall. Continuous colliders stop fast shots and high lobs;
 # no decorative obstacle stands between the player and a resting ball.
 for side in [-1, 1]:
  boundary(hall, Vector3(side * 8.35, 6, 0), Vector3(0.30, 12, 24.7))
  boundary(hall, Vector3(0, 6, side * 12.35), Vector3(17, 12, 0.30))
  VolleyGeometry.box(hall, Vector3(side * 8.37, 0.65, 0), Vector3(0.30, 1.3, 24.7), Color("234759"))
  VolleyGeometry.box(hall, Vector3(0, 0.65, side * 12.37), Vector3(17, 1.3, 0.30), Color("234759"))
  VolleyGeometry.box(hall, Vector3(side * 8.4, 6.65, 0), Vector3(0.25, 10.7, 24.7), Color("315366"))
  VolleyGeometry.box(hall, Vector3(0, 6.65, side * 12.4), Vector3(17, 10.7, 0.25), Color("315366"))
  for z in [-9, -3, 3, 9]:
   VolleyGeometry.box(hall, Vector3(side * 8.22, 5.3, z), Vector3(0.04, 3.8, 3.4), Color("88b8c7"))
   VolleyGeometry.box(hall, Vector3(side * 8.18, 5.3, z), Vector3(0.05, 3.8, 0.06), Color("2a465b"))
  VolleyGeometry.box(hall, Vector3(0, 1.32, side * 12.18), Vector3(16.4, 0.06, 0.04), Color("d9eea0"))
 boundary(hall, Vector3(0, ROOF + 0.15, 0), Vector3(17, 0.3, 25))
 VolleyGeometry.box(hall, Vector3(0, ROOF + 0.18, 0), Vector3(17, 0.3, 25), Color("233e51"))
 for z in [-9, -3, 3, 9]:
  VolleyGeometry.box(hall, Vector3(0, 9.5, z), Vector3(16.5, 0.18, 0.16), Color("66818d"))
  VolleyGeometry.box(hall, Vector3(0, 9.35, z), Vector3(7, 0.08, 0.25), Color("ecf4dd"))
 VolleyGeometry.collider(hall, Vector3(0, 1.93, 0), Vector3(9.7, 1, 0.035)).set_meta("surface", "net")
 VolleyGeometry.collider(hall, Vector3(0, 2.43, 0), Vector3(9.8, 0.06, 0.045)).set_meta("surface", "net")
 for i in range(49):
  VolleyGeometry.box(hall, Vector3(-4.8 + i * 0.2, 1.93, 0), Vector3(0.012, 1, 0.012), Color("a1b3bb"))
 for i in range(6):
  VolleyGeometry.box(hall, Vector3(0, 1.43 + i * 0.2, 0), Vector3(9.6, 0.012, 0.012), Color("a1b3bb"))
 VolleyGeometry.box(hall, Vector3(0, 2.43, 0), Vector3(9.8, 0.06, 0.045), Color("fff5dc"))
 for x in [-4.5, 4.5]:
  VolleyGeometry.box(hall, Vector3(x, 2.68, 0), Vector3(0.025, 1.3, 0.025), Color("ffac75"))
  VolleyGeometry.collider(hall, Vector3(x, 2.68, 0), Vector3(0.025, 1.3, 0.025)).set_meta("surface", "antenna")
 for x in [-4.9, 4.9]:
  VolleyGeometry.box(hall, Vector3(x, 1.3, 0), Vector3(0.18, 2.6, 0.18), Color("264d64"))
  VolleyGeometry.collider(hall, Vector3(x, 1.3, 0), Vector3(0.18, 2.6, 0.18))
 for side in [-1, 1]:
  var sign_text := Label3D.new()
  sign_text.text = "V O L L E Y  /  L A B\nby Selivonchyk Alexey"
  sign_text.font_size = 64
  sign_text.pixel_size = 0.012
  sign_text.position = Vector3(0, 4.0, side * 12.15)
  sign_text.rotation.y = PI if side > 0 else 0.0
  sign_text.modulate = Color("ecf3c4")
  hall.add_child(sign_text)

static func boundary(root: Node3D, at: Vector3, dimensions: Vector3) -> void:
 var wall := VolleyGeometry.collider(root, at, dimensions)
 wall.set_meta("surface", "boundary")
 var material := PhysicsMaterial.new()
 material.bounce = 0.32
 material.friction = 0.65
 wall.physics_material_override = material
