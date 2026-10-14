class_name VolleyBall
extends RigidBody3D

var athlete: VolleyAthlete
var acceleration := Vector3.ZERO
var last_velocity := Vector3.ZERO
var pending_feed := false
var feed_position := Vector3.ZERO
var feed_velocity := Vector3.ZERO

func _ready() -> void:
 mass = 0.27
 continuous_cd = true
 collision_layer = 4
 collision_mask = 1
 linear_damp = 0.025
 angular_damp = 0.15
 var mat := PhysicsMaterial.new()
 mat.bounce = 0.73
 mat.friction = 0.45
 physics_material_override = mat
 var cs := CollisionShape3D.new()
 var shape := SphereShape3D.new()
 shape.radius = VolleyAthlete.BALL_RADIUS
 cs.shape = shape
 add_child(cs)
 var ball_mesh := VolleyGeometry.sphere(self, Vector3.ZERO, VolleyAthlete.BALL_RADIUS, Color("ffdf79"))
 var shader := Shader.new()
 shader.code = "shader_type spatial; void fragment(){float p=sin(UV.x*18.8496+sin(UV.y*12.566)*0.6); ALBEDO=p>0.25?vec3(0.97,0.96,0.88):(p< -0.25?vec3(0.08,0.27,0.44):vec3(0.98,0.72,0.17)); ROUGHNESS=0.7;}"
 var material := ShaderMaterial.new()
 material.shader = shader
 ball_mesh.material_override = material

func feed(at: Vector3, speed: Vector3) -> void:
 feed_position = at
 feed_velocity = speed
 pending_feed = true
 sleeping = false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
 if pending_feed:
  state.transform = Transform3D(Basis.IDENTITY, feed_position)
  state.linear_velocity = feed_velocity
  state.angular_velocity = Vector3(2.3, 0.6, 1.1)
  pending_feed = false
  last_velocity = feed_velocity
  return
 if is_instance_valid(athlete):
  var delta_v := athlete.try_contact(state.transform.origin, state.linear_velocity)
  if delta_v != Vector3.ZERO:
   state.apply_central_impulse(delta_v * mass)
   state.angular_velocity += athlete.hand_velocity.cross(delta_v) * 0.12
 # Approximate, bounded Magnus force; no target or player tracking.
 state.apply_central_force((state.angular_velocity.cross(state.linear_velocity) * 0.0004).limit_length(0.15))
 acceleration = (state.linear_velocity - last_velocity) / state.step
 last_velocity = state.linear_velocity
