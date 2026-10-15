class_name VolleyFrontend
extends Control

var game: Node3D
var card: PanelContainer
var content: VBoxContainer
var info: Label
var address: LineEdit
var roster_label: Label
var in_home := true

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
 var join_row := HBoxContainer.new()
 content.add_child(join_row)
 address = LineEdit.new()
 address.placeholder_text = "IP создателя: 192.168.1.10"
 address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 address.custom_minimum_size.y = 52
 address.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
 join_row.add_child(address)
 var join_button: Button = game.hud._native_button(join_row, "Подключиться", join_from_field)
 join_button.custom_minimum_size.x = 160
 address.text_submitted.connect(func(_value: String): join_from_field())
 info = _label(game.lan.status, 16)
 _label("Все устройства — в одной Wi-Fi сети или на одной точке доступа.\nСоздатель сообщает свой IP остальным. Интернет не требуется.\nВ iOS разрешите доступ к локальной сети.", 16)
 _button("Настройки управления и спортсмена", func():
  game.hud.show()
  hide()
  game.hud.toggle_menu())

func join_from_field() -> void:
 game.lan.join_room(address.text)
 _refresh()

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
  _button("Скопировать IP комнаты", func(): DisplayServer.clipboard_set(game.lan.addresses()))
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
  if game.lan.connected:
   show_room()
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
 return visible or game.lower_serve.visible
