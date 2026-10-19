class_name VolleySettings
extends RefCounted
const PATH := "user://context_controls.cfg"
const DEFAULT_KEYS := {"bump": KEY_X, "lower_serve": KEY_V, "float_serve": KEY_B, "forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "primary": -MOUSE_BUTTON_LEFT, "secondary": KEY_Q, "jump": KEY_SPACE, "dive": KEY_CTRL, "jump_set": KEY_E, "pause": KEY_ESCAPE, "next": KEY_R, "pickup": KEY_F, "lock": KEY_SHIFT}
const KEY_LABELS := {"bump": "Нижний приём", "lower_serve": "Нижняя подача", "float_serve": "Подача планер", "forward": "Вперёд", "back": "Назад", "left": "Влево", "right": "Вправо", "primary": "Атака", "secondary": "Пас / блок", "jump": "Прыжок", "dive": "Подкат", "jump_set": "Пас в прыжке", "pause": "Меню", "next": "Следующий мяч", "pickup": "Подобрать / опустить", "lock": "Фиксация корпуса"}
var keys := DEFAULT_KEYS.duplicate()
var layout := {}
var sensitivity := 1.0
var button_scale := 1.0
var show_jump_set := true
var shift_lock := true
var orientation := 4
var nickname := "Игрок"

func _init() -> void:
 keys["super"] = KEY_G

static func clean_nickname(value: String) -> String:
 var result := ""
 for letter in value.strip_edges():
  var code := letter.unicode_at(0)
  if code >= 32 and code != 127 and code not in [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]:
   result += letter
 return result.left(24).strip_edges() if not result.strip_edges().is_empty() else "Игрок"

func load_settings(athlete: VolleyAthlete) -> void:
 var file := ConfigFile.new()
 if file.load(PATH) != OK:
  if not athlete.stats is VolleyStyleStats and file.load("user://controls.cfg") == OK:
   for key in athlete.stats.values:
    athlete.stats.set_stat(key, float(file.get_value("style_stats" if athlete.stats is VolleyStyleStats else "stats", key, athlete.stats.values[key])))
  install_keys()
  return
 sensitivity = clampf(float(file.get_value("camera", "sensitivity", 1)), 0.3, 2.5)
 nickname = clean_nickname(str(file.get_value("player", "nickname", "Игрок")))
 shift_lock = bool(file.get_value("camera", "lock", true))
 button_scale = clampf(float(file.get_value("hud", "scale", 1)), 0.7, 1.4)
 show_jump_set = bool(file.get_value("hud", "jump_set", true))
 orientation = int(file.get_value("hud", "orientation", 4))
 if orientation not in [0, 2, 4]:
  orientation = 4
 for key in keys:
  keys[key] = int(file.get_value("keys", key, keys[key]))
 if file.has_section("layout"):
  for key in file.get_section_keys("layout"):
   var entry: Variant = file.get_value("layout", key)
   if entry is Vector3:
    layout[key] = Vector3(clampf(entry.x, 0.04, 0.96), clampf(entry.y, 0.10, 0.94), clampf(entry.z, 0.65, 1.45))
 for key in athlete.stats.values:
  athlete.stats.set_stat(key, float(file.get_value("style_stats" if athlete.stats is VolleyStyleStats else "stats", key, athlete.stats.values[key])))
 athlete.reset_seed(int(file.get_value("training", "seed", 20261014)))
 install_keys()

func install_keys() -> void:
 for key in keys:
  var action: String = "volley_" + key
  if not InputMap.has_action(action):
   InputMap.add_action(action)
  InputMap.action_erase_events(action)
  var event: InputEvent
  if keys[key] < 0:
   event = InputEventMouseButton.new()
   event.button_index = -keys[key]
  else:
   event = InputEventKey.new()
   event.physical_keycode = keys[key]
  InputMap.action_add_event(action, event)

func rebind(action: String, keycode: int) -> bool:
 if keycode == 0 or not keys.has(action):
  return false
 for other in keys:
  if other != action and keys[other] == keycode:
   return false
 keys[action] = keycode
 install_keys()
 return true

func save(athlete: VolleyAthlete) -> Error:
 var file := ConfigFile.new()
 file.set_value("player", "nickname", clean_nickname(nickname))
 file.set_value("camera", "sensitivity", sensitivity)
 file.set_value("camera", "lock", shift_lock)
 file.set_value("hud", "scale", button_scale)
 file.set_value("hud", "jump_set", show_jump_set)
 file.set_value("hud", "orientation", orientation)
 file.set_value("training", "seed", athlete.random_seed)
 for key in keys:
  file.set_value("keys", key, keys[key])
 for key in layout:
  file.set_value("layout", key, layout[key])
 for key in athlete.stats.values:
  file.set_value("style_stats" if athlete.stats is VolleyStyleStats else "stats", key, athlete.stats.values[key])
 return file.save(PATH)
