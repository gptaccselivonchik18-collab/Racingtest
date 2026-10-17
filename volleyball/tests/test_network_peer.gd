extends SceneTree
var game: Node3D
var role := "host"
var port := 24930
var endpoint := "127.0.0.1"
var elapsed := 0.0
var phase := 0
var joined_at := -1.0
var old_id := 0
var start_snapshots := 0
var rejoin_at := 0.0
var admitted: Array[int] = []
var moved := false
var stopped := false
var released := false
var initial_name_seen := false
var renamed_name_seen := false
var rename_sent := false

func _initialize() -> void:
 var args := OS.get_cmdline_user_args()
 role = args[0]
 port = int(args[1])
 endpoint = args[2]
 call_deferred("run")

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 if role == "host":
  game.hud.settings.nickname = "Host.🏐"
  if game.lan.host_room(port) != OK:
   quit(1)
  print("NETWORK_HOST_READY")
 else:
  if role == "old":
   game.lan.multiplayer.connected_to_server.disconnect(game.lan._connected)
   game.lan.multiplayer.connected_to_server.connect(func(): game.lan.hello.rpc_id(1, VolleyLAN.PROTOCOL - 1, {}))
  game.athlete.stats.set_stat("set", 315)
  game.hud.settings.nickname = "Гость.🏐"
  game.lan.join_room(endpoint, port)

func _process(dt: float) -> bool:
 if not is_instance_valid(game):
  return false
 elapsed += dt
 if role == "old":
  if game.lan.rejected_reason.contains("Разные версии"):
   print("NETWORK_OLD_VERSION_REJECTED")
   quit(0)
 elif role == "host":
  for id in game.lan.players:
   if id == 1:
    continue
   if id not in admitted:
    admitted.append(id)
   var a: ContextAthlete = game.lan.players[id].actor
   initial_name_seen = initial_name_seen or game.lan.players[id].nickname == "Гость.🏐"
   renamed_name_seen = renamed_name_seen or game.lan.players[id].nickname == "Guest.Renamed"
   if a.stats.values.set != 315:
    push_error("Client style state lost during reconnect")
    quit(1)
   moved = moved or a.velocity.x > 0.4
   if moved and a.move_axis == Vector2.ZERO:
    stopped = true
   released = released or (a.strike_technique == 1 and a.action == VolleyAthlete.Action.STRIKE)
  if admitted.size() == 2 and game.lan.players.size() == 1:
   print("NETWORK_HOST_RESULT rejoined=true moved=%s stopped=%s released=%s" % [moved, stopped, released])
   print("NETWORK_NICKNAMES initial=", initial_name_seen, " renamed=", renamed_name_seen)
   quit(0 if moved and stopped and released and initial_name_seen and renamed_name_seen else 1)
 else:
  if phase == 1:
   if elapsed >= rejoin_at:
    game.lan.join_room(endpoint, port)
    phase = 2
   return false
  if game.lan.connected and joined_at < 0:
   joined_at = elapsed
   start_snapshots = game.lan.snapshot_count
   if phase == 0:
    old_id = game.lan.multiplayer.get_unique_id()
   elif old_id == game.lan.multiplayer.get_unique_id():
    push_error("Reconnect did not create a new session")
    quit(1)
  if joined_at >= 0:
   var age := elapsed - joined_at
   game.athlete.move_axis = Vector2(0.8, 0) if phase == 0 and age < 1.5 else Vector2.ZERO
   if phase == 0 and age > 0.7 and not moved:
    moved = true
    game.lan.local_action("bump", "press")
   if phase == 0 and age > 1.2 and not released:
    released = true
    game.lan.local_action("bump", "release")
   if phase == 0 and age > 1.7 and not rename_sent:
    rename_sent = true
    game.hud.settings.nickname = "Guest.Renamed"
    game.lan.rename_local(game.hud.settings.nickname)
   if age > 3.0:
    if not game.athlete.network_motion.active or not game.lan.ball_motion.active:
     push_error("Timestamped player/ball motion did not survive the real loss/jitter connection")
     quit(1)
     return false
    if game.athlete.get_node("TeamTag").visible or not game.lan.players[1].actor.get_node("TeamTag").visible or not game.lan.players[1].actor.get_node("TeamTag").text.contains("Host.🏐"):
     push_error("Personal name visibility did not replicate through the room")
     quit(1)
     return false
    if game.lan.snapshot_count - start_snapshots < 20 or game.lan.players.size() != 2 or not game.ball.replica or game.athlete.stats.values.set != 315:
     push_error("Replication failed through impaired network: phase=%s snapshots=%s players=%s ball_replica=%s Set=%s" % [phase, game.lan.snapshot_count - start_snapshots, game.lan.players.size(), game.ball.replica, game.athlete.stats.values.set])
     quit(1)
     return false
    game.lan.leave()
    if phase == 0:
     phase = 1
     joined_at = -1
     rejoin_at = elapsed + 0.5
    else:
     print("NETWORK_CLIENT_RESULT reconnect=true snapshots=true styles=true")
     quit(0)
 if elapsed > (45.0 if role == "host" else 24.0):
  push_error("Network scenario timeout " + role)
  quit(1)
 return false
