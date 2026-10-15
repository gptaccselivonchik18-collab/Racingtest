class_name VolleyTossPreview
extends Node3D

var ball: VolleyBall
var dots: Array[MeshInstance3D] = []
var elapsed := 0.0
var landing: MeshInstance3D

func _ready() -> void:
 var mesh := SphereMesh.new()
 mesh.radius = 0.028
 mesh.height = 0.056
 mesh.radial_segments = 8
 mesh.rings = 4
 var material := VolleyGeometry.material(Color("ffe3a0"))
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 for i in range(73):
  var dot := MeshInstance3D.new()
  dot.mesh = mesh
  dot.material_override = material
  dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(dot)
  dots.append(dot)
 landing = VolleyGeometry.sphere(self, Vector3.ZERO, 0.22, Color("ffe3a0"))
 landing.scale.y = 0.06
 landing.material_override = material

func _physics_process(dt: float) -> void:
 visible = ball.held
 if not visible:
  elapsed = 1
  return
 elapsed += dt
 if elapsed < 1.0 / 30.0:
  return
 elapsed = 0
 var points := ball.preview_points()
 landing.visible = ball.aiming_throw() and points.size() > 0
 if landing.visible:
  landing.global_position = Vector3(ball.throw_target.x, 0.045, ball.throw_target.z)
 for i in range(dots.size()):
  dots[i].visible = i < points.size()
  if i < points.size():
   dots[i].global_position = points[i]
