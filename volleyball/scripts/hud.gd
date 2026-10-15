class_name VolleyHUD
extends Control

var game: Node3D
var settings := VolleySettings.new()
var buttons: Dictionary = {}
var fingers: Dictionary = {}
var role_owners: Dictionary = {}
var finger_positions: Dictionary = {}
var queued: Dictionary = {}
var held_snapshot := false
var height_rect := Rect2()
var height_grab_offset := 0.0
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
 for key in ["primary", "secondary", "jump", "dive", "jump_set", "menu", "next", "lock", "context", "bump", "lower_serve"]:
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
 var defaults := {"bump": Vector2(size.x - margin - 280, size.y - 92), "lower_serve": Vector2(size.x - margin - 190, size.y - 103), "primary": Vector2(size.x - margin - 64, size.y - 174), "secondary": Vector2(size.x - margin - 174, size.y - 227), "jump": Vector2(size.x - margin - 70, size.y - 66), "dive": Vector2(size.x - margin - 190, size.y - 103), "jump_set": Vector2(size.x - margin - 272, size.y - 184), "menu": Vector2(size.x - margin - 26, 40), "next": Vector2(margin + 36, 42), "lock": Vector2(size.x - margin - 103, 40), "context": Vector2(size.x * 0.5, size.y - 48), "move": Vector2(margin + 84, size.y - 116)}
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
 height_rect = Rect2(Vector2(size.x * 0.5 - 140, 104), Vector2(280, 50))
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
 title.text = "   VOLLEY / LAB  0.10"
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
 help.text = "ЛКМ: атака. Q: пас / блок. E: пас в прыжке.\nX: нижний приём. V: нижняя подача.\nSpace: прыжок. Ctrl: подкат. R: следующий мяч. F: подобрать / опустить.\nРазбег: перевести палец с джойстика на АТАКУ и отпустить → прыжок.\nИли на бегу нажать и отпустить АТАКУ другим пальцем. Следующий нажим → удар.\nМяч в руках: высота ползунком, основная кнопка → подброс.\nПРИЦЕЛ БРОСКА / Q → выбрать место на площадке → БРОСИТЬ / ЛКМ."
 help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 help.text += "\nНа ПК высота: колесо мыши. Tilt: джойстик / WASD до контакта.\nОбычный удар без комбинации: удерживать для меньшей силы, отпустить для касания."
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
 _native_button(bindings, "Атака: вернуть ЛКМ", func(): settings.keys.primary = -MOUSE_BUTTON_LEFT; settings.install_keys(); _refresh_keys(); _save())
 var testing := _tab("Спортсмен")
 var explanation := Label.new()
 explanation.text = "Свободный эксперимент: 65 — исходное значение. 0–100 — ориентир. Можно вводить отрицательные значения и больше 100. Эффект плавно насыщается при крайних числах."
 explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 testing.add_child(explanation)
 for key in VolleyStyleStats.KEYS:
  var stat_key: String = key
  var label := Label.new()
  label.text = VolleyStyleStats.STYLE_LABELS[key]
  label.add_theme_font_size_override("font_size", 21)
  testing.add_child(label)
  var row := HBoxContainer.new()
  var value := SpinBox.new()
  value.min_value = 0
  value.max_value = 100
  value.allow_greater = true
  value.allow_lesser = true
  value.step = 1
  value.value = game.athlete.stats.values[key]
  value.custom_minimum_size = Vector2(180, 52)
  value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  value.value_changed.connect(func(v: float): _change_stat(stat_key, v))
  var minus := _native_button(row, "−10", func(): value.value -= 10)
  minus.custom_minimum_size.x = 64
  row.add_child(value)
  var plus := _native_button(row, "+10", func(): value.value += 10)
  plus.custom_minimum_size.x = 64
  testing.add_child(row)
  stat_sliders[key] = value
  var detail := Label.new()
  detail.text = VolleyStyleStats.DETAILS[key]
  detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  testing.add_child(detail)
 _native_button(testing, "Вернуть все характеристики к 65", func():
  for key in VolleyStyleStats.KEYS:
   stat_sliders[key].value = 65)
 _native_button(content, "Главное меню / выйти из комнаты", func():
  _cancel()
  menu.hide()
  menu_blocker.hide()
  get_tree().paused = false
  game.lan.leave()
  game.frontend.show_home())
 _native_button(content, "Продолжить", func():
  toggle_menu()
  if game.frontend.in_home:
   game.frontend.show_home())

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
 get_tree().paused = not game.lan.active
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

func _change_stat(key: String, value: float) -> void:
 game.athlete.stats.set_stat(key, value)
 _save()
 if is_instance_valid(game.lan) and game.lan.active:
  game.lan.local_action("stats", "press", {"skill": key, "value": value})

func _save() -> void:
 settings.save(game.athlete)

func toggle_menu() -> void:
 if edit_mode:
  end_editor()
  return
 menu.visible = not menu.visible
 menu_blocker.visible = menu.visible
 get_tree().paused = menu.visible and not game.lan.active
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu.visible else Input.MOUSE_MODE_CAPTURED if OS.get_name() not in ["iOS", "Android"] else Input.MOUSE_MODE_VISIBLE
 _cancel()

func _cancel() -> void:
 fingers.clear()
 role_owners.clear()
 finger_positions.clear()
 queued.clear()
 move_id = -1
 camera_id = -1
 move_value = Vector2.ZERO
 for key in ["left", "right", "forward", "back"]:
  Input.action_release("volley_" + key)
 game.athlete.cancel_input()
 game.cancel_action("")

func _notification(what: int) -> void:
 if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT] and is_instance_valid(game):
  _cancel()

func _input(event: InputEvent) -> void:
 if not visible or (is_instance_valid(game.frontend) and game.frontend.blocks_input()):
  return
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
  for key in ["primary", "secondary", "jump", "dive", "jump_set", "bump", "lower_serve", "next", "pickup", "lock"]:
   if event.is_action_pressed("volley_" + key):
    _press(key, -int(event.physical_keycode) - 100)
   elif event.is_action_released("volley_" + key):
    _release(key, -int(event.physical_keycode) - 100)
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
   if fingers.get(event.index, "") != "height":
    finger_positions[event.index] = event.position
   _touch_up(event.index)
 elif event is InputEventScreenDrag:
  _touch_move(event.index, event.position, event.relative)
 elif event is InputEventMouseButton and event.pressed and game.holding_ball() and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
  game.ball.set_release_height(game.ball.release_height() + (0.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1))
 elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
  if edit_mode or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
   if event.pressed:
    _touch_down(1000, event.position)
    if fingers.get(1000) == "camera" and not edit_mode:
     fingers[1000] = "primary"
     camera_id = -1
     Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
     if settings.keys.primary < 0:
      _press("primary", 1000)
   else:
    _touch_up(1000)
  elif event.pressed and settings.keys.primary < 0:
   _press("primary", 1000)
  elif not event.pressed and settings.keys.primary < 0:
   _release("primary", 1000)
 elif event is InputEventMouseMotion:
  if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not edit_mode:
   _look_or_aim(event.relative)
  else:
   _touch_move(1000, event.position, event.relative)

func _press(role: String, source := -2) -> bool:
 _sync_held_state()
 if role_owners.has(role):
  return false
 role_owners[role] = source
 queued.erase(role)
 var accepted := _perform(role)
 if not accepted and role in ["primary", "secondary", "jump_set", "bump", "jump"] and game.action_owner.is_empty():
  if game.athlete.action in [VolleyAthlete.Action.STRIKE, VolleyAthlete.Action.RECOVER] or game.athlete.jump_windup > 0 or (role == "jump" and game.athlete.velocity.y < 0):
   queued[role] = {"source": source, "remaining": 0.16, "released": false}
 return accepted

func _perform(role: String) -> bool:
 if role == "lower_serve":
  return game.lower_serve.open()
 if game.lan.active and role not in ["menu", "lock"]:
  return game.lan.local_action(role)
 match role:
  "bump": return game.begin_bump()
  "primary": return game.begin_primary()
  "secondary": return game.begin_secondary()
  "jump_set": return game.begin_jump_set()
  "jump":
   if game.athlete.airborne() or game.athlete.jump_windup > 0:
    return false
   game.athlete.jump()
   return game.athlete.velocity.y > 0.1
  "dive":
   if game.holding_ball():
    return false
   var did_dive: bool = game.athlete.dive()
   if did_dive:
    game.action_owner = ""
   return did_dive
  "menu": toggle_menu()
  "next": game.repeat_drill()
  "context", "pickup": game.pickup_or_drop()
  "lock":
   settings.shift_lock = not settings.shift_lock
   game.athlete.shift_lock = settings.shift_lock
   _save()
 return true

func _release(role: String, source := -2, canceled := false) -> void:
 if role_owners.get(role, -999999) != source:
  return
 role_owners.erase(role)
 if queued.has(role):
  if canceled:
   queued.erase(role)
  else:
   queued[role].released = true
  return
 if canceled:
  game.cancel_action(role)
  return
 if role in ["primary", "secondary", "jump_set", "bump"]:
  game.finish_action(role)

func _advance_buffers(dt: float) -> void:
 for role in queued.keys():
  queued[role].remaining -= dt
  if queued[role].remaining <= 0:
   queued.erase(role)
   continue
  if not game.action_owner.is_empty():
   continue
  if _perform(role):
   var released: bool = queued[role].released
   queued.erase(role)
   if released and role in ["primary", "secondary", "jump_set", "bump"]:
    game.finish_action(role)

func _button_at(pos: Vector2, padding := 12.0) -> String:
 var best := ""
 var distance := INF
 for key in buttons:
  var rect: Rect2 = buttons[key].rect
  if (buttons[key].visible or edit_mode) and rect.grow(padding).has_point(pos):
   var next := pos.distance_to(rect.get_center()) / minf(rect.size.x, rect.size.y)
   if next < distance:
    best = key
    distance = next
 return best

func _sync_axes() -> void:
 if move_id < 0 or fingers.get(move_id, "") not in ["move", "approach"]:
  move_value = Vector2.ZERO
  move_id = -1
 var keyboard := Input.get_vector("volley_left", "volley_right", "volley_forward", "volley_back")
 var axis := (keyboard + move_value).limit_length()
 game.athlete.move_axis = game.rig.movement(axis)
 game.athlete.tilt = axis

func _refresh_context() -> void:
 buttons.next.visible = not game.lan.active or game.lan.hosting
 buttons.bump.visible = not game.holding_ball()
 buttons.lower_serve.visible = game.holding_ball()
 var a: ContextAthlete = game.athlete
 buttons.dive.visible = not game.holding_ball()
 buttons.jump_set.visible = a.airborne() and settings.show_jump_set and not game.holding_ball()
 buttons.context.visible = game.holding_ball() or game.ball.can_pick_up_for(game.athlete)

func _touch_down(id: int, pos: Vector2) -> void:
 _sync_held_state()
 if fingers.has(id):
  # A reused OS index starts a new contact, never inherits an old hold.
  _touch_up(id, true)
 _refresh_context()
 if edit_mode and editor_bar.get_global_rect().has_point(pos):
  return
 finger_positions[id] = pos
 if game.holding_ball() and not edit_mode and height_rect.grow(12).has_point(pos) and "height" not in fingers.values():
  fingers[id] = "height"
  var knob: float = height_rect.position.x + 16 + (game.ball.release_height() - 0.35) / 3.15 * (height_rect.size.x - 32)
  height_grab_offset = pos.x - knob if absf(pos.x - knob) <= 24 else 0.0
  _touch_move(id, pos)
  return
 var key := _button_at(pos)
 if not key.is_empty():
  if edit_mode:
   edit_selected = key
   editor_scale.set_value_no_signal(settings.layout.get(key, Vector3(0, 0, 1)).z)
   fingers[id] = "edit:" + key
  elif not role_owners.has(key):
   fingers[id] = key
   _press(key, id)
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
 if role.is_empty():
  return
 finger_positions[id] = pos
 if role == "move":
  if not game.holding_ball() and game.running_approach() and buttons.primary.rect.grow(16).has_point(pos) and game.begin_approach():
   fingers[id] = "approach"
   return
  move_value = ((pos - left_center) / radius).limit_length()
  if move_value.length() < 0.10:
   move_value = Vector2.ZERO
  _sync_axes()
 elif role == "approach":
  if pos.distance_to(left_center) < radius * 1.3:
   game.cancel_action("approach")
   fingers[id] = "move"
   _touch_move(id, pos)
 elif role == "height":
  var fraction := clampf((pos.x - height_grab_offset - height_rect.position.x - 16) / (height_rect.size.x - 32), 0, 1)
  game.ball.set_release_height(snappedf(lerpf(0.35, 3.5, fraction), 0.05))
 elif role == "camera":
  var next := _button_at(pos, 0)
  if next in ["primary", "secondary", "jump", "dive", "jump_set", "bump"] and not role_owners.has(next) and not game.holding_ball():
   camera_id = -1
   fingers[id] = next
   _press(next, id)
  elif (game.holding_ball() and game.ball.aiming_throw()):
   game.ball.aim_throw_at(game.camera, pos)
  else:
   _look_or_aim(relative)
 elif role in ["primary", "secondary", "jump", "dive", "jump_set", "bump"]:
  var next := _button_at(pos, 0)
  if not next.is_empty() and next != role and next in ["primary", "secondary", "jump", "dive", "jump_set", "bump"] and not role_owners.has(next):
   _release(role, id, true)
   fingers[id] = next
   _press(next, id)
 elif role.begins_with("edit:"):
  var key := role.trim_prefix("edit:")
  settings.layout[key] = Vector3(clampf(pos.x / size.x, 0.04, 0.96), clampf(pos.y / size.y, 0.1, 0.94), editor_scale.value)
  _layout()

func _look_or_aim(relative: Vector2) -> void:
 if game.holding_ball():
  if (game.holding_ball() and game.ball.aiming_throw()):
   # On desktop the captured mouse moves the landing target on the floor.
   var right: Vector3 = game.rig.camera.global_basis.x
   var forward: Vector3 = -game.rig.camera.global_basis.z
   right.y = 0
   forward.y = 0
   game.ball.throw_target += right.normalized() * relative.x * 0.025 + forward.normalized() * -relative.y * 0.025
   var start: Vector3 = game.athlete.hold_position()
   var offset: Vector3 = game.ball.throw_target - start
   offset.y = 0
   game.ball.throw_target = start + offset.limit_length(14)
   game.ball.throw_target.y = VolleyAthlete.BALL_RADIUS
  else:
   game.rig.look(relative)
   game.ball.aim_toss(relative)
 else:
  game.rig.look(relative)

func _touch_up(id: int, canceled := false) -> void:
 if not fingers.has(id):
  finger_positions.erase(id)
  return
 var role: String = fingers.get(id, "")
 var pos: Vector2 = finger_positions.get(id, Vector2.ZERO)
 fingers.erase(id)
 finger_positions.erase(id)
 if role == "move":
  move_id = -1
  move_value = Vector2.ZERO
  _sync_axes()
 elif role == "approach":
  if canceled or not buttons.primary.rect.grow(20).has_point(pos):
   game.cancel_action("approach")
  else:
   game.finish_action("approach")
  move_id = -1
  move_value = Vector2.ZERO
  _sync_axes()
 elif role == "camera":
  camera_id = -1
  if not canceled and (game.holding_ball() and game.ball.aiming_throw()):
   game.ball.aim_throw_at(game.camera, pos)
 elif not edit_mode:
  var outside: bool = buttons.has(role) and not buttons[role].rect.grow(24).has_point(pos)
  _release(role, id, canceled or outside)

func _sync_held_state() -> void:
 if held_snapshot != game.holding_ball():
  held_snapshot = game.holding_ball()
  queued.clear()
  for id in fingers.keys():
   if fingers[id] in ["primary", "secondary", "dive", "jump_set", "bump", "lower_serve", "height", "approach"]:
    _touch_up(id, true)
  for role in role_owners.keys():
   if role in ["primary", "secondary", "dive", "jump_set", "bump"]:
    _release(role, role_owners[role], true)

func _process(dt: float) -> void:
 var a: ContextAthlete = game.athlete
 _sync_held_state()
 if not menu.visible and not edit_mode and visible and (not is_instance_valid(game.frontend) or not game.frontend.blocks_input()) and not is_instance_valid(game.lower_serve.busy_actor):
  _sync_axes()
  _advance_buffers(dt)
 _refresh_context()
 buttons.primary.text = ("БРОСИТЬ" if (game.holding_ball() and game.ball.aiming_throw()) else "ПОДБРОС") if game.holding_ball() else "АТАКА" if a.airborne() or game.running_approach() or a.approach_armed or a.jump_windup > 0 else "ПОДАЧА" if game.serving else "АТАКА"
 buttons.secondary.text = ("К ПОДАЧЕ" if (game.holding_ball() and game.ball.aiming_throw()) else "ПРИЦЕЛ\nБРОСКА") if game.holding_ball() else "БЛОК" if a.airborne() else "ПАС"
 buttons.bump.text = "НИЖНИЙ\nПРИЁМ"
 buttons.lower_serve.text = "НИЖНЯЯ\nПОДАЧА"
 buttons.jump.text = "ПРЫЖОК"
 buttons.dive.text = "ПОДКАТ"
 buttons.jump_set.text = "ПАС ↑"
 buttons.menu.text = "≡"
 buttons.next.text = "↻"
 buttons.lock.text = "●" if a.shift_lock else "○"
 buttons.context.text = "ОПУСТИТЬ • F" if game.holding_ball() else "ПОДОБРАТЬ • F"
 status.text = VolleyTraining.NAMES[game.training.selected] + "  •  " + (game.rules.message if game.rules.ended else a.last_result)
 if game.holding_ball():
  status.text = "Подброс: +%.1f м над руками • высота ползунком • свайп: направление" % game.ball.release_height()
  if (game.holding_ball() and game.ball.aiming_throw()):
   status.text = "Коснитесь места на площадке → БРОСИТЬ • высота ползунком"
 elif a.attack_ready or a.jump_windup > 0:
  status.text = "Прыжок с замахом • нажмите АТАКА для удара"
 elif "approach" in fingers.values() or a.approach_armed:
  status.text = "Отпустите на АТАКЕ → прыжок с замахом"
 elif game.running_approach():
  status.text = "Разбег: переведите палец на АТАКУ и отпустите → прыжок"
 if game.lan.active:
  status.text = "A %d : %d Б • %d/12 • " % [game.lan.scores[0], game.lan.scores[1], game.lan.players.size()] + (game.rules.message if game.rules.ended else a.last_result)
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
  var active: bool = role_owners.has(key) or (key == "primary" and "approach" in fingers.values()) or (edit_mode and key == edit_selected)
  var color := Color(0.14, 0.27, 0.34, 0.66)
  if key in ["primary", "jump"]:
   color = Color(0.75, 0.57, 0.25, 0.72)
  if active:
   color = Color("b78d45")
  draw_style_box(_panel(color, int(rect.size.y * 0.38)), rect)
  var lines: PackedStringArray = buttons[key].text.split("\n")
  for line in range(lines.size()):
   draw_string(font, rect.position + Vector2(4, rect.size.y * 0.5 + 5 + (line - (lines.size() - 1) * 0.5) * 17), lines[line], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8, 14 if key not in ["menu", "next", "lock"] else 25, Color("f2f1e9"))
 if game.holding_ball() and not edit_mode:
  var fraction: float = (game.ball.release_height() - 0.35) / 3.15
  var y := height_rect.get_center().y
  draw_style_box(_panel(Color(0.03, 0.09, 0.14, 0.85)), height_rect.grow(8))
  draw_line(Vector2(height_rect.position.x + 16, y), Vector2(height_rect.end.x - 16, y), Color("557580"), 5, true)
  var knob := Vector2(height_rect.position.x + 16 + fraction * (height_rect.size.x - 32), y)
  draw_circle(knob, 15, Color("f4cf77"))
  draw_string(font, height_rect.position + Vector2(0, -12), "ПОДБРОС +%.2f м" % game.ball.release_height(), HORIZONTAL_ALIGNMENT_CENTER, height_rect.size.x, 17, Color("f4cf77"))
  draw_string(font, height_rect.position + Vector2(0, 68), "0.35 м     высота над руками     3.50 м", HORIZONTAL_ALIGNMENT_CENTER, height_rect.size.x, 12, Color("cad9df"))
 if game.athlete.action == VolleyAthlete.Action.PREPARE and not game.athlete.attack_ready and not edit_mode:
  var at := Vector2(size.x * 0.5 - 90, size.y - 108)
  draw_style_box(_panel(Color(0.03, 0.09, 0.14, 0.8)), Rect2(at - Vector2(10, 23), Vector2(200, 48)))
  draw_string(font, at - Vector2(0, 5), ("ДОЛЬШЕ → МЯГЧЕ  %d%%" if game.athlete.is_receive(game.athlete.technique) else "СИЛА  %d%%") % int(game.athlete.power * 100), HORIZONTAL_ALIGNMENT_CENTER, 180, 14, Color("f4cf77"))
  draw_line(at + Vector2(0, 12), at + Vector2(180, 12), Color("334d5c"), 5)
  draw_line(at + Vector2(0, 12), at + Vector2(180 * game.athlete.power, 12), Color("f4cf77"), 5)
 draw_arc(size * 0.5, 3, 0, TAU, 12, Color(1, 1, 1, 0.45), 1, true)
 if game.athlete.action in [VolleyAthlete.Action.PREPARE, VolleyAthlete.Action.STRIKE] and game.athlete.tilt_affects(game.athlete.technique) and not edit_mode:
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
