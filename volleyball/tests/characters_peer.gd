extends SceneTree
var game: Node3D
var host := false
var elapsed := 0.0
var configured := false
var jumped := false
var launched := false
var saw_special := false
var saw_teams := false
var attack_requested := false
var ended := false
var swap := false
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var args := OS.get_cmdline_user_args()
 host = args[0] == "host"
 swap = args.size() > 2 and args[2] == "swap"
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.characters.demo = false
 game.athlete.set_character("hinata" if host == swap else "kageyama")
 game.characters.selected = game.athlete.character_id
 if host:
  game.lan.host_room(int(args[1]))
  print("CHARACTER_HOST_READY")
 else:
  game.lan.join_room("127.0.0.1", int(args[1]))
 game.frontend.enter_court()
func _process(dt: float) -> bool:
 if not is_instance_valid(game):
  return false
 elapsed += dt
 if ended:
  return false
 if elapsed > 18:
  push_error("Character LAN timed out")
  quit(1)
 if host and game.lan.players.size() == 2 and elapsed > 0.7 and not configured:
  configured = true
  var guest: int = game.lan.players.keys().filter(func(id): return id != 1)[0]
  var teams: Array = game.characters.default_teams()
  teams[0][0] = {"kind":"human","character":"hinata" if swap else "kageyama","human":1}
  teams[0][1] = {"kind":"human","character":"kageyama" if swap else "hinata","human":guest}
  teams[1][0] = {"kind":"bot","character":"hinata","human":0}
  teams[1][1] = {"kind":"bot","character":"kageyama","human":0}
  assert(game.characters.apply_teams(teams,2,false))
  game.athlete.position = Vector3(2 if swap else 0,0.02,3)
  game.lan.players[guest].actor.position = Vector3(0 if swap else 2,0.02,3)
  game.ball.feed(Vector3(0,0.3,8),Vector3.ZERO)
 if host and swap and configured and elapsed > 3.2 and not jumped:
  jumped = game.lan.local_action("jump")
 if not host and game.lan.connected and game.lan.players.size() == 2 and elapsed > 1.4 and not jumped:
  var other: ContextAthlete = game.lan.players[1].actor
  if other.character_id == ("hinata" if swap else "kageyama") and game.athlete.character_id == ("kageyama" if swap else "hinata") and other.court_team == 0 and game.athlete.court_team == 0:
   saw_teams = true
   if not swap:
    jumped = game.lan.local_action("jump")
   elif not game.characters.partners(game.athlete).is_empty():
    jumped = game.lan.local_action("freak")
    game.lan.local_action("freak","release")
   if jumped:
    game.lan.local_action("stats","press",{"skill":"jump","value":999})
    game.lan.local_action("super")
 if host and configured and not launched:
  var setters: Array = game.lan.players.values().filter(func(p): return p.actor.character_id == "kageyama")
  var setter: ContextAthlete = setters[0].actor
  if not game.characters.partners(setter).is_empty():
   if not swap:
    launched = game.begin_special("freak")
    setter.release()
   else:
    launched = setter.special_set == "freak"
  if launched:
   setter._update_pose(0)
   game.ball.feed((setter.wrists[0]+setter.wrists[1])*0.5 + Vector3.UP*0.15,Vector3.DOWN*2)
 if not host:
  for entry in game.lan.players.values():
   if entry.actor.special_set == "freak":
    saw_special = true
 if (host and elapsed > 5.0) or (not host and elapsed > 5.5):
  if host:
   var peer_id: int = game.lan.players.keys().filter(func(id): return id != 1)[0]
   var guest_actor: ContextAthlete = game.lan.players[peer_id].actor
   if not launched or game.characters.quick_launches != 1 or int(guest_actor.stats.values.jump) != (89 if swap else 100) or game.super_serve.active:
    var setter_debug: ContextAthlete = guest_actor if swap else game.athlete
    print("LAST SPECIAL ",game.characters.last_special_contact)
    push_error("Host validation/actual Freak Quick failed: %s launches %d contacts %d action %d kind %d result %s" % [launched, game.characters.quick_launches, setter_debug.contact_count, setter_debug.action, setter_debug.strike_technique, setter_debug.last_result])
    quit(1)
    return false
  else:
   if not saw_teams or not saw_special or game.game_bots.bots.size() != 2 or game.athlete.character_id != ("kageyama" if swap else "hinata") or absf(game.athlete.height_cm-(181.9 if swap else 164.2)) > 0.01:
    push_error("Guest replication failed: teams=%s special=%s bots=%d hero=%s height=%f" % [saw_teams,saw_special,game.game_bots.bots.size(),game.athlete.character_id,game.athlete.height_cm])
    quit(1)
    return false
  print("CHARACTER_PEER_PASSED role=", "host" if host else "guest")
  ended = true
  create_timer(2.8 if host else 0.35).timeout.connect(func(): game.lan.leave(); quit(0))
 return false
