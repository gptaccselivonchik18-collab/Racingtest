extends SceneTree
var game: Node3D
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1;push_error(label)
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
 var k: VolleyGameBot=game.game_bots.bots[-100]
 var h: VolleyGameBot=game.game_bots.bots[-101]
 k.energy=0
 h.energy=0
 check(is_equal_approx(k.effective_jump_height(),float(k.style_stats.movement().jump_height)) and is_equal_approx(h.effective_speed(),float(h.style_stats.movement().speed)),"No bot stamina penalty even from a stale saved zero value")
 var human: ContextAthlete=game.athlete
 human.visual.rotation.y=0
 check(human.direction_pace(Vector2(0,-1))>human.direction_pace(Vector2(1,0)) and human.direction_pace(Vector2(1,0))>human.direction_pace(Vector2(0,1)),"Forward > sideways > backwards for a real player")
 check(is_equal_approx(h.direction_pace(Vector2(0,-1)),human.direction_pace(Vector2(0,-1))),"Bots and players use the same directional movement")
 for grade in range(3):
  game.game_bots.configure({"difficulty":[0,2,4][grade]},false)
  var passes:=0
  var early:=0
  var late:=0
  var attacks:=0
  var attempted_hands:=0
  for trial in range(24):
   game.game_bots.tactics.reset()
   k.reset_plan()
   h.reset_plan()
   k.position=Vector3(-1.2,0.02,3.2)
   h.position=Vector3(1.6,0.02,4.1)
   k.velocity=Vector3.ZERO
   h.velocity=Vector3.ZERO
   k.camera_yaw=0.0 if trial%3!=2 else 1.2
   k.visual.rotation.y=k.camera_yaw
   h.camera_yaw=0
   h.visual.rotation.y=0
   game.ball.feed(Vector3(0,0.20,-7),Vector3.ZERO)
   for i in range(8):await physics_frame
   game.game_bots.last_team=0
   game.game_bots.touches=1
   game.game_bots.last_actor=h
   game.game_bots.last_kind=VolleyAthlete.Technique.UNDERHAND
   game.game_bots.last_touch_time=game.game_bots.clock
   game.game_bots.think_left=0
   var before:=k.contacts
   var h_before:=h.contacts
   var drift: float=(trial%3-1)*0.10
   game.ball.feed(k.position+Vector3(drift,k.natural_reach()+1.35,-0.30),Vector3(0,-0.3,0))
   for i in range(340):
    await physics_frame
    if k.contacts>before:break
    if game.ball.position.y<0.25 and not game.ball.pending_feed:break
   if k.contacts>before:
    passes+=1
    if trial<8:early+=1
    if trial>=16:late+=1
    if k.last_pass_recipient==h.get_instance_id():attempted_hands+=1
   for i in range(320):await physics_frame
   if h.contacts>h_before:attacks+=1
   if k.energy!=1.0 or h.energy!=1.0:
    check(false,"Bot energy must remain disabled throughout a long session")
    break
  print("NORMAL BOT SESSION grade=",grade," passes=",passes," /24 early=",early," late=",late," targeted_Hinata=",attempted_hands," following_contacts=",attacks," clock=",game.game_bots.clock)
  check(passes>=20,"Ordinary Kageyama contacts incoming sets reliably at grade %d"%grade)
  check(attempted_hands>=18,"Ordinary sets identify the actual teammate Hinata at grade %d"%grade)
  check(attacks>=18,"Hinata can play the ordinary sets at grade %d"%grade)
  check(late>=early-2,"No mid-session deterioration at grade %d"%grade)
 check(game.game_bots.tactics.teammate_readings.size()==3,"Live teammate observations track humans and each unique bot")
 print("BOT ADAPTATION PASSED" if failures==0 else "BOT ADAPTATION FAILED %d"%failures)
 quit(0 if failures==0 else 1)
