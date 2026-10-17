extends SceneTree
var game: Node3D
var gate: Node
var host := false
var elapsed := 0.0
var phase := 0
var phase_time := 0.0
var bot_seen := false
var match_seen := false

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 var args := OS.get_cmdline_user_args()
 host = args[0] == "host"
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 gate = load("res://tests/test_room_gate.gd").new()
 gate.name = "RoomGate"
 game.add_child(gate)
 game.frontend.start_solo()
 game.hud.set_process(false)
 if host:
  if game.lan.host_room(int(args[1])) != OK:
   quit(1)
  print("ROOM_HOST_READY")
 else:
  game.lan.join_room(args[2], int(args[1]))
 game.frontend.enter_court()

func fail(note: String) -> void:
 push_error(note)
 quit(1)

func _process(dt: float) -> bool:
 if not is_instance_valid(game):
  return false
 elapsed += dt
 phase_time += dt
 if elapsed > 28:
  fail("Room scenario timed out in phase %d" % phase)
 if host:
  if phase == 0 and game.lan.players.size() == 3:
   if game.lan.match_active or game.lan.round_live:
    fail("Room is not initially free play")
   game.practice.configure({"enabled": true, "modes": [4], "interval": 1.5, "anchor": Vector3(-2, 0.02, -6)})
   phase = 1
   phase_time = 0
  elif phase == 1 and gate.observed.size() == 2:
   if game.practice.bot.contacts < 1:
    return false
   var ids: Array = game.lan.players.keys()
   for i in range(ids.size()):
    var actor: ContextAthlete = game.lan.players[ids[i]].actor
    actor.set_physics_process(false)
    actor.position = Vector3(6.1 + i * 0.5, 0.02, 3) if i < 2 else Vector3(0, 0.02, -3)
    actor.velocity = Vector3.ZERO
   game.lan.ready_seconds = 10
   if game.lan.begin_match():
    fail("Host started without all players in the zones")
   phase = 2
   phase_time = 0
  elif phase == 2 and phase_time > 1.0:
   if game.lan.match_active or game.lan.ready_seconds > 0:
    fail("Readiness ignored the missing human")
   game.lan.players[game.lan.players.keys()[2]].actor.position = Vector3(6.5, 0.02, -3)
   phase = 3
   phase_time = 0
  elif phase == 3 and game.lan.match_active and gate.matched.size() == 2:
   var ids: Array = game.lan.players.keys()
   if game.lan.players[ids[0]].team != 0 or game.lan.players[ids[1]].team != 0 or game.lan.players[ids[2]].team != 1:
    fail("Chosen teams were not applied authoritatively")
   print("ROOM_HOST_PASSED bot_contacts=%d all_humans_ready=true teams=2:1" % game.practice.bot.contacts)
   gate.finish.rpc()
   phase = 4
   phase_time = 0
  elif phase == 4 and phase_time > 1:
   quit(0)
 elif game.lan.connected:
  if not bot_seen and game.practice.enabled and is_instance_valid(game.practice.bot) and game.practice.bot.replica and game.practice.bot.air_attack and game.practice.bot.position.y > 0.4:
   bot_seen = true
   if game.practice.configure({"enabled": false}):
    fail("A guest could override the host's bot")
   print("ROOM_BOT_REPLICA_OBSERVED")
   gate.saw_bot.rpc_id(1)
  if game.lan.match_active and not match_seen:
   match_seen = true
   if game.athlete.court_team < 0 or game.lan.selection_zone.visible:
    fail("Guest did not receive the match transition")
   gate.saw_match.rpc_id(1)
  if gate.finished:
   print("ROOM_CLIENT_PASSED bot=%s match=%s snapshots=%d" % [bot_seen, match_seen, game.lan.snapshot_count])
   quit(0 if bot_seen and match_seen else 1)
 return false
