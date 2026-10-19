class_name VolleySuperServe
extends Node3D
# Compatibility bridge for old rally hooks. The ability is archived, not active.
var game: Node3D
var active := false
var finished_sequence := -1
var charges := {}
func begin(_actor: ContextAthlete, _id: int) -> bool:
 return false
func request() -> bool:
 return false
func note_contact(_actor: ContextAthlete, _id: int, _kind: int) -> void:
 pass
func record_floor(_at: Vector3) -> void:
 pass
func clear_credit() -> void:
 pass
func finish(_release := true) -> void:
 pass
func percent(_id: int) -> int:
 return 0
func local_id() -> int:
 return 0
