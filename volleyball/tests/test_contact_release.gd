extends SceneTree
var game: Node3D
var failures:=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
 game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 var teams: Array=game.characters.default_teams()
 teams[0][0]={"kind":"bot","character":"kageyama","human":0}
 teams[0][1]={"kind":"bot","character":"hinata","human":0}
 teams[1][0]={"kind":"human","character":"oikawa","human":0}
 game.characters.apply_teams(teams,2,false)
 game.characters.demo=false
 game.athlete.set_physics_process(false)
 var k: VolleyGameBot=game.game_bots.bots[-100]
 var h: VolleyGameBot=game.game_bots.bots[-101]
 h.set_physics_process(false)
 for grade in range(3):
  game.game_bots.configure({"difficulty":[0,2,4][grade]},false)
  var contacts:=0
  var misses:=0
  for trial in range(12):
   game.game_bots.reset_rally()
   k.position=Vector3(0,0.02,3.4)
   k.velocity=Vector3.ZERO
   h.position=Vector3(3,0.02,3.0)
   h.cooldown=100
   game.ball.feed(Vector3(0,0.20,-7),Vector3.ZERO)
   for i in range(8):await physics_frame
   k.camera_yaw=[0.0,1.0,-1.0][trial%3]
   k.visual.rotation.y=k.camera_yaw
   k.velocity=Vector3((trial%3-1)*2.5,0,0)
   var aim:=k.position+Vector3(0,k.natural_reach()+0.15,-0.32)
   var incoming:=Vector3((trial%3-1)*4.0,4.0 if trial<6 else -6.0,1.5 if trial%2==0 else -1.5)
   var travel:=0.55 if trial<6 else 0.35
   var start:=aim-incoming*travel+Vector3.UP*4.905*travel*travel
   game.game_bots.last_team=0
   game.game_bots.touches=1
   game.game_bots.last_actor=h
   game.game_bots.last_kind=VolleyAthlete.Technique.UNDERHAND
   game.game_bots.last_touch_time=game.game_bots.clock
   game.game_bots.think_left=0
   var before:=k.contacts
   var counted:={}
   game.ball.feed(start,incoming,Vector3(1,2,0))
   for i in range(260):
    await physics_frame
    if k.action==VolleyAthlete.Action.RECOVER and not k.hit_used and not counted.has(k.strike_count):
     counted[k.strike_count]=true
     if k.strike_technique in [0,8]:misses+=1
    if k.contacts>before:contacts+=1;break
    if game.ball.position.y<0.24 and not game.ball.pending_feed:break
  print("CONTACT RELEASE grade=",grade," contacts=",contacts," /12 premature_misses=",misses)
  if contacts<11 or misses>1:
   failures+=1
   push_error("Moving setters must time rising and falling lateral balls with the real hands")
 print("CONTACT RELEASE PASSED" if failures==0 else "CONTACT RELEASE FAILED")
 quit(0 if failures==0 else 1)
