class_name VolleyCharacters
extends Node

const SAVE := "user://characters.json"
const LEVELS := [0, 2, 4]
var game: Node3D
var selected := "kageyama"
var teams: Array = []
var difficulty := 1
var demo := false
var demo_wait := 0.0
var jump_events: Dictionary = {}
var registered: Dictionary = {}
var ai_wait: Dictionary = {}
var quick_runs: Dictionary = {}
var quick_launches := 0
var last_special_contact := ""
var ui: VolleyCharacterSelection

func _ready() -> void:
 name = "Characters"
 process_priority = -20
 process_physics_priority = -20
 teams = default_teams()
 if FileAccess.file_exists(SAVE):
  var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
  if data is Dictionary:
   if VolleyCharacterDatabase.valid(str(data.get("selected", ""))):
    selected = data.selected
   if valid_teams(data.get("teams", [])):
    teams = data.teams
   difficulty = clampi(int(data.get("difficulty", 1)), 0, 2)
 game.athlete.set_character(selected)
 register(game.athlete)
 ui = VolleyCharacterSelection.new()
 ui.manager = self
 add_child(ui)

func default_teams() -> Array:
 var result: Array = []
 for team in range(2):
  var slots: Array = []
  for slot in range(6):
   slots.append({"kind": "human" if team == 0 and slot == 0 else "empty", "character": "kageyama", "human": 0})
  result.append(slots)
 return result

func save() -> void:
 var file := FileAccess.open(SAVE, FileAccess.WRITE)
 if file:
  file.store_string(JSON.stringify({"selected": selected, "teams": teams, "difficulty": difficulty}))

func authority() -> bool:
 return not game.lan.active or game.lan.hosting

func actors() -> Array:
 var result: Array = game.lan.players.values().map(func(p: Dictionary): return p.actor) if game.lan.active else [game.athlete]
 result.append_array(game.game_bots.bots.values())
 return result

func register(a: ContextAthlete) -> void:
 if registered.has(a.get_instance_id()):
  return
 registered[a.get_instance_id()] = weakref(a)
 a.ability_solver = solve_special
 a.jump_started.connect(func(player: ContextAthlete): jump_events[player.instance_uid] = game.game_bots.clock)

func same_team(a: ContextAthlete, b: ContextAthlete) -> bool:
 return a != b and a.court_team >= 0 and a.court_team == b.court_team

func partners(a: ContextAthlete, airborne_only := true) -> Array:
 if a.character_id != "kageyama":
  return []
 return actors().filter(func(b): return is_instance_valid(b) and same_team(a, b) and b.character_id == "hinata" and (not airborne_only or (b.jump_in_progress and b.airborne())))

func choose_local(id: String) -> bool:
 if not VolleyCharacterDatabase.valid(id):
  return false
 selected = id
 var owner: int = game.lan.multiplayer.get_unique_id() if game.lan.active else 0
 for team in teams:
  for slot in team:
   if slot.kind == "human" and slot.human in [0, owner]:
    slot.character = id
 save()
 if game.lan.active and not game.lan.hosting:
  select_character.rpc_id(1, id)
  return true
 game.athlete.set_character(id)
 if game.lan.active:
  game.lan._broadcast_roster()
 return true

@rpc("any_peer", "call_remote", "reliable", 4)
func select_character(id: String) -> void:
 var sender := multiplayer.get_remote_sender_id()
 if not game.lan.active or not game.lan.hosting or not game.lan.players.has(sender) or not VolleyCharacterDatabase.valid(id):
  return
 if game.lan.match_active and game.lan.round_live:
  return
 game.lan.players[sender].actor.set_character(id)
 game.lan._broadcast_roster()

func valid_teams(value: Variant) -> bool:
 if not value is Array or value.size() != 2:
  return false
 var humans: Array = []
 for team in value:
  if not team is Array or team.size() != 6:
   return false
  for slot in team:
   if not slot is Dictionary or slot.get("kind", "") not in ["empty", "human", "bot"] or not VolleyCharacterDatabase.valid(str(slot.get("character", ""))) or not slot.get("human", -1) is int:
    return false
   if slot.kind == "human":
    if slot.human in humans:
     return false
    humans.append(slot.human)
 return true

func apply_teams(value: Array, level: int, persist := true) -> bool:
 if not authority() or not valid_teams(value) or level not in [0, 1, 2]:
  return false
 var local: int = game.lan.multiplayer.get_unique_id() if game.lan.active else 0
 var normalized := value.duplicate(true)
 for team in normalized:
  for slot in team:
   if slot.kind == "human":
    if not game.lan.active and slot.human not in [0, 1]:
     slot.kind = "empty"
    elif slot.human == 0 or not game.lan.active:
     slot.human = local
 if not valid_teams(normalized):
  return false
 if game.lan.active:
  for team in normalized:
   for slot in team:
    if slot.kind == "human" and not game.lan.players.has(slot.human):
     return false
  game.lan.start_free_play()
 elif game.game_bots.solo_match:
  game.game_bots.end_solo()
 teams = normalized
 ai_wait.clear()
 quick_runs.clear()
 jump_events.clear()
 difficulty = level
 var counts := [0, 0]
 var human_team := 0
 for t in range(2):
  for slot in teams[t]:
   if slot.kind == "bot":
    counts[t] += 1
   elif slot.kind == "human" and slot.human == local:
    human_team = t
 game.game_bots.configure({"counts": counts, "human_team": human_team, "difficulty": LEVELS[level]}, false)
 for a: ContextAthlete in actors():
  if not a is VolleyGameBot:
   a.court_team = -1
 for t in range(2):
  var bot_slot := 0
  for s in range(6):
   var slot: Dictionary = teams[t][s]
   var a: ContextAthlete
   if slot.kind == "bot":
    a = game.game_bots.bots[VolleyGameBots.bot_id(t, bot_slot)]
    bot_slot += 1
   elif slot.kind == "human":
    a = game.lan.players[slot.human].actor if game.lan.active else game.athlete
   else:
    continue
   a.set_character(slot.character)
   a.velocity = Vector3.ZERO
   a.jump_in_progress = false
   a.air_swing_used = false
   if slot.kind == "human" and slot.human == local:
    selected = slot.character
   a.court_team = t
   a.instance_uid = "bot:%d:%d" % [t, s] if slot.kind == "bot" else "human:%d" % slot.human
   register(a)
   if not game.lan.active:
    a.position = Vector3((s % 3 - 1) * 2.4, 0.02, (3.0 if s < 3 else 6.0) * (1 if t == 0 else -1))
   elif slot.kind == "human":
    game.lan.players[slot.human].team = t
    game.lan.players[slot.human].slot = s
   a.camera_yaw = 0.0 if t == 0 else PI
   a.visual.rotation = Vector3(0, a.camera_yaw, 0)
   if a == game.athlete:
    game.rig.yaw = a.camera_yaw
    game.rig.rendered_yaw = a.camera_yaw
    game.rig.pitch = 0.08
   elif game.lan.active and slot.kind == "human" and game.lan._peer_ready(slot.human):
    game.lan.orient_player.rpc_id(slot.human, a.camera_yaw)
 if persist:
  save()
 game.lan.refresh_contacts()
 if game.lan.active:
  game.lan.send_game_bots()
  game.lan._broadcast_roster()
 return true

func begin_special(a: ContextAthlete, mode: String) -> bool:
 if not authority() or a.character_id != "kageyama" or mode != "freak" or game.ball.held:
  return false
 var targets := partners(a)
 if mode == "freak" and targets.is_empty():
  return false
 if not a.begin_action(ContextAthlete.JUMP_SET if a.airborne() else VolleyAthlete.Technique.OVERHEAD):
  return false
 a.special_set = mode
 a.last_result = "Freak Quick · отпустите для передачи"
 a.locked_yaw = a.visual.global_rotation.y
 a.special_yaw = a.camera_yaw
 if mode == "freak":
  targets.sort_custom(func(x, y): return x.position.distance_squared_to(a.position) < y.position.distance_squared_to(a.position))
  a.special_recipient = weakref(targets[0])
  var toward: Vector3 = targets[0].position - a.position
  a.special_yaw = atan2(-toward.x, -toward.z)
 return true

func solve_special(a: ContextAthlete, at: Vector3, _quality: float) -> Dictionary:
 if a.resolving_contact:
  last_special_contact = "%s %s at %s" % [a.character_id, a.special_set, at]
 if a.character_id != "kageyama":
  return {}
 if a.special_set != "freak" or a.special_recipient == null:
  return {}
 var recipient: Variant = a.special_recipient.get_ref()
 if not is_instance_valid(recipient) or recipient.character_id != "hinata" or not same_team(a, recipient) or not recipient.airborne():
  a.last_result = "Freak Quick: окно прыжка закрыто"
  if a.resolving_contact:
   last_special_contact += " closed"
  return {}
 var plan := quick_plan(a, recipient, at)
 if plan.is_empty():
  if a.resolving_contact:
   last_special_contact += " unreachable: %s %s" % [recipient.position, recipient.velocity]
  a.last_result = "Freak Quick: траектория недостижима"
  return {}
 if a.resolving_contact and authority():
  game.ball.configure_quick(float(plan.time), recipient)
  quick_launches += 1
 return {"velocity": plan.velocity, "spin": Vector3.ZERO, "direction": Vector3(plan.velocity).normalized()}

func quick_plan(setter: ContextAthlete, recipient: ContextAthlete, at: Vector3) -> Dictionary:
 var duration := clampf(at.distance_to(recipient.position + Vector3.UP * recipient.natural_reach()) / 28.0, 0.18, 0.48)
 var remaining := (recipient.velocity.y + sqrt(maxf(0, recipient.velocity.y * recipient.velocity.y + 19.62 * recipient.position.y))) / 9.81
 if remaining < duration + 0.05:
  return {}
 var root := recipient.position + recipient.velocity * duration + Vector3.DOWN * 4.905 * duration * duration
 var toward := -Basis(Vector3.UP, recipient.visual.global_rotation.y).z
 var destination := root + Vector3.UP * recipient.natural_reach() + toward * (0.38 * recipient.physical_scale)
 if destination.y < 1.0 or destination.y > VolleyCourt.ROOF - 0.4:
  return {}
 var velocity := (destination - at) / duration + Vector3.UP * 4.905 * duration
 # Solve drag before the launch; no target tracking or position correction.
 for iteration in range(4):
  var p := at
  var v := velocity
  var dt := duration / 48.0
  for step in range(48):
   v += (Vector3.DOWN * 9.81 + game.ball.aero_force(v, Vector3.ZERO) / game.ball.mass) * dt
   p += v * dt
  velocity += (destination - p) / duration
 if velocity.length() > 48 or not velocity.is_finite() or not game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at, destination, 1)).is_empty():
  return {}
 # Braking happens at arrival, not a tenth of a second before the target.
 return {"velocity": velocity, "time": duration, "target": destination}

func _physics_process(dt: float) -> void:
 if not is_instance_valid(game.frontend):
  return
 for id in registered.keys():
  if registered[id].get_ref() == null:
   registered.erase(id)
 for a: ContextAthlete in actors():
  register(a)
 if not authority() or not demo or game.frontend.in_home:
  return
 demo_wait -= dt
 if demo_wait > 0:
  return
 var setters := actors().filter(func(a): return a.character_id == "kageyama" and not partners(a, false).is_empty())
 if setters.is_empty():
  demo = false
  return
 var setter: ContextAthlete = setters[0]
 var busy := actors().any(func(a): return a.airborne() or a.action != VolleyAthlete.Action.IDLE)
 if not busy and not game.ball.held:
  # Explicit training feeder between attempts, never a bot's contact action.
  game.ball.feed(setter.position + Vector3(0, setter.natural_reach() + 2.3, -0.25), Vector3.ZERO)
  game.game_bots.reset_rally()
  demo_wait = 3.8

func start_demo() -> void:
 if not authority():
  return
 demo = true
 demo_wait = 0.3

func setter_contact_eta(setter: ContextAthlete) -> float:
 var at: Vector3 = game.ball.position
 var v: Vector3 = game.ball.linear_velocity
 var spin: Vector3 = game.ball.angular_velocity
 var hand_height := setter.position.y+setter.natural_reach()+0.10
 for tick in range(85):
  var time := tick/60.0
  var expected := setter.position+Vector3(setter.velocity.x,0,setter.velocity.z)*minf(time,0.20)
  if v.y <= 0 and at.y <= hand_height+0.18 and at.y >= hand_height-0.55:
   if Vector2(at.x-expected.x,at.z-expected.z).length()<1.65:
    return time
  if at.y < hand_height-0.55 and v.y<0:break
  v += (Vector3.DOWN*9.81+game.ball.aero_force(v,spin)/game.ball.mass)/60.0
  spin *= 1.0-game.ball.angular_damp/60.0
  at += v/60.0
 return INF

func ai_step(bot: VolleyGameBot, dt: float) -> bool:
 if not authority() or game.ball.held or game.ball.pending_feed or bot.action in [VolleyAthlete.Action.STRIKE, VolleyAthlete.Action.RECOVER] or bot.jump_serving or bot.is_server:
  return false
 if demo and bot.airborne() and not bot.jump_in_progress:
  bot.move_axis = Vector2.ZERO
  return true
 var profile: Dictionary = game.game_bots.decision_profile()
 if bot.character_id == "kageyama":
  var targets := partners(bot)
  if not targets.is_empty() and bot.cooldown <= 0:
   var reaction := float(profile.reaction)
   var event := float(jump_events.get(targets[0].instance_uid, game.game_bots.clock))
   var eta := setter_contact_eta(bot)
   var close: bool = is_finite(eta) and eta <= 0.65
   var willingness := 1 + roundi(float(profile.court_read) * 3)
   var opportunity := demo or posmod(int(event * 10) + absi(bot.bot_id), 4) < willingness
   var legal_touch: bool = demo or (game.game_bots.last_team == bot.court_team and game.game_bots.last_actor != bot and game.game_bots.touches < 3)
   if close and opportunity and legal_touch and game.game_bots.clock - event >= reaction:
    if bot.action == VolleyAthlete.Action.PREPARE and bot.special_set.is_empty():
     bot.cancel_input()
     bot.action = VolleyAthlete.Action.IDLE
    if bot.action == VolleyAthlete.Action.IDLE:
     begin_special(bot, "freak")
   if bot.special_set == "freak":
    bot.move_axis = Vector2.ZERO
    bot.planned_kind = bot.technique
    if bot.charged_for >= float(bot.mechanic(0).windup) and bot.contact_due():
     bot.release()
    elif bot.charged_for > 0.7:
     bot.cancel_input()
    return true
  if demo:
   if bot.action == VolleyAthlete.Action.PREPARE:
    bot.cancel_input()
    bot.action = VolleyAthlete.Action.IDLE
   bot.steer(Vector3(-2.4, 0.02, 3.0 * (1 if bot.court_team == 0 else -1)), 0.08)
   return true
 elif bot.character_id == "hinata":
  var setters := actors().filter(func(a): return same_team(bot, a) and a.character_id == "kageyama")
  if setters.is_empty():
   return false
  var setter: ContextAthlete = setters[0]
  var side := 1 if bot.court_team == 0 else -1
  var eta := setter_contact_eta(setter)
  var lead := clampf(0.50+VolleyBotTactics.flat(bot.position,setter.position)/50.0,0.54,0.62)
  var plant := float(bot.style_stats.movement().plant)
  if bot.jump_windup > 0 and ai_wait.has(bot.instance_uid):
   bot.move_axis = Vector2.ZERO
   return true
  if bot.approach_armed and quick_runs.has(bot.instance_uid):
   var run: Dictionary = quick_runs[bot.instance_uid]
   if not is_finite(eta) or eta < 0.16:
    bot.cancel_input()
    quick_runs.erase(bot.instance_uid)
    ai_wait.erase(bot.instance_uid)
    return false
   bot.steer(run.takeoff,0.08)
   var distance := VolleyBotTactics.flat(bot.position,run.takeoff)
   var pace := minf(3.4,distance/maxf(0.12,eta-lead-plant))
   bot.move_axis *= minf(1.0,pace/maxf(0.01,bot.move_axis.length()*bot.effective_speed()))
   bot.camera_yaw = 0 if side > 0 else PI
   if eta <= lead+plant and distance < 0.85:
    bot.launch_approach()
    ai_wait[bot.instance_uid] = 1.5
    quick_runs.erase(bot.instance_uid)
   return true
  if is_finite(eta) and eta >= 0.28 and eta <= 1.15 and not bot.airborne() and bot.can_act() and bot.cooldown <= 0 and (demo or (game.game_bots.last_team == bot.court_team and game.game_bots.touches == 1 and game.game_bots.last_actor != setter)):
   var depth := clampf(bot.position.z*side-0.65,2.6,4.2)
   var takeoff := Vector3(clampf(bot.position.x,-3.3,3.3),0.02,side*depth)
   # Do not promise a rushed quick if the attacker cannot reach the plant.
   var needed := VolleyBotTactics.flat(bot.position,takeoff)/3.4
   if eta < lead+plant+needed:
    takeoff.z = bot.position.z-side*maxf(0,eta-lead-plant)*3.0
    takeoff.z = side*maxf(2.6,takeoff.z*side)
   bot.camera_yaw = 0 if side > 0 else PI
   if bot.arm_approach(VolleyAthlete.Technique.SPIKE):
    quick_runs[bot.instance_uid] = {"takeoff":takeoff,"setter":weakref(setter)}
    ai_wait[bot.instance_uid] = 1.5
    bot.cooldown = 1.2
    return true
  if bot.airborne() and ai_wait.has(bot.instance_uid) and not bot.air_swing_used:
   bot.move_axis = Vector2.ZERO
   ai_wait[bot.instance_uid] -= dt
   if bot.action == VolleyAthlete.Action.IDLE:
    bot.begin_action(VolleyAthlete.Technique.SPIKE)
    bot.planned_kind = VolleyAthlete.Technique.SPIKE
   if bot.action == VolleyAthlete.Action.PREPARE:
    if game.ball.quick_active and game.ball.quick_target != null and game.ball.quick_target.get_ref() == bot and game.ball.quick_age < game.ball.quick_arrival - 0.02:
     return true
    var future: Vector3 = game.ball.position + game.ball.linear_velocity * 0.09 + Vector3.DOWN * 4.905 * 0.09 * 0.09
    var hand := bot.position + bot.velocity * 0.09 + Vector3.UP * bot.natural_reach() - bot.visual.global_basis.z * 0.35
    if future.distance_to(hand) < bot.effective_contact_radius() + 0.35:
     if bot.attack_ready:
      bot.hit_approach()
     else:
      bot.release()
   return true
  if demo and not bot.airborne():
   if bot.action == VolleyAthlete.Action.PREPARE:
    bot.cancel_input()
    bot.action = VolleyAthlete.Action.IDLE
   bot.steer(Vector3(0, 0.02, 4.0 * side), 0.10)
   return true
 return false
