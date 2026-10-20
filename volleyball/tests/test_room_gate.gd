extends Node
var observed: Dictionary = {}
var matched: Dictionary = {}
var finished := false
var block_stage := 0
var scored: Dictionary = {}

@rpc("any_peer", "call_remote", "reliable")
func saw_score() -> void:
 if multiplayer.is_server():
  scored[multiplayer.get_remote_sender_id()] = true

@rpc("authority", "call_remote", "reliable")
func hold_blocks() -> void:
 block_stage = 1

@rpc("authority", "call_remote", "reliable")
func release_blocks() -> void:
 block_stage = 2

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
