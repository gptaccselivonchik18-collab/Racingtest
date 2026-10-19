class_name VolleyLimbRig
extends Node3D

var athlete: ContextAthlete
var motion := VolleyMotion.new()
var shins: Array[MeshInstance3D] = []
var knees: Array[MeshInstance3D] = []
var elbow_joints: Array[MeshInstance3D] = []
var shoes: Array[MeshInstance3D] = []
var fingers: Array[MeshInstance3D] = []
var palm_frames: Array[Basis] = []
var shoulder_caps: Array[MeshInstance3D] = []
var neck: MeshInstance3D

static func jersey_mesh() -> ArrayMesh:
 # A shoulder/chest/waist silhouette, with bevelled corners, replaces the
 # runtime box without altering the original source athlete asset.
 var profile := [Vector3(-0.30, 0.22, 0.14), Vector3(-0.12, 0.23, 0.15), Vector3(0.15, 0.27, 0.16), Vector3(0.24, 0.28, 0.14), Vector3(0.30, 0.11, 0.10)]
 var outline := [Vector2(-0.75, -1), Vector2(0.75, -1), Vector2(1, -0.70), Vector2(1, 0.70), Vector2(0.75, 1), Vector2(-0.75, 1), Vector2(-1, 0.70), Vector2(-1, -0.70)]
 var surface := SurfaceTool.new()
 surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 surface.set_smooth_group(0)
 for ring in range(profile.size() - 1):
  for side in range(8):
   var vertices: Array[Vector3] = []
   for index in [side, (side + 1) % 8]:
    for layer in [ring, ring + 1]:
     var p: Vector3 = profile[layer]
     var q: Vector2 = outline[index]
     vertices.append(Vector3(q.x * p.y, p.x, q.y * p.z))
   for vertex in [0, 2, 1, 2, 3, 1]:
    surface.add_vertex(vertices[vertex])
 # Close both ends so looking down cannot see into the jersey.
 for layer in [0, profile.size() - 1]:
  var p: Vector3 = profile[layer]
  for side in range(8):
   var first: Vector2 = outline[side]
   var second: Vector2 = outline[(side + 1) % 8]
   var cap := [Vector3(0, p.x, 0), Vector3(first.x * p.y, p.x, first.y * p.z), Vector3(second.x * p.y, p.x, second.y * p.z)]
   if layer == 0:
    cap.reverse()
   for vertex in cap:
    surface.add_vertex(vertex)
 surface.generate_normals()
 return surface.commit()

func limb(color: Color) -> MeshInstance3D:
 var node := MeshInstance3D.new()
 var mesh := CylinderMesh.new()
 mesh.top_radius = 0.78
 mesh.bottom_radius = 1.0
 mesh.height = 1.0
 mesh.radial_segments = 10
 node.mesh = mesh
 node.material_override = VolleyGeometry.material(color)
 add_child(node)
 return node

func _ready() -> void:
 motion.athlete = athlete
 athlete.visual.get_child(0).mesh = jersey_mesh()
 neck = VolleyGeometry.sphere(self, Vector3.ZERO, 0.08, Color("c28d6b"))
 for i in range(2):
  shoulder_caps.append(VolleyGeometry.sphere(self, Vector3.ZERO, 0.076, Color("c28d6b")))
  shins.append(limb(Color("243952")))
  knees.append(VolleyGeometry.sphere(self, Vector3.ZERO, 0.083, Color("243952")))
  elbow_joints.append(VolleyGeometry.sphere(self, Vector3.ZERO, 0.064, Color("c28d6b")))
  shoes.append(VolleyGeometry.box(self, Vector3.ZERO, Vector3(0.17, 0.10, 0.29), Color("e7e6dc")))
  for j in range(5):
   fingers.append(limb(Color("e3b193")))
 for arm in athlete.arms:
  var mesh := arm.mesh.duplicate() as CylinderMesh
  mesh.top_radius = 0.78
  mesh.bottom_radius = 1.0
  arm.mesh = mesh

static func joint(start: Vector3, end: Vector3, pole: Vector3, upper: float, lower: float) -> Vector3:
 var offset := end - start
 var distance := clampf(offset.length(), 0.001, upper + lower - 0.001)
 var axis := offset.normalized() if offset.length() > 0.001 else Vector3.DOWN
 var across := pole - start - axis * (pole - start).dot(axis)
 if across.length() < 0.001:
  across = axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD)
 across = across.normalized()
 var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
 return start + axis * along + across * sqrt(maxf(0, upper * upper - along * along))

static func palm_frame(elbow: Vector3, wrist: Vector3, normal: Vector3) -> Basis:
 # Fingers follow the forearm; its roll comes from a deliberate palm normal
 # instead of the ambiguous shortest rotation from an upward vector.
 var up := (wrist - elbow).normalized()
 var back := -normal + up * normal.dot(up)
 if back.length_squared() < 0.01:
  back = Vector3.UP - up * up.y
 if back.length_squared() < 0.01:
  back = Vector3.BACK - up * up.z
 back = back.normalized()
 var right := up.cross(back).normalized()
 return Basis(right, up, right.cross(up))

func world_segment(node: MeshInstance3D, start: Vector3, end: Vector3, radius: float) -> void:
 segment(node, to_local(start), to_local(end), radius)

static func segment(node: MeshInstance3D, start: Vector3, end: Vector3, radius: float) -> void:
 var up := (end - start).normalized()
 var right := up.cross(Vector3.FORWARD).normalized()
 if right.length_squared() < 0.01:
  right = Vector3.RIGHT
 # Assign the whole transform together. Reading node.scale after changing it
 # on an already rotated limb introduces shear in Godot's decomposition.
 var axes := Basis(right, up, right.cross(up))
 node.transform = Transform3D(axes.scaled_local(Vector3(radius, start.distance_to(end), radius)), (start + end) * 0.5)

func apply_pose(dt := 0.0) -> void:
 var a := athlete
 motion.update(dt)
 if a.cinema_pose.is_valid():
  a.cinema_pose.call(motion)
 var chest := a.visual.get_child(0) as MeshInstance3D
 chest.transform = Transform3D(motion.torso_basis, Vector3(0, 1.23, 0) + motion.body_offset)
 a.visual.get_child(1).position = Vector3(0, 0.86, 0) + motion.body_offset * 0.75
 var number := a.visual.get_child(4) as Label3D
 number.transform = Transform3D(motion.torso_basis, Vector3(0, 1.23, 0) + motion.body_offset + motion.torso_basis * Vector3(0, 0.02, 0.16))
 update_head()
 neck.global_transform = Transform3D(a.visual.global_basis.scaled_local(Vector3(1, 1.25, 1)), a.visual.to_global(Vector3(0, 1.60, 0) + motion.body_offset))
 var kind: int = a.strike_technique if a.action in [VolleyAthlete.Action.STRIKE, VolleyAthlete.Action.RECOVER] else a.planned_technique() if a.action == VolleyAthlete.Action.PREPARE else a.technique
 for i in range(2):
  var side := -1.0 if i == 0 else 1.0
  var shoulder := motion.shoulder(i)
  shoulder_caps[i].global_position = a.visual.to_global(shoulder)
  var wrist := shoulder + (motion.wrists[i] - shoulder).limit_length(0.855)
  var elbow := joint(shoulder, wrist, motion.poles[i], 0.44, 0.42)
  segment(a.arms[i * 2], shoulder, elbow, 0.071)
  segment(a.arms[i * 2 + 1], elbow, wrist, 0.060)
  a.elbows[i] = a.visual.to_global(elbow)
  a.wrists[i] = a.visual.to_global(wrist)
  elbow_joints[i].global_position = a.elbows[i]
  var normal := Vector3(-side, 0, 0)
  if a.action != VolleyAthlete.Action.IDLE:
   normal = Vector3.FORWARD
  if kind == ContextAthlete.BLOCK and a.action != VolleyAthlete.Action.IDLE:
   var facing := Basis(Vector3.UP, a.visual.global_rotation.y)
   normal = a.visual.global_basis.inverse() * VolleyBlockDuel.hand_normal(-facing.z, facing.x, a.body_tilt(), a.style_stats.n("block"))
  if a.holding_ball:
   normal = (Vector3(0.18, 1.40, -0.56) - wrist).normalized()
  if motion.cinema_palms.size() == 2:
   normal = motion.cinema_palms[i]
  var palm := palm_frame(elbow, wrist, normal)
  if a.float_serve_active and i == 1:
   palm = Basis.IDENTITY
  if kind in [2, 3, 4, 9] and a.action == VolleyAthlete.Action.STRIKE and i == 1 and not a.float_serve_active:
   palm = palm * Basis(Vector3.RIGHT, -smoothstep(0.40, 0.72, a.action_time / a.strike_duration) * 0.65)
  if motion.cinema_wrist_flex.size() == 2:
   palm = palm * Basis(Vector3.RIGHT, motion.cinema_wrist_flex[i])
  if palm_frames.size() > i:
   if dt > 0:
    palm = palm_frames[i].slerp(palm, 1.0 - exp(-24.0 * dt))
   palm_frames[i] = palm
  else:
   palm_frames.append(palm)
  a.hands[i].transform = Transform3D(palm.scaled_local(Vector3(0.86, 0.90, 0.48)), wrist)
  for j in range(5):
   var spread := 1.25 if kind in [0, 6, 8] and a.action != VolleyAthlete.Action.IDLE else 0.80
   var base := Vector3((j - 1.5) * 0.026 * spread, 0.052, 0)
   var curl := 0.035 if a.holding_ball else 0.01 + a.contact_flash * 0.12
   var tip := base + Vector3(0, 0.052 - absf(j - 1.5) * 0.006, -curl)
   if j == 4:
    base = Vector3(-side * 0.058, 0, 0)
    tip = base + Vector3(-side * 0.035, 0.035, -curl)
   world_segment(fingers[i * 5 + j], a.visual.to_global(wrist + palm * base), a.visual.to_global(wrist + palm * tip), 0.012)
  var hip := Vector3(side * 0.14, 0.83, 0) + motion.body_offset * 0.75
  var foot := hip + (motion.feet[i] - hip).limit_length(0.765)
  var knee := joint(hip, foot, hip + Vector3(0, -0.3, -0.4), 0.39, 0.38)
  segment(a.legs[i], hip, knee, 0.094)
  world_segment(shins[i], a.visual.to_global(knee), a.visual.to_global(foot), 0.072)
  knees[i].global_position = a.visual.to_global(knee)
  var shoe_basis := a.visual.global_basis.orthonormalized()
  if not a.airborne() and a.dive_time < 0:
   shoe_basis = Basis(Vector3.UP, a.visual.global_rotation.y)
  if motion.cinema_shoe_pitch.size() == 2:
   shoe_basis = a.visual.global_basis.orthonormalized() * Basis(Vector3.RIGHT, motion.cinema_shoe_pitch[i])
  shoes[i].global_transform = Transform3D(shoe_basis, a.visual.to_global(foot) + shoe_basis * Vector3(0, -0.035, -0.05))

func update_head() -> void:
 var a := athlete
 var head_at := Vector3(0, 1.78, -0.015) + motion.body_offset
 # Counter-rotate body lean: the head points where the player aims, while the
 # torso retains its Tilt and action animation. Nothing is hidden or recast.
 var head_basis := a.visual.global_basis.inverse() * a.view_basis()
 if motion.cinema_head is Basis:
  head_basis = motion.cinema_head
 a.visual.get_child(2).transform = Transform3D(head_basis, head_at)
 a.visual.get_child(3).transform = Transform3D(head_basis, head_at + head_basis * Vector3(0, 0.09, 0.035))
