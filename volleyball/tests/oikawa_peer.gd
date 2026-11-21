extends SceneTree
var game: Node3D
var host := false
var elapsed := 0.0
var stage := 0
var setup_time := -1.0
var started := false
var requested := false
var observed := 0
var previous_sequence := -1
var completed := 0
var pause_until := 0.0
var ending := false
var before := Vector3.ZERO
var moved := false
var saw_jump := false
var saw_flight := false
func _initialize() -> void:call_deferred("run")
func fail(message: String) -> void:
 push_error(message)
 ending=true
 quit(1)
func run() -> void:
 var args:=OS.get_cmdline_user_args()
 host=args[0]=="host"
 game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.characters.demo=false
 game.characters.set_physics_process(false)
 if host:
  game.lan.host_room(int(args[1]))
  print("OIKAWA_HOST_READY")
 else:game.lan.join_room("127.0.0.1",int(args[1]))
 game.frontend.enter_court()
func configure() -> void:
 var guest: int=game.lan.players.keys().filter(func(id):return id!=1)[0]
 var teams: Array=game.characters.default_teams()
 teams[0][0]={"kind":"human","character":"oikawa","human":1}
 teams[1][0]={"kind":"human","character":"oikawa","human":guest}
 teams[0][1]={"kind":"bot","character":"oikawa","human":0}
 if not game.characters.apply_teams(teams,2,false):fail("Roster setup failed");return
 game.game_bots.bots[-100].set_physics_process(false)
 stage=1
 prepare()
func prepare() -> void:
 var guest: int=game.lan.players.keys().filter(func(id):return id!=1)[0]
 var server: ContextAthlete=game.athlete if stage==1 else game.lan.players[guest].actor if stage==2 else game.game_bots.bots[-100]
 for entry in game.lan.players.values():
  entry.actor.position=Vector3(5.8,0.02,4 if entry.actor.court_team==0 else -4)
  entry.actor.velocity=Vector3.ZERO
 server.position=Vector3(0,0.02,10.4 if server.court_team==0 else -10.4)
 server.velocity=Vector3.ZERO
 game.ball.athlete=server
 game.ball.feed(server.position+Vector3(0,0.25,0),Vector3.ZERO)
 setup_time=elapsed
 requested=false
 started=false
func _process(dt: float) -> bool:
 if not is_instance_valid(game) or ending:return false
 elapsed+=dt
 if elapsed>28:fail("Oikawa LAN timed out stage %d observed %d"%[stage,observed]);return false
 var s: VolleySuperServe=game.super_serve
 if host and game.lan.players.size()==2 and elapsed>1.0 and stage==0:configure()
 if host and stage>0 and setup_time>=0 and elapsed-setup_time>0.3 and not requested:
  requested=true
  game.ball.pick_up()
  if stage==1:
   if not s.begin(game.athlete,1):fail("Host owner could not start");return false
  elif stage==3:
   var bot: VolleyGameBot=game.game_bots.bots[-100]
   bot.serve_wait=0
   bot.set_physics_process(true)
 if not host and game.lan.connected and game.ball.held and not s.active and game.athlete.character_id=="oikawa" and absf(game.athlete.position.z)>9.3 and not requested:
  requested=true
  game.lan.local_action("super")
 if s.active:
  if previous_sequence!=s.sequence:
   previous_sequence=s.sequence
   observed+=1
   moved=false
   saw_jump=false
   saw_flight=false
   before=game.athlete.position
   print("OIKAWA_PLAN sequence=",s.sequence," target=",s.target," inside=",s.inside)
  started=true
  var owner: bool=s.actor==game.athlete
  if s.local_cinematic!=owner or s.camera.current!=owner or game.hud.visible==owner:
   fail("Owner-only camera/HUD isolation failed actor %d owner %s"%[s.actor_id,owner]);return false
  if s.actor.position.y>0.4:saw_jump=true
  if s.contact_done and game.ball.position.z*s.side<0:saw_flight=true
  if not owner:
   Input.action_press("volley_right")
   game.rig.yaw=0.22
   if game.athlete.position.distance_to(before)>0.20:moved=true
   if not game.camera.current:fail("Spectator lost gameplay camera");return false
 elif started and completed<observed:
  completed=observed
  game.athlete.move_axis=Vector2.ZERO
  Input.action_release("volley_right")
  var owner: bool=s.actor==game.athlete
  if not game.camera.current or not game.hud.visible or not saw_jump or not saw_flight or (not owner and not moved):
   fail("Physical motion, live spectator input or restoration failed jump %s flight %s moved %s"%[saw_jump,saw_flight,moved]);return false
  if host and s.impulse_count!=1:fail("Host applied duplicate/missing impulse");return false
  print("OIKAWA_SEQUENCE_PASSED ",completed," owner=",owner)
  if host:
   game.game_bots.bots[-100].set_physics_process(false)
   pause_until=elapsed+0.6
  else:requested=false
 if host and completed==stage and stage>0 and not s.active and elapsed>=pause_until:
  if stage<3:
   stage+=1
   prepare()
  elif not ending:
   ending=true
   print("OIKAWA_PEER_PASSED role=host")
   create_timer(1.0).timeout.connect(func():game.lan.leave();quit(0))
 if not host and completed==3 and not ending:
  ending=true
  print("OIKAWA_PEER_PASSED role=guest")
  create_timer(0.3).timeout.connect(func():game.lan.leave();quit(0))
 return false
