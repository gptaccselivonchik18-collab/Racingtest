extends SceneTree
var game: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
 checks+=1
 if not ok:
  failures+=1
  push_error(text)
 print("PASS: " if ok else "FAIL: ",text)

func roster(human_libero := false) -> Array:
 var value: Array=game.characters.default_teams()
 var roles := ["S","OP","MB","OH","MB","OH"]
 for t in range(2):
  for s in range(6):
   value[t][s]={"kind":"human" if t==0 and s==0 and not human_libero else "bot","human":0,"character":"hinata" if roles[s]=="MB" else "kageyama","role":roles[s],"rotation":s+1}
 return value

func run() -> void:
 game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.set_physics_process(false)
 game.characters.set_physics_process(false)
 game.game_bots.set_physics_process(false)
 var cm: VolleyCharacters=game.characters
 var config:=cm.default_lineup_settings()
 for t in range(2):config.liberos[t]={"kind":"bot","character":"yu_nishinoya","human":0}
 check(cm.apply_teams(roster(),2,false,config),"Six ordinary rotation places plus a separately designated libero are valid")
 check(cm.actors().size()==14,"Two bench players do not consume one of the twelve active places")
 check(game.game_bots.start_solo() and game.formation.enabled,"A full scored match enables classical six-position rules")
 var f: VolleyFormation=game.formation
 for a: ContextAthlete in cm.actors():a.set_physics_process(false)
 check(f.lineups[0].size()==6 and f.lineups[1].size()==6,"Liberos never become seventh rotation slots")
 check(game.game_bots.members(0).size()==6 and game.game_bots.members(1).size()==6,"Exactly six active players per court side")
 check(f.libero.replaced[0].volley_role=="MB" and f.libero.replaced[1].volley_role=="MB","Back-row middle blockers have substitution priority")
 check(f.receiving_order(0) and f.receiving_order(1),"Both initial layouts satisfy foot-based relative positions")
 check(not f.libero.enter(0,f.lineups[0][0]) and not f.libero.leave(0),"No front-row entry or second replacement in the same interruption")
 for point in range(120):
  var previous: int=game.game_bots.serve_team
  var winner: int=previous if point%3==0 else 1-previous
  var old: Array=f.lineups[winner].map(func(a):return a.rotation_slot)
  game.game_bots.advance_service(winner,previous)
  game.game_bots.serve_team=winner
  game.game_bots.reset_round()
  var correct:=true
  for i in range(6):
   var expected: int=old[i] if winner==previous else f.NEXT[old[i]]
   correct=correct and f.lineups[winner][i].rotation_slot==expected
  check(correct,"Clockwise rotation only on side-out, point %d" % point)
  var valid:=true
  for t in range(2):
   valid=valid and game.game_bots.members(t).size()==6 and f.receiving_order(t)
   var defender: ContextAthlete=f.libero.designated[t]
   valid=valid and (defender.benched or defender.rotation_slot in [1,5,6])
  check(valid and game.game_bots.current_server.rotation_slot==1 and game.game_bots.current_server.volley_role!="L","Twelve active actors, legal receivers and ordinary position-one server (%d)" % point)
 var last := [-1,-1]
 var history_ok:=true
 for entry in f.libero.history:
  history_ok=history_ok and int(entry.rally)>int(last[entry.team])
  last[entry.team]=entry.rally
 check(history_ok and f.libero.history.size()>20,"Every Libero replacement has at least one completed rally between it and the previous change")
 var back: ContextAthlete=f.lineups[0].filter(func(a):return not a.benched and a.rotation_slot in [1,5,6])[0]
 back.action=VolleyAthlete.Action.IDLE
 check(not back.begin_action(ContextAthlete.BLOCK),"Back-row humans and bots cannot initiate an illegal block")
 var libero: ContextAthlete=f.libero.designated[0]
 libero.action=VolleyAthlete.Action.IDLE
 check(not libero.begin_action(3) and not libero.begin_action(ContextAthlete.BLOCK),"Libero serving and attempted blocking are rejected")
 game.game_bots.round_wait=-1
 game.game_bots.last_team=0
 back.jump_in_progress=true
 back.jump_origin=Vector3(0,0.02,2.5)
 game.rules.reset()
 game.rules.strict=true
 f.note_contact(back,2,Vector3(0,3.1,1.5),Vector3(0,0,-20))
 check(not f.pending_attack.is_empty() and not game.rules.ended,"A high illegal attack is pending until it is completed")
 f.note_contact(f.lineups[0][0],1,Vector3(0,1.4,1.0),Vector3.UP*8)
 check(f.pending_attack.is_empty() and not game.rules.ended,"A high pass intercepted by a teammate is not incorrectly called a completed attack")
 f.note_contact(back,2,Vector3(0,3.1,1.5),Vector3(0,0,-20))
 var old_score: int=game.game_bots.scores[1]
 f.crossing(Vector3(0,3.1,0.1),Vector3(0,3.1,-0.1))
 check(game.rules.ended and game.game_bots.scores[1]==old_score+1,"A completed illegal back-row attack awards exactly one opponent point")
 game.game_bots.round_wait=-1
 game.game_bots.last_team=0
 game.rules.reset()
 back.jump_origin=Vector3(0,0.02,3.4)
 f.note_contact(back,2,Vector3(0,3.1,1.5),Vector3(0,0,-20))
 check(f.pending_attack.is_empty(),"A back-row attacker may jump from behind the three-metre line and land in front")
 game.rules.reset()
 libero.position=Vector3(0,0.02,1.5)
 libero.jump_in_progress=false
 f.note_contact(libero,0,Vector3(0,2.0,1.5),Vector3(0,8,2))
 var hitter: ContextAthlete=f.lineups[0][0]
 hitter.rotation_slot=3
 hitter.jump_in_progress=true
 hitter.jump_origin=Vector3(0,0,1.5)
 f.note_contact(hitter,2,Vector3(0,3.2,1.5),Vector3(0,0,-20))
 check(not f.pending_attack.is_empty() and str(f.pending_attack.reason).contains("либеро"),"Front-zone Libero finger set restricts the following completed high attack")
 f.pending_attack.clear()
 libero.position=Vector3(0,0.02,6)
 libero.jump_in_progress=false
 game.rules.reset()
 f.note_contact(libero,0,Vector3(0,2.0,6),Vector3.UP*8)
 f.note_contact(hitter,2,Vector3(0,3.2,1.5),Vector3(0,0,-20))
 check(f.pending_attack.is_empty(),"An overhead Libero set from the rear zone may be freely attacked")
 game.game_bots.serve_team=0
 f.begin_match()
 game.game_bots.reset_round()
 var left_front := f.active_at(1,4)
 var left_back := f.active_at(1,5)
 var front_feet := left_front.last_ground_feet.duplicate()
 var back_feet := left_back.last_ground_feet.duplicate()
 var old_position := left_back.position
 left_back.position=Vector3(3,2,-0.4)
 check(f.receiving_order(1),"Airborne torso movement does not replace the receiving player's last grounded feet")
 left_back.position=old_position
 left_front.last_ground_feet=back_feet
 left_back.last_ground_feet=front_feet
 check(not f.receiving_order(1),"Crossed front/back feet correctly violate the receiving lineup")
 game.game_bots.round_wait=-1
 game.rules.reset()
 var before_fault: int=game.game_bots.scores[0]
 f.note_contact(game.game_bots.current_server,3,Vector3(0,2,9.7),Vector3(0,7,-12))
 check(game.rules.ended and game.game_bots.scores[0]==before_fault+1,"Receiving overlap at the real service event awards the serving team one point")
 game.game_bots.reset_round()
 var serving_front := f.active_at(0,4)
 var serving_back := f.active_at(0,5)
 front_feet=serving_front.last_ground_feet.duplicate()
 serving_front.last_ground_feet=serving_back.last_ground_feet.duplicate()
 serving_back.last_ground_feet=front_feet
 game.rules.reset()
 f.note_contact(game.game_bots.current_server,3,Vector3(0,2,9.7),Vector3(0,7,-12))
 check(not game.rules.ended,"FIVB 2025 serving-side freedom does not incorrectly call a receiving-overlap fault")
 var incomplete:=cm.default_teams()
 incomplete[0][1]={"kind":"bot","human":0,"character":"hinata"}
 incomplete[0][2]={"kind":"bot","human":0,"character":"yu_nishinoya"}
 incomplete[1][0]={"kind":"bot","human":0,"character":"kageyama"}
 check(cm.apply_teams(incomplete,1,false) and game.game_bots.start_solo() and not f.enabled,"Kageyama + Hinata + Nishinoya keeps incomplete training without artificial six-slot rotations")
 var saved_slot: int=game.athlete.rotation_slot
 game.game_bots.advance_service(1,0)
 check(game.athlete.rotation_slot==saved_slot,"Incomplete teams do not perform classical rotation")
 config=cm.default_lineup_settings()
 config.auto=[false,true]
 config.liberos[0]={"kind":"human","character":"yu_nishinoya","human":0}
 config.liberos[1]={"kind":"bot","character":"yu_nishinoya","human":0}
 check(cm.apply_teams(roster(true),1,false,config) and game.game_bots.start_solo(),"A human can be designated Libero outside the six regular positions")
 var controlled: ContextAthlete=game.athlete
 check(controlled.benched and controlled.character_id=="yu_nishinoya","A benched human keeps their own Nishinoya actor")
 game.hud._refresh_context()
 check(game.hud.buttons.context.visible and not game.hud.buttons.primary.visible,"Bench HUD provides a return control without active attack buttons")
 check(f.libero.request_return(controlled) and game.athlete==controlled and not controlled.benched and game.game_bots.members(0).size()==6,"Manual legal return preserves human control and the six-player limit")
 var bytes:=var_to_bytes([game.lan.pack_actor(controlled,1),game.lan.pack_actor(f.lineups[1][0],2)]).size()
 print("TWO_POSE_BYTES=",bytes)
 check(bytes<1350,"Two role/rotation snapshots still fit an ENet MTU before small ball fields")
 var saved: Dictionary=JSON.parse_string(JSON.stringify({"teams":cm.teams,"lineup":cm.lineup_settings}))
 cm.normalize_saved(saved)
 check(cm.valid_teams(saved.teams) and cm.valid_lineup_settings(saved.lineup,saved.teams),"Actual JSON round-trip restores integer player IDs, rotation slots and Libero settings")
 var malformed: Dictionary=saved.duplicate(true)
 malformed.teams[0][0].human=1.5
 cm.normalize_saved(malformed)
 check(not cm.valid_teams(malformed.teams),"Save migration never silently rounds a malformed fractional player identity")
 var bench_regular: ContextAthlete=f.libero.replaced[0]
 f.rallies_completed+=1
 f.service_authorized=true
 check(not f.libero.leave(0) and not f.libero.request_return(bench_regular),"Libero replacements close once service is authorized, before physical contact")
 f.service_authorized=false
 game.queue_free()
 await process_frame
 print("FORMATIONS PASSED (%d checks)" % checks if failures==0 else "FORMATIONS FAILED (%d)" % failures)
 quit(0 if failures==0 else 1)
