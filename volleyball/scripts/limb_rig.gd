class_name VolleyLimbRig
extends Node3D

var athlete: ContextAthlete
var motion := VolleyMotion.new()
var shins: Array[MeshInstance3D] = []
var knees: Array[MeshInstance3D] = []
var elbow_joints: Array[MeshInstance3D] = []
var shoes: Array[MeshInstance3D] = []
var fingers: Array[MeshInstance3D] = []

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
 for i in range(2):
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
  across = axis.cross(Vector3.RIGHT)
 across = across.normalized()
 var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
 return start + axis * along + across * sqrt(maxf(0, upper * upper - along * along))

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
 var chest := a.visual.get_child(0) as MeshInstance3D
 chest.transform = Transform3D(motion.torso_basis, Vector3(0, 1.23, 0) + motion.body_offset)
 a.visual.get_child(1).position = Vector3(0, 0.86, 0) + motion.body_offset * 0.75
 var number := a.visual.get_child(4) as Label3D
 number.transform = Transform3D(motion.torso_basis, Vector3(0, 1.23, 0) + motion.body_offset + motion.torso_basis * Vector3(0, 0.02, 0.16))
 var head_basis := motion.torso_basis
 if a.look_target_valid:
  var look := a.visual.to_local(a.look_target) - Vector3(0, 1.78, 0)
  if look.length() > 0.05:
   head_basis = Basis.from_euler(Vector3(clampf(atan2(look.y, maxf(0.1, Vector2(look.x, look.z).length())), -0.35, 0.35), clampf(atan2(-look.x, -look.z), -0.7, 0.7), 0))
 var head_at := Vector3(0, 1.78, -0.015) + motion.body_offset
 a.visual.get_child(2).position = head_at
 a.visual.get_child(3).transform = Transform3D(head_basis, head_at + head_basis * Vector3(0, 0.09, 0.035))
 var kind: int = a.strike_technique if a.action in [VolleyAthlete.Action.STRIKE, VolleyAthlete.Action.RECOVER] else a.technique
 for i in range(2):
  var side := -1.0 if i == 0 else 1.0
  var shoulder := motion.shoulder(i)
  var wrist := shoulder + (motion.wrists[i] - shoulder).limit_length(0.855)
  var elbow := joint(shoulder, wrist, motion.poles[i] + Vector3(side * 0.15, 0, 0.08), 0.44, 0.42)
  segment(a.arms[i * 2], shoulder, elbow, 0.071)
  segment(a.arms[i * 2 + 1], elbow, wrist, 0.060)
  a.elbows[i] = a.visual.to_global(elbow)
  a.wrists[i] = a.visual.to_global(wrist)
  elbow_joints[i].global_position = a.elbows[i]
  var palm := Basis(Quaternion(Vector3.UP, (wrist - elbow).normalized()))
  if kind in [2, 3, 4, 9] and a.action == VolleyAthlete.Action.STRIKE and i == 1:
   palm = palm * Basis(Vector3.RIGHT, -smoothstep(0.40, 0.72, a.action_time / a.strike_duration) * 0.65)
  a.hands[i].transform = Transform3D(palm.scaled_local(Vector3(0.86, 0.90, 0.48)), wrist)
  for j in range(5):
   var spread := 1.25 if kind in [0, 6, 8] and a.action != VolleyAthlete.Action.IDLE else 0.80
   var base := Vector3((j - 1.5) * 0.026 * spread, 0.052, 0)
   var curl := 0.035 if a.holding_ball else 0.01 + a.contact_flash * 0.12
   var tip := base + Vector3(0, 0.052 - absf(j - 1.5) * 0.006, -curl)
   if j == 4:
    base = Vector3(side * 0.058, 0, 0)
    tip = base + Vector3(side * 0.035, 0.035, -curl)
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
  shoes[i].global_transform = Transform3D(shoe_basis, a.visual.to_global(foot) + shoe_basis * Vector3(0, -0.035, -0.05))
