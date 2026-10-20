class_name VolleyCharacterSelection
extends Node

var manager: VolleyCharacters
var return_to_court := false
var draft: Array = []
var chosen_level := 1
var selected_side := 0
var selected_club := ""

func close() -> void:
 if return_to_court:
  manager.game.frontend.enter_court()
 else:
  manager.game.frontend.show_home()

func open_characters(from_court := false) -> void:
 return_to_court = from_court
 var f: VolleyFrontend = manager.game.frontend
 f._open_page("characters")
 f.get_tree().paused = from_court and not manager.game.lan.active
 f._button("← Назад", close)
 f._heading("ПЕРСОНАЖИ")
 f._label("Karasuno / Aoba Johsai · фиксированные характеристики · без прокачки", 16)
 for id in VolleyCharacterDatabase.IDS:
  var data := VolleyCharacterDatabase.get_character(id)
  var panel := PanelContainer.new()
  panel.add_theme_stylebox_override("panel", VolleySettingsTheme.box("102f3b", 16))
  f.content.add_child(panel)
  var box := VBoxContainer.new()
  box.add_theme_constant_override("separation", 10)
  panel.add_child(box)
  var title := Label.new()
  title.text = "%s   #%d   %s" % [data.name, int(data.number), data.rarity]
  title.add_theme_font_size_override("font_size", 24)
  title.add_theme_color_override("font_color", Color("f1c88c"))
  title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  box.add_child(title)
  var info := Label.new()
  info.text = "%s · %s · %.1f см" % [data.team, data.position, float(data.height_cm)]
  info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  box.add_child(info)
  var grid := GridContainer.new()
  grid.columns = 2
  grid.add_theme_constant_override("h_separation", 28)
  box.add_child(grid)
  for stat in VolleyStyleStats.KEYS:
   var label := Label.new()
   label.text = "%s  %d" % [stat.capitalize(), int(data.stats[stat])]
   grid.add_child(label)
  for description in data.abilities:
   var label := Label.new()
   label.text = description
   label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
   label.add_theme_font_size_override("font_size", 16)
   label.add_theme_color_override("font_color", Color("b8cbd1"))
   box.add_child(label)
  var hero: String = id
  f._make_button(box, "Выбран" if manager.selected == id else "Выбрать персонажа", func():
   manager.choose_local(hero)
   open_characters(return_to_court), manager.selected == id)
 f._layout()

func open_teams(from_court := false) -> void:
 return_to_court = from_court
 draft = manager.teams.duplicate(true)
 var owner: int = manager.game.lan.multiplayer.get_unique_id() if manager.game.lan.active else 0
 var humans: Array = manager.game.lan.players.keys() if manager.game.lan.active else [0]
 for team in draft:
  for slot in team:
   if slot.kind == "human":
    if slot.human in [0, 1] and not manager.game.lan.active:
     slot.human = 0
    elif slot.human == 0:
     slot.human = owner
    elif not slot.human in humans:
     slot.kind = "empty"
 if from_court or manager.game.lan.active:
  snapshot_court()
 chosen_level = manager.difficulty
 draw_teams()

func draw_teams() -> void:
 var f: VolleyFrontend = manager.game.frontend
 f._open_page("teams")
 f.get_tree().paused = return_to_court and not manager.game.lan.active
 f._button("← Назад", close)
 f._heading("НАСТРОЙКА МАТЧА")
 if not manager.authority():
  f._label("Составы меняет создатель комнаты. Своего персонажа можно выбрать в карточках.")
  f._button("Персонажи", func(): open_characters(return_to_court))
  f._layout()
  return
 f._label("1 · Сторона площадки   →   2 · Команда аниме   →   3 · Персонажи", 16)
 var level := OptionButton.new()
 for title in ["Лёгкий · характеристики ботов 80%", "Средний · характеристики ботов 90%", "Сложный · характеристики ботов 100%"]:
  level.add_item(title)
 level.select(chosen_level)
 level.item_selected.connect(func(index: int): chosen_level = index)
 level.custom_minimum_size.y = 48
 f.content.add_child(level)
 for team in range(2):
  var side := team
  var box := card()
  card_label(box, "КОМАНДА %s   ·   %d / 6" % [side_name(side), occupied(side)], 24)
  var names: Array[String] = []
  for hero in VolleyCharacterDatabase.IDS:
   var count := bot_count(side, hero)
   if count > 0:
    names.append("%s × %d" % [VolleyCharacterDatabase.get_character(hero).name, count])
  card_label(box, "Людей: %d · Ботов: %d · Свободно: %d" % [human_count(side), occupied(side)-human_count(side), 6-occupied(side)], 16)
  if not names.is_empty():
   card_label(box, " · ".join(names), 16)
  f._make_button(box, "Выбрать ботов  →", func(): selected_side = side; draw_clubs(), true)
 f._label("ИГРОКИ", 20)
 var humans: Array = manager.game.lan.players.keys() if manager.game.lan.active else [0]
 for id in humans:
  var human: int = id
  var row := HBoxContainer.new()
  f.content.add_child(row)
  var nick := Label.new()
  nick.text = str(manager.game.lan.players[id].get("nickname", "Игрок")) if manager.game.lan.active else "Я"
  nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  row.add_child(nick)
  var side_picker := OptionButton.new()
  side_picker.add_item("Команда A")
  side_picker.add_item("Команда B")
  var current := human_side(human)
  side_picker.select(current if current >= 0 else -1)
  side_picker.custom_minimum_size = Vector2(170, 48)
  side_picker.item_selected.connect(func(side: int): move_human(human, side); draw_teams())
  row.add_child(side_picker)
 var result := f._label("", 16)
 var apply := func():
  if not contains_room_players():
   result.text = "Состав комнаты изменился. Откройте настройку матча заново: учтём новых игроков."
   return false
  if not manager.apply_teams(draft, chosen_level):
   result.text = "Игрок может занимать только один слот. Проверьте участников комнаты."
   return false
  result.text = "Составы сохранены"
  return true
 f._button("Сохранить составы", func(): apply.call(), true)
 f._button("Свободная игра", func():
  if apply.call():
   manager.demo = false
   f.enter_court())
 f._button("Начать матч", func():
  if apply.call():
   if manager.game.lan.active:
    result.text = "Для начала все люди должны подтвердить команду в зонах у корта."
   else:
    if manager.game.game_bots.start_solo():
     f.enter_court()
    else:
     result.text = "Для матча нужны обе команды. Без соперника выберите свободную игру.")
 f._button("Демонстрация синергии", func():
  if apply.call():
   manager.start_demo()
   f.enter_court())
 f._layout()

# Read actual court participants: saved settings can predate a room join or bot spawn.
func snapshot_court() -> void:
 draft = manager.default_teams()
 for team in draft:
  for slot in team:
   slot.kind = "empty"
 if manager.game.lan.active:
  for id in manager.game.lan.players:
   var entry: Dictionary = manager.game.lan.players[id]
   var side: int = entry.actor.court_team if entry.actor.court_team >= 0 else entry.team
   insert_slot(side, {"kind":"human", "human":id, "character":entry.actor.character_id})
 else:
  var side: int = manager.game.athlete.court_team
  insert_slot(side if side in [0,1] else manager.game.game_bots.human_team, {"kind":"human", "human":0, "character":manager.game.athlete.character_id})
 for bot in manager.game.game_bots.bots.values():
  insert_slot(bot.court_team, {"kind":"bot", "human":0, "character":bot.character_id})

func insert_slot(side: int, value: Dictionary) -> bool:
 if side not in [0,1]:
  return false
 for index in range(6):
  if draft[side][index].kind == "empty":
   draft[side][index] = value.duplicate(true)
   return true
 return false

func occupied(side: int) -> int:
 return draft[side].filter(func(slot: Dictionary): return slot.kind != "empty").size()

func human_count(side: int) -> int:
 return draft[side].filter(func(slot: Dictionary): return slot.kind == "human").size()

func bot_count(side: int, hero: String) -> int:
 return draft[side].filter(func(slot: Dictionary): return slot.kind == "bot" and slot.character == hero).size()

func human_side(id: int) -> int:
 for side in range(2):
  for slot in draft[side]:
   if slot.kind == "human" and slot.human == id:
    return side
 return -1

func move_human(id: int, side: int) -> bool:
 var previous := human_side(id)
 if previous == side:
  return true
 var value := {"kind":"human", "human":id, "character":manager.selected}
 if previous >= 0:
  for slot in draft[previous]:
   if slot.kind == "human" and slot.human == id:
    value = slot.duplicate(true)
 if not insert_slot(side, value):
  return false
 if previous >= 0:
  for slot in draft[previous]:
   if slot.kind == "human" and slot.human == id:
    slot.kind = "empty"
 return true

func contains_room_players() -> bool:
 var humans: Array = manager.game.lan.players.keys() if manager.game.lan.active else [0]
 for id in humans:
  if human_side(id) < 0:
   return false
 return true

func change_bot(side: int, hero: String, delta: int) -> bool:
 if not manager.authority() or not VolleyCharacterDatabase.valid(hero):
  return false
 if delta == 1:
  return insert_slot(side, {"kind":"bot", "human":0, "character":hero})
 if delta == -1:
  for slot in draft[side]:
   if slot.kind == "bot" and slot.character == hero:
    slot.kind = "empty"
    return true
 return false

func side_name(side: int) -> String:
 return "A" if side == 0 else "B"

func clubs() -> Dictionary:
 var groups := {}
 for hero in VolleyCharacterDatabase.IDS:
  var club: String = VolleyCharacterDatabase.get_character(hero).team
  if not groups.has(club):
   groups[club] = []
  groups[club].append(hero)
 return groups

func card() -> VBoxContainer:
 var panel := PanelContainer.new()
 panel.add_theme_stylebox_override("panel", VolleySettingsTheme.box("102f3b", 16))
 manager.game.frontend.content.add_child(panel)
 var box := VBoxContainer.new()
 box.add_theme_constant_override("separation", 10)
 panel.add_child(box)
 return box

func card_label(parent: Node, text: String, size: int) -> Label:
 var label := Label.new()
 label.text = text
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 label.add_theme_font_size_override("font_size", size)
 parent.add_child(label)
 return label

func picker_page(back: Callable) -> VolleyFrontend:
 var f: VolleyFrontend = manager.game.frontend
 f._open_page("teams")
 f.get_tree().paused = return_to_court and not manager.game.lan.active
 f._button("← Назад", back)
 f._heading("БОТЫ · КОМАНДА " + side_name(selected_side))
 f._label("Занято %d / 6 · Свободно %d · Люди тоже занимают места" % [occupied(selected_side), 6-occupied(selected_side)], 16)
 return f

func draw_clubs() -> void:
 var f := picker_page(draw_teams)
 f._label("ВЫБЕРИТЕ КОМАНДУ АНИМЕ", 20)
 for name in clubs():
  var club: String = name
  var box := card()
  card_label(box, club, 26)
  var names: Array[String] = []
  for hero in clubs()[club]:
   names.append(VolleyCharacterDatabase.get_character(hero).name)
  card_label(box, " · ".join(names), 16)
  f._make_button(box, "Выбрать персонажей  →", func(): selected_club = club; draw_bot_characters(), true)
 f._button("Готово · к составам", draw_teams)
 f._layout()

func draw_bot_characters() -> void:
 var f := picker_page(draw_clubs)
 f._label(selected_club.to_upper(), 24)
 f._label("Добавляйте любые копии персонажей. Счётчик показывает только ботов.", 16)
 for id in clubs().get(selected_club, []):
  var hero: String = id
  var data := VolleyCharacterDatabase.get_character(hero)
  var box := card()
  card_label(box, "%s   #%d" % [data.name, int(data.number)], 24)
  card_label(box, "%s · %s" % [data.position, data.rarity], 16)
  var row := HBoxContainer.new()
  row.add_theme_constant_override("separation", 16)
  box.add_child(row)
  var count := bot_count(selected_side, hero)
  var minus := f._make_button(row, "−1", func(): change_bot(selected_side, hero, -1); draw_bot_characters())
  minus.disabled = count == 0
  var number := card_label(row, "× %d" % count, 28)
  number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
  number.custom_minimum_size.x = 64
  var plus := f._make_button(row, "+1", func(): change_bot(selected_side, hero, 1); draw_bot_characters(), true)
  plus.disabled = occupied(selected_side) >= 6
 f._button("Готово · к составам", draw_teams)
 f._layout()
