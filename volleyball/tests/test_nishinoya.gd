extends SceneTree
var game: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, text: String) -> void:
 checks += 1
 print("PASS: " if ok else "FAIL: ",text)
 if not ok:
  failures += 1
  push_error(text)

func settle(a: ContextAthlete) -> void:
 a.cancel_input()
 a.action=VolleyAthlete.Action.IDLE
 a.position=Vector3(-3,0.02,6)
 a.velocity=Vector3.ZERO
 a.move_axis=Vector2.ZERO
 a.dive_cooldown=0
 for i in range(16):
  await physics_frame

func run() -> void:
 game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.characters.set_physics_process(false)
 game.game_bots.set_physics_process(false)
 game.ball.feed(Vector3(0,0.3,-8),Vector3.ZERO)
 var a: ContextAthlete=game.athlete
 a.court_team=0
 a.set_character("yu_nishinoya")
 check(VolleyCharacterDatabase.IDS.has("yu_nishinoya") and a.volley_role=="L","Nishinoya is catalog-driven Libero")
 var sheet := {"spike":20,"jump":75,"serve":20,"set":68,"block":18,"bump":100,"dive":100,"speed":96}
 for key in sheet:
  check(is_equal_approx(float(a.stats.values[key]),float(sheet[key])),"Exact Nishinoya stat "+key)
 check(is_equal_approx(a.height_cm,160.5) and is_equal_approx(a.physical_scale,160.5/204.0),"Existing model and real collider scale to 160.5 cm")
 var base := VolleyStyleStats.new()
 base.values=a.stats.values.duplicate()
 var p := a.mechanic(1)
 var original := base.profile(1)
 check(is_equal_approx(p.accuracy,original.accuracy*0.70),"Defensive passive reduces bump angular error by 30 percent")
 check(is_equal_approx(p.carry,original.carry*0.75) and p.pressure>original.pressure,"Defensive passive absorbs excess hard-hit momentum")
 check(p.windup<original.windup and p.spin<original.spin,"Faster ready stance and improved spin control use real contact profiles")
 check(not a.begin_action(ContextAthlete.BLOCK) and not a.begin_action(3) and not a.begin_action(4),"A Libero cannot serve or attempt a block")
 await settle(a)
 a.move_axis=Vector2.RIGHT
 var normal_start := a.position
 check(a.dive(),"Ordinary reference dive starts on the floor")
 var normal_time := 0.0
 for i in range(240):
  await physics_frame
  normal_time += 1.0/120
  if a.dive_time<0:
   break
 var normal_distance := VolleyBotTactics.flat(a.position,normal_start)
 await settle(a)
 a.move_axis=Vector2.RIGHT
 var rolling_start := a.position
 check(a.defensive_dive() and a.rolling_active,"Nishinoya's existing dive control starts Rolling Thunder")
 var recover: float=a.mechanic(ContextAthlete.DIVE).recover_time
 var reference: Dictionary=base.profile(ContextAthlete.DIVE)
 check(is_equal_approx(recover,float(reference.travel)+(float(reference.recover_time)-float(reference.travel))*0.65),"Rolling Thunder reduces the stand-up tail by 35 percent")
 check(is_equal_approx(a.mechanic(ContextAthlete.DIVE).accuracy,base.profile(ContextAthlete.DIVE).accuracy*0.70*0.80),"Rolling contact adds its own 20 percent accuracy improvement")
 var real_contact := false
 var rolled := false
 var tried_reuse := false
 var rolling_time := 0.0
 for i in range(240):
  await physics_frame
  rolling_time+=1.0/120
  if a.dive_time>=0.15 and not real_contact:
   var at: Vector3=(a.wrists[1]+a.elbows[1])*0.5
   check(a.try_contact(at+Vector3(3,0,0),Vector3(0,-4,-25))==Vector3.ZERO and not a.hit_used,"Rolling Thunder misses a ball three metres from the real forearms")
   var impulse := a.try_contact(at,Vector3(0,-4,-25))
   real_contact=impulse!=Vector3.ZERO
   check(real_contact and impulse.is_finite(),"Rolling Thunder makes an actual forearm impulse against a hard ball")
  if a.dive_time>0.80:
   rolled=rolled or absf(a.visual.rotation.x)>2.0
   if not tried_reuse:
    check(not a.defensive_dive(),"Rolling Thunder cannot be restarted during the roll/stand-up")
    tried_reuse=true
  if a.dive_time<0:
   break
 var rolling_distance:=VolleyBotTactics.flat(a.position,rolling_start)
 check(absf(rolling_distance/normal_distance-1.30)<0.035,"Rolling Thunder really travels 30 percent farther without teleporting")
 check(rolled and rolling_time<normal_time and not a.rolling_active and a.action==VolleyAthlete.Action.IDLE,"Existing model rolls, stands earlier and restores ordinary movement")
 for direction in [Vector2.LEFT,Vector2(0,-1),Vector2(1,-1).normalized(),Vector2(-1,1).normalized()]:
  await settle(a)
  a.move_axis=direction
  check(a.defensive_dive() and Vector2(a.dive_direction.x,a.dive_direction.z).dot(direction)>0.99,"Rolling Thunder follows selected direction "+str(direction))
  for i in range(180):
   await physics_frame
   if a.dive_time<0:
    break
 a.set_character("kageyama")
 await settle(a)
 check(not a.dive(true),"Other characters cannot request Nishinoya's special technique")
 var roster: Array=game.characters.default_teams()
 roster[0][1]={"kind":"bot","character":"yu_nishinoya","human":0}
 roster[1][0]={"kind":"bot","character":"hinata","human":0}
 check(game.characters.apply_teams(roster,1,false),"Nishinoya participates in an incomplete training squad")
 var bot: VolleyGameBot=game.game_bots.bots[-100]
 game.game_bots.set_physics_process(false)
 bot.set_physics_process(false)
 bot.position=Vector3(0,0.02,6)
 bot.velocity=Vector3.DOWN
 for i in range(16):bot._physics_process(1.0/120)
 bot.cooldown=0
 bot.reaction_until=0
 game.ball.position=Vector3(2,0.8,6)
 game.ball.pending_feed=false
 check(bot.attempt_dive(Vector3(2,0.02,6),0.35,true) and bot.rolling_active,"The same bot controller selects Rolling Thunder for an unreachable low ball")
 check(game.game_bots.tactics.block_plan(bot).is_empty() and not VolleyRoles.attack_capable(bot),"Nishinoya keeps defensive responsibilities rather than attempting blocks or spikes")
 game.characters.ui.open_characters()
 check(game.frontend.page=="characters","Nishinoya's character card opens normally")
 game.characters.ui.open_teams(true)
 check(game.characters.ui.clubs().Karasuno.has("yu_nishinoya"),"Nishinoya appears in Karasuno bot picker")
 game.characters.ui.selected_side=0
 game.characters.ui.draw_lineup()
 check(game.frontend.page=="teams","Roles, rotation and separate Libero controls render")
 game.queue_free()
 await process_frame
 print("NISHINOYA PASSED (%d checks)" % checks if failures==0 else "NISHINOYA FAILED (%d)" % failures)
 quit(0 if failures==0 else 1)
