class_name AthleteStats
extends RefCounted

const LABELS := {
 "strength": "Сила", "jump": "Прыгучесть", "speed": "Скорость",
 "agility": "Ловкость", "accuracy": "Точность", "control": "Контроль мяча",
 "reaction": "Реакция", "coordination": "Координация", "stamina": "Выносливость"
}
var values := {"strength": 65.0, "jump": 65.0, "speed": 65.0,
 "agility": 65.0, "accuracy": 75.0, "control": 75.0, "reaction": 65.0,
 "coordination": 65.0, "stamina": 75.0}

func n(key: String) -> float:
 return clampf(float(values[key]), 1.0, 100.0) / 100.0

func set_stat(key: String, value: float) -> void:
 if values.has(key):
  values[key] = clampf(value, 1.0, 100.0)
