class_name VolleyCharacterAbilities
extends RefCounted

static func pose(m: VolleyMotion) -> void:
 var a := m.athlete
 if a.character_id != "kageyama" or a.special_set.is_empty() or a.action not in [VolleyAthlete.Action.PREPARE, VolleyAthlete.Action.STRIKE, VolleyAthlete.Action.RECOVER]:
  return
 var relative := angle_difference(a.visual.global_rotation.y, a.special_yaw)
 var backward := maxf(0, -cos(relative))
 var sideways := sin(relative)
 var progress := smoothstep(0, float(a.mechanic(0).windup), a.action_time)
 var recover := 1.0 - smoothstep(0, float(a.mechanic(0).recovery), a.action_time) if a.action == VolleyAthlete.Action.RECOVER else 1.0
 var load := progress * recover
 m.torso_basis = Basis.from_euler(Vector3(backward * 0.25, clampf(relative, -0.60, 0.60) * 0.55, -sideways * 0.08)).slerp(Basis.IDENTITY, 1.0 - load)
 m.body_offset = Vector3(0, -0.045, 0)
 var direction := Vector3(-sin(relative), 0, -cos(relative))
 var chest := Vector3(0, 1.23, 0)
 for i in range(2):
  var s := -1.0 if i == 0 else 1.0
  var wrist := Vector3(s * 0.14, 2.08 + progress * 0.08, 0) + direction * 0.25
  var pole := Vector3(s * 0.43, 1.70, 0) + direction * 0.12
  m.wrists[i] = chest + m.body_offset + m.torso_basis * (wrist - chest)
  m.poles[i] = chest + m.body_offset + m.torso_basis * (pole - chest)
  m.cinema_palms.append((Vector3.UP * 0.65 + direction * 0.65).normalized())
  m.cinema_wrist_flex.append(-progress * 0.18)
 m.cinema_head = Basis.from_euler(Vector3(backward * 0.22, clampf(relative, -0.55, 0.55), 0))
