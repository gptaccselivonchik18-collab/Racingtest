class_name VolleyTossPreview
extends Node3D

var ball: VolleyBall
var dots: Array[MeshInstance3D] = []
var elapsed := 0.0

func _ready() -> void:
 var mesh := SphereMesh.new()
 mesh.radius = 0.028
 mesh.height = 0.056
 mesh.radial_segments = 8
 mesh.rings = 4
 var material := VolleyGeometry.material(Color("ffe3a0"))
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 for i in range(49):
  var dot := MeshInstance3D.new()
  dot.mesh = mesh
  dot.material_override = material
  dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(dot)
  dots.append(dot)

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
 for i in range(dots.size()):
  dots[i].visible = i < points.size()
  if i < points.size():
   dots[i].global_position = points[i]
