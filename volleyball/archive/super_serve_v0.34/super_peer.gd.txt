extends SceneTree
var game: Node3D
var host := false
var elapsed := 0.0
var started := false
var requested := false
var finished := -1.0
var original := Vector3.ZERO
var result := ""
var charged := false
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var args := OS.get_cmdline_user_args()
 host = args[0] == "host"
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 if host:
  game.lan.host_room(int(args[1]))
  print("SUPER_HOST_READY")
 else:
  game.lan.join_room("127.0.0.1", int(args[1]))
 game.frontend.enter_court()
func _process(dt: float) -> bool:
 if not is_instance_valid(game):
  return false
 elapsed += dt
 if elapsed > 16:
  push_error("Super room timed out")
  quit(1)
 if host and game.lan.players.size() == 2 and elapsed > 0.6 and not charged:
  charged = true
  for id in game.lan.players:
   if id != 1:
    var player: ContextAthlete = game.lan.players[id].actor
    player.position.z = 10.5 if player.position.z >= 0 else -10.5
    for i in range(7):
     game.super_serve.note_contact(player, id, 2)
     game.super_serve.record_floor(Vector3(0, 0.155, -5 if player.position.z >= 0 else 5))
  if game.super_serve.percent(1) != 0:
   push_error("Guest scores incorrectly charged the host")
   quit(1)
 if not host and game.lan.connected and game.super_serve.ready_for(game.super_serve.local_id()) and elapsed > 1 and not requested:
  requested = true
  game.lan.local_action("super")
 if game.super_serve.active and not started:
  started = true
  original = game.athlete.position
  result = str(game.super_serve.target) + ":" + str(game.super_serve.inside)
  if not game.super_serve.camera.current or game.hud.visible:
   push_error("Viewer did not enter the shared cinematic")
   quit(1)
 if started and not game.super_serve.active and finished < 0:
  finished = elapsed
  if not game.camera.current or not game.hud.visible or (host and game.athlete.position.distance_to(original) > 0.05):
   push_error("Cinematic changed a spectator position or did not restore camera")
   quit(1)
 if finished >= 0 and elapsed - finished > (0.8 if host else 0.2):
  print("SUPER_PEER_PASSED role=", "host" if host else "guest", " result=", result)
  game.lan.leave()
  quit(0)
 return false
