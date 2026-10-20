class_name VolleyCharacterDatabase
extends RefCounted

static var IDS: Array = _load_ids()
static var catalog: Dictionary = {}

static func _load_ids() -> Array:
 var index: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://characters/catalog.json"))
 assert(index is Dictionary and index.get("characters") is Array)
 var ids: Array = []
 for id in index.characters:
  assert(id is String and id.is_valid_identifier() and id not in ids and FileAccess.file_exists("res://characters/%s.json" % id))
  ids.append(id)
 return ids

static func get_character(id: String) -> Dictionary:
 if not id in IDS:
  id = "kageyama"
 if not catalog.has(id):
  var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://characters/%s.json" % id))
  assert(data is Dictionary and data.id == id)
  catalog[id] = data
 return catalog[id].duplicate(true)

static func valid(id: String) -> bool:
 return id in IDS
