class_name VolleyGeometry
extends RefCounted

static func material(color: Color) -> StandardMaterial3D:
 var m := StandardMaterial3D.new()
 m.albedo_color = color
 m.roughness = 0.85
 return m

static func box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
 var mesh := BoxMesh.new()
 mesh.size = size
 var node := MeshInstance3D.new()
 node.mesh = mesh
 node.material_override = material(color)
 parent.add_child(node)
 node.position = at
 return node

static func sphere(parent: Node3D, at: Vector3, radius: float, color: Color) -> MeshInstance3D:
 var mesh := SphereMesh.new()
 mesh.radius = radius
 mesh.height = radius * 2.0
 mesh.radial_segments = 16
 mesh.rings = 8
 var node := MeshInstance3D.new()
 node.mesh = mesh
 node.material_override = material(color)
 parent.add_child(node)
 node.position = at
 return node

static func segment(node: MeshInstance3D, a: Vector3, b: Vector3, radius: float) -> void:
 node.position = (a + b) * 0.5
 node.scale = Vector3(radius, a.distance_to(b), radius)
 var up := (b - a).normalized()
 var right := up.cross(Vector3.FORWARD).normalized()
 if right.length_squared() < 0.01:
  right = Vector3.RIGHT
 node.basis = Basis(right, up, right.cross(up)).scaled(node.scale)

static func limb(parent: Node3D, color: Color) -> MeshInstance3D:
 var mesh := CylinderMesh.new()
 mesh.top_radius = 1.0
 mesh.bottom_radius = 1.0
 mesh.height = 1.0
 mesh.radial_segments = 8
 var node := MeshInstance3D.new()
 node.mesh = mesh
 node.material_override = material(color)
 parent.add_child(node)
 return node

static func collider(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
 var body := StaticBody3D.new()
 body.collision_layer = 1
 body.collision_mask = 0
 parent.add_child(body)
 body.position = at
 var shape := BoxShape3D.new()
 shape.size = size
 var cs := CollisionShape3D.new()
 cs.shape = shape
 body.add_child(cs)
 return body

static func distance_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
 var ab := b - a
 var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
 return p.distance_to(a + ab * t)
