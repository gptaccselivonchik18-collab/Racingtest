class_name VolleyGameBots
extends Node3D

# Deterministic state machines and a shared trajectory predictor; no AI service.
const MAX_PER_TEAM := 6
var game: Node3D
var bots: Dictionary = {}
var counts := [0, 0]
var level := 65.0
var difficulty := 2
var thinking_level := -1
var thinking: Dictionary = {}
var tactics := VolleyBotTactics.new()
var difficulty_picker: OptionButton
var difficulty_hint: Label
var human_team := 0
var solo_match := false
var scores := [0, 0]
var sets := [0, 0]
var match_winner := -1
var serve_team := 0
var serving_turn := [0, -1]
var rotation_turn := [0, 0]
var current_server: ContextAthlete
var round_wait := -1.0
var last_actor: ContextAthlete
var last_team := -1
var touches := 0
var last_kind := -1
var last_touch_time := -10.0
var clock := 0.0
var think_left := 0.0
var samples: Array = []
var receivers := [0, 0]
var receive_dives := [false, false]
var intercepts := [Vector3.ZERO, Vector3.ZERO]
var arrival := [0.0, 0.0]
var contact_heights := [1.35, 1.35]
var ui_controls: Array[Control] = []
var count_labels: Array[Label] = []
var hint: Label

func _ready() -> void:
 name = "GameBots"
 tactics.manager = self
 process_mode = Node.PROCESS_MODE_ALWAYS

func authority() -> bool:
 return not game.lan.active or game.lan.hosting

func decision_profile() -> Dictionary:
 # Covering bots evaluate every frame; allocate this only when level changes.
 if thinking_level != difficulty:
  thinking_level = difficulty
  thinking = VolleyBotDifficulty.profile(difficulty)
 return thinking

func settings_state() -> Dictionary:
 return {"counts": counts.duplicate(), "level": level, "human_team": human_team, "difficulty": difficulty, "characters": bots.keys().reduce(func(acc, id): acc[str(id)] = bots[id].character_id; return acc, {})}

func configure(values: Dictionary, broadcast := true) -> bool:
 if broadcast and not authority():
  return false
 var requested: Variant = values.get("counts", counts)
 var skill: Variant = values.get("level", level)
 var side: Variant = values.get("human_team", human_team)
 var chosen: Variant = values.get("difficulty", VolleyBotDifficulty.closest(float(skill)) if (skill is float or skill is int) and is_finite(float(skill)) else difficulty)
 if not chosen is int or chosen < 0 or chosen >= VolleyBotDifficulty.NAMES.size():
  return false
 if not requested is Array or requested.size() != 2 or not (skill is float or skill is int) or not is_finite(float(skill)) or not side is int or side not in [0, 1]:
  return false
 for n in requested:
  if not n is int or n < 0 or n > MAX_PER_TEAM:
   return false
 if broadcast and game.lan.match_active:
  game.lan.start_free_play()
 if solo_match and broadcast:
  end_solo()
 counts = requested.duplicate()
 difficulty = chosen
 level = VolleyBotDifficulty.SKILLS[difficulty] if values.has("difficulty") and not values.has("level") else float(skill)
 human_team = side
 for team in range(2):
  for slot in range(MAX_PER_TEAM):
   var id := bot_id(team, slot)
   if slot >= counts[team]:
    if bots.has(id):
     var removed: VolleyGameBot = bots[id]
     if game.ball.athlete == removed and game.ball.held:
      game.ball.drop()
     if game.ball.athlete == removed:
      game.ball.athlete = game.athlete
     if last_actor == removed:
      last_actor = null
     if game.lower_serve.busy_actor == removed:
      game.lower_serve.cancel_sequence()
     if game.float_serve.busy_actor == removed:
      game.float_serve.cancel_sequence()
     bots.erase(id)
     removed.queue_free()
    continue
   if not bots.has(id):
    var actor := VolleyGameBot.new()
    actor.name = "Bot_%d_%d" % [team, slot]
    actor.manager = self
    actor.bot_id = id
    actor.set_character("kageyama" if slot % 2 == 0 else "hinata")
    actor.court_team = team
    actor.slot = slot
    actor.process_mode = Node.PROCESS_MODE_PAUSABLE
    actor.replica = not authority()
    add_child(actor)
    actor.position = home(team, slot)
    actor.serve_solver = game.ball.solve_launch
    actor.power_serve_solver = game.ball.solve_power_serve
    actor.lifted_attack_solver = game.ball.solve_lifted_hit
    actor.set_physics_process(not actor.replica)
    bots[id] = actor
   var bot: VolleyGameBot = bots[id]
   bot.execution_level = difficulty
   (bot.style_stats as VolleyCharacterStats).set_difficulty_multiplier(VolleyBotDifficulty.stat_multiplier(difficulty))
   var hero := str(values.get("characters", {}).get(str(id), bot.character_id))
   if bot.character_id != hero and VolleyCharacterDatabase.valid(hero):
    bot.set_character(hero)
   if is_instance_valid(game.characters):
    game.characters.register(bot)
 game.lan.refresh_contacts()
 think_left = 0
 if broadcast and game.lan.active:
  game.lan.send_game_bots()
 tactics.reset()
 tactics.teammate_readings.clear()
 return true

static func bot_id(team: int, slot: int) -> int:
 return -100 - team * MAX_PER_TEAM - slot

func home(team: int, slot: int) -> Vector3:
 var n: int = counts[team]
 n += members(team).filter(func(a): return not a is VolleyGameBot).size()
 var side := 1.0 if team == 0 else -1.0
 slot = posmod(slot + rotation_turn[team], maxi(1, n))
 if n == 1:
  return Vector3(0, 0.02, side * 4.2)
 if n == 2:
  return Vector3((-1.0 if slot == 0 else 1.0) * 1.9, 0.02, side * 4.5)
 if n == 3:
  return Vector3((-2.1 if slot == 0 else 2.1) if slot < 2 else 0.0, 0.02, side * (2.7 if slot < 2 else 6.1))
 if n == 4:
  return Vector3((-1.0 if slot % 2 == 0 else 1.0) * 2.1, 0.02, side * (2.7 if slot < 2 else 6.1))
 return Vector3((slot % 3 - 1) * 2.7, 0.02, side * (2.4 if slot < 3 else 6.2))

func members(team: int) -> Array:
 var result: Array = []
 for bot in bots.values():
  if bot.court_team == team:
   result.append(bot)
 if game.lan.active:
  for entry in game.lan.players.values():
   var side: int = entry.actor.court_team if entry.actor.court_team >= 0 else entry.team
   if side == team:
    result.append(entry.actor)
 elif game.athlete.court_team == team:
  result.append(game.athlete)
 return result

func is_match() -> bool:
 return solo_match or game.lan.match_active

func reset_service(first_team: int) -> void:
 rotation_turn = [0, 0]
 serving_turn = [-1, -1]
 serving_turn[first_team] = 0
 current_server = null

func advance_service(winner: int, previous: int) -> void:
 # The winner keeps its current server; a side-out rotates the new team.
 if winner != previous:
  serving_turn[winner] += 1
  rotation_turn[winner] += 1

func place_team(team: int) -> void:
 var roster := members(team)
 for i in range(roster.size()):
  var actor: ContextAthlete = roster[i]
  actor.position = home(team, i)
  actor.velocity = Vector3.ZERO
  actor.energy = 1.0

func role_for(actor: ContextAthlete) -> String:
 if actor.character_id in ["kageyama", "oikawa"]:
  return "setter"
 if actor.character_id == "hinata":
  return "attacker"
 return legacy_role_for(actor)

func legacy_role_for(actor: ContextAthlete) -> String:
 var team := actor.court_team if actor.court_team >= 0 else (0 if actor.position.z >= 0 else 1) if game.lan.active else human_team
 var roster := members(team)
 var slot := roster.find(actor)
 var rotated := posmod(slot + rotation_turn[team], maxi(1, roster.size()))
 return "setter" if rotated == 0 else "attacker" if rotated < 3 else "defender"

func serving_actor(team: int) -> ContextAthlete:
 var candidates := members(team)
 candidates.sort_custom(func(a: ContextAthlete, b: ContextAthlete):
  if (a is VolleyGameBot) != (b is VolleyGameBot):
   return not a is VolleyGameBot
  return absi(a.bot_id) < absi(b.bot_id) if a is VolleyGameBot else game.lan.player_id(a) < game.lan.player_id(b))
 if candidates.is_empty():
  return null
 current_server = candidates[maxi(0, serving_turn[team]) % candidates.size()]
 return current_server

func note_touch(actor: ContextAthlete, kind: int) -> void:
 if actor is VolleyGameBot and kind in [VolleyAthlete.Technique.SERVE, VolleyAthlete.Technique.JUMP_SERVE]:
  actor.is_server = false
 var team := actor.court_team if actor.court_team >= 0 else (0 if actor.position.z >= 0 else 1)
 if team != last_team:
  touches = 0
  tactics.runs.clear()
 if kind != ContextAthlete.BLOCK:
  touches += 1
 last_actor = actor
 last_team = team
 last_kind = kind
 last_touch_time = clock
 think_left = 0

func reset_rally() -> void:
 if is_instance_valid(game.characters):
  game.characters.ai_wait.clear()
  game.characters.quick_runs.clear()
  game.characters.jump_events.clear()
 if is_instance_valid(game.super_serve):
  game.super_serve.clear_credit()
 tactics.reset()
 last_actor = null
 last_team = -1
 touches = 0
 last_kind = -1
 last_touch_time = -10
 receivers = [0, 0]
 receive_dives = [false, false]
 contact_heights = [1.35, 1.35]
 samples.clear()
 think_left = 0
 for team in range(2):
  for actor: ContextAthlete in members(team):
   actor.energy = 1.0
 for bot in bots.values():
  bot.reset_plan()
  bot.holding_ball = game.ball.held and game.ball.athlete == bot

func _physics_process(dt: float) -> void:
 if get_tree().paused or not authority() or bots.is_empty():
  return
 clock += dt
 tactics.observe_teammates(dt)
 if not game.super_serve.active and solo_match and match_winner < 0 and round_wait >= 0:
  round_wait -= dt
  if round_wait < 0:
   reset_round()
 if solo_match and game.rules.ended and round_wait < 0 and game.rules.last_player != -1:
  award(1 - last_team)
 think_left -= dt
 if think_left <= 0:
  think_left = float(decision_profile().scan)
  predict()

func predict() -> void:
 samples.clear()
 receivers = [0, 0]
 receive_dives = [false, false]
 contact_heights = [1.35, 1.35]
 if game.ball.held or game.ball.pending_feed or game.automatic_serve_busy():
  return
 for bot in bots.values():
  if bot.jump_serving:
   return
 var at: Vector3 = game.ball.position
 var v: Vector3 = game.ball.linear_velocity
 var spin: Vector3 = game.ball.angular_velocity
 # Match the authoritative 120 Hz integrator, publishing samples at 20 Hz.
 # This is shared by all bots, rather than re-simulated for every actor.
 var step := 1.0 / 120.0
 var observed_wake := Vector3.ZERO
 if game.ball.float_active:
  # Read the current visible acceleration, never the future float seed.
  observed_wake = (game.ball.acceleration - Vector3.DOWN * 9.81 - game.ball.aero_force(v, spin) / game.ball.mass).limit_length(2.0)
 for tick in range(432):
  var previous := at
  var time := (tick + 1) * step
  v += (Vector3.DOWN * (9.81 + game.ball.super_curve) + game.ball.aero_force(v, spin) / game.ball.mass + observed_wake * exp(-time * 5.0)) * step
  spin *= 1.0 - game.ball.angular_damp * step
  at += v * step
  if previous.z * at.z < 0 and at.y < 2.65 and at.y > 1.3 and absf(at.x) < 4.9:
   v.z *= -0.45
   at.z = signf(previous.z) * 0.20
  if absf(at.x) > VolleyCourt.INNER_X:
   at.x = clampf(at.x, -VolleyCourt.INNER_X, VolleyCourt.INNER_X)
   v.x *= -0.5
  if absf(at.z) > VolleyCourt.INNER_Z:
   at.z = clampf(at.z, -VolleyCourt.INNER_Z, VolleyCourt.INNER_Z)
   v.z *= -0.5
  if tick % 6 == 5 or at.y <= VolleyBall.RADIUS:
   samples.append({"at": at, "v": v, "time": time})
  if at.y <= VolleyBall.RADIUS:
   break
 tactics.choose_receivers()

func target_for(actor: VolleyGameBot, kind: int) -> Vector3:
 if kind in [VolleyAthlete.Technique.SERVE, VolleyAthlete.Technique.JUMP_SERVE]:
  return tactics.serve_target(actor)
 var own_touches := touches if last_team == actor.court_team else 0
 if kind in [VolleyAthlete.Technique.UNDERHAND, VolleyAthlete.Technique.OVERHEAD, ContextAthlete.JUMP_SET, ContextAthlete.DIVE] and own_touches < 2:
  var plan := tactics.pass_plan(actor, kind)
  if not plan.is_empty():
   return plan.target
 return tactics.attack_target(actor, kind)

func start_solo() -> bool:
 if game.lan.active or counts[1 - human_team] == 0:
  return false
 game.lower_serve.cancel_sequence()
 game.float_serve.cancel_sequence()
 solo_match = true
 scores = [0, 0]
 sets = [0, 0]
 match_winner = -1
 serve_team = human_team
 reset_service(serve_team)
 var observing: bool = game.athlete.court_team < 0
 if not observing:
  game.athlete.court_team = human_team
 var side := 1.0 if human_team == 0 else -1.0
 game.athlete.position = Vector3(6.8, 0.02, 0) if observing else Vector3(0, 0.02, side * 6.3)
 game.athlete.velocity = Vector3.ZERO
 game.athlete.cancel_input()
 game.athlete.action = VolleyAthlete.Action.IDLE
 game.athlete.camera_yaw = PI / 2 if observing else 0.0 if human_team == 0 else PI
 game.athlete.visual.rotation.y = game.athlete.camera_yaw
 game.rig.yaw = game.athlete.camera_yaw
 reset_round()
 return true

func end_solo() -> void:
 solo_match = false
 round_wait = -1
 game.rules.reset()
 game.rules.strict = false
 game.athlete.court_team = -1

func reset_round() -> void:
 if match_winner >= 0:
  return
 reset_rally()
 game.rules.reset()
 game.rules.strict = true
 game.previous_ball_valid = false
 game.serving = false
 round_wait = -1
 for team in range(2):
  place_team(team)
 var side := 1.0 if serve_team == 0 else -1.0
 var server := serving_actor(serve_team)
 if not is_instance_valid(server):
  return
 server.position = Vector3(0, 0.02, side * 9.7)
 server.velocity = Vector3.ZERO
 if server is VolleyGameBot:
  server.prepare_serve()
 else:
  game.ball.feed(server.position + Vector3(0, 0.25, -side * 0.5), Vector3.ZERO)
  server.camera_yaw = 0 if side > 0 else PI
  server.visual.rotation.y = server.camera_yaw
  game.rig.yaw = server.camera_yaw
  server.last_result = "Ваша подача • подберите мяч за задней линией"

func award(winner: int) -> void:
 if not solo_match or round_wait >= 0 or match_winner >= 0:
  return
 winner = clampi(winner, 0, 1)
 match_winner = VolleyMatchScore.point(scores, sets, winner)
 advance_service(winner, serve_team)
 serve_team = winner
 round_wait = 2.0
 game.show_feedback(VolleyMatchScore.label(scores, sets, match_winner), false)

func on_floor(at: Vector3) -> void:
 if solo_match and last_team >= 0:
  award((1 if at.z >= 0 else 0) if absf(at.x) <= 4.5 + VolleyBall.RADIUS and absf(at.z) <= 9 + VolleyBall.RADIUS else 1 - last_team)

func add_settings(hud: VolleyHUD) -> void:
 var list := hud._tab("Команды")
 hud._native_button(list, "Персонажи и способности", func(): game.characters.ui.open_characters(true))
 hud._native_button(list, "Составы команд / демонстрация", func(): game.characters.ui.open_teams(true))


func change_count(team: int, delta: int) -> void:
 var next := counts.duplicate()
 next[team] = clampi(next[team] + delta, 0, MAX_PER_TEAM)
 configure({"counts": next})

func _process(_dt: float) -> void:
 if not is_instance_valid(hint) or not game.hud.menu.visible:
  return
 for team in range(2):
  count_labels[team].text = "%s  ·  %d ботов" % ["A" if team == 0 else "Б", counts[team]]
 difficulty_picker.select(difficulty)
 difficulty_hint.text = "СЛОЖНОСТЬ · " + VolleyBotDifficulty.NAMES[difficulty] + "\n" + VolleyBotDifficulty.THINKING[difficulty] + "\nМеняются также все 8 характеристик."
 for control in ui_controls:
  if control is BaseButton:
   control.disabled = not authority() or (control.has_meta("solo_only") and game.lan.active)
  elif control is Range:
   control.editable = authority()
 hint.text = "LAN: всем людям нужно встать в зоны выбора команд; боты займут свою сторону. До 6 участников в команде." if game.lan.active else "Выберите свою команду и нажмите «Матч с ботами». В свободной игре боты тоже активны."
