extends SceneTree
var game: Node3D
var host := false
var elapsed := 0.0
var stage := 0
var mark := 0.0
var peer_id := 0
var initial_bench := false
var saw_active := false
var saw_roll := false
var saw_return := false
var requested := false
var rolling_requested := false
var done := false

func _initialize() -> void:call_deferred("run")
func run() -> void:
 var args:=OS.get_cmdline_user_args()
 host=args[0]=="host"
 game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.characters.demo=false
 game.characters.set_physics_process(false)
 game.game_bots.set_physics_process(false)
 if host:
  game.lan.host_room(int(args[1]))
  print("FORMATION_HOST_READY")
 else:
  game.lan.join_room("127.0.0.1",int(args[1]))
 game.frontend.enter_court()

func _process(dt: float) -> bool:
 if not is_instance_valid(game) or done:return false
 elapsed+=dt
 if elapsed>20:
  push_error("Formation LAN timeout host=%s stage=%d bench=%s active=%s roll=%s return=%s" % [host,stage,initial_bench,saw_active,saw_roll,saw_return])
  quit(1)
  return false
 if host:
  host_step()
 else:
  guest_step()
 return false

func host_step() -> void:
 if stage==0 and game.lan.players.size()==2 and elapsed>0.6:
  peer_id=game.lan.players.keys().filter(func(id):return id!=1)[0]
  var roster: Array=game.characters.default_teams()
  var roles: Array=["S","OP","MB","OH","MB","OH"]
  for t in range(2):
   for s in range(6):
    roster[t][s]={"kind":"human" if t==0 and s==0 else "bot","human":1,"character":"hinata" if roles[s]=="MB" else "kageyama","role":roles[s],"rotation":s+1}
  var config: Dictionary=game.characters.default_lineup_settings()
  config.auto=[false,true]
  config.liberos=[{"kind":"human","character":"yu_nishinoya","human":peer_id},{"kind":"bot","character":"yu_nishinoya","human":0}]
  assert(game.characters.apply_teams(roster,2,false,config))
  for a: ContextAthlete in game.characters.actors():a.set_physics_process(false)
  game.athlete.position=Vector3(6.5,0.02,3)
  game.athlete.velocity=Vector3.ZERO
  stage=1
 if stage==1 and game.lan.readiness().valid:
  game.lan.ready_seconds=3.1
  assert(game.lan.begin_match())
  assert(game.formation.enabled and game.lan.players[peer_id].actor.benched)
  assert(game.game_bots.members(0).size()==6 and game.game_bots.members(1).size()==6)
  game.lan.players[peer_id].actor.set_physics_process(true)
  stage=2
  mark=elapsed
 if stage==2 and not game.lan.players[peer_id].actor.benched:
  assert(game.lan.players[peer_id].actor.character_id=="yu_nishinoya")
  stage=3
 if stage==3 and game.lan.players[peer_id].actor.rolling_active:
  saw_roll=true
  stage=4
  mark=elapsed
 if stage==4 and elapsed-mark>1.5:
  assert(not game.lan.players[peer_id].actor.rolling_active)
  game.lan.award(1)
  game.lan.reset_round()
  stage=5
  mark=elapsed
 if stage==5 and elapsed-mark>0.65:
  game.lan.award(0)
  game.lan.reset_round()
  assert(game.lan.players[peer_id].actor.benched)
  assert(game.game_bots.members(0).size()==6 and game.game_bots.members(1).size()==6)
  stage=6
  mark=elapsed
 if stage==6 and elapsed-mark>1.8:
  print("FORMATION_PEER_PASSED role=host active=12 roster=14 rolling=",saw_roll," replacements=",game.formation.libero.history.size())
  done=true
  create_timer(2.5).timeout.connect(func():game.lan.leave();quit(0))

func guest_step() -> void:
 if not game.lan.connected or game.lan.players.size()!=2:return
 var a: ContextAthlete=game.athlete
 if a.designated_libero and a.benched and not game.lan.match_active:
  initial_bench=true
  if not requested:
   requested=true
   game.lan.local_action("context")
 if game.lan.match_active and a.benched and not saw_active and requested:
  assert(a.character_id=="yu_nishinoya" and a.volley_role=="L")
  game.lan.local_action("context")
 if game.lan.match_active and not a.benched and a.designated_libero:
  saw_active=true
  assert(a.rotation_slot in [1,5,6] and is_equal_approx(a.height_cm,160.5))
  if not rolling_requested and elapsed>2.5:
   rolling_requested=true
   game.lan.local_action("dive","press",{"axis":Vector2.RIGHT,"role":"S","rotation":2})
 if a.rolling_active:
  saw_roll=true
 if saw_active and a.benched:
  saw_return=true
 if initial_bench and saw_active and saw_roll and saw_return:
  assert(a.character_id=="yu_nishinoya" and a.volley_role=="L" and game.characters.actors().size()==14)
  assert(game.game_bots.members(0).size()==6 and game.game_bots.members(1).size()==6)
  print("FORMATION_PEER_PASSED role=guest active=12 roster=14 human-control-preserved=true rolling=true")
  done=true
  create_timer(0.3).timeout.connect(func():game.lan.leave();quit(0))
