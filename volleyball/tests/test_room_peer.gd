extends SceneTree
var game: Node3D
var gate: Node
var host := false
var elapsed := 0.0
var phase := 0
var phase_time := 0.0
var bot_seen := false
var match_seen := false
var block_stage := 0
var score_seen := false

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
   for id in game.lan.players:
    if id != 1:
     var actor: ContextAthlete = game.lan.players[id].actor
     actor.set_physics_process(false)
     actor.cancel_input()
     actor.action = VolleyAthlete.Action.IDLE
     actor.position = Vector3(3, 2, 5)
     actor.velocity = Vector3.ZERO
   gate.hold_blocks.rpc()
   phase = 10
   phase_time = 0
  elif phase == 10 and phase_time > 1.0:
   for id in game.lan.players:
    if id != 1 and (not game.lan.players[id].actor.block_held or game.lan.owners[id] != "secondary"):
     fail("Reliable remote block press did not remain held")
   gate.release_blocks.rpc()
   phase = 11
   phase_time = 0
  elif phase == 11 and phase_time > 0.7:
   for id in game.lan.players:
    if id != 1 and (game.lan.players[id].actor.block_held or not game.lan.owners[id].is_empty()):
     fail("Reliable remote block release left a stuck block")
   print("ROOM_REMOTE_BLOCK_HOLD_RELEASE_PASSED")
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
   game.lan.sets = [2, 2]
   game.lan.scores = [14, 15]
   game.lan.award(1)
   phase = 12
   phase_time = 0
  elif phase == 12 and gate.scored.size() == 2:
   print("ROOM_HOST_PASSED bot_contacts=%d all_humans_ready=true teams=2:1 victory_replicated=true" % game.practice.bot.contacts)
   gate.finish.rpc()
   phase = 4
   phase_time = 0
  elif phase == 4 and phase_time > 1:
   quit(0)
 elif game.lan.connected:
  if gate.block_stage > block_stage:
   block_stage = gate.block_stage
   game.lan.local_action("secondary", "press" if block_stage == 1 else "release")
  if not score_seen and game.lan.match_winner == 1 and game.lan.scores == [14, 16]:
   if game.lan.sets != [2, 3]:
    fail("Guest received the wrong set victory state")
   score_seen = true
   gate.saw_score.rpc_id(1)
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
   var ids: Array = game.lan.players.keys()
   if game.lan.players[ids[0]].team != 0 or game.lan.players[ids[1]].team != 0 or game.lan.players[ids[2]].team != 1:
    fail("Guest kept the preselection roster instead of the chosen teams")
   for entry in game.lan.players.values():
    if entry.actor.court_team != entry.team:
     fail("Guest body/team assignment disagrees with the roster")
   gate.saw_match.rpc_id(1)
  if gate.finished:
   print("ROOM_CLIENT_PASSED bot=%s match=%s snapshots=%d" % [bot_seen, match_seen, game.lan.snapshot_count])
   quit(0 if bot_seen and match_seen and score_seen else 1)
 return false
