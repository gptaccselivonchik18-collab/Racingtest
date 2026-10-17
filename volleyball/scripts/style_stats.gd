class_name VolleyStyleStats
extends AthleteStats

const KEYS := ["block", "bump", "dive", "jump", "serve", "set", "speed", "spike"]
const STYLE_LABELS := {"block": "Block · блок", "bump": "Bump · нижний приём", "dive": "Dive · подкат", "jump": "Jump · прыжок", "serve": "Serve · подача", "set": "Set · верхний пас", "speed": "Speed · бег", "spike": "Spike · атака"}
const DETAILS := {
 "block": "Шанс остановить Spike соперника с учётом скорости и качества удара; ширина рук, скорость их постановки, устойчивость к сильному мячу, точность угла и гашение вращения. Блок удерживается кнопкой, силы блока нет; Tilt меняет плоскость ладоней.",
 "bump": "Площадь платформы, допуск к моменту касания, приём сильного мяча, точность, высота и гашение боковой скорости / вращения.",
 "dive": "Дальность и скорость подката, ширина спасения, время контакта, контроль отскока, подъём мяча и скорость подъёма на ноги.",
 "jump": "Высота, скорость постановки ног, расход энергии, небольшая коррекция в воздухе, устойчивость и восстановление при приземлении.",
 "serve": "Скорость и верхнее вращение силовой подачи, контроль замаха, доступная глубина обычной подачи, точность, разброс силы, зона и время касания, устойчивость подброса, шанс соскальзывания; точность планера, чистота касания и устойчивость его полёта.",
 "set": "Сила и дуга передачи, точность, стабильность силы, качество сложного касания, гашение входящей скорости / вращения, окно и восстановление.",
 "speed": "Скорость бега, разгон, торможение, смена направления, поворот корпуса и экономичность движения.",
 "spike": "Шанс пробить Block соперника, скорость атаки, точность направления, контроль сильного входящего мяча, окно удара, управление углом, верхнее вращение и восстановление."
}
var cache: Dictionary = {}

func _init() -> void:
 values = {}
 for key in KEYS:
  values[key] = 65.0

func set_stat(key: String, value: float) -> void:
 if key in KEYS and is_finite(value):
  values[key] = value
  cache.clear()

func n(key: String) -> float:
 # Only proportions such as accuracy/control belong in [0,1]. Physical
 # magnitudes use factor() independently and have no rating ceiling.
 return 1.0 / (1.0 + pow(factor(key), -3))

func factor(key: String) -> float:
 var difference := (float(values.get(key, 65)) - 65.0) / 100.0
 return 1.0 + difference if difference >= 0 else 1.0 / (1.0 - difference)

func reset_all() -> void:
 for key in KEYS:
  set_stat(key, 65)

func skill_for(kind: int) -> String:
 match kind:
  0, 8: return "set"
  1: return "bump"
  2, 9: return "spike"
  3, 4: return "serve"
  6: return "block"
  7: return "dive"
 return "set"

func profile(kind: int) -> Dictionary:
 var key := skill_for(kind)
 if cache.has(key):
  return cache[key]
 var w := n(key)
 var p := {"skill": key, "weight": w, "control": lerpf(0.25, 0.98, w), "accuracy": lerpf(6.0, 0.3, w), "strength": lerpf(0.66, 1.28, w), "stability": lerpf(0.10, 0.005, w), "edge": lerpf(0.42, 0.90, w), "pressure": lerpf(23, 75, w), "radius": lerpf(0.86, 1.14, w), "start": lerpf(0.20, 0.04, w), "end": lerpf(0.82, 0.98, w), "duration": lerpf(0.28, 0.34, w), "recovery": lerpf(0.29, 0.11, w), "carry": lerpf(0.20, 0.025, w), "spin": lerpf(0.70, 0.08, w), "windup": lerpf(0.14, 0.06, w)}
 match key:
  "block":
   p.start = lerpf(0.30, 0.10, w)
   p.end = lerpf(0.82, 0.98, w)
   p.duration = lerpf(0.35, 0.57, w)
   p.width = lerpf(0.14, 0.28, w)
   p.reflect = 1.0
   p.steer = lerpf(0.20, 0.70, w)
  "bump":
   p.lift = lerpf(0.84, 1.12, w)
   p.soft_floor = lerpf(0.44, 0.30, w)
  "dive":
   p.travel = lerpf(0.50, 0.86, w)
   p.recover_time = lerpf(1.30, 0.94, w)
   p.cooldown = lerpf(2.4, 0.9, w)
   p.speed = lerpf(4.8, 9.0, w)
   p.contact_from = lerpf(0.14, 0.06, w)
   p.contact_to = lerpf(0.44, 0.68, w)
   p.duration = p.contact_to
   p.lift = lerpf(0.80, 1.15, w)
  "serve":
   p.duration = lerpf(0.40, 0.52, w)
   p.start = lerpf(0.035, 0.005, w)
   p.end = lerpf(0.965, 0.995, w)
   p.radius = lerpf(0.94, 1.12, w)
   p.stability = lerpf(0.04, 0.004, w)
   p.depth = lerpf(5.4, 7.6, w)
   p.arc = lerpf(1.15, 0.85, w)
   p.scatter = lerpf(1.15, 0.15, w)
   p.slip = lerpf(0.15, 0.015, w)
   p.toss_drift = lerpf(0.50, 0.20, w)
   p.power_speed = lerpf(0.82, 1.13, w)
   p.topspin = lerpf(14, 38, w)
   p.coordination = lerpf(0.84, 1.06, w)
  "set":
   p.strength = lerpf(0.68, 1.35, w)
   p.arc = lerpf(0.90, 1.10, w)
   p.soft_floor = lerpf(0.44, 0.30, w)
  "spike":
   p.strength = lerpf(0.68, 1.32, w)
   p.angle = lerpf(42, 58, w)
   p.topspin = lerpf(5, 25, w)
 var gain := factor(key)
 var reach := sqrt(gain)
 p.strength *= gain
 p.radius *= reach
 p.pressure *= gain
 p.accuracy /= gain
 p.stability /= gain
 p.carry /= gain
 p.spin /= gain
 p.windup /= reach
 p.recovery /= reach
 if key == "block":
  p.width *= reach
  p.windup = minf(p.windup, p.duration * 0.40)
 elif key == "dive":
  p.speed *= gain
  p.travel *= reach
  p.recover_time = p.travel + 0.45 / reach
  p.cooldown /= reach
  p.contact_from /= reach
  p.contact_to *= reach
  p.duration = p.contact_to
 elif key == "serve":
  p.depth *= gain
  p.power_speed *= gain
  p.topspin *= gain
  p.scatter /= gain
  p.slip /= gain
 elif key == "spike":
  p.topspin *= gain
 cache[key] = p
 return p

func movement() -> Dictionary:
 var w := n("speed")
 var j := n("jump")
 var speed_gain := factor("speed")
 var jump_gain := factor("jump")
 return {"speed": lerpf(2.8, 7.2, w) * speed_gain, "acceleration": lerpf(7, 19, w) * speed_gain, "braking": lerpf(14, 28, w) * speed_gain, "turn": lerpf(2.5, 6.5, w) * sqrt(speed_gain), "drain": lerpf(0.030, 0.010, w) / speed_gain, "jump_height": lerpf(0.60, 2.0, j) * jump_gain, "plant": lerpf(0.16, 0.04, j) / sqrt(jump_gain), "jump_cost": lerpf(0.11, 0.045, j) / jump_gain, "air": lerpf(0.40, 0.90, j) * sqrt(jump_gain), "landing": lerpf(1.35, 0.65, j), "landing_recovery": lerpf(0.28, 0.10, j) / sqrt(jump_gain)}
