class_name VolleyCharacterStats
extends VolleyStyleStats

var character_id := "kageyama"
var difficulty_multiplier := 1.0

func install(id: String) -> void:
 character_id = id
 values = VolleyCharacterDatabase.get_character(id).stats.duplicate()
 for key in KEYS:
  values[key]=float(values[key])*difficulty_multiplier
 cache.clear()

func set_difficulty_multiplier(value: float) -> void:
 if is_equal_approx(difficulty_multiplier,value):return
 difficulty_multiplier=value
 install(character_id)

func set_stat(_key: String, _value: float) -> void:
 # Character sheets are authoritative data, never user/client supplied ratings.
 pass

func reset_all() -> void:
 install(character_id)

func profile(kind: int) -> Dictionary:
 var result := super.profile(kind).duplicate()
 if character_id == "kageyama" and kind in [0, 8]:
  result.accuracy *= 0.30
  result.stability *= 0.40
  result.windup /= 1.20
  result.start /= 1.20
  result.edge = lerpf(1.0, float(result.edge), 0.60)
  result.control = lerpf(float(result.control), 1.0, 0.40)
 return result
