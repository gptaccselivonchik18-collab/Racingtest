extends Node
var phases: Dictionary = {}
var finished := false
@rpc("any_peer", "call_remote", "reliable")
func observed(phase: int) -> void:
 if multiplayer.is_server():
  if not phases.has(phase):
   phases[phase] = {}
  phases[phase][multiplayer.get_remote_sender_id()] = true
@rpc("authority", "call_remote", "reliable")
func finish() -> void:
 finished = true
