class_name VolleyLiberoManager
extends RefCounted

var formation: VolleyFormation
var designated: Array = [null,null]
var replaced: Array = [null,null]
var last_change := [-1,-1]
var history: Array = []

func reset() -> void:
 designated = [null,null]
 replaced = [null,null]
 last_change = [-1,-1]
 history.clear()
 for a: ContextAthlete in formation.all_actors():
  if a.designated_libero and a.court_team in [0,1]:
   designated[a.court_team] = a

func prepare(team: int, serving_team: int, automatic := true) -> void:
 var libero: Variant = designated[team]
 if not is_instance_valid(libero):
  return
 if not formation.enabled:
  formation.set_benched(libero,formation.lineups[team].size()>=6)
  return
 var regular: Variant = replaced[team]
 if is_instance_valid(regular):
  var must_leave: bool = regular.rotation_slot in [2,3,4] or (regular.rotation_slot==1 and serving_team==team)
  if must_leave:
   leave(team)
  else:
   libero.rotation_slot = regular.rotation_slot
  return
 formation.set_benched(libero,true)
 if not automatic or last_change[team] >= formation.rallies_completed:
  return
 var options: Array = formation.lineups[team].filter(func(a: ContextAthlete): return a.rotation_slot in [1,5,6] and not (a.rotation_slot==1 and serving_team==team))
 options.sort_custom(func(a: ContextAthlete,b: ContextAthlete):
  var priority := {"MB":0,"OH":1,"OP":2,"S":3}
  if priority.get(a.volley_role,4)!=priority.get(b.volley_role,4):
   return priority.get(a.volley_role,4)<priority.get(b.volley_role,4)
  return a.style_stats.n("bump") < b.style_stats.n("bump"))
 if not options.is_empty():
  enter(team,options[0])

func enter(team: int, regular: ContextAthlete) -> bool:
 var libero: Variant = designated[team]
 if not formation.enabled or formation.rally_live() or formation.service_authorized or not is_instance_valid(libero) or is_instance_valid(replaced[team]) or regular not in formation.lineups[team] or regular.rotation_slot not in [1,5,6] or (regular.rotation_slot==1 and formation.serving_team()==team) or last_change[team]>=formation.rallies_completed:
  return false
 replaced[team] = regular
 formation.set_benched(regular,true)
 formation.set_benched(libero,false)
 libero.rotation_slot = regular.rotation_slot
 last_change[team] = formation.rallies_completed
 history.append({"team":team,"enter":true,"regular":formation.actor_id(regular),"rally":formation.rallies_completed})
 formation.revision += 1
 return true

func leave(team: int) -> bool:
 var libero: Variant = designated[team]
 var regular: Variant = replaced[team]
 if formation.rally_live() or formation.service_authorized or not is_instance_valid(libero) or not is_instance_valid(regular) or last_change[team]>=formation.rallies_completed:
  return false
 formation.set_benched(libero,true)
 formation.set_benched(regular,false)
 replaced[team] = null
 last_change[team] = formation.rallies_completed
 history.append({"team":team,"enter":false,"regular":formation.actor_id(regular),"rally":formation.rallies_completed})
 formation.revision += 1
 return true

func request_return(actor: ContextAthlete) -> bool:
 var team := actor.court_team
 if not formation.authority() or team not in [0,1] or formation.rally_live() or formation.service_authorized:
  return false
 if formation.game.lan.active and not formation.game.lan.match_active and actor.designated_libero and actor.benched:
  # An off-court human explicitly confirms their side without becoming
  # a seventh active player or losing control of their own character.
  actor.position = Vector3(6.7,0.02,(1 if team==0 else -1)*4.8)
  formation.broadcast()
  return true
 var changed := false
 if actor == designated[team]:
  prepare(team,formation.serving_team(),true)
  changed = not actor.benched
 elif actor == replaced[team]:
  changed = leave(team)
 if changed:
  formation.place(team)
  formation.broadcast()
 return changed
