class_name VolleyPractice
extends Node3D

const ACTIONS := ["Нижний приём под сетку", "Нижний приём за сетку", "Пас под сетку", "Пас за сетку", "Атака за сетку в прыжке", "Подача"]
var game: Node3D
var enabled := false
var modes: Array = [1, 3, 4, 5]
var interval := 3.0
var anchor := Vector3(0, 0.02, -5)
var target_x := 0.0
var target_depth := 5.0
var level := 65.0
var bot: VolleyPracticeBot
var controls: Array[Control] = []
var hint: Label

func _ready() -> void:
 name = "Practice"
 process_mode = Node.PROCESS_MODE_ALWAYS

func settings_state() -> Dictionary:
 return {"enabled": enabled, "modes": modes.duplicate(), "interval": interval, "anchor": anchor, "target_x": target_x, "target_depth": target_depth, "level": level}

func can_configure() -> bool:
 return not game.lan.active or game.lan.hosting

func configure(values: Dictionary, broadcast := true) -> bool:
 if broadcast and not can_configure():
  return false
 var at: Variant = values.get("anchor", anchor)
 if not at is Vector3 or not at.is_finite():
  return false
 var chosen: Variant = values.get("modes", modes)
 if not chosen is Array or chosen.size() > ACTIONS.size():
  return false
 for mode in chosen:
  if not mode is int or mode < 0 or mode >= ACTIONS.size():
   return false
 for key in ["interval", "target_x", "target_depth", "level"]:
  var value: Variant = values.get(key, 0)
  if not (value is int or value is float) or not is_finite(float(value)):
   return false
 enabled = bool(values.get("enabled", enabled))
 modes = chosen.duplicate()
 interval = clampf(float(values.get("interval", interval)), 1.5, 12)
 anchor = Vector3(clampf(at.x, -4.0, 4.0), 0.02, clampf(at.z, -10.5, 10.5))
 if absf(anchor.z) < 1.0:
  anchor.z = 1.0 if anchor.z >= 0 else -1.0
 target_x = clampf(float(values.get("target_x", target_x)), -4, 4)
 target_depth = clampf(float(values.get("target_depth", target_depth)), 1.5, 8)
 level = float(values.get("level", level))
 if enabled and not is_instance_valid(bot):
  bot = VolleyPracticeBot.new()
  bot.name = "Coach"
  bot.practice = self
  bot.process_mode = Node.PROCESS_MODE_PAUSABLE
  bot.replica = game.lan.active and not game.lan.hosting
  add_child(bot)
  bot.serve_solver = game.ball.solve_launch
  bot.power_serve_solver = game.ball.solve_power_serve
  bot.set_physics_process(not bot.replica)
 if is_instance_valid(bot):
  bot.visible = enabled
  bot.set_physics_process(enabled and not bot.replica)
  bot.position = anchor
  bot.network_age = -1
  bot.velocity = Vector3.ZERO
  bot.cancel_input()
  bot.action = VolleyAthlete.Action.IDLE
  bot.scheduled = false
  bot.waiting = 0
  bot.camera_yaw = 0 if anchor.z > 0 else PI
  bot.visual.rotation.y = bot.camera_yaw
  for key in VolleyStyleStats.KEYS:
   bot.stats.set_stat(key, level)
 if is_instance_valid(game.lan):
  game.lan.refresh_contacts()
 if broadcast and game.lan.active and game.lan.hosting:
  game.lan._send_room_state()
 return true

func target_for(mode: int) -> Vector3:
 var side := 1.0 if anchor.z >= 0 else -1.0
 var z := side * 1.5 if mode in [0, 2] else -side * target_depth
 return Vector3(target_x, VolleyBall.RADIUS, z)

func add_settings(hud: VolleyHUD) -> void:
 var panel := hud._tab("Бот / комната")
 hint = Label.new()
 hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 panel.add_child(hint)
 var toggle := CheckButton.new()
 toggle.text = "Тренировочный бот на площадке"
 toggle.toggled.connect(func(on: bool): configure({"enabled": on}))
 panel.add_child(toggle)
 controls.append(toggle)
 toggle.set_meta("setting", "enabled")
 for i in range(ACTIONS.size()):
  var mode: int = i
  var box := CheckButton.new()
  box.text = ACTIONS[i]
  box.button_pressed = i in modes
  box.toggled.connect(func(on: bool):
   var next := modes.duplicate()
   if on and mode not in next:
    next.append(mode)
   elif not on:
    next.erase(mode)
   configure({"modes": next}))
  panel.add_child(box)
  controls.append(box)
  box.set_meta("mode", mode)
 controls.append(hud._native_button(panel, "Поставить бота передо мной", func():
  configure({"anchor": game.athlete.position - Vector3(sin(game.rig.yaw), 0, cos(game.rig.yaw)) * 2.0})))
 controls.append(hud._native_button(panel, "Перенести бота на другую сторону", func(): configure({"anchor": Vector3(anchor.x, 0.02, -anchor.z)})))
 controls.append(hud._slider(panel, "Положение бота: влево / вправо", -4, 4, anchor.x, func(v: float): configure({"anchor": Vector3(v, 0.02, anchor.z)}), 0.25))
 controls.append(hud._slider(panel, "Положение бота: вдоль поля", -10.5, 10.5, anchor.z, func(v: float): configure({"anchor": Vector3(anchor.x, 0.02, v)}), 0.25))
 controls.append(hud._slider(panel, "Интервал подачи нового мяча, сек", 1.5, 12, interval, func(v: float): configure({"interval": v}), 0.5))
 controls.append(hud._slider(panel, "Цель: влево / вправо", -4, 4, target_x, func(v: float): configure({"target_x": v}), 0.25))
 controls.append(hud._slider(panel, "Глубина цели за сеткой", 1.5, 8, target_depth, func(v: float): configure({"target_depth": v}), 0.25))
 controls.append(hud._slider(panel, "Характеристики бота", 0, 150, level, func(v: float): configure({"level": v})))
 controls.append(hud._native_button(panel, "Вернуться в свободную игру (создатель)", func():
  if game.lan.hosting:
   game.lan.start_free_play()))
 var render := hud._tab("Экран")
 var fps := OptionButton.new()
 for text in ["FPS: автоматически / частота экрана", "FPS: до 60", "FPS: до 90", "FPS: до 120"]:
  fps.add_item(text)
 fps.select([0, 60, 90, 120].find(game.frame_rate.limit))
 fps.item_selected.connect(func(i: int): game.frame_rate.choose([0, 60, 90, 120][i]))
 render.add_child(fps)
 var note := Label.new()
 note.text = "FPS настраивается отдельно на каждом устройстве. Сеть 30 Гц не ограничивает отрисовку. Частоту экрана и режим энергосбережения контролирует телефон."
 note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 render.add_child(note)

func _process(_dt: float) -> void:
 if not is_instance_valid(hint) or not game.hud.menu.visible:
  return
 hint.text = "Выберите действия: бот повторяет их по очереди. Если мяч у игрока, бот ждёт. Для нового мяча дождитесь приземления. В матче бот отдыхает.\n" + ("В комнате бота настраивает создатель." if game.lan.active else "Бот работает в одиночной игре и в сетевой разминке.")
 for control in controls:
  if control is BaseButton:
   control.disabled = not can_configure()
   if control.has_meta("setting"):
    control.set_pressed_no_signal(enabled)
   elif control.has_meta("mode"):
    control.set_pressed_no_signal(int(control.get_meta("mode")) in modes)
  elif control is Range:
   control.editable = can_configure() if control is Slider else false
