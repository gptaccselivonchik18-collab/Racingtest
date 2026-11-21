class_name VolleyBotDifficulty
extends RefCounted

const NAMES := ["Новичок", "Любитель", "Клубный", "Сильный", "Профессионал"]
const SKILLS := [35.0, 50.0, 65.0, 100.0, 140.0]
const THINKING := ["Простые направления, ближайший партнёр, поздняя защита.", "Замечает свободную сторону, строит простую комбинацию.", "Выбирает нападающего и свободные зоны, начинает страховку.", "Читает блок и движение защиты, меняет направления подачи.", "Планирует продолжение атаки, учитывает блок, швы защиты и предыдущие подачи."]

static func closest(skill: float) -> int:
 var result := 0
 for i in range(SKILLS.size()):
  if absf(skill - SKILLS[i]) < absf(skill - SKILLS[result]):
   result = i
 return result

static func profile(index: int) -> Dictionary:
 var w := clampf(index / 4.0, 0, 1)
 # Basic execution is calibrated to the player's body at every level.
 # Tactical reading/noise still distinguishes novice decisions from experts.
 return {"reaction": lerpf(0.14, 0.06, w), "anticipation": 1.0, "scan": lerpf(0.08, 0.04, w), "uncertainty": lerpf(0.02, 0.005, w), "placement": 0.025, "tempo": lerpf(0.85, 0.48, w), "court_read": w, "lookahead": 3.6, "decision_noise": lerpf(0.60, 0.15, w), "coverage": w * w}

static func stat_multiplier(index: int) -> float:
 # Public match levels map to internal indices 0 / 2 / 4.
 return lerpf(0.80,1.0,clampf(index/4.0,0,1))

static func execution(index: int, bot := false) -> Dictionary:
 if bot:return {"fault":0.0005,"scatter":0.04}
 # Game balance targets, not empirical professional-player statistics.
 # Human actors always use club (2); bot difficulty changes this baseline.
 var grade := clampi(index, 0, 4)
 return {"fault": [0.08, 0.05, 0.025, 0.012, 0.004][grade], "scatter": [0.95, 0.76, 0.56, 0.35, 0.20][grade]}

static func contact_error(random: RandomNumberGenerator, index: int, quality: float, accuracy: float, stability: float, bot := false) -> Dictionary:
 var policy := execution(index,bot)
 var pressure := lerpf(2.0, 0.65, clampf(quality, 0, 1))
 var fault := random.randf() < float(policy.fault) * pressure
 var spread := accuracy * float(policy.scatter) * lerpf(1.3, 0.45, quality)
 var pace := stability * float(policy.scatter)
 # Poor touches can go astray; a clean professional touch stays reliable.
 # Accuracy/stability retain their unlimited-stat scaling even on mishits.
 if fault:
  spread *= 4.0
  pace *= 3.0
 return {"fault": fault, "angle": Vector2(random.randf_range(-spread, spread), random.randf_range(-spread, spread) * 0.5), "pace": random.randf_range(1.0 - pace, 1.0 + pace)}
