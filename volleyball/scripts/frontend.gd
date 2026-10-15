class_name VolleyFrontend
extends Control

var game: Node3D
var card: PanelContainer
var content: VBoxContainer
var info: Label
var address: LineEdit
var roster_label: Label
var in_home := true
var rooms_box: VBoxContainer
var search_info: Label
var join_button: Button
var auto_enter := false
var remembered := ""

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var shade := ColorRect.new()
 shade.color = Color(0.025, 0.06, 0.10, 0.94)
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(shade)
 card = PanelContainer.new()
 card.add_theme_stylebox_override("panel", game.hud._panel(Color("132b3c"), 24))
 add_child(card)
 var scroll := ScrollContainer.new()
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 card.add_child(scroll)
 content = VBoxContainer.new()
 content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 content.add_theme_constant_override("separation", 12)
 scroll.add_child(content)
 resized.connect(_layout)
 game.lan.changed.connect(_refresh)
 game.lan.discovery.changed.connect(_refresh_rooms)
 var saved := ConfigFile.new()
 if saved.load("user://rooms.cfg") == OK:
  remembered = str(saved.get_value("last", "address", ""))
 _layout()
 show_home()

func _layout() -> void:
 card.position = Vector2(size.x * 0.21, size.y * 0.06)
 card.size = Vector2(size.x * 0.58, size.y * 0.88)

func _clear() -> void:
 for child in content.get_children():
  content.remove_child(child)
  child.queue_free()

func _label(text: String, font_size := 18) -> Label:
 var label := Label.new()
 label.text = text
 label.add_theme_font_size_override("font_size", font_size)
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 content.add_child(label)
 return label

func _button(text: String, callback: Callable) -> Button:
 var button: Button = game.hud._native_button(content, text, callback)
 button.add_theme_font_size_override("font_size", 19)
 button.custom_minimum_size.y = 56
 return button

func show_home() -> void:
 get_tree().paused = false
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 visible = true
 in_home = true
 game.hud._cancel()
 game.hud.hide()
 _clear()
 _label("VOLLEY / LAB", 38).add_theme_color_override("font_color", Color("f4cf77"))
 _label("Площадка для себя и своей команды", 20)
 _button("Играть одному", start_solo)
 _button("Создать комнату • до 12 игроков", func():
  if game.lan.host_room() == OK:
   show_room()
  else:
   _refresh())
 _button("Найти комнаты в моей сети", func(): game.lan.discovery.search(); _refresh_rooms())
 search_info = _label("Откройте комнату у друга и нажмите поиск — IP вводить не нужно.", 16)
 rooms_box = VBoxContainer.new()
 content.add_child(rooms_box)
 var join_row := HBoxContainer.new()
 content.add_child(join_row)
 address = LineEdit.new()
 address.placeholder_text = "IP создателя: 192.168.1.10"
 address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 address.custom_minimum_size.y = 52
 address.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
 address.text = remembered
 address.max_length = 96
 address.select_all_on_focus = true
 join_row.add_child(address)
 join_button = game.hud._native_button(join_row, "Войти по IP", join_from_field)
 join_button.custom_minimum_size.x = 160
 var extras := HBoxContainer.new()
 content.add_child(extras)
 var dot: Button = game.hud._native_button(extras, ".", func():
  address.grab_focus()
  address.deselect()
  address.insert_text_at_caret("."))
 dot.custom_minimum_size.x = 70
 game.hud._native_button(extras, "Вставить IP", func(): address.text = VolleyLAN.normalize_address(DisplayServer.clipboard_get()))
 game.hud._native_button(extras, "Отменить подключение", func(): game.lan.leave(); game.lan.status = ""; auto_enter = false; _refresh())
 address.text_submitted.connect(func(_value: String): join_from_field())
 info = _label(game.lan.status, 16)
 _label("Android и iPhone играют вместе, версия должна совпадать. Подключите оба телефона к одной Wi-Fi сети или один к точке доступа другого. Один создаёт комнату, второй ищет её или вводит IP создателя. На iPhone разрешите локальную сеть.", 16)
 _refresh_rooms()
 _button("Настройки управления и спортсмена", func():
  game.hud.show()
  hide()
  game.hud.toggle_menu())

func join_from_field() -> void:
 join_to(VolleyLAN.normalize_address(address.text))

func join_to(ip: String, port := VolleyLAN.PORT) -> void:
 if game.lan.active and not game.lan.connected:
  return
 auto_enter = true
 remembered = ip
 if game.lan.join_room(ip, port) == OK:
  var saved := ConfigFile.new()
  saved.set_value("last", "address", ip)
  saved.save("user://rooms.cfg")
 if is_instance_valid(address):
  address.release_focus()
 _refresh()

func _refresh_rooms() -> void:
 if not in_home or not is_instance_valid(rooms_box):
  return
 for child in rooms_box.get_children():
  rooms_box.remove_child(child)
  child.queue_free()
 if is_instance_valid(search_info):
  search_info.text = game.lan.discovery.message if not game.lan.discovery.message.is_empty() else "Откройте комнату у друга и нажмите поиск."
 for room in game.lan.discovery.rooms.values():
  var entry: Dictionary = room
  var button: Button = game.hud._native_button(rooms_box, "Войти • %s • %d/12" % [entry.ip, entry.players], func(): join_to(entry.ip, entry.port))
  button.disabled = entry.players >= 12


func show_room() -> void:
 get_tree().paused = false
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 visible = true
 in_home = false
 game.hud._cancel()
 game.hud.hide()
 _clear()
 _label("КОМНАТА • VOLLEY / LAB", 30)
 info = _label("", 18)
 if game.lan.hosting:
  _button("Скопировать IP Wi-Fi / точки доступа", func(): DisplayServer.clipboard_set(game.lan.addresses().get_slice(",", 0).strip_edges()))
 roster_label = _label("", 20)
 _label("Две стороны, до 6 игроков в каждой. Можно входить во время игры.\nСоздатель рассчитывает мяч и счёт. Следующий розыгрыш — через 3 секунды.", 16)
 _button("На площадку", enter_court)
 _button("Выйти в главное меню", func(): game.lan.leave(); show_home())
 _refresh()

func _refresh() -> void:
 if not is_instance_valid(info):
  return
 if in_home:
  info.text = game.lan.status
  if is_instance_valid(join_button):
   join_button.disabled = game.lan.active and not game.lan.connected
   join_button.text = "Подключаюсь…" if join_button.disabled else "Войти по IP"
  if game.lan.connected:
   show_room()
   if auto_enter:
    enter_court()
  return
 info.text = ("Ваш IP: " + game.lan.addresses() + "\n" if game.lan.hosting else "Подключено к создателю\n") + "Игроки: %d / 12" % game.lan.players.size()
 if is_instance_valid(roster_label):
  var teams := [PackedStringArray(), PackedStringArray()]
  for id in game.lan.players:
   var entry: Dictionary = game.lan.players[id]
   teams[entry.team].append("№%d%s" % [entry.slot + 1, " (вы)" if id == multiplayer.get_unique_id() else ""])
  roster_label.text = "Сторона A: " + ", ".join(teams[0]) + "\nСторона Б: " + ", ".join(teams[1])

func enter_court() -> void:
 in_home = false
 visible = false
 game.hud.show()
 game.hud.menu.hide()
 game.hud.menu_blocker.hide()
 get_tree().paused = false
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.get_name() in ["iOS", "Android"] else Input.MOUSE_MODE_CAPTURED

func start_solo() -> void:
 game.lan.leave()
 enter_court()
 game.rules.strict = false
 game.start_drill()

func blocks_input() -> bool:
 return visible or game.lower_serve.visible or game.float_serve.visible
