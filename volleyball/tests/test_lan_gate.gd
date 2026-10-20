extends Node
# Test-only barrier: keep the held pose until every real client has observed it.
# This makes privacy verification independent of CI process scheduling.
var observed: Dictionary = {}
var proceed_sent := false
var may_serve := false
var results: Dictionary = {}
var may_finish := false

@rpc("any_peer", "call_remote", "reliable")
func observed_result() -> void:
 if multiplayer.is_server():
  results[multiplayer.get_remote_sender_id()] = true
  if results.size() == 11:
   finish.rpc()

@rpc("authority", "call_remote", "reliable")
func finish() -> void:
 may_finish = true

@rpc("any_peer", "call_remote", "reliable")
func observed_held() -> void:
 if multiplayer.is_server():
  observed[multiplayer.get_remote_sender_id()] = true

@rpc("authority", "call_remote", "reliable")
func proceed() -> void:
 may_serve = true
