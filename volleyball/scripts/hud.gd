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
var stat_effects := {}
var control_sliders := {}
var category_picker: OptionButton
var stat_grid: GridContainer
var resume_button: Button
var navigation: VBoxContainer
var nav_scroll: ScrollContainer
var nav_buttons: Array[Button] = []
var menu_mode: Label

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
 for key in ["super", "freak", "primary", "secondary", "jump", "dive", "jump_set", "menu", "next", "lock", "context", "bump", "lower_serve", "float_serve"]:
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
 var defaults := {"super": Vector2(size.x*0.80,106),"freak": Vector2(size.x * 0.65, 106), "float_serve": Vector2(size.x - margin - 300, size.y - 103), "bump": Vector2(size.x - margin - 280, size.y - 92), "lower_serve": Vector2(size.x - margin - 190, size.y - 103), "primary": Vector2(size.x - margin - 64, size.y - 174), "secondary": Vector2(size.x - margin - 174, size.y - 227), "jump": Vector2(size.x - margin - 70, size.y - 66), "dive": Vector2(size.x - margin - 190, size.y - 103), "jump_set": Vector2(size.x - margin - 272, size.y - 184), "menu": Vector2(size.x - margin - 26, 40), "next": Vector2(margin + 36, 42), "lock": Vector2(size.x - margin - 103, 40), "context": Vector2(size.x * 0.5, size.y - 48), "move": Vector2(margin + 84, size.y - 116)}
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
  if key in ["super", "freak"]:
   dimensions = Vector2(112, 52) * scale_value
  if key == "context":
   dimensions = Vector2(190, 44)
  at.x = clampf(at.x, margin + dimensions.x * 0.5, size.x - margin - dimensions.x * 0.5)
  at.y = clampf(at.y, 18 + dimensions.y * 0.5, size.y - dimensions.y * 0.5 - 12)
  buttons[key].rect = Rect2(at - dimensions * 0.5, dimensions)

 status.position = Vector2(margin + 70, 28)
 status.size = Vector2(size.x - margin * 2 - 260, 44)
 height_rect = Rect2(Vector2(size.x * 0.5 - 140, 104), Vector2(280, 50))
 var menu_width := minf(1120, size.x - 32)
 menu.position = Vector2((size.x - menu_width) * 0.5, 12)
 menu.size = Vector2(menu_width, size.y - 24)
 if is_instance_valid(nav_scroll):
  nav_scroll.custom_minimum_size.x = 156 if size.x < 1000 else 204
 if is_instance_valid(stat_grid):
  stat_grid.columns = 2 if menu.size.x > 620 else 1
 if is_instance_valid(editor_bar):
  editor_bar.position = Vector2(size.x * 0.16, 16)
  editor_bar.size = Vector2(size.x * 0.68, 64)

func _menu() -> void:
 menu_blocker = ColorRect.new()
 menu_blocker.color = Color(0.015, 0.04, 0.06, 0.91)
 menu_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 menu_blocker.visible = false
 add_child(menu_blocker)
 menu = PanelContainer.new()
 var shell := VolleySettingsTheme.box("091f2a", 22)
 shell.set_border_width_all(1)
 shell.border_color = Color("38515a")
 shell.shadow_color = Color(0, 0, 0, 0.35)
 shell.shadow_size = 18
 menu.add_theme_stylebox_override("panel", shell)
 menu.theme = VolleySettingsTheme.build()
 menu.add_theme_font_override("font", VolleyMenuArt.typeface())
 menu.visible = false
 add_child(menu)
 var content := VBoxContainer.new()
 content.add_theme_constant_override("separation", 8)
 menu.add_child(content)
 var header := HBoxContainer.new()
 header.add_theme_constant_override("separation", 16)
 content.add_child(header)
 var title := Label.new()
 title.text = "VOLLEY / LAB  /"
 title.add_theme_font_size_override("font_size", 20)
 title.add_theme_color_override("font_color", Color("f4f0e5"))
 header.add_child(title)
 menu_mode = Label.new()
 menu_mode.text = "НАСТРОЙКИ"
 menu_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 menu_mode.add_theme_font_size_override("font_size", 12)
 menu_mode.add_theme_color_override("font_color", Color("ff9b76"))
 header.add_child(menu_mode)
 category_picker = OptionButton.new()
 category_picker.visible = false
 category_picker.item_selected.connect(func(index: int): tabs.current_tab = index)
 header.add_child(category_picker)
 _native_button(header, "✕", toggle_menu).custom_minimum_size = Vector2(44, 44)
 var workspace := HBoxContainer.new()
 workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
 workspace.add_theme_constant_override("separation", 16)
 content.add_child(workspace)
 nav_scroll = ScrollContainer.new()
 nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 nav_scroll.follow_focus = true
 nav_scroll.custom_minimum_size.x = 156
 workspace.add_child(nav_scroll)
 navigation = VBoxContainer.new()
 navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 navigation.add_theme_constant_override("separation", 6)
 nav_scroll.add_child(navigation)
 tabs = TabContainer.new()
 tabs.tabs_visible = false
 tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
 tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 tabs.add_theme_stylebox_override("panel", VolleySettingsTheme.box("112d39", 16))
 tabs.tab_changed.connect(func(index: int):
  if index < category_picker.item_count:
   category_picker.select(index)
  _refresh_navigation_style())
 workspace.add_child(tabs)
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
 help.text = "ЛКМ: атака. Q: пас / блок. E: пас в прыжке.\nX: нижний приём. V: нижняя подача. B: планер.\nSpace: прыжок. Ctrl: подкат. R: следующий мяч. F: подобрать / опустить.\nРазбег: нажать и отпустить АТАКУ другим пальцем → прыжок.\nСледующий нажим АТАКИ → удар.\nМяч в руках: высота ползунком, основная кнопка → подброс.\nПРИЦЕЛ БРОСКА / Q → выбрать место на площадке → БРОСИТЬ / ЛКМ."
 help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 help.text += "\nНа ПК высота: колесо мыши. Tilt: джойстик / WASD до контакта.\nНижний приём всегда вверх; дольше держать — мягче.\nУдерживая действие, ведите палец для поворота камеры.\nОбычный удар без комбинации: удерживать для меньшей силы, отпустить для касания."
 help.visible = false
 _native_button(practice, "Как играть  ▾", func(): help.visible = not help.visible)
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
 var nick_label := Label.new()
 nick_label.text = "Ваш ник · виден другим игрокам"
 testing.add_child(nick_label)
 var nick_row := HBoxContainer.new()
 testing.add_child(nick_row)
 var nickname := LineEdit.new()
 nickname.name = "Nickname"
 nickname.text = settings.nickname
 nickname.placeholder_text = "Введите ник"
 nickname.max_length = 24
 nickname.custom_minimum_size.y = 46
 nickname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 nick_row.add_child(nickname)
 var apply_nickname := func():
  settings.nickname = VolleySettings.clean_nickname(nickname.text)
  nickname.text = settings.nickname
  _save()
  game.lan.rename_local(settings.nickname)
  nickname.release_focus()
 _native_button(nick_row, "Сохранить", apply_nickname)
 nickname.text_submitted.connect(func(_text: String): apply_nickname.call())
 var explanation := Label.new()
 explanation.text = "Характеристики определяются выбранным персонажем. Изменение вручную отключено."
 explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 testing.add_child(explanation)
 _native_button(testing, "Персонажи", func(): game.characters.ui.open_characters(true))
 _native_button(testing, "Настройка матча", func(): game.characters.ui.open_teams(true))
 var footer := HBoxContainer.new()
 footer.add_theme_constant_override("separation", 12)
 content.add_child(footer)
 _native_button(footer, "Главное меню", func():
  _cancel()
  menu.hide()
  menu_blocker.hide()
  get_tree().paused = false
  game.lan.leave()
  game.frontend.show_home())
 resume_button = _native_button(footer, "Продолжить", func():
  toggle_menu()
  if game.frontend.in_home:
   game.frontend.show_home())
 for button in footer.get_children():
  button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 VolleyMenuArt.style_button(footer.get_child(1), true)
 refresh_navigation()

func refresh_navigation() -> void:
 category_picker.clear()
 for button in nav_buttons:
  navigation.remove_child(button)
  button.queue_free()
 nav_buttons.clear()
 for index in range(tabs.get_tab_count()):
  category_picker.add_item(tabs.get_tab_title(index))
  var tab_index := index
  var button := Button.new()
  button.text = "%02d   %s" % [index + 1, tabs.get_tab_title(index)]
  button.alignment = HORIZONTAL_ALIGNMENT_LEFT
  button.custom_minimum_size = Vector2(144, 44)
  button.pressed.connect(func(): tabs.current_tab = tab_index)
  navigation.add_child(button)
  nav_buttons.append(button)
 category_picker.select(tabs.current_tab)
 _refresh_navigation_style()

func _refresh_navigation_style() -> void:
 for index in range(nav_buttons.size()):
  VolleySettingsTheme.navigation(nav_buttons[index], index == tabs.current_tab)
 if tabs.current_tab >= 0 and tabs.current_tab < nav_buttons.size():
  call_deferred("_scroll_current_category")

func _scroll_current_category() -> void:
 if not is_instance_valid(nav_scroll) or tabs.current_tab < 0 or tabs.current_tab >= nav_buttons.size():
  return
 var button: Button = nav_buttons[tabs.current_tab]
 if is_instance_valid(button) and nav_scroll.is_ancestor_of(button):
  nav_scroll.ensure_control_visible(button)

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
 button.custom_minimum_size.y = 44
 VolleyMenuArt.style_button(button)
 button.add_theme_font_size_override("font_size", 17)
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
 list.add_theme_constant_override("separation", 10)
 scroll.add_child(list)
 var heading := Label.new()
 heading.text = title.to_upper()
 heading.add_theme_font_override("font", VolleyMenuArt.typeface(750))
 heading.add_theme_font_size_override("font_size", 25)
 heading.add_theme_color_override("font_color", Color("f4f0e5"))
 list.add_child(heading)
 var accent := ColorRect.new()
 accent.color = Color("ff9b76")
 accent.custom_minimum_size = Vector2(48, 3)
 accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
 accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
 list.add_child(accent)
 return list

func _slider(parent: Node, title: String, low: float, high: float, value: float, callback: Callable, step_value := 1.0) -> HSlider:
 var card := PanelContainer.new()
 card.add_theme_stylebox_override("panel", VolleySettingsTheme.box("193945", 12))
 var row := VBoxContainer.new()
 card.add_child(row)
 var label := Label.new()
 label.text = "%s  ·  %.2f" % [title, value]
 label.add_theme_color_override("font_color", Color("c4d9d8"))
 row.add_child(label)
 var slider := HSlider.new()
 slider.min_value = low
 slider.max_value = high
 slider.step = step_value
 slider.value = value
 slider.custom_minimum_size = Vector2(180, 44)
 slider.value_changed.connect(func(v: float): label.text = "%s  ·  %.2f" % [title, v]; callback.call(v))
 row.add_child(slider)
 parent.add_child(card)
 return slider

func _refresh_keys() -> void:
 for key in key_buttons:
  key_buttons[key].text = "%s: %s" % [VolleySettings.KEY_LABELS.get(key, "Суперподача"), "ЛКМ" if settings.keys[key] < 0 else OS.get_keycode_string(settings.keys[key])]

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
 if is_instance_valid(game.super_serve) and game.super_serve.locks(game.athlete):
  return
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
  for key in ["super", "freak", "primary", "secondary", "jump", "dive", "jump_set", "bump", "lower_serve", "float_serve", "next", "pickup", "lock"]:
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
 if game.super_serve.locks(game.athlete):
  return false
 if role == "super":
  return game.super_serve.request()
 if game.athlete.court_team < 0 and not game.game_bots.bots.is_empty() and role not in ["menu", "lock", "next"]:
  return false
 if role in ["freak"] and not game.lan.active:
  return game.begin_special(role)
 if game.automatic_serve_busy() and role not in ["menu", "lock", "next"]:
  return false
 if role == "lower_serve":
  return game.lower_serve.open()
 if role == "float_serve":
  return game.float_serve.open()
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
 if role in ["primary", "secondary", "jump_set", "bump", "freak"]:
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
   if released and role in ["primary", "secondary", "jump_set", "bump", "freak"]:
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
 if is_instance_valid(game.super_serve) and game.super_serve.locks(game.athlete):
  game.athlete.move_axis = Vector2.ZERO
  return
 if move_id < 0 or fingers.get(move_id, "") not in ["move", "approach"]:
  move_value = Vector2.ZERO
  move_id = -1
 var keyboard := Input.get_vector("volley_left", "volley_right", "volley_forward", "volley_back")
 var axis := (keyboard + move_value).limit_length()
 game.athlete.move_axis = game.rig.movement(axis)
 game.athlete.tilt = axis

func _refresh_context() -> void:
 var kageyama: bool = game.athlete.character_id == "kageyama" and not game.holding_ball()
 buttons.super.visible = is_instance_valid(game.super_serve) and game.super_serve.eligible(game.athlete)
 buttons.freak.visible = kageyama and is_instance_valid(game.characters) and not game.characters.partners(game.athlete).is_empty()
 buttons.next.visible = not game.lan.active or game.lan.hosting
 buttons.bump.visible = not game.holding_ball()
 buttons.lower_serve.visible = game.holding_ball()
 buttons.float_serve.visible = game.holding_ball()
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
  if (game.holding_ball() and game.ball.aiming_throw()):
   game.ball.aim_throw_at(game.camera, pos)
  else:
   _look_or_aim(relative)
 elif role in ["primary", "secondary", "jump", "dive", "jump_set", "bump", "freak"]:
  # Capture is fixed at touch-down. Sliding across another button cannot
  # activate it, and leaving the original rectangle does not cancel a hold.
  # A dedicated look finger keeps priority; otherwise this finger can aim.
  if camera_id == -1:
   camera_id = id
  if camera_id == id:
   _look_or_aim(relative)
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
   game.ball.throw_target.y = VolleyBall.RADIUS
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
 if camera_id == id:
  camera_id = -1
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
  _release(role, id, canceled)

func _sync_held_state() -> void:
 if held_snapshot != game.holding_ball():
  held_snapshot = game.holding_ball()
  queued.clear()
  for id in fingers.keys():
   if fingers[id] in ["primary", "secondary", "dive", "jump_set", "bump", "lower_serve", "float_serve", "height", "approach", "freak"]:
    _touch_up(id, true)
  for role in role_owners.keys():
   if role in ["primary", "secondary", "dive", "jump_set", "bump", "freak"]:
    _release(role, role_owners[role], true)

func _process(dt: float) -> void:
 var a: ContextAthlete = game.athlete
 _sync_held_state()
 if not menu.visible and not edit_mode and visible and (not is_instance_valid(game.frontend) or not game.frontend.blocks_input()) and not game.automatic_serve_busy():
  _sync_axes()
  _advance_buffers(dt)
 _refresh_context()
 buttons.primary.text = ("БРОСИТЬ" if (game.holding_ball() and game.ball.aiming_throw()) else "ПОДБРОС") if game.holding_ball() else "АТАКА" if a.airborne() or game.running_approach() or a.approach_armed or a.jump_windup > 0 else "ПОДАЧА" if game.serving else "АТАКА"
 buttons.secondary.text = ("К ПОДАЧЕ" if (game.holding_ball() and game.ball.aiming_throw()) else "ПРИЦЕЛ\nБРОСКА") if game.holding_ball() else "БЛОК" if a.airborne() else "ПАС"
 if not game.holding_ball() and a.airborne() and not a.approach_jump and not game.serving:
  buttons.primary.text = "ФИНТ"
 buttons.bump.text = "НИЖНИЙ\nПРИЁМ"
 buttons.lower_serve.text = "НИЖНЯЯ\nПОДАЧА"
 buttons.float_serve.text = "ПОДАЧА\nПЛАНЕР"
 buttons.freak.text = "FREAK\nQUICK"
 buttons.super.text = "SUPER\nSERVE"
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
  status.text = "Разбег: нажмите и отпустите АТАКУ → прыжок с замахом"
 if game.lan.active:
  status.text = VolleyMatchScore.label(game.lan.scores, game.lan.sets, game.lan.match_winner) + " • %d/12 • " % game.lan.players.size() + (game.rules.message if game.rules.ended else a.last_result)
 elif game.game_bots.solo_match:
  status.text = VolleyMatchScore.label(game.game_bots.scores, game.game_bots.sets, game.game_bots.match_winner) + " • " + (game.rules.message if game.rules.ended else a.last_result)
 if game.lan.active and not game.lan.match_active:
  status.text = game.lan.ready_message + " • " + a.last_result
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
  if key in ["super", "freak"]:
   color = Color("a26335")
  if key == "super":
   color = Color("287a80")
   draw_style_box(_panel(Color("f2cf87"),20),rect.grow(3))
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
 if game.athlete.action == VolleyAthlete.Action.PREPARE and game.athlete.technique != ContextAthlete.BLOCK and not game.athlete.attack_ready and not edit_mode:
  var at := Vector2(size.x * 0.5 - 90, size.y - 108)
  draw_style_box(_panel(Color(0.03, 0.09, 0.14, 0.8)), Rect2(at - Vector2(10, 23), Vector2(200, 48)))
  draw_string(font, at - Vector2(0, 5), ("ДОЛЬШЕ → МЯГЧЕ  %d%%" if game.athlete.is_receive(game.athlete.technique) else "СИЛА  %d%%") % int(game.athlete.power * 100), HORIZONTAL_ALIGNMENT_CENTER, 180, 14, Color("f4cf77"))
  draw_line(at + Vector2(0, 12), at + Vector2(180, 12), Color("334d5c"), 5)
  draw_line(at + Vector2(0, 12), at + Vector2(180 * game.athlete.power, 12), Color("f4cf77"), 5)
 if game.feedback_left > 0 and not edit_mode:
  if not game.feedback_text.is_empty():
   var box := Rect2(Vector2(size.x * 0.5 - 200, size.y * 0.29), Vector2(400, 58))
   draw_style_box(_panel(Color(0.025, 0.07, 0.11, 0.94)), box)
   draw_string(font, box.position + Vector2(8, 37), game.feedback_text, HORIZONTAL_ALIGNMENT_CENTER, 384, 23, game.feedback_color)
  for x in [-1, 1]:
   draw_line(size * 0.5 + Vector2(x * 14, -10), size * 0.5 + Vector2(x * 25, -18), game.feedback_color, 4, true)
 draw_string(font, Vector2(24, size.y - 12), "%d FPS" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("a7bdc9"))
 draw_arc(size * 0.5, 3, 0, TAU, 12, Color(1, 1, 1, 0.45), 1, true)

func _panel(color: Color, corners := 12) -> StyleBoxFlat:
 var style := StyleBoxFlat.new()
 style.bg_color = color
 style.set_corner_radius_all(corners)
 style.content_margin_left = 12
 style.content_margin_right = 12
 style.content_margin_top = 8
 style.content_margin_bottom = 8
 return style

func add_bot_settings() -> void:
 game.practice.add_settings(self)
