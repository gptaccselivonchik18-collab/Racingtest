class_name VolleyTraining
extends RefCounted

const NAMES := ["Медленный высокий", "Быстрый мяч", "Мяч слева", "Мяч справа", "Верхняя передача", "Нижний приём"]
var selected := 0
var attempts := 0

func launch(ball: VolleyBall, athlete: VolleyAthlete) -> void:
 attempts += 1
 # Fixed world-space launchers. Never recomputed to chase the athlete.
 var origins := [Vector3(0, 4.5, -2), Vector3(0, 2.9, -3), Vector3(-3, 3.5, 0), Vector3(3, 3.5, 0), Vector3(0, 3.6, 2.6), Vector3(0, 1.7, 1)]
 var velocities := [Vector3(0, 4.0, 5.1), Vector3(0, 3.0, 10), Vector3(3.6, 3.0, 4.3), Vector3(-3.6, 3.0, 4.3), Vector3(0, 1.0, 1.5), Vector3(0, 1.3, 4.8)]
 ball.feed(origins[selected], velocities[selected])
 athlete.last_result = "Мяч запущен • найдите точку встречи"
