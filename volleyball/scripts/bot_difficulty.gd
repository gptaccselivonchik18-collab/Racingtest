class_name VolleyBotDifficulty
extends RefCounted

const NAMES := ["Новичок", "Любитель", "Клубный", "Сильный", "Профессионал"]
const SKILLS := [15.0, 40.0, 65.0, 100.0, 140.0]

static func closest(skill: float) -> int:
 var result := 0
 for i in range(SKILLS.size()):
  if absf(skill - SKILLS[i]) < absf(skill - SKILLS[result]):
   result = i
 return result

static func profile(index: int) -> Dictionary:
 var w := clampf(index / 4.0, 0, 1)
 return {"reaction": lerpf(0.30, 0.075, w), "anticipation": lerpf(0.67, 1.0, w), "placement": lerpf(0.50, 0.07, w), "tempo": lerpf(0.85, 0.48, w)}
