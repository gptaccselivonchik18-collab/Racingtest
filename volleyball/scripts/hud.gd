class_name VolleyHUD
extends Control

var game: Node3D
var settings := VolleySettings.new()
var buttons: Dictionary = {}
var fingers: Dictionary = {}
var move_id := -1
var camera_id := -1
var move_value := Vector2.ZERO
var left_center := Vector2.ZERO
var radius := 68.0
var menu: PanelContainer
var menu_blocker: ColorRect
var tabs: TabContainer
var status: Label
var font: Font
var key_capture := ""
var key_buttons := {}
var edit_mode := false
var edit_selected := "primary"
var editor_bar: PanelContainer
var editor_scale: HSlider
var stat_sliders := {}
var control_sliders := {}

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 font = ThemeDB.fallback_font
 settings.load_settings(game.athlete)
 game.athlete.shift_lock = settings.shift_lock
 game.rig.sensitivity = settings.sensitivity
 _orientation(settings.orientation)
 status = Label.new()
 status.add_theme_font_size_override("font_size", 16)
 status.add_theme_color_override("font_color", Color("e3ebed"))
 status.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(status)
 for key in ["primary", "secondary", "jump", "dive", "jump_set", "menu", "next", "lock", "context"]:
  buttons[key] = {"rect": Rect2(), "text": "", "visible": true}
 _menu()
 _editor()
 resized.connect(func(): _cancel(); _layout())
 _layout()

func _layout() -> void:
 if not is_instance_valid(menu):
  return
 var margin := 40.0
 if OS.get_name() in ["iOS", "Android"]:
  var safe := DisplayServer.get_display_safe_area()
  var screen := DisplayServer.screen_get_size()
  if screen.x > 0:
   margin = maxf(margin, maxf(safe.position.x, screen.x - safe.end.x) * size.x / screen.x + 12)
 var defaults := {"primary": Vector2(size.x - margin - 64, size.y - 174), "secondary": Vector2(size.x - margin - 174, size.y - 227), "jump": Vector2(size.x - margin - 70, size.y - 66), "dive": Vector2(size.x - margin - 190, size.y - 103), "jump_set": Vector2(size.x - margin - 272, size.y - 184), "menu": Vector2(size.x - margin - 26, 40), "next": Vector2(margin + 36, 42), "lock": Vector2(size.x - margin - 103, 40), "context": Vector2(size.x * 0.5, size.y - 48), "move": Vector2(margin + 84, size.y - 116)}
 for key in defaults:
  var at: Vector2 = defaults[key]
  var scale_value := settings.button_scale
  if settings.layout.has(key):
   var saved: Vector3 = settings.layout[key]
   at = Vector2(saved.x * size.x, saved.y * size.y)
   scale_value *= saved.z
  if key == "move":
   radius = 68 * scale_value
   left_center = Vector2(clampf(at.x, margin + radius, size.x - margin - radius), clampf(at.y, radius + 80, size.y - radius - 18))
   continue
  var side := 88.0 * scale_value
  if key == "primary":
   side = 98 * scale_value
  elif key == "jump_set":
   side = 68 * scale_value
  elif key in ["menu", "lock", "next"]:
   side = 46
  var dimensions := Vector2(side, side)
  if key == "context":
   dimensions = Vector2(190, 44)
  at.x = clampf(at.x, margin + dimensions.x * 0.5, size.x - margin - dimensions.x * 0.5)
  at.y = clampf(at.y, 18 + dimensions.y * 0.5, size.y - dimensions.y * 0.5 - 12)
  buttons[key].rect = Rect2(at - dimensions * 0.5, dimensions)
 status.position = Vector2(margin + 70, 28)
 status.size = Vector2(size.x - margin * 2 - 260, 44)
 menu.position = Vector2(size.x * 0.08, size.y * 0.07)
 menu.size = Vector2(size.x * 0.84, size.y * 0.86)
 if is_instance_valid(editor_bar):
  editor_bar.position = Vector2(size.x * 0.16, 16)
  editor_bar.size = Vector2(size.x * 0.68, 64)

func _menu() -> void:
 menu_blocker = ColorRect.new()
 menu_blocker.color = Color(0.02, 0.05, 0.08, 0.88)
 menu_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 menu_blocker.visible = false
 add_child(menu_blocker)
 menu = PanelContainer.new()
 menu.add_theme_stylebox_override("panel", _panel(Color("132b3c")))
 menu.visible = false
 add_child(menu)
 var content := VBoxContainer.new()
 content.add_theme_constant_override("separation", 12)
 menu.add_child(content)
 var title := Label.new()
 title.text = "   VOLLEY / LAB  0.4"
 title.add_theme_font_size_override("font_size", 24)
 content.add_child(title)
 tabs = TabContainer.new()
 tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
 content.add_child(tabs)
 var practice := _tab("Тренировка")
 var list := OptionButton.new()
 list.custom_minimum_size.y = 52
 for name_value in VolleyTraining.NAMES:
  list.add_item(name_value)
 list.item_selected.connect(func(index: int): game.training.selected = index)
 practice.add_child(list)
 _native_button(practice, "Начать упражнение / следующий мяч", func(): toggle_menu(); game.start_drill())
 _native_button(practice, "Вернуть игрока в центр", func(): game.reset_player(); toggle_menu())
 var strict_box := CheckButton.new()
 strict_box.text = "Правила команды: двойное и максимум три касания"
 strict_box.toggled.connect(func(on: bool): game.rules.strict = on; game.rules.reset())
 practice.add_child(strict_box)
 var help := Label.new()
 help.text = "ЛКМ: приём / атака. Q: пас / блок. E: пас в прыжке.\nSpace: прыжок. Ctrl: подкат. R: следующий мяч.\nУдерживайте действие для меньшей силы, отпустите для касания.\nВ воздухе: короткое ЛКМ — скидка; удержание ≥ 0.13 с — атака.\nПодача: основная кнопка — подброс, затем удержать и отпустить.\nF: подобрать / опустить. Shift: фиксация корпуса. Мышь / свайп: камера."
 help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 help.text += "\nМяч в руках: свайп / мышь настраивает дугу подброса.\nTilt: левый джойстик / WASD до контакта. В прыжке сохраняется инерция."
 practice.add_child(help)
 var controls := _tab("Управление")
 control_sliders.sensitivity = _slider(controls, "Чувствительность камеры", 0.3, 2.5, settings.sensitivity, func(v: float): settings.sensitivity = v; game.rig.sensitivity = v; _save(), 0.05)
 control_sliders.size = _slider(controls, "Размер кнопок", 0.7, 1.4, settings.button_scale, func(v: float): settings.button_scale = v; _layout(); _save(), 0.05)
 var lock := CheckButton.new()
 lock.text = "Фиксация направления корпуса за камерой"
 lock.button_pressed = settings.shift_lock
 lock.toggled.connect(func(on: bool): settings.shift_lock = on; game.athlete.shift_lock = on; _save())
 controls.add_child(lock)
 var jump_set := CheckButton.new()
 jump_set.text = "Показывать компактную кнопку паса в прыжке"
 jump_set.button_pressed = settings.show_jump_set
 jump_set.toggled.connect(func(on: bool): settings.show_jump_set = on; _save())
 controls.add_child(jump_set)
 _native_button(controls, "Редактор расположения и размеров кнопок", start_editor)
 _native_button(controls, "Сбросить расположение", func(): settings.layout.clear(); settings.button_scale = 1; _layout(); _save())
 var orientation := OptionButton.new()
 for text in ["Поворот: автоматически", "Альбомный", "Альбомный: другая сторона"]:
  orientation.add_item(text)
 orientation.select([4, 0, 2].find(settings.orientation))
 orientation.item_selected.connect(func(i: int): _orientation([4, 0, 2][i]); _save())
 controls.add_child(orientation)
 var bindings := _tab("Клавиши")
 for key in settings.keys:
  var key_name: String = key
  var button := _native_button(bindings, "", func(): key_capture = key_name; key_buttons[key_name].text = "Нажмите клавишу • Esc — отмена")
  key_buttons[key] = button
 _refresh_keys()
 _native_button(bindings, "Приём / атака: вернуть ЛКМ", func(): settings.keys.primary = -MOUSE_BUTTON_LEFT; settings.install_keys(); _refresh_keys(); _save())
 var testing := _tab("Спортсмен")
 for key in game.athlete.stats.values:
  var stat_key: String = key
  stat_sliders[key] = _slider(testing, AthleteStats.LABELS[key], 1, 100, game.athlete.stats.values[key], func(v: float): game.athlete.stats.set_stat(stat_key, v); _save())
 _native_button(content, "Продолжить", toggle_menu)

func _editor() -> void:
 editor_bar = PanelContainer.new()
 editor_bar.add_theme_stylebox_override("panel", _panel(Color("163748")))
 editor_bar.visible = false
 add_child(editor_bar)
 var row := HBoxContainer.new()
 editor_bar.add_child(row)
 var title := Label.new()
 title.text = " Перетащите кнопку • размер: "
 row.add_child(title)
 editor_scale = HSlider.new()
 editor_scale.min_value = 0.65
 editor_scale.max_value = 1.45
 editor_scale.step = 0.05
 editor_scale.value = 1
 editor_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 editor_scale.custom_minimum_size = Vector2(150, 50)
 editor_scale.value_changed.connect(func(v: float):
  var center: Vector2 = left_center if edit_selected == "move" else buttons[edit_selected].rect.get_center()
  settings.layout[edit_selected] = Vector3(center.x / size.x, center.y / size.y, v)
  _layout())
 row.add_child(editor_scale)
 _native_button(row, "Сохранить", end_editor)

func start_editor() -> void:
 _cancel()
 menu.visible = false
 menu_blocker.visible = false
 edit_mode = true
 editor_bar.visible = true
 get_tree().paused = true
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func end_editor() -> void:
 edit_mode = false
 editor_bar.visible = false
 _save()
 menu.visible = true
 menu_blocker.visible = true
 _cancel()

func _native_button(parent: Node, text: String, callback: Callable) -> Button:
 var button := Button.new()
 button.text = text
 button.custom_minimum_size.y = 50
 button.pressed.connect(callback)
 parent.add_child(button)
 return button

func _tab(title: String) -> VBoxContainer:
 var scroll := ScrollContainer.new()
 scroll.name = title
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 tabs.add_child(scroll)
 var list := VBoxContainer.new()
 list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 list.add_theme_constant_override("separation", 12)
 scroll.add_child(list)
 return list

func _slider(parent: Node, title: String, low: float, high: float, value: float, callback: Callable, step_value := 1.0) -> HSlider:
 var row := VBoxContainer.new()
 var label := Label.new()
 label.text = "  %s: %.2f" % [title, value]
 row.add_child(label)
 var slider := HSlider.new()
 slider.min_value = low
 slider.max_value = high
 slider.step = step_value
 slider.value = value
 slider.custom_minimum_size = Vector2(300, 44)
 slider.value_changed.connect(func(v: float): label.text = "  %s: %.2f" % [title, v]; callback.call(v))
 row.add_child(slider)
 parent.add_child(row)
 return slider

func _refresh_keys() -> void:
 for key in key_buttons:
  key_buttons[key].text = "%s: %s" % [VolleySettings.KEY_LABELS[key], "ЛКМ" if settings.keys[key] < 0 else OS.get_keycode_string(settings.keys[key])]

func _orientation(value: int) -> void:
 settings.orientation = value
 if OS.get_name() in ["iOS", "Android"]:
  DisplayServer.screen_set_orientation(value)

func _save() -> void:
 settings.save(game.athlete)

func toggle_menu() -> void:
 if edit_mode:
  end_editor()
  return
 menu.visible = not menu.visible
 menu_blocker.visible = menu.visible
 get_tree().paused = menu.visible
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu.visible else Input.MOUSE_MODE_CAPTURED if OS.get_name() not in ["iOS", "Android"] else Input.MOUSE_MODE_VISIBLE
 _cancel()

func _cancel() -> void:
 fingers.clear()
 move_id = -1
 camera_id = -1
 move_value = Vector2.ZERO
 game.athlete.cancel_input()
 game.cancel_action("")

func _notification(what: int) -> void:
 if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(game):
  _cancel()

func _input(event: InputEvent) -> void:
 if event is InputEventKey and not event.echo:
  if not key_capture.is_empty() and event.pressed:
   if event.physical_keycode != KEY_ESCAPE:
    if not settings.rebind(key_capture, event.physical_keycode):
     key_buttons[key_capture].text = "Клавиша уже занята • выберите другую"
     return
    _save()
   key_capture = ""
   _refresh_keys()
   get_viewport().set_input_as_handled()
   return
  if event.is_action_pressed("volley_pause"):
   toggle_menu()
   get_viewport().set_input_as_handled()
   return
  if menu.visible or edit_mode:
   return
  for key in ["primary", "secondary", "jump", "dive", "jump_set", "next", "pickup", "lock"]:
   if event.is_action_pressed("volley_" + key):
    _press(key)
   elif event.is_action_released("volley_" + key):
    _release(key)
 if menu.visible:
  return
 if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
  return
 if event is InputEventScreenTouch:
  if event.canceled:
   _touch_up(event.index, true)
  elif event.pressed:
   _touch_down(event.index, event.position)
  else:
   _touch_up(event.index)
 elif event is InputEventScreenDrag:
  _touch_move(event.index, event.position, event.relative)
 elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
  if edit_mode or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
   if event.pressed:
    _touch_down(1000, event.position)
    if fingers.get(1000) == "camera" and not edit_mode:
     fingers[1000] = "primary"
     camera_id = -1
     Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
     if settings.keys.primary < 0:
      _press("primary")
   else:
    _touch_up(1000)
  elif event.pressed and settings.keys.primary < 0:
   _press("primary")
  elif not event.pressed and settings.keys.primary < 0:
   _release("primary")
 elif event is InputEventMouseMotion:
  if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not edit_mode:
   _look_or_aim(event.relative)
  else:
   _touch_move(1000, event.position, event.relative)

func _press(role: String) -> void:
 match role:
  "primary": game.begin_primary()
  "secondary": game.begin_secondary()
  "jump_set": game.begin_jump_set()
  "jump": game.athlete.jump()
  "dive": game.athlete.dive()
  "menu": toggle_menu()
  "next": game.repeat_drill()
  "context", "pickup": game.pickup_or_drop()
  "lock":
   settings.shift_lock = not settings.shift_lock
   game.athlete.shift_lock = settings.shift_lock
   _save()

func _release(role: String) -> void:
 if role in ["primary", "secondary", "jump_set"]:
  game.finish_action(role)

func _touch_down(id: int, pos: Vector2) -> void:
 if fingers.has(id):
  return
 if edit_mode and editor_bar.get_global_rect().has_point(pos):
  return
 for key in buttons:
  if (buttons[key].visible or edit_mode) and buttons[key].rect.has_point(pos):
   if edit_mode:
    edit_selected = key
    editor_scale.set_value_no_signal(settings.layout.get(key, Vector3(0, 0, 1)).z)
    fingers[id] = "edit:" + key
   elif key not in fingers.values():
    fingers[id] = key
    _press(key)
   return
 if pos.distance_to(left_center) < radius * 1.2 and move_id == -1:
  if edit_mode:
   edit_selected = "move"
   editor_scale.set_value_no_signal(settings.layout.get("move", Vector3(0, 0, 1)).z)
   fingers[id] = "edit:move"
  else:
   move_id = id
   fingers[id] = "move"
   _touch_move(id, pos)
 elif camera_id == -1 and not edit_mode:
  camera_id = id
  fingers[id] = "camera"

func _touch_move(id: int, pos: Vector2, relative := Vector2.ZERO) -> void:
 var role: String = fingers.get(id, "")
 if role == "move":
  move_value = ((pos - left_center) / radius).limit_length()
  if move_value.length() < 0.10:
   move_value = Vector2.ZERO
 elif role == "camera":
  _look_or_aim(relative)
 elif role.begins_with("edit:"):
  var key := role.trim_prefix("edit:")
  settings.layout[key] = Vector3(clampf(pos.x / size.x, 0.04, 0.96), clampf(pos.y / size.y, 0.1, 0.94), editor_scale.value)
  _layout()

func _look_or_aim(relative: Vector2) -> void:
 if game.ball.held and not game.ball.aiming_throw():
  game.ball.aim_toss(relative)
 else:
  game.rig.look(relative)

func _touch_up(id: int, canceled := false) -> void:
 if not fingers.has(id):
  return
 var role: String = fingers.get(id, "")
 fingers.erase(id)
 if role == "move":
  move_id = -1
  move_value = Vector2.ZERO
 elif role == "camera":
  camera_id = -1
 elif canceled:
  game.cancel_action(role)
 elif not edit_mode:
  _release(role)

func _process(_dt: float) -> void:
 var a: ContextAthlete = game.athlete
 if not menu.visible and not edit_mode:
  var keyboard := Input.get_vector("volley_left", "volley_right", "volley_forward", "volley_back")
  var axis := (keyboard + move_value).limit_length()
  a.move_axis = game.rig.movement(axis)
  a.tilt = axis
 buttons.primary.text = "ПОДБРОС" if game.ball.held else "ПОДАЧА" if game.serving and not a.airborne() else "АТАКА" if a.airborne() else "ПРИЁМ"
 buttons.secondary.text = "БРОСОК" if game.ball.held else "БЛОК" if a.airborne() else "ПАС"
 buttons.jump.text = "ПРЫЖОК"
 buttons.dive.text = "ПОДКАТ"
 buttons.jump_set.text = "ПАС ↑"
 buttons.menu.text = "≡"
 buttons.next.text = "↻"
 buttons.lock.text = "●" if a.shift_lock else "○"
 buttons.context.text = "ОПУСТИТЬ • F" if game.ball.held else "ПОДОБРАТЬ • F"
 buttons.jump_set.visible = a.airborne() and settings.show_jump_set and not game.ball.held
 buttons.context.visible = game.ball.held or game.ball.can_pick_up()
 status.text = VolleyTraining.NAMES[game.training.selected] + "  •  " + (game.rules.message if game.rules.ended else a.last_result)
 if game.ball.held:
  status.text = "Свайп: направление и высота подброса • ПОДБРОС: запустить"
  if game.ball.aiming_throw():
   status.text = "БРОСОК: свайп — прицел • отпустить кнопку — бросить"
 if edit_mode:
  status.text = ""
 queue_redraw()

func _draw() -> void:
 if buttons.is_empty():
  return
 draw_circle(left_center, radius, Color(0.04, 0.10, 0.15, 0.48))
 draw_arc(left_center, radius, 0, TAU, 60, Color(0.7, 0.83, 0.88, 0.6), 2, true)
 draw_circle(left_center + move_value * radius * 0.6, radius * 0.31, Color(0.8, 0.89, 0.91, 0.75))
 for key in buttons:
  if not buttons[key].visible and not edit_mode:
   continue
  var rect: Rect2 = buttons[key].rect
  var active: bool = key in fingers.values() or (edit_mode and key == edit_selected)
  var color := Color(0.14, 0.27, 0.34, 0.66)
  if key in ["primary", "jump"]:
   color = Color(0.75, 0.57, 0.25, 0.72)
  if active:
   color = Color("b78d45")
  draw_style_box(_panel(color, int(rect.size.y * 0.38)), rect)
  draw_string(font, rect.position + Vector2(4, rect.size.y * 0.5 + 5), buttons[key].text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8, 14 if key not in ["menu", "next", "lock"] else 25, Color("f2f1e9"))
 if game.athlete.action == VolleyAthlete.Action.PREPARE and not edit_mode:
  var at := Vector2(size.x * 0.5 - 90, size.y - 108)
  draw_style_box(_panel(Color(0.03, 0.09, 0.14, 0.8)), Rect2(at - Vector2(10, 23), Vector2(200, 48)))
  draw_string(font, at - Vector2(0, 5), "СИЛА  %d%%" % int(game.athlete.power * 100), HORIZONTAL_ALIGNMENT_CENTER, 180, 14, Color("f4cf77"))
  draw_line(at + Vector2(0, 12), at + Vector2(180, 12), Color("334d5c"), 5)
  draw_line(at + Vector2(0, 12), at + Vector2(180 * game.athlete.power, 12), Color("f4cf77"), 5)
 draw_arc(size * 0.5, 3, 0, TAU, 12, Color(1, 1, 1, 0.45), 1, true)
 if game.athlete.action in [VolleyAthlete.Action.PREPARE, VolleyAthlete.Action.STRIKE] and not edit_mode:
  var at := Vector2(size.x * 0.5, size.y - 168)
  draw_circle(at, 23, Color(0.03, 0.09, 0.14, 0.65))
  draw_arc(at, 23, 0, TAU, 32, Color("8eaebc"), 1, true)
  draw_line(at, at + game.athlete.tilt * 20, Color("f4cf77"), 3, true)
  draw_circle(at + game.athlete.tilt * 20, 4, Color("f4cf77"))
  draw_string(font, at + Vector2(-35, -29), "TILT", HORIZONTAL_ALIGNMENT_CENTER, 70, 13, Color("f4cf77"))

func _panel(color: Color, corners := 12) -> StyleBoxFlat:
 var style := StyleBoxFlat.new()
 style.bg_color = color
 style.set_corner_radius_all(corners)
 style.content_margin_left = 12
 style.content_margin_right = 12
 style.content_margin_top = 8
 style.content_margin_bottom = 8
 return style
