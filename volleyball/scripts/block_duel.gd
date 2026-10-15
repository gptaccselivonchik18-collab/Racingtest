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

static func resolve(attack: Dictionary, block: float, block_quality: float, incoming: Vector3, normal: Vector3, rng: RandomNumberGenerator) -> Dictionary:
 var head_on := maxf(0, -incoming.normalized().dot(normal.normalized()))
 var chance := pierce_probability(attack.skill, block, attack.quality, block_quality, incoming.length(), head_on, int(attack.kind) == ContextAthlete.TIP)
 # Exactly one outcome draw per real contact, after geometry/timing checks.
 var pierced := rng.randf() < chance
 var result := {"pierced": pierced, "pierce_chance": chance, "block_chance": 1.0 - chance}
 if pierced:
  var retention := lerpf(0.82, 0.56, clampf(block_quality, 0, 1))
  var scatter := deg_to_rad(lerpf(12.0, 4.0, clampf(block_quality, 0, 1)))
  result.velocity = incoming.rotated(Vector3.UP, rng.randf_range(-scatter, scatter)) * retention
 return result
