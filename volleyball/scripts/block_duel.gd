class_name VolleyBlockDuel
extends RefCounted

# These are balance probabilities, not a claim about professional match rates.
# StyleStats.n supplies smooth, bounded ratings for unrestricted raw stats.
static func pierce_probability(spike: float, block: float, attack_quality: float, block_quality: float, speed: float, head_on := 1.0, tip := false) -> float:
 var attack_rating := lerpf(0.45, 1.55, clampf(spike, 0, 1))
 var defense_rating := lerpf(0.45, 1.55, clampf(block, 0, 1))
 if tip:
  attack_rating *= 0.65
 var odds := 1.8 * log(attack_rating / defense_rating)
 odds += 1.2 * (clampf(attack_quality, 0, 1) - clampf(block_quality, 0, 1))
 odds += 0.45 * clampf((speed - 20.0) / 15.0, -1, 1)
 odds += 0.75 * (1.0 - clampf(head_on, 0, 1))
 return clampf(1.0 / (1.0 + exp(-odds)), 0.05, 0.95)

static func hand_normal(forward: Vector3, right: Vector3, tilt: Vector2, skill: float) -> Vector3:
 # Forward input is negative Y. Pressed palms turn the reflection down;
 # withdrawn palms open upward. Side tilt also permits a real block-out.
 return (forward + Vector3.UP * (0.20 + tilt.y * lerpf(0.47, 0.56, skill)) + right * tilt.x * lerpf(0.40, 0.55, skill)).normalized()

static func reflection(incoming: Vector3, normal: Vector3, quality: float) -> Vector3:
 # A passive hand plane redirects existing momentum, without charged power
 # or a speed boost from rapidly animated wrists.
 return incoming.bounce(normal.normalized()) * lerpf(0.97, 1.0, clampf(quality, 0, 1))

static func resolve(attack: Dictionary, block: float, block_quality: float, incoming: Vector3, normal: Vector3, rng: RandomNumberGenerator, backward_lean := 0.0) -> Dictionary:
 var head_on := maxf(0, -incoming.normalized().dot(normal.normalized()))
 var chance := pierce_probability(attack.skill, block, attack.quality, block_quality, incoming.length(), head_on, int(attack.kind) == ContextAthlete.TIP)
 # Exactly one outcome draw per real contact, after geometry/timing checks.
 var pierced := rng.randf() < chance
 var result := {"pierced": pierced, "pierce_chance": chance, "block_chance": 1.0 - chance}
 if pierced:
  var velocity := incoming * lerpf(0.98, 0.94, clampf(block_quality, 0, 1))
  var open_hands := smoothstep(0.12, 1.0, backward_lean)
  if open_hands > 0:
   var horizontal := Vector3(incoming.x, 0, incoming.z).normalized()
   var elevation := lerpf(atan2(incoming.y, Vector2(incoming.x, incoming.z).length()), deg_to_rad(44), open_hands)
   velocity = (horizontal * cos(elevation) + Vector3.UP * sin(elevation)) * velocity.length()
  result.velocity = velocity
 return result
