class_name VolleyTraining
extends RefCounted

const NAMES := ["Приём", "Верхний пас", "Пас в прыжке", "Нападение", "Блок", "Подача", "Подача в прыжке", "Подкат"]
const ORIGINS := [Vector3(0, 2.2, 1.2), Vector3(0, 3.4, 2.3), Vector3(0, 3.8, 2.75), Vector3(0.2, 4.3, 0.6), Vector3(0.16, 3.68, -1.6), Vector3(0.3, 0.2, 9), Vector3(0.3, 0.2, 9), Vector3(0, 0.86, 0.4)]
const VELOCITIES := [Vector3(0, 1.65, 3.15), Vector3(0, 1.26, 1.7), Vector3(0, 1.3, 1.7), Vector3(0, 2, 0.9), Vector3(0, 2, 4.2), Vector3.ZERO, Vector3.ZERO, Vector3(0, 1.3, 5)]
var selected := 0
var attempts := 0

func start_position() -> Vector3:
 return Vector3(0, 0.02, 9.6 if selected in [5, 6] else 1.6 if selected == 3 else 0.65 if selected == 4 else 4.0)

func launch(ball: VolleyBall, athlete: VolleyAthlete) -> void:
 selected = clampi(selected, 0, NAMES.size() - 1)
 attempts += 1
 # World-space launchers never chase the athlete. Resetting a player is a
 # separate explicit menu action, so a badly positioned receive can miss.
 ball.feed(ORIGINS[selected], VELOCITIES[selected])
 athlete.last_result = "Подача: подберите мяч" if selected in [5, 6] else "Найдите момент касания • ↻ / R — следующий"
