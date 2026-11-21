extends SceneTree
var game: Node3D
var failures:=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
 game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 var calibration:=VolleyBotCalibration.new()
 for grade in range(3):
  var teams: Array=game.characters.default_teams()
  teams[0][0]={"kind":"human","character":"kageyama","human":0}
  teams[0][1]={"kind":"bot","character":"hinata","human":0}
  game.characters.apply_teams(teams,grade,false)
  game.characters.demo=false
  var k: ContextAthlete=game.athlete
  var h: VolleyGameBot=game.game_bots.bots[-100]
  k.position=Vector3(-1.6,0.02,3.0)
  h.position=Vector3(1.5,0.02,4.0)
  game.ball.feed(Vector3(0,0.20,-7),Vector3.ZERO)
  for i in range(12):await physics_frame
  game.game_bots.reset_rally()
  game.game_bots.last_team=0
  game.game_bots.touches=1
  game.game_bots.last_actor=h
  game.game_bots.last_kind=VolleyAthlete.Technique.UNDERHAND
  game.game_bots.last_touch_time=game.game_bots.clock
  k.move_axis=Vector2.ZERO
  k.camera_yaw=0
  k.visual.rotation.y=0
  game.ball.feed(k.position+Vector3(0,k.natural_reach()+3.0,-0.28),Vector3.ZERO)
  var takeoff:=-1.0
  var contacted:=-1.0
  var idle_takeoff:=false
  var before:=k.contact_count
  for frame in range(360):
   # A human may wait to see the attacker's jump before pressing a pass.
   if h.jump_in_progress and takeoff<0:
    takeoff=game.game_bots.clock
    idle_takeoff=k.action==VolleyAthlete.Action.IDLE
   if takeoff>=0 and k.action==VolleyAthlete.Action.IDLE:k.begin_action(VolleyAthlete.Technique.OVERHEAD)
   if k.action==VolleyAthlete.Action.PREPARE and k.charged_for>=k.mechanic(0).windup and calibration.contact_due(k,game.ball,0):
    game.characters.begin_special(k,"freak")
    k.release()
   await physics_frame
   if k.contact_count>before:contacted=game.game_bots.clock;break
  var lead:=contacted-takeoff
  print("HUMAN QUICK grade=",grade," takeoff_before_input=",idle_takeoff," lead=",lead," contacted=",contacted>=0)
  if not idle_takeoff or contacted<0 or lead<0.35:
   failures+=1
   push_error("Hinata must show his jump early enough for a human setter to react")
  game.ball.clear_quick()
 print("HINATA LEAD PASSED" if failures==0 else "HINATA LEAD FAILED")
 quit(0 if failures==0 else 1)
