extends SceneTree
var game: Node3D
var checks := 0
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
 checks+=1
 print("PASS: " if ok else "FAIL: ",text)
 if not ok:
  failures+=1
  push_error(text)
func run() -> void:
 game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.characters.set_physics_process(false)
 game.game_bots.set_physics_process(false)
 var cm: VolleyCharacters=game.characters
 var b: VolleyGameBots=game.game_bots
 var roles:= ["OH","S","MB","L","OP","OH"]
 var heroes:= ["kageyama","kageyama","hinata","yu_nishinoya","kageyama","kageyama"]
 var roster:=cm.default_teams()
 for i in range(6):roster[0][i]={"kind":"human" if i==0 else "bot","human":0,"character":heroes[i],"role":roles[i],"rotation":i+1}
 roster[1][0]={"kind":"bot","human":0,"character":"kageyama"}
 roster[1][1]={"kind":"bot","human":0,"character":"hinata"}
 for level in range(3):
  check(cm.apply_teams(roster,level,false),"All five universal roles configure at difficulty %d" % level)
  for a: ContextAthlete in b.bots.values():
   var data:=VolleyCharacterDatabase.get_character(a.character_id)
   var valid:=true
   for key in VolleyStyleStats.KEYS:
    valid=valid and is_equal_approx(float(a.stats.values[key]),float(data.stats[key])*[0.80,0.90,1.0][level])
   check(valid,"Role does not alter fixed character stats or difficulty multipliers: "+a.character_id)
 var setter: VolleyGameBot=b.bots[-100]
 var middle: VolleyGameBot=b.bots[-101]
 var defender: VolleyGameBot=b.bots[-102]
 var opposite: VolleyGameBot=b.bots[-103]
 var outside: VolleyGameBot=b.bots[-104]
 for a: ContextAthlete in cm.actors():
  a.set_physics_process(false)
  a.position=Vector3(7,0.02,8) if a==game.athlete else Vector3(0,0.02,-6)
  a.velocity=Vector3.ZERO
 setter.position=Vector3(0,0.02,3)
 middle.position=Vector3(-2,0.02,2.6)
 defender.position=Vector3(1,0.02,5)
 opposite.position=Vector3(2.8,0.02,3.8)
 outside.position=Vector3(-2.8,0.02,3.8)
 b.clock=10
 b.last_touch_time=10
 for a: VolleyGameBot in b.bots.values():
  a.noticed_touch=10
  a.reaction_until=0
  a.cooldown=0
 b.last_team=0
 b.touches=1
 b.last_actor=defender
 b.last_kind=1
 b.samples=[{"at":Vector3(0,2,3),"v":Vector3.DOWN*2,"time":0.4}]
 b.tactics.choose_receivers()
 check(b.receivers[0]==setter.bot_id,"The setter organizes the second touch after a Libero reception")
 b.tactics.reset()
 b.last_actor=setter
 b.samples=[{"at":Vector3(1,1.4,5),"v":Vector3.DOWN*2,"time":0.4}]
 b.tactics.choose_receivers()
 check(b.receivers[0]==defender.bot_id,"Libero covers the second touch when the setter received the first ball")
 check(b.receivers[0]!=setter.bot_id,"A setter never repeats their first touch illegally")
 b.tactics.reset()
 b.last_actor=null
 b.last_team=1
 b.last_kind=3
 b.samples=[{"at":Vector3(1,1.3,5),"v":Vector3(0,-2,14),"time":0.4}]
 b.tactics.choose_receivers()
 check(b.receivers[0]==defender.bot_id,"Well-positioned Libero takes the difficult service reception")
 b.tactics.reset()
 defender.position=Vector3(-5,0.02,8)
 b.samples=[{"at":Vector3(2.8,1.3,3.8),"v":Vector3.DOWN*2,"time":0.25}]
 b.tactics.choose_receivers()
 check(b.receivers[0]==opposite.bot_id,"Libero yields to a better-positioned teammate rather than chasing every ball")
 b.last_team=0
 b.touches=1
 b.last_actor=defender
 b.last_touch_time=11
 b.tactics.reset()
 var plan:=b.tactics.pass_plan(setter,0)
 check(not plan.is_empty() and plan.recipient!=defender,"Second-touch plans choose a real attacker instead of the Libero")
 var run_options: Dictionary=b.tactics.runs[0]
 check(not run_options.has(defender.get_instance_id()),"Libero stays out of attacking approach lanes")
 middle.strict_positions=true
 middle.rotation_slot=5
 b.tactics.runs.clear()
 b.tactics.prepare_runs(setter)
 var rear_target:=b.tactics.pass_point(middle,setter,true)
 check(rear_target.z>=3.35,"Back-row attack targets preserve a legal take-off behind the attack line")
 check(b.tactics.block_plan(middle).is_empty() and b.tactics.block_plan(defender).is_empty(),"Back-row players and Liberos are not allocated illegal blocks")
 check(VolleyRoles.base(outside,true).x<0 and VolleyRoles.base(opposite,true).x>0,"Outside and opposite hitters prepare on their respective edges")
 check(VolleyRoles.base(defender,false).z>5.5,"Libero's role base remains on the rear defensive line")
 var expected_roles := {"hinata":"MB","kageyama":"S","oikawa":"S","yu_nishinoya":"L"}
 for id in expected_roles:
  check(VolleyRoles.default_role(id)==expected_roles[id],"Catalog primary role: "+id)
 var prior: String=VolleyCharacterDatabase.catalog.kageyama.role
 VolleyCharacterDatabase.catalog.kageyama.role="OP"
 setter.set_character("kageyama")
 check(setter.volley_role=="OP" and b.role_for(setter)=="opposite","The shared controller adopts new catalog roles without a hero-specific AI rewrite")
 VolleyCharacterDatabase.catalog.kageyama.role=prior
 setter.set_character("kageyama")
 b.tactics.reset()
 b.solo_match=true
 b.last_team=-1
 b.round_wait=-1
 check(b.tactics.state_for(setter)==VolleyRoles.State.PRE_SERVE,"PRE_SERVE tactical state")
 setter.is_server=true
 check(b.tactics.state_for(setter)==VolleyRoles.State.SERVE,"SERVE tactical state")
 setter.is_server=false
 b.last_team=1
 b.last_kind=3
 b.receivers[0]=setter.bot_id
 check(b.tactics.state_for(setter)==VolleyRoles.State.RECEIVE,"RECEIVE tactical state")
 b.last_kind=2
 check(b.tactics.state_for(setter)==VolleyRoles.State.DEFENSE,"DEFENSE tactical state")
 b.last_team=0
 b.touches=1
 check(b.tactics.state_for(setter)==VolleyRoles.State.SETUP,"SETUP tactical state")
 b.touches=2
 check(b.tactics.state_for(setter)==VolleyRoles.State.ATTACK,"ATTACK tactical state")
 setter.state="block"
 check(b.tactics.state_for(setter)==VolleyRoles.State.BLOCK,"BLOCK tactical state")
 setter.state="cover"
 b.receivers[0]=0
 check(b.tactics.state_for(setter)==VolleyRoles.State.COVER,"COVER tactical state")
 setter.volley_role="OP"
 b.touches=1
 b.tactics.runs[0]={setter.get_instance_id():{"target":Vector3(2,3,3.8)}}
 check(b.tactics.state_for(setter)==VolleyRoles.State.TRANSITION,"TRANSITION tactical state")
 b.round_wait=2
 game.formation.rallies_completed=1
 check(b.tactics.state_for(setter)==VolleyRoles.State.ROTATION,"ROTATION tactical state")
 game.formation.set_benched(setter,true)
 check(b.tactics.state_for(setter)==VolleyRoles.State.BENCH,"BENCH tactical state")
 game.action_owner="primary"
 game.hud.fingers[99]="primary"
 game.hud.role_owners.primary=99
 game.formation.set_benched(game.athlete,true)
 check(game.action_owner.is_empty() and game.hud.fingers.is_empty() and game.hud.role_owners.is_empty(),"Bench substitutions clear held input owners instead of reintroducing permanent attack locks")
 game.formation.set_benched(game.athlete,false)
 var a: ContextAthlete=game.athlete
 a.formation_revision=12
 var pose: Array=game.lan.pack_actor(a,1)
 pose[48]=11
 pose[44]=true
 pose[1]=Vector3(7,4,7)
 var position_before:=a.position
 game.lan.apply_actor_pose(a,pose,0,1)
 check(not a.benched and a.position==position_before,"A stale network snapshot cannot undo a newer substitution or teleport the player")
 game.queue_free()
 await process_frame
 print("ROLE TACTICS PASSED (%d checks)" % checks if failures==0 else "ROLE TACTICS FAILED (%d)" % failures)
 quit(0 if failures==0 else 1)
