class_name VolleyHUD
extends Control

const DEFAULT_CONFIG := {"sensitivity": 1.0, "stick_size": 1.0, "left_x": 0.0, "left_y": 0.0, "right_x": 0.0, "right_y": 0.0, "button_size": 1.0, "jump_y": 0.0, "power": 65.0, "orientation": 4.0}
var config := DEFAULT_CONFIG.duplicate()
var game: Node3D
var move_id := -1
var aim_id := -1
var sprint_id := -1
var power_id := -1
var angle_id := -1
var move_value := Vector2.ZERO
var aim_value := Vector2.ZERO
var mouse_aim := false
var mouse_origin := Vector2.ZERO
var menu: PanelContainer
var menu_blocker: ColorRect
var tabs: TabContainer
var status: Label
var debug_label: Label
var buttons: Dictionary = {}
var left_center := Vector2.ZERO
var right_center := Vector2.ZERO
var power_rect := Rect2()
var angle_rect := Rect2()
var radius := 74.0
var mobile_sprint := false
var font: Font
var stat_sliders: Dictionary = {}
var control_sliders: Dictionary = {}

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 font = ThemeDB.fallback_font
 _load_config()
 game.athlete.power = float(config.power) / 100.0
 _orientation(int(config.orientation))
 var title := _label("VOLLEY / LAB  0.2", 25, Color("f8d376"))
 title.position = Vector2(56, 25)
 status = _label("", 15, Color.WHITE)
 status.position = Vector2(56, 65)
 status.size = Vector2(315, 54)
 status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 debug_label = _label("", 13, Color("b5cbd6"))
 debug_label.position = Vector2(56, 122)
 for i in range(6):
  _button("tech_%d" % i, VolleyAthlete.TECHNIQUE_NAMES[i])
 for entry in [["menu", "МЕНЮ  Esc"], ["drill", ""], ["feed", "ЗАПУСТИТЬ  R"], ["jump", "ПРЫЖОК"], ["sprint", "СПРИНТ"], ["pickup", "ПОДОБРАТЬ  F"], ["toss", "ПОДБРОС  T"], ["serve_start", "НА ПОДАЧУ"]]:
  _button(entry[0], entry[1])
 _menu()
 resized.connect(_on_resize)
 _layout()

func _load_config() -> void:
 var saved := ConfigFile.new()
 if saved.load("user://controls.cfg") != OK:
  return
 for key in config:
  config[key] = float(saved.get_value("controls", key, config[key]))
 config.power = clampf(config.power, 5, 100)
 config.sensitivity = clampf(config.sensitivity, 0.6, 1.4)
 config.stick_size = clampf(config.stick_size, 0.8, 1.15)
 config.button_size = clampf(config.button_size, 0.8, 1.2)
 for key in ["left_x", "left_y", "right_x", "right_y", "jump_y"]:
  config[key] = clampf(config[key], -30, 30)
 for key in game.athlete.stats.values:
  game.athlete.stats.set_stat(key, float(saved.get_value("stats", key, game.athlete.stats.values[key])))
 game.athlete.reset_seed(int(saved.get_value("training", "seed", 20261014)))

func _label(text: String, font_size: int, color: Color) -> Label:
 var node := Label.new()
 node.text = text
 node.mouse_filter = Control.MOUSE_FILTER_IGNORE
 node.add_theme_font_size_override("font_size", font_size)
 node.add_theme_color_override("font_color", color)
 add_child(node)
 return node

func _button(key: String, text: String) -> void:
 buttons[key] = {"text": text, "rect": Rect2()}

func _on_resize() -> void:
 _cancel()
 _layout()

func _layout() -> void:
 if not is_instance_valid(menu):
  return
 radius = 74.0 * float(config.stick_size)
 left_center = Vector2(145 + float(config.left_x), size.y - 145 + float(config.left_y))
 right_center = Vector2(size.x - 150 + float(config.right_x), size.y - 145 + float(config.right_y))
 left_center.x = clampf(left_center.x, radius + 48, 230)
 right_center.x = clampf(right_center.x, size.x - 230, size.x - radius - 48)
 left_center.y = clampf(left_center.y, size.y - 180, size.y - radius - 44)
 right_center.y = clampf(right_center.y, size.y - 180, size.y - radius - 44)
 for i in range(6):
  buttons["tech_%d" % i].rect = Rect2(400 + (i % 3) * 190, 20 + (i / 3) * 62, 180, 52)
 buttons.menu.rect = Rect2(size.x - 208, 20, 160, 52)
 buttons.drill.rect = Rect2(400, 152, 360, 48)
 buttons.feed.rect = Rect2(780, 152, 180, 48)
 power_rect = Rect2(size.x - 445, size.y - 490, 395, 64)
 angle_rect = Rect2(size.x - 445, size.y - 402, 395, 64)
 var jump_size := Vector2(110, 72) * float(config.button_size)
 buttons.jump.rect = Rect2(right_center - Vector2(radius + 16 + jump_size.x, 18) + Vector2(0, config.jump_y), jump_size)
 buttons.sprint.rect = Rect2(left_center.x - 85, left_center.y - radius - 64, 170, 48)
 buttons.pickup.rect = Rect2(size.x - 570, size.y - 240, 150, 56)
 buttons.toss.rect = Rect2(size.x - 410, size.y - 240, 140, 56)
 buttons.serve_start.rect = Rect2(size.x - 570, size.y - 172, 150, 48)
 menu.position = Vector2(110, 30)
 menu.size = Vector2(size.x - 220, size.y - 60)
 menu_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 queue_redraw()

func _menu() -> void:
 menu_blocker = ColorRect.new()
 menu_blocker.color = Color(0.01, 0.02, 0.04, 0.8)
 menu_blocker.visible = false
 add_child(menu_blocker)
 menu = PanelContainer.new()
 menu.add_theme_stylebox_override("panel", _panel(Color("102536")))
 menu.visible = false
 add_child(menu)
 var layout := VBoxContainer.new()
 layout.add_theme_constant_override("separation", 10)
 menu.add_child(layout)
 var close := _native_button(layout, "ВЕРНУТЬСЯ НА ПЛОЩАДКУ", toggle_menu)
 close.name = "Resume"
 tabs = TabContainer.new()
 tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
 tabs.add_theme_font_size_override("font_size", 22)
 layout.add_child(tabs)
 var player := _tab("Игрок")
 for key in AthleteStats.LABELS:
  stat_sliders[key] = _slider(player, AthleteStats.LABELS[key], 1, 100, game.athlete.stats.values[key], func(v: float): game.athlete.stats.set_stat(key, v); _save())
 var controls := _tab("Управление")
 var hint := Label.new()
 hint.text = "Сила задаётся отдельно и не меняется от правого стика.\nПрыжок — слева от правого стика. Подбор и подброс — рядом."
 controls.add_child(hint)
 var orientation := OptionButton.new()
 orientation.name = "Orientation"
 orientation.custom_minimum_size.y = 54
 for label in ["Поворот: автоматически", "Поворот: альбомная сторона 1", "Поворот: альбомная сторона 2"]:
  orientation.add_item(label)
 orientation.select([4, 0, 2].find(int(config.orientation)))
 orientation.item_selected.connect(func(i: int): _orientation([4, 0, 2][i]); _save())
 controls.add_child(orientation)
 var labels := {"sensitivity": "Чувствительность", "stick_size": "Размер стиков", "left_x": "Левый стик: X", "left_y": "Левый стик: Y", "right_x": "Правый стик: X", "right_y": "Правый стик: Y", "button_size": "Размер прыжка", "jump_y": "Прыжок: выше / ниже"}
 for key in labels:
  var scale_value: bool = key in ["sensitivity", "stick_size", "button_size"]
  var low := 0.6 if key == "sensitivity" else 0.8
  var high := 1.4 if key == "sensitivity" else (1.15 if key == "stick_size" else 1.2)
  control_sliders[key] = _slider(controls, labels[key], low if scale_value else -30.0, high if scale_value else 30.0, config[key], func(v: float): config[key] = v; _layout(); _save(), 0.05 if scale_value else 1.0)
 _native_button(controls, "СБРОСИТЬ РАСПОЛОЖЕНИЕ УПРАВЛЕНИЯ", func():
  for key in control_sliders:
   control_sliders[key].value = DEFAULT_CONFIG[key]
  _layout()
  _save())
 var training := _tab("Тренировка")
 var help := Label.new()
 help.text = "ПОДАЧА: На подачу → Подобрать → Подброс → правый стик.\nВ ПРЫЖКЕ: подбросьте, прыгните и ударьте по мячу в воздухе.\nБРОСОК: подберите мяч, выберите «Бросок», направление и силу,\nзатем отпустите правый стик. Угол регулируется от −60° до 85°.\n\nWASD — ходьба; Shift — спринт; Space — прыжок.\n1–6 — техника; F — подобрать/опустить; T — подброс.\nПКМ — прицел; отпускание — удар/бросок.\nQ/E — угол; Z/X — сила; R — упражнение; Esc — меню."
 training.add_child(help)
 _native_button(training, "Вернуть игрока в центр", func(): game.reset_player(); toggle_menu())
 _native_button(training, "Перейти за заднюю линию для подачи", func(): game.serve_start(); toggle_menu())
 var seed_edit := SpinBox.new()
 seed_edit.prefix = "Seed: "
 seed_edit.max_value = 2147483647
 seed_edit.value = game.athlete.random_seed
 seed_edit.custom_minimum_size = Vector2(260, 52)
 training.add_child(seed_edit)
 _native_button(training, "Применить seed заново", func(): game.athlete.reset_seed(int(seed_edit.value)); _save())

func _native_button(parent: Node, title: String, callback: Callable) -> Button:
 var b := Button.new()
 b.text = title
 b.custom_minimum_size.y = 56
 b.pressed.connect(callback)
 parent.add_child(b)
 return b

func _tab(title: String) -> VBoxContainer:
 var scroll := ScrollContainer.new()
 scroll.name = title
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 tabs.add_child(scroll)
 var list := VBoxContainer.new()
 list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 list.add_theme_constant_override("separation", 14)
 scroll.add_child(list)
 return list

func _slider(parent: Node, title: String, low: float, high: float, value: float, callback: Callable, step_value := 1.0) -> HSlider:
 var row := HBoxContainer.new()
 row.custom_minimum_size.y = 56
 parent.add_child(row)
 var label := Label.new()
 label.text = "  " + title
 label.custom_minimum_size.x = 265
 row.add_child(label)
 var slider := HSlider.new()
 slider.min_value = low
 slider.max_value = high
 slider.step = step_value
 slider.value = value
 slider.custom_minimum_size = Vector2(280, 52)
 slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 row.add_child(slider)
 var readout := Label.new()
 readout.custom_minimum_size.x = 70
 readout.text = "%.2f" % value if step_value < 1 else str(int(value))
 row.add_child(readout)
 slider.value_changed.connect(func(v: float):
  readout.text = "%.2f" % v if step_value < 1 else str(int(v))
  callback.call(v))
 return slider

func _orientation(value: int) -> void:
 if value not in [0, 2, 4]:
  value = 4
 config.orientation = float(value)
 _cancel()
 if OS.get_name() in ["iOS", "Android"]:
  DisplayServer.screen_set_orientation(value)

func _save() -> void:
 config.power = roundf(game.athlete.power * 100)
 var file := ConfigFile.new()
 for key in config:
  file.set_value("controls", key, config[key])
 for key in game.athlete.stats.values:
  file.set_value("stats", key, game.athlete.stats.values[key])
 file.set_value("training", "seed", game.athlete.random_seed)
 file.save("user://controls.cfg")

func toggle_menu() -> void:
 menu.visible = not menu.visible
 menu_blocker.visible = menu.visible
 get_tree().paused = menu.visible
 _cancel()

func _cancel() -> void:
 move_id = -1
 aim_id = -1
 sprint_id = -1
 power_id = -1
 angle_id = -1
 mouse_aim = false
 mobile_sprint = false
 move_value = Vector2.ZERO
 aim_value = Vector2.ZERO
 if is_instance_valid(game) and is_instance_valid(game.athlete):
  game.athlete.cancel_input()

func _notification(what: int) -> void:
 if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
  _cancel()

func _input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo:
  if event.physical_keycode == KEY_ESCAPE:
   toggle_menu()
   get_viewport().set_input_as_handled()
   return
  if menu.visible:
   return
  if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_6:
   game.athlete.select_technique(event.physical_keycode - KEY_1)
  match event.physical_keycode:
   KEY_SPACE: game.athlete.jump()
   KEY_R: game.repeat_drill()
   KEY_F: game.pickup_or_drop()
   KEY_T: game.ball.toss()
   KEY_Z: _set_power(game.athlete.power - 0.05); _save()
   KEY_X: _set_power(game.athlete.power + 0.05); _save()
 # Native GUI receives emulated mouse events in menus. Gameplay never counts
 # an emulated mouse as a second copy of the same finger.
 if menu.visible:
  return
 if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
  return
 if event is InputEventScreenTouch:
  if event.canceled:
   _touch_cancel(event.index)
  elif event.pressed:
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
    game.release_action()
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
 if power_rect.has_point(pos) and power_id == -1:
  power_id = id
  _touch_move(id, pos)
  return
 if angle_rect.has_point(pos) and angle_id == -1:
  angle_id = id
  _touch_move(id, pos)
  return
 for key in buttons:
  if buttons[key].rect.has_point(pos):
   if key.begins_with("tech_"):
    game.athlete.select_technique(int(key.trim_prefix("tech_")))
   match key:
    "menu": toggle_menu()
    "feed": game.repeat_drill()
    "drill": game.training.selected = (game.training.selected + 1) % 6
    "jump": game.athlete.jump()
    "pickup": game.pickup_or_drop()
    "toss": game.ball.toss()
    "serve_start": game.serve_start()
    "sprint":
     if sprint_id == -1:
      sprint_id = id
      mobile_sprint = true
   return
 if pos.distance_to(left_center) < radius * 1.1 and move_id == -1:
  move_id = id
  _touch_move(id, pos)
 elif pos.distance_to(right_center) < radius * 1.1 and aim_id == -1 and not mouse_aim:
  aim_id = id
  game.athlete.prepare()
  _touch_move(id, pos)

func _touch_move(id: int, pos: Vector2) -> void:
 if id == move_id:
  move_value = ((pos - left_center) / radius).limit_length()
  if move_value.length() < 0.12:
   move_value = Vector2.ZERO
 if id == aim_id:
  _aim((pos - right_center) / radius * float(config.sensitivity))
 if id == power_id:
  _set_power(_range_fraction(power_rect, pos))
 if id == angle_id:
  game.athlete.elevation = snappedf(lerpf(-60, 85, _range_fraction(angle_rect, pos)), 1)

func _range_fraction(rect: Rect2, pos: Vector2) -> float:
 return clampf((pos.x - rect.position.x - 20) / (rect.size.x - 40), 0, 1)

func _set_power(value: float) -> void:
 game.athlete.power = clampf(snappedf(value, 0.05), 0.05, 1)

func _aim(value: Vector2) -> void:
 aim_value = value.limit_length()
 if aim_value.length() > 0.18:
  game.athlete.aim = aim_value.normalized()

func _touch_up(id: int) -> void:
 if id == move_id:
  move_id = -1
  move_value = Vector2.ZERO
 if id == aim_id:
  aim_id = -1
  game.release_action()
  aim_value = Vector2.ZERO
 if id == sprint_id:
  sprint_id = -1
  mobile_sprint = false
 if id == power_id:
  power_id = -1
  _save()
 if id == angle_id:
  angle_id = -1

func _touch_cancel(id: int) -> void:
 if id == aim_id:
  aim_id = -1
  aim_value = Vector2.ZERO
  if game.athlete.action == VolleyAthlete.Action.PREPARE:
   game.athlete.action = VolleyAthlete.Action.IDLE
 _touch_up(id)

func _process(dt: float) -> void:
 if not menu.visible:
  var keyboard := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
  game.athlete.move_axis = (keyboard + move_value).limit_length()
  game.athlete.sprint = mobile_sprint or Input.is_physical_key_pressed(KEY_SHIFT)
  var angle_change := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
  game.athlete.elevation = clampf(game.athlete.elevation + angle_change * dt * 35, -60, 85)
 var a: VolleyAthlete = game.athlete
 status.text = a.last_result
 debug_label.text = "Мяч %.1f м/с • %d FPS\nКасание %d%% • %+.1f° • %s" % [game.ball.linear_velocity.length(), Engine.get_frames_per_second(), int(a.quality * 100), a.deviation, ["ПОКОЙ", "ПРИЦЕЛ", "УДАР", "ВОЗВРАТ"][a.action]]
 buttons.drill.text = "Упражнение: " + VolleyTraining.NAMES[game.training.selected] + "  ›"
 buttons.pickup.text = "ОПУСТИТЬ  F" if game.ball.held else "ПОДОБРАТЬ  F"
 queue_redraw()

func _draw() -> void:
 if not is_instance_valid(game) or buttons.is_empty():
  return
 draw_style_box(_panel(Color("102536")), Rect2(40, 16, 340, 151))
 for center in [left_center, right_center]:
  draw_circle(center, radius, Color(0.04, 0.1, 0.16, 0.85))
  draw_arc(center, radius, 0, TAU, 64, Color("62889b"), 2, true)
 draw_circle(left_center + move_value * radius * 0.65, radius * 0.28, Color("c1d5dd"))
 draw_circle(right_center + aim_value * radius * 0.65, radius * 0.28, Color("f5cf70"))
 for center in [left_center, right_center]:
  draw_style_box(_panel(Color("102536")), Rect2(center + Vector2(-86, radius + 5), Vector2(172, 28)))
 draw_string(font, left_center + Vector2(-55, radius + 25), "ДВИЖЕНИЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("c1d5dd"))
 draw_string(font, right_center + Vector2(-70, radius + 25), "НАПРАВЛЕНИЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("f5cf70"))
 for key in buttons:
  var rect: Rect2 = buttons[key].rect
  var selected: bool = key == "tech_%d" % game.athlete.technique
  var color := Color("a87535") if selected or key == "jump" else Color("26485d")
  draw_style_box(_panel(color), rect)
  draw_string(font, rect.position + Vector2(8, rect.size.y * 0.5 + 6), buttons[key].text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 16, 16, Color.WHITE)
 _draw_range(power_rect, game.athlete.power, "СИЛА  %d%%  •  фиксирована" % int(game.athlete.power * 100), Color("f4cb6b"))
 _draw_range(angle_rect, (game.athlete.elevation + 60) / 145.0, "УГОЛ  %d°  •  вниз / вверх" % int(game.athlete.elevation), Color("a1dbe3"))
 draw_rect(Rect2(left_center.x - 75, left_center.y - radius - 12, 150 * game.athlete.energy, 4), Color("e4bd61"))

func _draw_range(rect: Rect2, fraction: float, title: String, color: Color) -> void:
 draw_style_box(_panel(Color("102536")), rect)
 draw_string(font, rect.position + Vector2(18, 23), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)
 var start := rect.position + Vector2(20, 46)
 draw_line(start, start + Vector2(rect.size.x - 40, 0), Color("425969"), 6, true)
 draw_line(start, start + Vector2((rect.size.x - 40) * fraction, 0), color, 6, true)
 draw_circle(start + Vector2((rect.size.x - 40) * fraction, 0), 12, color)

func _panel(color: Color) -> StyleBoxFlat:
 var style := StyleBoxFlat.new()
 style.bg_color = color
 style.set_corner_radius_all(10)
 return style
