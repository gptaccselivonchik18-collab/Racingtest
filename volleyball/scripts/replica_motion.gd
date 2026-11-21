class_name VolleyReplicaMotion
extends RefCounted

# Presentation follows the host's physics timeline, never packet arrival time.
# No added interpolation queue: input/aim retain their existing latency.
var active := false
var clock := 0.0
var stamp := -1.0
var position := Vector3.ZERO
var sample_position := Vector3.ZERO
var speed := Vector3.ZERO
var correction := 10.0
var teleport_distance := 2.0
var clock_rate := 1.0

func reset() -> void:
 active = false
 stamp = -1.0
 clock_rate = 1.0

static func horizon(age: float) -> float:
 # Short losses ease to rest instead of hitting a hard 120 ms stop.
 # Prediction is bounded to 25 cm per m/s, even if the host disappears.
 if age <= 0.10:
  return maxf(-0.10, age)
 return 0.10 + 0.15 * (1.0 - exp(-(age - 0.10) / 0.15))

func push(at: Vector3, velocity: Vector3, time: float) -> bool:
 if not at.is_finite() or not velocity.is_finite() or not is_finite(time) or time < 0:
  return false
 if active and time <= stamp:
  return false
 var discontinuity := active and at.distance_to(sample_position + speed * (time - stamp)) > teleport_distance
 if not active or discontinuity or absf(time - clock) > 0.75:
  clock = time
  position = at
  clock_rate = 1.0
 else:
  # Ignore ordinary Wi-Fi jitter. Only correct sustained clock drift, gently.
  var drift := time - clock
  clock_rate = 1.0 + clampf((absf(drift) - 0.08) * signf(drift), -0.01, 0.01) if absf(drift) > 0.08 else 1.0
 sample_position = at
 speed = velocity
 stamp = time
 active = true
 return true

func advance(dt: float) -> Vector3:
 if not active:
  return position
 var previous := horizon(clock - stamp)
 clock += maxf(0, dt) * clock_rate
 var prediction := horizon(clock - stamp)
 position += speed * (prediction - previous)
 var target := sample_position + speed * prediction
 position = position.lerp(target, 1.0 - exp(-correction * maxf(0, dt)))
 return position
