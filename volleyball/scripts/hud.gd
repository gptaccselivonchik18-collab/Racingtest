class_name VolleyHUD
extends Control

var game: Node3D
var config := {"sensitivity": 1.0, "stick_size": 1.0, "left_x": 0.0, "left_y": 0.0, "right_x": 0.0, "right_y": 0.0, "button_size": 1.0, "buttons_y": 0.0}
var move_id := -1
var aim_id := -1
var sprint_id := -1
var move_value := Vector2.ZERO
var aim_value := Vector2.ZERO
var mouse_aim := false
var mouse_origin := Vector2.ZERO
var menu: PanelContainer
var status: Label
var debug_label: Label
var technique_label: Label
var angle_label: Label
var angle: HSlider
var scenario: OptionButton
var buttons: Dictionary = {}
var left_center := Vector2.ZERO
var right_center := Vector2.ZERO
var radius := 78.0
var mobile_sprint := false
var font: Font

func _ready() -> void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 font = ThemeDB.fallback_font
 var saved := ConfigFile.new()
 if saved.load("user://controls.cfg") == OK:
  for key in config:
   config[key] = float(saved.get_value("controls", key, config[key]))
  for key in game.athlete.stats.values:
   game.athlete.stats.set_stat(key, float(saved.get_value("stats", key, 65.0)))
  game.athlete.reset_seed(int(saved.get_value("training", "seed", 20261014)))
 var title := _label("VOLLEY / LAB", 28, Color("f8d376"))
 title.position = Vector2(28, 18)
 var subtitle := _label("РУЧНОЕ УПРАВЛЕНИЕ  /  ТРЕНИРОВКА", 14, Color("afc5cf"))
 subtitle.position = Vector2(30, 53)
 status = _label("", 20, Color.WHITE)
 status.position = Vector2(30, 86)
 debug_label = _label("", 14, Color("c7d9e3"))
 debug_label.position = Vector2(30, 120)
 technique_label = _label("", 17, Color("f8d376"))
 angle_label = _label("", 16, Color.WHITE)
 angle = HSlider.new()
 angle.min_value = 15
 angle.max_value = 80
 angle.value = game.athlete.elevation
 angle.custom_minimum_size = Vector2(195, 35)
 add_child(angle)
 angle.value_changed.connect(func(v: float): game.athlete.elevation = v)
 scenario = OptionButton.new()
 for item in VolleyTraining.NAMES:
  scenario.add_item(item)
 add_child(scenario)
 scenario.item_selected.connect(func(i: int): game.training.selected = i)
 _button("menu", "МЕНЮ  Esc")
 _button("feed", "МЯЧ  R")
 _button("technique", "СМЕНИТЬ  1 / 2")
 _button("jump", "ПРЫЖОК")
 _button("sprint", "СПРИНТ")
 _menu()
 resized.connect(_layout)
 _layout()

func _label(text: String, font_size: int, color: Color) -> Label:
 var node := Label.new()
 node.text = text
 node.add_theme_font_size_override("font_size", font_size)
 node.add_theme_color_override("font_color", color)
 add_child(node)
 return node

func _button(key: String, text: String) -> void:
 # Drawn controls share the same per-finger router as both joysticks.
 buttons[key] = {"text": text, "rect": Rect2()}

func _layout() -> void:
 radius = 78.0 * float(config.stick_size)
 left_center = Vector2(135 + float(config.left_x), size.y - 132 + float(config.left_y))
 right_center = Vector2(size.x - 155 + float(config.right_x), size.y - 132 + float(config.right_y))
 left_center.x = clampf(left_center.x, radius + 12, size.x * 0.4)
 right_center.x = clampf(right_center.x, size.x * 0.6, size.x - radius - 12)
 left_center.y = clampf(left_center.y, size.y * 0.55, size.y - radius - 28)
 right_center.y = clampf(right_center.y, size.y * 0.55, size.y - radius - 28)
 buttons.menu.rect = Rect2(size.x - 165, 20, 140, 42)
 buttons.feed.rect = Rect2(size.x - 165, 77, 140, 46)
 scenario.position = Vector2(size.x - 410, 81)
 scenario.size = Vector2(230, 40)
 angle.position = Vector2(size.x - 250, size.y - 305)
 angle.size = Vector2(220, 35)
 angle_label.position = angle.position - Vector2(0, 25)
 technique_label.position = Vector2(size.x - 250, size.y - 380)
 var scale_factor := float(config.button_size)
 var by := size.y - 68 + float(config.buttons_y)
 buttons.technique.rect = Rect2(size.x - 250, size.y - 350, 220, 38)
 buttons.jump.rect = Rect2(size.x * 0.5 + 8, by, 135 * scale_factor, 48 * scale_factor)
 buttons.sprint.rect = Rect2(size.x * 0.5 - 153 * scale_factor, by, 135 * scale_factor, 48 * scale_factor)
 menu.position = Vector2(size.x * 0.5 - 300, 30)
 menu.size = Vector2(600, size.y - 60)
 queue_redraw()

func _menu() -> void:
 menu = PanelContainer.new()
 menu.visible = false
 add_child(menu)
 var scroll := ScrollContainer.new()
 scroll.custom_minimum_size = Vector2(600, 0)
 menu.add_child(scroll)
 var list := VBoxContainer.new()
 list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 list.add_theme_constant_override("separation", 8)
 scroll.add_child(list)
 var heading := Label.new()
 heading.text = "   ИГРОК И УПРАВЛЕНИЕ"
 heading.add_theme_font_size_override("font_size", 24)
 list.add_child(heading)
 var close := Button.new()
 close.text = "Вернуться на площадку"
 close.custom_minimum_size.y = 44
 close.pressed.connect(toggle_menu)
 list.add_child(close)
 var home := Button.new()
 home.text = "Вернуть игрока на стартовую отметку"
 home.pressed.connect(game.reset_player)
 list.add_child(home)
 for key in AthleteStats.LABELS:
  _slider(list, AthleteStats.LABELS[key], 1, 100, game.athlete.stats.values[key], func(v: float): game.athlete.stats.set_stat(key, v); _save())
 var seed_row := HBoxContainer.new()
 list.add_child(seed_row)
 var seed_label := Label.new()
 seed_label.text = "  Seed разброса: "
 seed_row.add_child(seed_label)
 var seed_edit := SpinBox.new()
 seed_edit.max_value = 2147483647
 seed_edit.value = game.athlete.random_seed
 seed_row.add_child(seed_edit)
 var seed_button := Button.new()
 seed_button.text = "Применить / повторить seed"
 seed_button.pressed.connect(func(): game.athlete.reset_seed(int(seed_edit.value)); _save())
 seed_row.add_child(seed_button)
 var labels := {"sensitivity": "Чувствительность", "stick_size": "Размер джойстиков", "left_x": "Левый джойстик: X", "left_y": "Левый джойстик: Y", "right_x": "Правый джойстик: X", "right_y": "Правый джойстик: Y", "button_size": "Размер кнопок", "buttons_y": "Положение кнопок: Y"}
 for key in config:
  var is_scale: bool = key in ["sensitivity", "stick_size", "button_size"]
  _slider(list, labels[key], 0.6 if is_scale else -65, 1.4 if is_scale else 65, config[key], func(v: float): config[key] = v; _layout(); _save(), 0.05 if is_scale else 1.0)
 var help := Label.new()
 help.text = "  WASD — ходьба • Shift — спринт • Space — прыжок\n  ПКМ + движение мыши — направление и сила\n  Отпускание ПКМ / правого стика — движение рук\n  1 / 2 — техника • Q / E — угол • R — новый мяч\n  Передача требует точного совпадения мяча и рук.\n  Линия показывает намерение, а не прогноз полёта.\n  Изменения сохраняются локально. Меню приостанавливает игру."
 list.add_child(help)

func _slider(parent: Node, title: String, low: float, high: float, value: float, callback: Callable, step_value := 1.0) -> void:
 var row := HBoxContainer.new()
 parent.add_child(row)
 var label := Label.new()
 label.text = "  " + title
 label.custom_minimum_size.x = 255
 row.add_child(label)
 var slider := HSlider.new()
 slider.min_value = low
 slider.max_value = high
 slider.step = step_value
 slider.value = value
 slider.custom_minimum_size = Vector2(235, 30)
 row.add_child(slider)
 var readout := Label.new()
 readout.text = "%.2f" % value if step_value < 1 else str(int(value))
 row.add_child(readout)
 slider.value_changed.connect(func(v: float):
  readout.text = "%.2f" % v if step_value < 1 else str(int(v))
  callback.call(v))

func _save() -> void:
 var file := ConfigFile.new()
 for key in config:
  file.set_value("controls", key, config[key])
 for key in game.athlete.stats.values:
  file.set_value("stats", key, game.athlete.stats.values[key])
 file.set_value("training", "seed", game.athlete.random_seed)
 file.save("user://controls.cfg")

func toggle_menu() -> void:
 menu.visible = not menu.visible
 # Keep only this UI alive while the training scene is paused.
 process_mode = Node.PROCESS_MODE_ALWAYS
 get_tree().paused = menu.visible
 _cancel()

func _cancel() -> void:
 move_id = -1
 aim_id = -1
 sprint_id = -1
 mouse_aim = false
 mobile_sprint = false
 move_value = Vector2.ZERO
 aim_value = Vector2.ZERO
 game.athlete.cancel_input()

func _notification(what: int) -> void:
 if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(game):
  _cancel()

func _input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo:
  if event.physical_keycode == KEY_ESCAPE:
   toggle_menu()
   get_viewport().set_input_as_handled()
   return
  if menu.visible:
   return
  match event.physical_keycode:
   KEY_1: game.athlete.technique = VolleyAthlete.Technique.OVERHEAD
   KEY_2: game.athlete.technique = VolleyAthlete.Technique.UNDERHAND
   KEY_SPACE: game.athlete.jump()
   KEY_R: game.repeat_drill()
 if menu.visible:
  return
 if event is InputEventScreenTouch:
  if event.pressed:
   _touch_down(event.index, event.position)
  else:
   _touch_up(event.index)
 elif event is InputEventScreenDrag:
  _touch_move(event.index, event.position)
 elif event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_RIGHT:
   if event.pressed:
    mouse_aim = true
    mouse_origin = event.position
    aim_value = Vector2.ZERO
    game.athlete.prepare()
   elif mouse_aim:
    mouse_aim = false
    game.athlete.release()
  elif event.button_index == MOUSE_BUTTON_LEFT:
   if event.pressed:
    _touch_down(1000, event.position)
   else:
    _touch_up(1000)
 elif event is InputEventMouseMotion:
  if mouse_aim:
   _aim((event.position - mouse_origin) / (120.0 / float(config.sensitivity)))
  _touch_move(1000, event.position)

func _touch_down(id: int, pos: Vector2) -> void:
 for key in buttons:
  if buttons[key].rect.has_point(pos):
   match key:
    "menu": toggle_menu()
    "feed": game.repeat_drill()
    "technique": game.athlete.technique = 1 - game.athlete.technique
    "jump": game.athlete.jump()
    "sprint":
     if sprint_id == -1:
      sprint_id = id
      mobile_sprint = true
   get_viewport().set_input_as_handled()
   return
 if pos.distance_to(left_center) < radius * 1.15 and move_id == -1:
  move_id = id
  _touch_move(id, pos)
 elif pos.distance_to(right_center) < radius * 1.15 and aim_id == -1 and not mouse_aim:
  aim_id = id
  game.athlete.prepare()
  _touch_move(id, pos)

func _touch_move(id: int, pos: Vector2) -> void:
 if id == move_id:
  move_value = ((pos - left_center) / radius).limit_length()
 if id == aim_id:
  _aim((pos - right_center) / radius * float(config.sensitivity))

func _aim(value: Vector2) -> void:
 aim_value = value.limit_length()
 if aim_value.length() > 0.08:
  game.athlete.aim = aim_value.normalized()
 game.athlete.power = clampf(aim_value.length(), 0.05, 1)

func _touch_up(id: int) -> void:
 if id == move_id:
  move_id = -1
  move_value = Vector2.ZERO
 if id == aim_id:
  aim_id = -1
  game.athlete.release()
  aim_value = Vector2.ZERO
 if id == sprint_id:
  sprint_id = -1
  mobile_sprint = false

func _process(dt: float) -> void:
 if not menu.visible:
  var keyboard := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
  game.athlete.move_axis = (keyboard + move_value).limit_length()
  game.athlete.sprint = mobile_sprint or Input.is_physical_key_pressed(KEY_SHIFT)
  var angle_change := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
  angle.value = clampf(angle.value + angle_change * dt * 35, 15, 80)
 var a: VolleyAthlete = game.athlete
 status.text = a.last_result
 debug_label.text = "Мяч  %.1f м/с  •  %.1f м/с²\nКасание  %d%%  •  отклонение %+.1f°  •  %s\nПопытки %d  /  касания %d  •  %d FPS" % [game.ball.linear_velocity.length(), game.ball.acceleration.length(), int(a.quality * 100), a.deviation, ["ПОКОЙ", "ПОДГОТОВКА", "ДВИЖЕНИЕ", "ВОЗВРАТ"][a.action], game.training.attempts, a.contact_count, Engine.get_frames_per_second()]
 technique_label.text = "ВЕРХНЯЯ ПЕРЕДАЧА" if a.technique == 0 else "НИЖНИЙ ПРИЁМ"
 angle_label.text = "Угол %d°  •  сила %d%%" % [int(a.elevation), int(a.power * 100)]
 queue_redraw()

func _draw() -> void:
 if not is_instance_valid(game):
  return
 draw_style_box(_panel(Color(0.035, 0.075, 0.12, 0.88)), Rect2(14, 12, 440, 186))
 for center in [left_center, right_center]:
  draw_circle(center, radius, Color(0.04, 0.1, 0.16, 0.7))
  draw_arc(center, radius, 0, TAU, 64, Color(0.75, 0.86, 0.88, 0.45), 2, true)
  draw_line(center - Vector2(radius * 0.65, 0), center + Vector2(radius * 0.65, 0), Color(1, 1, 1, 0.12))
  draw_line(center - Vector2(0, radius * 0.65), center + Vector2(0, radius * 0.65), Color(1, 1, 1, 0.12))
 draw_circle(left_center + move_value * radius * 0.65, radius * 0.28, Color("c1d5dd"))
 draw_circle(right_center + aim_value * radius * 0.65, radius * 0.28, Color("f5cf70"))
 draw_string(font, left_center + Vector2(-55, radius + 23), "ДВИЖЕНИЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("c1d5dd"))
 draw_string(font, right_center + Vector2(-62, radius + 23), "ПЕРЕДАЧА", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("f5cf70"))
 for key in buttons:
  var rect: Rect2 = buttons[key].rect
  draw_style_box(_panel(Color("30556a") if key != "feed" else Color("a87535")), rect)
  draw_string(font, rect.position + Vector2(10, rect.size.y * 0.5 + 6), buttons[key].text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20, 15, Color.WHITE)
 draw_rect(Rect2(size.x * 0.5 - 145, size.y - 88, 290, 4), Color("243b4d"))
 draw_rect(Rect2(size.x * 0.5 - 145, size.y - 88, 290 * game.athlete.energy, 4), Color("e4bd61"))

func _panel(color: Color) -> StyleBoxFlat:
 var style := StyleBoxFlat.new()
 style.bg_color = color
 style.set_corner_radius_all(10)
 return style
