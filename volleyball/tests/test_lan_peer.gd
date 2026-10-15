extends SceneTree
var game: Node3D
var role := "host"
var index := 0
var elapsed := 0.0
var joined_at := -1.0
var full_at := -1.0
var fed := false
var moved := false
var jumped := false
var held_seen := false
var served := false
var lower_requested_at := -1.0
var float_requested := false
var float_seen := false
var float_contact := false
var second_fed := false
var saw_full := false
var disconnected := false
var drive := false
var sent_jump := false
var pickup_tick := 0.0
var client_passed := false
var reported := false
var stats_seen := false
var view_seen := false
var hold_seen := false
var bump_started := false
var bump_released := false
var private_local_seen := false
var private_remote_seen := false
var private_hold_time := 0.0
var float_requested_at := -1.0
var port := 24702

func _initialize() -> void:
 var args := OS.get_cmdline_user_args()
 if args.size() > 0:
  role = args[0]
 if args.size() > 1:
  index = int(args[1])
 if args.size() > 2:
  port = int(args[2])
 call_deferred("run")

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 if role == "host":
  if game.lan.host_room(port) != OK:
   quit(1)
  print("LAN_HOST_READY")
 else:
  game.athlete.stats.set_stat("set", 135 + index)
  if index == 1:
   game.frontend.show_home()
   var targets: Array[String] = ["127.0.0.1"]
   game.lan.discovery.search(targets, port + 1)
  else:
   game.lan.join_room("127.0.0.1", port)
 if role == "host" or index != 1:
  game.frontend.enter_court()
 game.hud.set_process(false)

func _process(dt: float) -> bool:
 if not is_instance_valid(game):
  return false
 elapsed += dt
 var toss: VolleyTossPreview = game.get_node("TossPreview")
 toss._physics_process(0)
 if game.holding_ball() and game.athlete.holding_ball:
  private_local_seen = toss.is_visible_in_tree()
 for entry in game.lan.players.values():
  if entry.actor != game.athlete and entry.actor.holding_ball:
   if toss.is_visible_in_tree():
    push_error("Foreign player trajectory leaked onto this device")
    quit(1)
   private_remote_seen = true
 if role == "host":
  if game.lan.players.size() == 12:
   saw_full = true
   if full_at < 0:
    full_at = elapsed
    print("LAN_FULL_12")
   var counts := [0, 0]
   for entry in game.lan.players.values():
    counts[entry.team] += 1
   if counts != [6, 6]:
    push_error("Bad team balance")
    quit(1)
  for id in game.lan.players:
   if id == 1:
    continue
   var a: ContextAthlete = game.lan.players[id].actor
   if a.stats.values.set == 136 and a.stats.values.spike == 250:
    stats_seen = true
   if absf(a.camera_pitch - 0.6) < 0.01:
    view_seen = true
   if a.strike_technique == 1 and a.action == VolleyAthlete.Action.STRIKE and not a.lower_serve_active and a.strike_power > 0.35 and a.strike_power < 0.85:
    hold_seen = true
   if a.move_axis.x > 0.9 and a.velocity.x > 0.5:
    moved = true
   if a.velocity.y > 1.0:
    jumped = true
   if a.float_serve_active:
    float_seen = true
   if game.ball.float_active:
    float_contact = true
   if game.ball.held and game.ball.athlete == a:
    held_seen = true
  if saw_full and not fed and elapsed - full_at > 1.8:
   fed = true
   # First admitted client is the driver (orchestrator waits for its admission).
   var id: int = game.lan.players.keys()[1]
   var actor: ContextAthlete = game.lan.players[id].actor
   game.ball.athlete = actor
   game.ball.feed(actor.position + Vector3(0, 0.3, 0.5), Vector3.ZERO)
   print("LAN_BALL_OFFERED")
  if held_seen and game.lan.round_live:
   served = true
  if served and not second_fed and not game.automatic_serve_busy() and elapsed - full_at > 3.0:
   second_fed = true
   var actor: ContextAthlete = game.lan.players[game.lan.players.keys()[1]].actor
   game.lan.round_wait = -1
   game.lan.round_live = false
   game.rules.reset()
   game.ball.athlete = actor
   game.ball.feed(actor.position + Vector3(0, 0.3, 0.5), Vector3.ZERO)
   print("LAN_FLOAT_BALL_OFFERED")
  if saw_full and game.lan.players.size() == 11:
   disconnected = true
  if elapsed > 18:
   var ok := saw_full and moved and jumped and held_seen and served and disconnected and stats_seen and view_seen and hold_seen and float_seen and float_contact and private_remote_seen
   print("LAN_PRIVATE_HELPERS host_remote_hidden=%s" % private_remote_seen)
   print("LAN_FLOAT_HOST_RESULT pose=%s contact=%s" % [float_seen, float_contact])
   print("LAN_HOST_RESULT full=%s moved=%s jumped=%s pickup=%s serve=%s disconnect=%s stats=%s view=%s hold=%s" % [saw_full, moved, jumped, held_seen, served, disconnected, stats_seen, view_seen, hold_seen])
   quit(0 if ok else 1)
 else:
  if index == 1 and not drive and game.lan.discovery.rooms.has("127.0.0.1"):
   drive = true
   var room: Dictionary = game.lan.discovery.rooms["127.0.0.1"]
   game.frontend.join_to(room.ip, room.port)
   print("LAN_DISCOVERY_JOIN")
  if game.lan.connected and joined_at < 0:
   joined_at = elapsed
   print("LAN_CLIENT_JOINED ", index)
   if index == 1:
    game.lan.local_action("stats", "press", {"skill": "spike", "value": 250.0})
  if joined_at >= 0:
   var age := elapsed - joined_at
   for entry in game.lan.players.values():
    if entry.actor.stats.values.set == 136 and entry.actor.stats.values.spike == 250:
     stats_seen = true
     var actor: ContextAthlete = entry.actor
     if actor.float_serve_active:
      float_seen = true
     if absf(actor.camera_pitch - 0.6) < 0.01 and (-actor.visual.get_child(2).global_basis.z).dot(-actor.view_basis().z) > 0.99:
      view_seen = true
   if game.lan.players.size() == 12:
    saw_full = true
   if index == 1:
    # Let every observer receive a held pose before starting the serve.
    private_hold_time = private_hold_time + dt if game.holding_ball() else 0.0
    game.rig.pitch = 0.6
    if age > 1.2 and not bump_started:
     bump_started = true
     game.lan.local_action("bump")
    if age > 1.8 and not bump_released:
     bump_released = true
     game.lan.local_action("bump", "release")
    game.athlete.move_axis = Vector2(1, 0) if age < 0.55 else Vector2.ZERO
    if age > 0.7 and not sent_jump:
     sent_jump = true
     game.lan.local_action("jump")
    pickup_tick += dt
    if pickup_tick > 0.4 and age > 2 and not game.holding_ball() and (not served or not float_requested):
     pickup_tick = 0
     game.lan.local_action("pickup")
    if game.holding_ball() and private_hold_time > 0.5 and served and not float_requested and age - lower_requested_at > 1.2:
     float_requested = true
     float_requested_at = age
     var side := 1.0 if game.athlete.position.z >= 0 else -1.0
     var aim := Vector3(0, 0.105, -side * 5)
     var direction: Vector3 = aim - game.athlete.position
     game.rig.yaw = atan2(-direction.x, -direction.z)
     game.lan.local_action("float_serve", "press", {"aim": aim, "apex": 1.8})
     print("LAN_CLIENT_FLOAT_REQUEST")
    elif game.holding_ball() and private_hold_time > 0.5 and not served:
     served = true
     lower_requested_at = age
     var side := 1.0 if game.athlete.position.z >= 0 else -1.0
     game.lan.local_action("lower_serve", "press", {"aim": Vector3(0, 0.105, -side * 5), "apex": 3.5})
     print("LAN_CLIENT_SERVE_REQUEST")
   if index == 11 and age > 9:
    game.lan.leave()
    print("LAN_CLIENT_LEFT")
    quit(0)
   if age > 8 and not reported and float_seen:
    reported = true
    client_passed = saw_full and game.lan.players.size() >= 11 and game.lan.snapshot_count > 100 and game.ball.replica and game.athlete.stats.values.set == 135 + index
    client_passed = client_passed and stats_seen and view_seen and float_seen
    client_passed = client_passed and (private_local_seen if index == 1 else private_remote_seen)
    print("LAN_PRIVATE_HELPERS client=%d own=%s foreign_hidden=%s" % [index, private_local_seen, private_remote_seen])
    if index == 1:
     client_passed = client_passed and not game.frontend.visible
    print("LAN_CLIENT_RESULT %d snapshots=%d peers=%d" % [index, game.lan.snapshot_count, game.lan.players.size()])
   # The driver must finish its automatic serve before disconnecting; a
   # delayed first held snapshot must not cancel the sequence mid-toss.
   if age > 11 and index != 11 and reported and (index != 1 or age - float_requested_at > 2.0):
    quit(0 if client_passed else 1)
  if elapsed > 26:
   push_error("Client timeout " + str(index))
   quit(1)
 return false
