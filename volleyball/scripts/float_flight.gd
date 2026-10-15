class_name VolleyFloatFlight
extends RefCounted

# A bounded, smoothly changing wake-force approximation for a low-spin ball.
# No destination is stored here. The same seed is independent of frame rate.
var phases := Vector3.ZERO
var frequencies := Vector3.ONE
var bias := Vector2.ZERO
var coefficient := 0.1

func configure(skill: float, seed_value: int) -> void:
 var random := RandomNumberGenerator.new()
 random.seed = seed_value
 phases = Vector3(random.randf_range(-PI, PI), random.randf_range(-PI, PI), random.randf_range(-PI, PI))
 frequencies = Vector3(random.randf_range(4.5, 8.0), random.randf_range(9.0, 15.0), random.randf_range(2.0, 3.8))
 bias = Vector2(random.randf_range(-0.45, 0.45), random.randf_range(-0.28, 0.28))
 coefficient = lerpf(0.14, 0.075, clampf(skill, 0, 1))

func force(velocity: Vector3, spin: Vector3, seconds: float) -> Vector3:
 var speed := velocity.length()
 var side := Vector3(velocity.z, 0, -velocity.x).normalized()
 if side.length_squared() < 0.01:
  return Vector3.ZERO
 var lift := side.cross(velocity.normalized()).normalized()
 if lift.y < 0:
  lift = -lift
 var phase := phases + frequencies * seconds
 var lateral := bias.x + sin(phase.x) * 0.58 + sin(phase.y) * 0.26 + sin(phase.z) * 0.32
 var vertical := bias.y + sin(phase.y + 0.8) * 0.34 + sin(phase.z + 1.7) * 0.30
 var dynamic_pressure := 0.5 * 1.2 * PI * 0.105 * 0.105 * speed * speed
 var regime := smoothstep(4, 11, speed) * (1.0 - smoothstep(20, 32, speed) * 0.60)
 var low_spin := 1.0 / (1.0 + spin.length_squared() * 0.18)
 return ((side * lateral + lift * vertical) * dynamic_pressure * coefficient * regime * low_spin).limit_length(0.48)
