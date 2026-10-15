class_name VolleyLimbRig
extends Node3D

var athlete: ContextAthlete
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

func apply_pose() -> void:
 var a := athlete
 var speed := Vector2(a.velocity.x, a.velocity.z).length()
 for i in range(2):
  var side := -1.0 if i == 0 else 1.0
  var shoulder := Vector3(side * 0.3, 1.45, 0)
  var wrist := a.visual.to_local(a.wrists[i])
  var elbow := a.visual.to_local(a.elbows[i])
  if a.action == VolleyAthlete.Action.IDLE and not a.holding_ball:
   var swing := sin(a.gait + i * PI) * minf(0.28, speed * 0.055)
   wrist = Vector3(side * 0.33, 0.99 + absf(swing) * 0.12, -0.10 + swing)
  wrist = shoulder + (wrist - shoulder).limit_length(0.855)
  elbow = joint(shoulder, wrist, elbow + Vector3(side * 0.15, 0, 0.08), 0.44, 0.42)
  segment(a.arms[i * 2], shoulder, elbow, 0.071)
  segment(a.arms[i * 2 + 1], elbow, wrist, 0.060)
  a.elbows[i] = a.visual.to_global(elbow)
  a.wrists[i] = a.visual.to_global(wrist)
  elbow_joints[i].global_position = a.elbows[i]
  var palm := Basis(Quaternion(Vector3.UP, (wrist - elbow).normalized()))
  a.hands[i].transform = Transform3D(palm.scaled_local(Vector3(0.86, 0.90, 0.48)), wrist)
  for j in range(5):
   var base := Vector3((j - 1.5) * 0.026, 0.052, 0)
   var tip := base + Vector3(0, 0.052 - absf(j - 1.5) * 0.006, -0.018)
   if j == 4:
    base = Vector3(side * 0.058, 0.0, 0)
    tip = base + Vector3(side * 0.035, 0.035, -0.016)
   world_segment(fingers[i * 5 + j], a.visual.to_global(wrist + palm * base), a.visual.to_global(wrist + palm * tip), 0.012)
  var phase := a.gait + i * PI
  var stride := sin(phase) * minf(0.26, speed * 0.055)
  var lift := maxf(0, cos(phase)) * minf(0.16, speed * 0.032)
  var foot := Vector3(side * 0.15, 0.11 + lift, stride)
  if a.airborne():
   foot.y += 0.14
   foot.z = 0.13 if a.velocity.y > 0 else -0.06
  foot.y += a.landing_load * 0.10
  var hip := Vector3(side * 0.14, 0.83, 0)
  var knee := joint(hip, foot, hip + Vector3(0, -0.3, -0.4), 0.39, 0.38)
  segment(a.legs[i], hip, knee, 0.094)
  world_segment(shins[i], a.visual.to_global(knee), a.visual.to_global(foot), 0.072)
  knees[i].global_position = a.visual.to_global(knee)
  shoes[i].global_transform = Transform3D(a.visual.global_basis, a.visual.to_global(foot + Vector3(0, -0.035, -0.05)))
