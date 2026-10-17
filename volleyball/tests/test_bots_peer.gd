extends SceneTree
var game: Node3D
var gate: Node
var host := false
var elapsed := 0.0
var phase := 0
var phase_time := 0.0
var reported: Dictionary = {}
var first_position := Vector3.ZERO
var snapshot_seen := false
var pickup_id := 0
var pickup_sent := false

func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var args := OS.get_cmdline_user_args()
 host = args[0] == "host"
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 gate = load("res://tests/test_bots_gate.gd").new()
 gate.name = "BotsGate"
 game.add_child(gate)
 game.frontend.start_solo()
 game.hud.set_process(false)
 if host:
  if game.lan.host_room(int(args[1])) != OK:
   quit(1)
  print("BOTS_HOST_READY")
 else:
  game.lan.join_room(args[2], int(args[1]))
 game.frontend.enter_court()
func fail(note: String) -> void:
 push_error(note)
 quit(1)
func acknowledged(value: int) -> bool:
 return gate.phases.get(value, {}).size() == 2
func _process(dt: float) -> bool:
 if not is_instance_valid(game):
  return false
 elapsed += dt
 phase_time += dt
 if elapsed > 38:
  fail("Bot room scenario timed out in phase %d" % phase)
 if host:
  if phase == 0 and game.lan.players.size() == 3:
   for entry in game.lan.players.values():
    entry.actor.set_physics_process(false)
    entry.actor.position = Vector3(-7.2, 0.02, 10)
   game.game_bots.configure({"counts": [6, 6], "level": 77})
   game.practice.configure({"enabled": true, "modes": [2], "anchor": Vector3(-3, 0.02, -7), "interval": 12})
   game.ball.feed(Vector3(1, 3, 5), Vector3(0, -1, -1))
   phase = 1
   phase_time = 0
  elif phase == 1 and acknowledged(1):
   game.game_bots.configure({"counts": [2, 3], "difficulty": 4})
   phase = 2
   phase_time = 0
  elif phase == 2 and acknowledged(2):
   var ids: Array = game.lan.players.keys()
   for i in range(ids.size()):
    game.lan.players[ids[i]].actor.position = Vector3(6.1 + i * 0.5, 0.02, 3) if i < 2 else Vector3(0, 0.02, -3)
    game.lan.players[ids[i]].actor.velocity = Vector3.ZERO
   game.lan.ready_seconds = 10
   if game.lan.begin_match():
    fail("Bots bypassed human readiness")
   phase = 3
   phase_time = 0
  elif phase == 3 and phase_time > 0.6:
   game.lan.players[game.lan.players.keys()[2]].actor.position = Vector3(6.5, 0.02, -3)
   phase = 4
   phase_time = 0
  elif phase == 4 and game.lan.match_active and acknowledged(3):
   var server: VolleyGameBot = game.game_bots.bots[-100]
   if server.serves == 0 or server.contact_count == 0:
    return false
   if game.lan.readiness().totals != [4, 4]:
    # Readiness uses physical zones after teleport, so count the match roster.
    var count := [2, 3]
    for entry in game.lan.players.values():
     count[entry.team] += 1
    if count != [4, 4]:
     fail("Incorrect mixed teams")
   print("BOTS_HOST_PASSED max_bots=12 training_coexists=true teams=4:4 physical_serve=true")
   game.lan.start_free_play()
   game.practice.configure({"enabled": false})
   game.game_bots.set_physics_process(false)
   for bot in game.game_bots.bots.values():
    bot.set_physics_process(false)
    bot.position = Vector3(7, 0.02, -10)
   for id in game.lan.players:
    game.lan.players[id].actor.position = Vector3(7, 0.02, 10)
    if id != 1:
     pickup_id = id
   var recipient: ContextAthlete = game.lan.players[pickup_id].actor
   recipient.position = Vector3(0, 0.02, 6)
   game.ball.athlete = game.game_bots.bots[-100]
   # Pin the loose ball while the teleported player pose reaches the guest.
   # Ownership, permission checks and pickup itself still use the actual RPC.
   game.ball.held = false
   game.ball.pending_feed = false
   game.ball.freeze = true
   game.ball.position = Vector3(0.9, 0.4, 6)
   game.ball.linear_velocity = Vector3.ZERO
   game.ball.angular_velocity = Vector3.ZERO
   gate.request_pickup.rpc_id(pickup_id)
   phase = 5
   phase_time = 0
  elif phase == 5 and game.ball.held:
   var recipient: ContextAthlete = game.lan.players[pickup_id].actor
   if game.ball.athlete != recipient or not recipient.holding_ball:
    fail("Remote pickup after a bot has the wrong owner")
   game.ball.drop()
   game.game_bots.reset_rally()
   var setter: VolleyGameBot = game.game_bots.bots[-100]
   setter.position = Vector3(0, 0.02, 4)
   recipient.position = Vector3(-2, 0.02, 2.6)
   recipient.velocity = Vector3(-1, 0, -0.5)
   var plan: Dictionary = game.game_bots.tactics.pass_plan(setter, 0)
   if plan.is_empty() or plan.recipient != recipient or Vector3(plan.target).z <= 0:
    fail("Bots did not plan an own-side set for a remote human")
   print("BOTS_REMOTE_HUMAN_PASSED pickup_after_bot=true moving_attacker=true difficulty=4 skills=140")
   gate.finish.rpc()
   phase = 6
   phase_time = 0
  elif phase == 6 and phase_time > 1:
   quit(0)
 elif game.lan.connected:
  var manager: VolleyGameBots = game.game_bots
  if manager.bots.size() == 12 and not reported.has(1):
   if manager.configure({"counts": [0, 0]}):
    fail("Guest can change shared bot composition")
   var moving := false
   for bot in manager.bots.values():
    if not bot.replica or bot.is_physics_processing() or bot.stats.values["set"] != 77:
     fail("Bot replica authority/skills differ")
    moving = moving or (bot.network_age >= 0 and bot.velocity.length() > 0.2)
   if moving and game.practice.enabled and is_instance_valid(game.practice.bot):
    reported[1] = true
    gate.observed.rpc_id(1, 1)
    print("BOTS_MAX_ROSTER_OBSERVED")
  if manager.bots.size() == 5 and reported.has(1) and not reported.has(2):
   if manager.counts != [2, 3] or manager.bots.has(-102) or manager.bots.has(-109):
    fail("Deleted bots stayed in the remote roster")
   if manager.difficulty != 4:
    return false
   for bot in manager.bots.values():
    for key in VolleyStyleStats.KEYS:
     if bot.stats.values[key] != 140:
      fail("Named difficulty did not replicate all eight bot skills")
   reported[2] = true
   gate.observed.rpc_id(1, 2)
  if game.lan.match_active and not reported.has(3):
   var teams := [0, 0]
   for bot in manager.bots.values():
    teams[bot.court_team] += 1
   for entry in game.lan.players.values():
    teams[entry.team] += 1
   if teams != [4, 4]:
    return false
   reported[3] = true
   gate.observed.rpc_id(1, 3)
  if gate.pickup_requested and not pickup_sent and game.athlete.position.distance_to(Vector3(0, 0.02, 6)) < 0.5 and game.ball.can_pick_up_for(game.athlete):
   game.lan.local_action("pickup")
   pickup_sent = true
   print("BOTS_REMOTE_PICKUP_SENT")
  if gate.finished:
   print("BOTS_CLIENT_PASSED bots=12 replicas=host_only removal=shared teams=4:4")
   quit(0)
 return false
