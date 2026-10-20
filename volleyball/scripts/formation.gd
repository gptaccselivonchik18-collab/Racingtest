class_name VolleyFormation
extends Node

var game: Node3D
var lineups: Array = [[],[]]
var libero := VolleyLiberoManager.new()
var enabled := false
var revision := 0
var rallies_completed := 0
var pending_attack: Dictionary = {}
var front_libero_set := -1
var service_authorized := false
var error := ""
const NEXT := {1:6,6:5,5:4,4:3,3:2,2:1}
const POSITIONS := {1:Vector2(2.7,6.2),2:Vector2(2.7,2.1),3:Vector2(0,2.1),4:Vector2(-2.7,2.1),5:Vector2(-2.7,6.2),6:Vector2(0,6.2)}

func _ready() -> void:
 libero.formation = self

func authority() -> bool:
 return not game.lan.active or game.lan.hosting

func all_actors() -> Array:
 return game.characters.actors()

func actor_id(a: ContextAthlete) -> int:
 return game.lan.player_id(a) if game.lan.active or a is VolleyGameBot else 0

func find_actor(id: int) -> ContextAthlete:
 for a: ContextAthlete in all_actors():
  if actor_id(a) == id:
   return a
 return null

func serving_team() -> int:
 return game.lan.serve_team if game.lan.match_active else game.game_bots.serve_team

func rally_live() -> bool:
 return game.lan.round_live if game.lan.match_active else game.game_bots.solo_match and game.game_bots.last_team>=0 and game.game_bots.round_wait<0

func capture() -> void:
 lineups = [[],[]]
 for a: ContextAthlete in all_actors():
  if a.court_team in [0,1] and not a.designated_libero:
   lineups[a.court_team].append(a)
 for team in range(2):
  lineups[team].sort_custom(func(a: ContextAthlete,b: ContextAthlete):
   if a.lineup_index>=0 and b.lineup_index>=0 and a.lineup_index!=b.lineup_index:
    return a.lineup_index<b.lineup_index
   return actor_id(a)>actor_id(b))
  var used: Array = []
  for index in range(lineups[team].size()):
   var a: ContextAthlete = lineups[team][index]
   if a.starting_rotation_slot not in range(1,7) or a.starting_rotation_slot in used:
    for candidate in range(1,7):
     if candidate not in used:
      a.starting_rotation_slot = candidate
      break
   used.append(a.starting_rotation_slot)
   a.rotation_slot = a.starting_rotation_slot
 enabled = game.game_bots.is_match() and lineups[0].size()==6 and lineups[1].size()==6 and lineups[0].all(func(a):return a.volley_role!="L") and lineups[1].all(func(a):return a.volley_role!="L")
 for a: ContextAthlete in all_actors():
  a.strict_positions = enabled
  set_benched(a,false)
 libero.reset()
 for team in range(2):
  if is_instance_valid(libero.designated[team]):
   set_benched(libero.designated[team],lineups[team].size()>=6)

func validate_lineups() -> bool:
 error = ""
 var regulars: Array = [[],[]]
 var totals := [0,0]
 for team in range(2):
  regulars[team] = all_actors().filter(func(a):return a.court_team==team and not a.designated_libero)
  totals[team] = mini(6,regulars[team].size()+all_actors().filter(func(a):return a.court_team==team and a.designated_libero).size())
  if totals[team]>0 and not regulars[team].any(func(a):return a.volley_role!="L"):
   error = "Либеро не подаёт. Добавьте обычного игрока или выберите свободную тренировку."
   return false
 if totals[0]!=6 or totals[1]!=6:
  return true
 for team in range(2):
  var players: Array = regulars[team]
  if players.size()!=6 or players.any(func(a):return a.volley_role=="L"):
   error = "Для полного состава нужны 6 обычных игроков. Назначьте либеро отдельно в расстановке."
   return false
 return true

func begin_match() -> void:
 service_authorized = false
 rallies_completed = 0
 capture()
 if enabled:
  for team in range(2):
   var offset: int = int(game.characters.lineup_settings.get("initial",[0,0])[team])
   for turn in range(offset):
    for a: ContextAthlete in lineups[team]:
     a.rotation_slot = NEXT[a.rotation_slot]
 revision += 1

func finish_match() -> void:
 service_authorized = false
 enabled = false
 pending_attack.clear()
 front_libero_set = -1
 capture()
 broadcast()

func complete_rally(winner: int, previous: int) -> void:
 rallies_completed += 1
 if enabled and winner!=previous:
  for a: ContextAthlete in lineups[winner]:
   a.rotation_slot = NEXT[a.rotation_slot]
 pending_attack.clear()
 front_libero_set = -1
 revision += 1

func authorize_server(a: ContextAthlete) -> void:
 if game.game_bots.is_match() and VolleyRules.in_service_zone(a.service_origin()):
  service_authorized = true

func slot_position(team: int, slot: int) -> Vector3:
 var at: Vector2 = POSITIONS.get(slot,Vector2(0,6.2))
 var side := 1.0 if team==0 else -1.0
 return Vector3(at.x*side,0.02,at.y*side)

func set_benched(a: ContextAthlete, on: bool) -> void:
 var changed := a.benched != on
 if changed:
  a.cancel_input()
  a.action = VolleyAthlete.Action.IDLE
  a.reset_dive()
  a.finish_service_attempt()
  a.velocity = Vector3.ZERO
  a.move_axis = Vector2.ZERO
  if a==game.athlete:
   game.action_owner = ""
   if is_instance_valid(game.hud):
    game.hud.clear_pointer_state()
  if game.lan.active:
   game.lan.owners[game.lan.player_id(a)] = ""
 a.benched = on
 a.collision_layer = 0 if on else 2
 if on:
  if changed:
   a.position = Vector3(6.8,0.02,(1 if a.court_team==0 else -1)*6.0)
  a.tactical_state = VolleyRoles.State.BENCH

func prepare(team: int) -> void:
 if not enabled:
  return
 libero.prepare(team,serving_team(),bool(game.characters.lineup_settings.get("auto",[true,true])[team]))
 place(team)

func place(team: int) -> void:
 if not enabled:
  return
 for a: ContextAthlete in all_actors():
  if a.court_team!=team or a.benched:
   continue
  a.position = slot_position(team,a.rotation_slot)
  a.velocity = Vector3.ZERO
  a.last_ground_feet = [a.position+Vector3(-0.16,0,0),a.position+Vector3(0.16,0,0)]
  a.tactical_state = VolleyRoles.State.PRE_SERVE

func server(team: int) -> ContextAthlete:
 for a: ContextAthlete in lineups[team]:
  if a.rotation_slot==1 and not a.benched and VolleyRoles.can_serve(a):
   return a
 return null

func active_at(team: int, slot: int) -> ContextAthlete:
 for a: ContextAthlete in all_actors():
  if a.court_team==team and not a.benched and a.rotation_slot==slot:
   return a
 return null

func feet_bounds(a: ContextAthlete) -> Rect2:
 var side := 1.0 if a.court_team==0 else -1.0
 var points: Array = a.last_ground_feet
 if points.is_empty():
  points = [a.position+Vector3(-0.16,0,0),a.position+Vector3(0.16,0,0)]
 var result := Rect2(Vector2(points[0].x*side,points[0].z*side),Vector2.ZERO)
 for point: Vector3 in points:
  result = result.expand(Vector2(point.x*side,point.z*side))
 return result

func receiving_order(team: int) -> bool:
 if not enabled:
  return true
 var bounds := {}
 for slot in range(1,7):
  var a := active_at(team,slot)
  if not is_instance_valid(a):
   return false
  bounds[slot] = feet_bounds(a)
  if not feet_in_court(bounds[slot]):
   return false
 for pair in [[5,4],[6,3],[1,2]]:
  if bounds[pair[0]].end.y+0.025 < bounds[pair[1]].position.y:
   return false
 for row in [[4,3,2],[5,6,1]]:
  if bounds[row[0]].position.x > bounds[row[1]].end.x+0.025 or bounds[row[2]].end.x+0.025 < bounds[row[1]].position.x:
   return false
 return true

func feet_in_court(bounds: Rect2) -> bool:
 return bounds.position.x>=-4.65 and bounds.end.x<=4.65 and bounds.position.y>=-0.10 and bounds.end.y<=9.15

func serving_positions(team: int, player: ContextAthlete) -> bool:
 for a: ContextAthlete in all_actors():
  if a.court_team==team and a!=player and not a.benched and not feet_in_court(feet_bounds(a)):
   return false
 return true

func penalize(team: int, message: String) -> void:
 if not authority() or game.rules.ended:
  return
 game.rules.fault(message)
 if game.lan.match_active:
  game.lan.award(1-team)
 elif game.game_bots.solo_match:
  game.game_bots.award(1-team)

func note_contact(a: ContextAthlete, kind: int, at: Vector3, outgoing: Vector3) -> void:
 if not authority() or not game.game_bots.is_match():
  return
 if not pending_attack.is_empty() and a.court_team!=int(pending_attack.team):
  penalize(int(pending_attack.team),str(pending_attack.reason))
 pending_attack.clear()
 if kind in [VolleyAthlete.Technique.SERVE,VolleyAthlete.Technique.JUMP_SERVE]:
  if a.volley_role=="L":
   penalize(a.court_team,"Либеро не подаёт")
  elif enabled and not receiving_order(1-a.court_team):
   penalize(1-a.court_team,"Ошибка расстановки принимающей команды")
  elif enabled and not serving_positions(a.court_team,a):
   penalize(a.court_team,"Игрок подающей команды вне собственной площадки")
  front_libero_set = -1
  return
 if kind==ContextAthlete.BLOCK:
  if not VolleyRoles.can_block(a):
   penalize(a.court_team,"Недопустимый блок либеро или игрока задней линии")
  return
 var high := at.y-VolleyBall.RADIUS>2.43
 var reason := ""
 if high and a.volley_role=="L":
  reason = "Либеро завершил атаку выше сетки"
 elif enabled and high and a.rotation_slot in [1,5,6] and absf(a.jump_origin.z if a.jump_in_progress or a.airborne() else a.position.z)<3.0:
  reason = "Атака задней линии после отталкивания в передней зоне"
 elif high and front_libero_set==a.court_team:
  reason = "Атака выше сетки после передачи либеро из передней зоны"
 if not reason.is_empty():
  pending_attack = {"team":a.court_team,"reason":reason,"from":at,"outgoing":outgoing}
 front_libero_set = a.court_team if a.volley_role=="L" and kind in [VolleyAthlete.Technique.OVERHEAD,ContextAthlete.JUMP_SET] and absf(a.jump_origin.z if a.jump_in_progress else a.position.z)<3.0 else -1

func crossing(from: Vector3, to: Vector3) -> void:
 if pending_attack.is_empty() or from.z*to.z>=0:
  return
 var side := 1.0 if int(pending_attack.team)==0 else -1.0
 if from.z*side>=0 and to.z*side<0:
  penalize(int(pending_attack.team),str(pending_attack.reason))
  pending_attack.clear()

func state() -> Dictionary:
 var entries: Array = []
 for a: ContextAthlete in all_actors():
  a.formation_revision = revision
  entries.append([actor_id(a),a.court_team,a.volley_role,a.rotation_slot,a.benched,a.designated_libero,a.lineup_index,a.strict_positions,a.starting_rotation_slot,a.position])
 var replacements := []
 for team in range(2):
  replacements.append(actor_id(libero.replaced[team]) if is_instance_valid(libero.replaced[team]) else 999999)
 return {"revision":revision,"enabled":enabled,"authorized":service_authorized,"rallies":rallies_completed,"actors":entries,"replaced":replacements,"last_change":libero.last_change.duplicate()}

func accept_state(value: Dictionary) -> void:
 if authority() or int(value.get("revision",-1))<revision:
  return
 revision = int(value.revision)
 enabled = bool(value.enabled)
 service_authorized = bool(value.get("authorized",false))
 rallies_completed = int(value.rallies)
 lineups = [[],[]]
 libero.reset()
 for row in value.actors:
  var a := find_actor(int(row[0]))
  if not is_instance_valid(a):
   continue
  var was_benched := a.benched
  a.court_team = int(row[1])
  a.volley_role = str(row[2])
  a.rotation_slot = int(row[3])
  a.designated_libero = bool(row[5])
  a.lineup_index = int(row[6])
  a.strict_positions = bool(row[7])
  a.starting_rotation_slot = int(row[8])
  a.formation_revision = revision
  set_benched(a,bool(row[4]))
  if was_benched!=a.benched:
   a.position = row[9]
   a.network_motion.reset()
  if a.court_team in [0,1]:
   if a.designated_libero:
    libero.designated[a.court_team] = a
   else:
    lineups[a.court_team].append(a)
 for team in range(2):
  libero.replaced[team] = find_actor(int(value.replaced[team]))
 libero.last_change = value.last_change.duplicate()

func broadcast() -> void:
 if game.lan.active and game.lan.hosting:
  game.lan.send_game_bots()
 game.lan.refresh_contacts()
