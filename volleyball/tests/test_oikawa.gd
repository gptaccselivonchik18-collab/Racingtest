extends SceneTree
var game: Node3D
var failures := 0
var checks := 0
var floor_at := Vector3.INF
var probe_live := false
func _initialize() -> void:
 call_deferred("run")
func check(ok: bool, message: String) -> void:
 checks += 1
 print("PASS: " if ok else "FAIL: ",message)
 if not ok:
  failures += 1
  push_error(message)
func settle(a: ContextAthlete, side: float) -> void:
 a.position=Vector3(0,0.02,side*10.4)
 a.velocity=Vector3.ZERO
 a.move_axis=Vector2.ZERO
 for i in range(12):await physics_frame
 a._update_pose(0)
 game.ball.athlete=a
 game.ball.feed(a.position+Vector3(0,0.25,-side*0.4),Vector3.ZERO)
 for i in range(4):await physics_frame
 game.ball.pick_up()
func run() -> void:
 game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.characters.demo=false
 game.characters.set_physics_process(false)
 var a: ContextAthlete=game.athlete
 var s: VolleySuperServe=game.super_serve
 a.court_team=0
 a.set_character("oikawa")
 var expected := {"spike":76,"jump":78,"serve":100,"set":98,"block":75,"bump":79,"dive":72,"speed":74}
 var exact := true
 for key in expected:
  exact = exact and int(a.stats.values[key]) == expected[key]
 check(exact,"Oikawa exact fixed sheet")
 check(a.height_cm==184.3 and absf(a.physical_scale-184.3/204.0)<0.00001,"Physical height scales existing rig and reach")
 check(s.SPEED_MULTIPLIER>=0.85 and s.SPEED_MULTIPLIER<=0.90,"Exposed requested-speed multiplier reduces archived pace 10–15%")
 var good := 0
 var transitions := 0
 var previous := false
 s.random.seed=913673
 for i in range(10000):
  var result:=s.choose_target(Vector3(0,0,10.4))
  if result.inside:good+=1
  if result.inside!=previous:transitions+=1
  previous=result.inside
  if bool(result.inside)!=(absf(result.target.x)<4.5 and absf(result.target.z)<9):
   check(false,"Every planned target matches its independent result")
   break
 check(absf(good/10000.0-0.70)<0.02 and transitions>3000,"10,000 independent trials approach 70/30: %d inside"%good)
 game.ball.surface_contact.connect(func(surface: String):
  if surface=="floor" and ((s.active and s.contact_done) or probe_live) and floor_at==Vector3.INF:floor_at=game.ball.position)
 for side in [1.0,-1.0]:
  for forced_good in [true,false]:
   a.energy=1
   a.court_team=0 if side>0 else 1
   await settle(a,side)
   check(game.ball.held and s.eligible(a),"Available without charge with own ball behind baseline")
   var expected_height:=a.effective_jump_height()
   var ordinary:=a.power_serve_speed()
   floor_at=Vector3.INF
   var start:=s.begin(a,0)
   s.inside=forced_good
   s.target=Vector3(-1.5,VolleyBall.RADIUS,-side*(8.2 if forced_good else 10.0))
   s.packet.target=s.target
   s.packet.inside=forced_good
   check(start and s.local_cinematic and s.camera.current,"Owner enters archived local cinematic")
   check(not s.begin(a,0),"Repeated press cannot restart serve")
   var highest:=0.0
   for tick in range(800):
    await physics_frame
    highest=maxf(highest,a.position.y)
    if not s.active:break
   print("DELIVERY side=",side," planned=",forced_good," floor=",floor_at," impulse=",s.impulse_count," jump=",s.jump_count," peak=",highest," limit=",expected_height," pace=",s.launch_velocity.length()," ordinary-request=",ordinary," net=",game.rules.message)
   check(not s.active and s.impulse_count==1 and s.jump_count==1,"Automatic serve produces one jump and one actual contact")
   check(absf(highest-expected_height)<0.08,"Jump follows Jump 78 ballistic height")
   check(floor_at!=Vector3.INF and floor_at.distance_to(s.target)<0.40,"Real unassisted flight reaches planned floor area")
   check(forced_good==(absf(floor_at.x)<=4.5+VolleyBall.RADIUS and absf(floor_at.z)<=9+VolleyBall.RADIUS),"Actual floor classification agrees with planned in/out")
   check(not game.ball.freeze and game.ball.collision_mask==1 and not game.ball.quick_active,"Ball retains collisions, gravity and no reception slowing")
   check(a.cinema_time<0 and game.camera.current and game.hud.visible,"Control and original owner camera restore")
 # A batch of actual rigid-body flights checks the probability after physics,
 # rather than counting only the RNG flags. No characters touch these probes.
 probe_live=true
 var physical_in := 0
 var disagreements := 0
 s.random.seed=246813
 for sample in range(200):
  var side := 1.0 if sample%2==0 else -1.0
  var start:=Vector3(s.random.randf_range(-3.3,3.3),3.5,side*9.2)
  var aim:=s.choose_target(start)
  var delivery:=s.solve_delivery(start,aim.target)
  floor_at=Vector3.INF
  game.ball.feed(start,delivery.velocity,s.SPIN)
  for tick in range(240):
   await physics_frame
   if floor_at!=Vector3.INF:break
  var actual: bool=floor_at!=Vector3.INF and absf(floor_at.x)<=4.5+VolleyBall.RADIUS and absf(floor_at.z)<=9+VolleyBall.RADIUS
  if actual:physical_in+=1
  if floor_at==Vector3.INF or actual!=aim.inside:disagreements+=1
 check(disagreements==0,"200 real rigid-body flights preserve planned in/out without late steering: %d mismatches"%disagreements)
 check(absf(physical_in/200.0-0.70)<0.08,"Actual physics flight batch remains near 70/30: %d/200 inside"%physical_in)
 probe_live=false
 # Ordinary serves remain separate; only Oikawa has the special action.
 await settle(a,1)
 a.court_team=0
 game.game_bots.solo_match=true
 game.game_bots.current_server=a
 game.game_bots.serve_team=0
 game.game_bots.last_team=-1
 game.game_bots.round_wait=-1
 check(s.eligible(a),"Available immediately on Oikawa's nominated match turn")
 game.game_bots.current_server=null
 check(not s.eligible(a),"Teammate's serve turn cannot be stolen")
 game.game_bots.current_server=a
 game.game_bots.last_team=0
 check(not s.eligible(a),"Cannot activate in a live rally")
 game.game_bots.last_team=-1
 check(s.eligible(a),"Available on the next eligible turn without earning any points")
 game.game_bots.scores=[0,0]
 game.game_bots.sets=[0,0]
 game.rules.strict=true
 game.rules.reset()
 check(s.begin(a,0),"Nominated Super Serve starts in a scored match")
 s.target=Vector3(0,VolleyBall.RADIUS,-8.0)
 var early_score:=false
 for tick in range(800):
  await physics_frame
  if not s.landed and game.game_bots.scores!=[0,0]:early_score=true
  if not s.active:break
 check(not early_score and game.game_bots.scores==[1,0],"Only the real floor collision awards one normal match point")
 game.game_bots.solo_match=false
 game.rules.strict=false
 await settle(a,1)
 check(game.begin_primary() and game.ball.pending_feed,"Ordinary toss/serve remains available")
 a.set_character("kageyama")
 check(not s.begin(a,0),"Kageyama cannot activate Oikawa serve")
 a.set_character("hinata")
 check(not s.begin(a,0),"Hinata cannot activate Oikawa serve")
 print("OIKAWA PASSED (%d checks)"%checks if failures==0 else "OIKAWA FAILED %d"%failures)
 quit(0 if failures==0 else 1)
