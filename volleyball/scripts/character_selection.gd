class_name VolleyCharacterSelection
extends Node

var manager: VolleyCharacters
var return_to_court := false
var draft: Array = []
var chosen_level := 1

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
 f._label("Пустые слоты допустимы. Выберите участников и героев независимо.", 16)
 var level := OptionButton.new()
 for title in ["Лёгкий · медленная реакция", "Средний · обычная игра", "Сложный · сильная тактика"]:
  level.add_item(title)
 level.select(chosen_level)
 level.item_selected.connect(func(index: int): chosen_level = index)
 level.custom_minimum_size.y = 48
 f.content.add_child(level)
 var humans := [0]
 if manager.game.lan.active:
  humans = manager.game.lan.players.keys()
 for team in range(2):
  f._label("КОМАНДА %s" % ("A" if team == 0 else "B"), 24)
  for index in range(6):
   var t := team
   var s := index
   var slot: Dictionary = draft[t][s]
   var row := HBoxContainer.new()
   f.content.add_child(row)
   var number := Label.new()
   number.text = "%d" % (s + 1)
   row.add_child(number)
   var kind := OptionButton.new()
   kind.add_item("Пусто")
   kind.add_item("Бот")
   for id in humans:
    kind.add_item("Я" if id == (manager.game.lan.multiplayer.get_unique_id() if manager.game.lan.active else 0) else str(manager.game.lan.players[id].get("nickname", "Игрок")))
   var current := 0 if slot.kind == "empty" else 1 if slot.kind == "bot" else 2 + maxi(0, humans.find(slot.human))
   kind.select(current)
   kind.custom_minimum_size = Vector2(125, 48)
   kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
   kind.item_selected.connect(func(value: int):
    draft[t][s].kind = "empty" if value == 0 else "bot" if value == 1 else "human"
    if value >= 2:
     draft[t][s].human = humans[value - 2])
   row.add_child(kind)
   var hero := OptionButton.new()
   for id in VolleyCharacterDatabase.IDS:
    hero.add_item(VolleyCharacterDatabase.get_character(id).name)
   hero.select(VolleyCharacterDatabase.IDS.find(slot.character))
   hero.custom_minimum_size = Vector2(160, 48)
   hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
   hero.item_selected.connect(func(value: int): draft[t][s].character = VolleyCharacterDatabase.IDS[value])
   row.add_child(hero)
 var result := f._label("", 16)
 var apply := func():
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
