extends SceneTree
var game: Node3D
var failed := false
func _initialize() -> void:call_deferred("run")
func run() -> void:
 game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.characters.set_physics_process(false)
 game.characters.demo=false
 game.hud.set_process(false)
 var a: ContextAthlete=game.athlete
 var s: VolleySuperServe=game.super_serve
 var human := ContextAthlete.new()
 game.add_child(human)
 human.set_character("kageyama")
 human.court_team=1
 human.camera_yaw=PI
 human.visual.rotation.y=PI
 var successes := [0,0]
 for mode in range(2):
  var teams: Array=game.characters.default_teams()
  teams[0][0]={"kind":"human","character":"oikawa","human":0}
  if mode==1:teams[1][0]={"kind":"bot","character":"kageyama","human":0}
  game.characters.apply_teams(teams,2,false)
  human.set_physics_process(mode==0)
  human.visible=mode==0
  var receiver: ContextAthlete=human if mode==0 else game.game_bots.bots[VolleyGameBots.bot_id(1,0)]
  if mode==0:game.ball.contact_athletes.append(human)
  for attempt in range(4):
   game.game_bots.reset_rally()
   a.position=Vector3(0,0.02,10.4)
   a.velocity=Vector3.ZERO
   a.energy=1
   receiver.position=Vector3(-1.1,0.02,-6.6)
   receiver.velocity=Vector3.ZERO
   receiver.camera_yaw=PI
   receiver.action=VolleyAthlete.Action.IDLE
   game.ball.athlete=a
   game.ball.feed(a.position+Vector3(0,0.25,0),Vector3.ZERO)
   for i in range(14):await physics_frame
   game.ball.pick_up()
   var before:=receiver.contact_count
   if not s.begin(a,0):push_error("Reception fixture could not start serve");quit(1);return
   s.target=Vector3(-1.3,VolleyBall.RADIUS,-8.2)
   s.inside=true
   var pressed:=false
   for i in range(700):
    if mode==0 and s.contact_done and game.ball.position.z < -3.2 and not pressed:
     pressed=true
     receiver.begin_action(VolleyAthlete.Technique.UNDERHAND)
     receiver.release()
    await physics_frame
    if receiver.contact_count>before:break
    if not s.active:break
   if receiver.contact_count>before:
    if game.ball.super_curve!=0:
     push_error("Special curvature must stop at the defender's real contact");quit(1);return
    successes[mode]+=1
   print("RECEPTION mode=",mode," attempt=",attempt," received=",receiver.contact_count>before," state=",receiver.last_result)
   if s.active:s.finish(true)
 print("RECEPTION COUNTS human=",successes[0]," ai=",successes[1])
 if successes[0]==0 or successes[1]==0:
  push_error("Super serve must allow real human and AI defensive contact")
  quit(1)
 else:
  print("OIKAWA RECEPTION PASSED")
  quit(0)
