extends Node
var observed: Dictionary = {}
var matched: Dictionary = {}
var finished := false

@rpc("any_peer", "call_remote", "reliable")
func saw_bot() -> void:
 if multiplayer.is_server():
  observed[multiplayer.get_remote_sender_id()] = true

@rpc("any_peer", "call_remote", "reliable")
func saw_match() -> void:
 if multiplayer.is_server():
  matched[multiplayer.get_remote_sender_id()] = true

@rpc("authority", "call_remote", "reliable")
func finish() -> void:
 finished = true
