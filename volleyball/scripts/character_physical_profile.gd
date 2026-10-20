class_name VolleyCharacterPhysicalProfile
extends RefCounted

const MODEL_HEIGHT := 2.04

static func apply(a: ContextAthlete) -> void:
 if not is_instance_valid(a.visual):
  return
 var ratio := a.height_cm / (MODEL_HEIGHT * 100.0)
 a.physical_scale = ratio
 a.visual.scale = Vector3.ONE * ratio
 if a.volley_role=="L":
  var shirt := a.visual.get_child(0) as MeshInstance3D
  if shirt:
   var material := StandardMaterial3D.new()
   material.albedo_color = Color("f4e9c9")
   shirt.material_override = material
 var shape := a.get_child(0) as CollisionShape3D
 if shape and shape.shape is CapsuleShape3D:
  shape.shape = shape.shape.duplicate()
  shape.shape.height = 1.75 * ratio
  shape.shape.radius = 0.26 * ratio
  shape.position.y = shape.shape.height * 0.5
 var tag := a.get_node_or_null("TeamTag") as Label3D
 if tag:
  tag.position.y = a.height_cm / 100.0 + 0.20
  if a is VolleyGameBot:
   tag.text = "%s · #%d · %s%d" % [VolleyCharacterDatabase.get_character(a.character_id).name, int(VolleyCharacterDatabase.get_character(a.character_id).number), "A" if a.court_team == 0 else "B", a.slot + 1]
 var number := a.visual.get_child(4) as Label3D
 if number:
  number.text = str(VolleyCharacterDatabase.get_character(a.character_id).number)
 if is_instance_valid(a.limb_rig):
  for node in a.limb_rig.shoulder_caps + a.limb_rig.elbow_joints + a.limb_rig.knees:
   node.scale = Vector3.ONE * ratio
