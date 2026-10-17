class_name VolleyBotDifficulty
extends RefCounted

const NAMES := ["Новичок", "Любитель", "Клубный", "Сильный", "Профессионал"]
const SKILLS := [15.0, 40.0, 65.0, 100.0, 140.0]
const THINKING := ["Простые направления, ближайший партнёр, поздняя защита.", "Замечает свободную сторону, строит простую комбинацию.", "Выбирает нападающего и свободные зоны, начинает страховку.", "Читает блок и движение защиты, меняет направления подачи.", "Планирует продолжение атаки, учитывает блок, швы защиты и предыдущие подачи."]

static func closest(skill: float) -> int:
 var result := 0
 for i in range(SKILLS.size()):
  if absf(skill - SKILLS[i]) < absf(skill - SKILLS[result]):
   result = i
 return result

static func profile(index: int) -> Dictionary:
 var w := clampf(index / 4.0, 0, 1)
 return {"reaction": lerpf(0.30, 0.075, w), "anticipation": lerpf(0.67, 1.0, w), "placement": lerpf(0.50, 0.07, w), "tempo": lerpf(0.85, 0.48, w), "court_read": w, "lookahead": lerpf(0.9, 3.6, w), "decision_noise": lerpf(2.0, 0.22, w), "coverage": w * w}
