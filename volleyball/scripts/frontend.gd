class_name VolleyFrontend
extends Control

var game: Node3D
var card: PanelContainer
var scroll: ScrollContainer
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
var page := "home"
var art: VolleyMenuArt
var footer: HBoxContainer
var manual_nodes: Array[Control] = []
var cancel_button: Button
var headings: Array[Label] = []

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 art = VolleyMenuArt.new()
 add_child(art)
 card = PanelContainer.new()
 card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
 add_child(card)
 scroll = ScrollContainer.new()
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 scroll.follow_focus = true
 card.add_child(scroll)
 content = VBoxContainer.new()
 content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 content.add_theme_constant_override("separation", 12)
 scroll.add_child(content)
 footer = HBoxContainer.new()
 footer.add_theme_constant_override("separation", 20)
 add_child(footer)
 var author := Label.new()
 author.text = "by Selivonchyk Alexey"
 author.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 author.add_theme_font_size_override("font_size", 15)
 author.add_theme_color_override("font_color", Color("c2d0d2"))
 footer.add_child(author)
 var version := Label.new()
 version.text = "0.39"
 version.add_theme_font_size_override("font_size", 15)
 version.add_theme_color_override("font_color", Color("c2d0d2"))
 footer.add_child(version)
 resized.connect(_layout)
 game.lan.changed.connect(_refresh)
 game.lan.discovery.changed.connect(_refresh_rooms)
 var saved := ConfigFile.new()
 if saved.load("user://rooms.cfg") == OK:
  remembered = str(saved.get_value("last", "address", ""))
 show_home()

func _layout() -> void:
 if not is_instance_valid(card):
  return
 var margin := maxf(28, size.x * 0.07)
 var wide := size.x >= size.y * 1.45
 card.position = Vector2(margin, maxf(20, size.y * 0.075))
 card.size = Vector2(size.x * (0.44 if page == "home" and wide else 0.68) if wide else size.x - margin * 2, size.y - card.position.y - 66)
 footer.position = Vector2(margin, size.y - 43)
 footer.size = Vector2(size.x - margin * 2, 24)
 var compact := size.y < 500
 if page == "home" and headings.size() == 2:
  headings[0].text = "VOLLEY / LAB" if compact else "VOLLEY"
  headings[1].visible = not compact
 for heading in headings:
  heading.add_theme_font_size_override("font_size", clampi(int(size.y * (0.087 if compact else 0.106)), 28, 82) if page == "home" else clampi(int(size.y * 0.067), 28, 46))
 content.add_theme_constant_override("separation", 8 if size.y < 500 else 12)
 for button in content.find_children("*", "Button", true, false):
  button.custom_minimum_size.y = clampf(size.y * 0.088, 48, 66)
  button.add_theme_font_size_override("font_size", 18 if size.y < 500 else 20)
 art.show_ball = page == "home"
 art.queue_redraw()

func _clear() -> void:
 address = null
 rooms_box = null
 search_info = null
 join_button = null
 roster_label = null
 info = null
 cancel_button = null
 manual_nodes.clear()
 headings.clear()
 for child in content.get_children():
  content.remove_child(child)
  child.queue_free()

func _label(text: String, font_size := 18) -> Label:
 var label := Label.new()
 label.text = text
 label.add_theme_font_override("font", VolleyMenuArt.typeface(500))
 label.add_theme_font_size_override("font_size", font_size)
 label.add_theme_color_override("font_color", Color("a4bac2"))
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 content.add_child(label)
 return label

func _heading(text: String, accent := false) -> void:
 var label := _label(text, 48)
 label.add_theme_font_override("font", VolleyMenuArt.typeface(800))
 label.add_theme_color_override("font_color", Color("f18b58") if accent else Color("f5f2df"))
 headings.append(label)

func _make_button(parent: Node, text: String, callback: Callable, primary := false) -> Button:
 var button := Button.new()
 button.text = text
 button.custom_minimum_size.y = clampf(size.y * 0.088, 50, 66)
 button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 VolleyMenuArt.style_button(button, primary)
 button.pressed.connect(callback)
 parent.add_child(button)
 return button

func _button(text: String, callback: Callable, primary := false) -> Button:
 return _make_button(content, text, callback, primary)

func _open_page(next: String) -> void:
 get_tree().paused = false
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 visible = true
 in_home = next != "room"
 page = next
 game.hud._cancel()
 game.hud.hide()
 _clear()

func show_home() -> void:
 _open_page("home")
 _label("ВОЛЕЙБОЛ  /  1–12 ИГРОКОВ", 15)
 _heading("VOLLEY")
 _heading("/ LAB", true)
 _button("Играть одному   →", start_solo, true)
 _button("Играть с друзьями", show_network)
 _button("Персонажи", func(): game.characters.ui.open_characters())
 _button("Настройка матча", func(): game.characters.ui.open_teams())
 _button("Тренировка", func(): game.characters.ui.open_teams())
 _button("Настройки", func():
  game.hud.show()
  hide()
  game.hud.toggle_menu())
 info = _label(game.lan.status, 15)
 info.visible = not info.text.is_empty()
 _layout()

func show_network() -> void:
 _open_page("network")
 _button("←  Назад", show_home).custom_minimum_size.y = 44
 _heading("С ДРУЗЬЯМИ")
 _label("Одна Wi-Fi сеть или точка доступа · до 12 игроков", 17)
 var actions: BoxContainer = HBoxContainer.new() if size.x >= 600 else VBoxContainer.new()
 actions.add_theme_constant_override("separation", 12)
 content.add_child(actions)
 _make_button(actions, "Создать комнату", func():
  if game.lan.host_room() == OK:
   show_room()
  else:
   _refresh(), true)
 _make_button(actions, "Найти комнаты", func(): game.lan.discovery.search(); _refresh_rooms())
 search_info = _label("", 16)
 rooms_box = VBoxContainer.new()
 rooms_box.add_theme_constant_override("separation", 8)
 content.add_child(rooms_box)
 _button("Войти по IP", func(): _set_manual(manual_nodes.is_empty() or not manual_nodes[0].visible)).custom_minimum_size.y = 48
 var join_row := HBoxContainer.new()
 join_row.add_theme_constant_override("separation", 10)
 content.add_child(join_row)
 address = LineEdit.new()
 address.placeholder_text = "IP создателя: 192.168.1.10"
 address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 address.custom_minimum_size.y = 54
 address.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
 address.text = remembered
 address.max_length = 96
 address.select_all_on_focus = true
 address.add_theme_font_size_override("font_size", 18)
 address.add_theme_stylebox_override("normal", VolleyMenuArt.panel(Color("112b3c")))
 join_row.add_child(address)
 join_button = _make_button(join_row, "Войти", join_from_field, true)
 join_button.custom_minimum_size.x = 110
 join_button.size_flags_horizontal = Control.SIZE_FILL
 var extras := HBoxContainer.new()
 extras.add_theme_constant_override("separation", 10)
 content.add_child(extras)
 var dot := _make_button(extras, ".", func():
  address.grab_focus()
  address.deselect()
  address.insert_text_at_caret("."))
 dot.custom_minimum_size.x = 64
 dot.size_flags_horizontal = Control.SIZE_FILL
 _make_button(extras, "Вставить IP", func(): address.text = VolleyLAN.normalize_address(DisplayServer.clipboard_get()))
 manual_nodes = [join_row, extras]
 _set_manual(false)
 cancel_button = _button("Отменить подключение", func(): game.lan.leave(); game.lan.status = ""; auto_enter = false; _refresh())
 address.text_submitted.connect(func(_value: String): join_from_field())
 info = _label(game.lan.status, 16)
 _refresh_rooms()
 _refresh()
 _layout()

func _set_manual(on: bool) -> void:
 for node in manual_nodes:
  node.visible = on
 if on:
  _scroll_to_manual.call_deferred()

func _scroll_to_manual() -> void:
 await get_tree().process_frame
 if not manual_nodes.is_empty() and is_instance_valid(manual_nodes[-1]) and manual_nodes[-1].visible:
  scroll.ensure_control_visible(manual_nodes[-1])

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
 if page != "network" or not is_instance_valid(rooms_box):
  return
 for child in rooms_box.get_children():
  rooms_box.remove_child(child)
  child.queue_free()
 if is_instance_valid(search_info):
  search_info.text = game.lan.discovery.message
  search_info.visible = not search_info.text.is_empty()
 for room in game.lan.discovery.rooms.values():
  var entry: Dictionary = room
  var button := _make_button(rooms_box, "%s    ·    %d / 12    →" % [entry.ip, entry.players], func(): join_to(entry.ip, entry.port))
  button.disabled = entry.players >= 12

func show_room() -> void:
 _open_page("room")
 _label("СЕТЕВАЯ ИГРА", 15)
 _heading("КОМНАТА")
 _label("Свободная игра. Для матча всем нужно встать в цветные зоны справа от площадки.", 17)
 info = _label("", 18)
 if game.lan.hosting:
  _button("Скопировать IP", func(): DisplayServer.clipboard_set(game.lan.addresses().get_slice(",", 0).strip_edges()))
 roster_label = _label("", 20)
 _button("На площадку   →", enter_court, true)
 _button("Выйти в меню", func(): game.lan.leave(); show_home())
 _refresh()
 _layout()

func _refresh() -> void:
 if not is_instance_valid(info):
  return
 if in_home:
  info.text = game.lan.status
  info.visible = not info.text.is_empty()
  var connecting: bool = game.lan.active and not game.lan.connected
  if is_instance_valid(cancel_button):
   cancel_button.visible = connecting
  if is_instance_valid(join_button):
   join_button.disabled = connecting
   join_button.text = "Ждём…" if connecting else "Войти"
  if game.lan.connected:
   show_room()
   if auto_enter:
    enter_court()
  return
 info.text = ("Ваш IP: " + game.lan.addresses() + "\n" if game.lan.hosting else "Подключено\n") + "Игроки: %d / 12" % game.lan.players.size()
 if is_instance_valid(roster_label):
  var teams := [PackedStringArray(), PackedStringArray()]
  for id in game.lan.players:
   var entry: Dictionary = game.lan.players[id]
   teams[entry.team].append(str(entry.get("nickname", "Игрок")) + (" (вы)" if id == multiplayer.get_unique_id() else ""))
  roster_label.text = "Сторона A   " + ", ".join(teams[0]) + "\nСторона Б   " + ", ".join(teams[1]) if game.lan.match_active else "Свободная разминка • %d игроков" % game.lan.players.size()

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
 game.characters.apply_teams(game.characters.teams, game.characters.difficulty, false)
 game.start_drill()

func blocks_input() -> bool:
 return visible or game.lower_serve.visible or game.float_serve.visible
