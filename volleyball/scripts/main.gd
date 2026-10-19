extends Node3D

var athlete: ContextAthlete
var ball: VolleyBall
var training := VolleyTraining.new()
var camera: Camera3D
var rig: VolleyCameraRig
var rules := VolleyRules.new()
var serving := false
var action_owner := ""
var previous_ball := Vector3.ZERO
var previous_ball_valid := false
var hud: VolleyHUD
var ball_shadow: MeshInstance3D
var lan: VolleyLAN
var frontend: VolleyFrontend
var lower_serve: VolleyLowerServe
var float_serve: VolleyFloatServe
var practice: VolleyPractice
var game_bots: VolleyGameBots
var frame_rate: VolleyFrameRate
var feedback_text := ""
var feedback_color := Color.WHITE
var feedback_left := 0.0
var net_contact_times: Dictionary = {}

func _ready() -> void:
 if OS.get_name() in ["iOS", "Android"]:
  DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
 frame_rate = VolleyFrameRate.new()
 add_child(frame_rate)
 _court()
 athlete = ContextAthlete.new()
 athlete.name = "Athlete"
 add_child(athlete)
 athlete.position = Vector3(0, 0.02, 4)
 ball = VolleyBall.new()
 ball.athlete = athlete
 add_child(ball)
 ball.position = Vector3(0, 0.2, 1)
 athlete.serve_solver = ball.solve_launch
 athlete.power_serve_solver = ball.solve_power_serve
 athlete.lifted_attack_solver = ball.solve_lifted_hit
 var preview := VolleyTossPreview.new()
 preview.name = "TossPreview"
 preview.ball = ball
 preview.viewer = athlete
 add_child(preview)
 var strike_preview := VolleyStrikePreview.new()
 strike_preview.name = "StrikePreview"
 strike_preview.game = self
 strike_preview.ball = ball
 strike_preview.viewer = athlete
 add_child(strike_preview)
 athlete.touched.connect(_on_touch)
 athlete.block_missed.connect(func(): _on_block_missed(athlete, lan.player_id(athlete)))
 ball.surface_contact.connect(_on_surface)
 ball_shadow = VolleyGeometry.sphere(self, Vector3.ZERO, 0.16, Color("143c42"))
 ball_shadow.scale.y = 0.02
 rig = VolleyCameraRig.new()
 rig.athlete = athlete
 rig.ball = ball
 add_child(rig)
 camera = rig.camera
 var layer := CanvasLayer.new()
 add_child(layer)
 hud = VolleyHUD.new()
 hud.game = self
 layer.add_child(hud)
 lan = VolleyLAN.new()
 lan.game = self
 add_child(lan)
 lower_serve = VolleyLowerServe.new()
 lower_serve.game = self
 layer.add_child(lower_serve)
 float_serve = VolleyFloatServe.new()
 float_serve.game = self
 layer.add_child(float_serve)
 practice = VolleyPractice.new()
 practice.game = self
 add_child(practice)
 game_bots = VolleyGameBots.new()
 game_bots.game = self
 add_child(game_bots)
 hud.add_bot_settings()
 game_bots.add_settings(hud)
 frontend = VolleyFrontend.new()
 frontend.game = self
 layer.add_child(frontend)

func automatic_serve_busy() -> bool:
 return (is_instance_valid(lower_serve) and is_instance_valid(lower_serve.busy_actor)) or (is_instance_valid(float_serve) and is_instance_valid(float_serve.busy_actor))

func _court() -> void:
 VolleyCourt.build(self)

func _process(_dt: float) -> void:
 feedback_left = maxf(0, feedback_left - _dt)
 for entry in ([athlete] if not lan.active else lan.players.values().map(func(p: Dictionary): return p.actor)):
  entry.look_target = ball.global_position
  entry.look_target_valid = true
 ball_shadow.position = Vector3(ball.position.x, 0.037, ball.position.z)
 if (not lan.active or lan.hosting) and (ball.position.y < -3 or ball.position.length() > 45):
  ball.feed(Vector3(0, 0.3, 1), Vector3.ZERO)

func _physics_process(_dt: float) -> void:
 if lan.active and not lan.hosting:
  return
 if (lan.active and not lan.match_active) or (not lan.active and not game_bots.bots.is_empty() and not game_bots.solo_match):
  return
 if not ball.held and not ball.pending_feed:
  if previous_ball_valid:
   rules.crossing(previous_ball, ball.global_position)
  previous_ball = ball.global_position
  previous_ball_valid = true
 else:
  previous_ball_valid = false
 var actors: Array = lan.players.values().map(func(entry: Dictionary): return entry.actor) if lan.active else [athlete]
 actors.append_array(game_bots.bots.values())
 for actor in actors:
  check_net_contact(actor, _dt)

func player_touches_net(actor: ContextAthlete) -> bool:
 for index in range(actor.get_slide_collision_count()):
  var collision: KinematicCollision3D = actor.get_slide_collision(index)
  if collision.get_collider().get_meta("surface", "") == "net":
   return true
 for wrist in actor.wrists:
  # Use the palm, not the larger assisted ball-contact radius.
  if absf(wrist.z) < 0.065 and absf(wrist.x) < 4.5 and wrist.y >= 1.43 and wrist.y <= 2.47:
   return true
 return false

func check_net_contact(actor: ContextAthlete, dt: float) -> void:
 var id := actor.get_instance_id()
 var live := lan.round_live if lan.match_active else game_bots.last_team >= 0 if game_bots.solo_match else rules.touches > 0
 if not live or rules.ended or actor.action not in [VolleyAthlete.Action.PREPARE, VolleyAthlete.Action.STRIKE] or not player_touches_net(actor):
  net_contact_times.erase(id)
  return
 # Ignore a single animated-frame graze; a real sustained touch still faults.
 net_contact_times[id] = float(net_contact_times.get(id, 0)) + dt
 if net_contact_times[id] >= 0.075:
  record_fault(actor, "Касание сетки игроком")

func record_fault(actor: ContextAthlete, text: String) -> void:
 if rules.ended:
  return
 var side := VolleyBall.team_of(actor)
 if lan.match_active:
  lan.last_touch_team = side
  lan.round_live = true
 if game_bots.solo_match:
  game_bots.last_team = side
  rules.last_player = lan.player_id(actor)
 rules.fault(text)

func _on_touch(kind: int, point: Vector3, outgoing: Vector3) -> void:
 _on_player_touch(athlete, lan.player_id(athlete), kind, point, outgoing)

func _on_player_touch(actor: ContextAthlete, id: int, kind: int, _point: Vector3, _outgoing: Vector3) -> void:
 var first_match_touch: bool = (lan.match_active and not lan.round_live) or (game_bots.solo_match and game_bots.last_team < 0)
 if first_match_touch:
  rules.reset()
  if kind not in [VolleyAthlete.Technique.SERVE, VolleyAthlete.Technique.JUMP_SERVE]:
   rules.fault("Розыгрыш начинается подачей из-за задней линии")
  elif (actor.court_team if actor.court_team >= 0 else (0 if actor.position.z >= 0 else 1)) != (lan.serve_team if lan.match_active else game_bots.serve_team):
   rules.fault("Подаёт другая команда")
  elif is_instance_valid(game_bots.current_server) and actor != game_bots.current_server:
   rules.fault("Сейчас подача другого игрока команды")
 if is_instance_valid(game_bots):
  game_bots.note_touch(actor, kind)
 if kind == ContextAthlete.BLOCK:
  var pierced := bool(actor.duel_result.get("pierced", false))
  if actor == athlete:
   show_feedback("", pierced)
  if lan.active and lan.hosting and id != 1 and lan.players.has(id):
   lan.contact_feedback.rpc_id(id, "", pierced)
 if kind in [VolleyAthlete.Technique.SERVE, VolleyAthlete.Technique.JUMP_SERVE, VolleyAthlete.Technique.SPIKE, ContextAthlete.TIP]:
  serving = false
  if lan.active and lan.serve_flags.has(id):
   lan.serve_flags[id] = false
 if lan.active and not lan.match_active:
  actor.last_result = "Свободная игра • " + actor.last_result
  return
 if not lan.active and not game_bots.bots.is_empty() and not game_bots.solo_match:
  return
 var side: int = actor.court_team if actor.court_team >= 0 else (0 if actor.position.z >= 0 else 1)
 rules.touch(side, id, kind, actor.strike_count, _point.y)
 if lan.active:
  lan.last_touch_team = side
  lan.round_live = true
 if kind in [VolleyAthlete.Technique.SERVE, VolleyAthlete.Technique.JUMP_SERVE]:
  rules.serve_contact(actor.service_origin())

func holding_ball() -> bool:
 return ball.held and ball.athlete == athlete

func begin_bump() -> bool:
 if not action_owner.is_empty() or holding_ball():
  return false
 if athlete.begin_action(VolleyAthlete.Technique.UNDERHAND):
  action_owner = "bump"
  return true
 return false

func _on_surface(surface: String) -> void:
 if lan.active and not lan.hosting:
  return
 if lan.active and not lan.match_active:
  return
 if not lan.active and not game_bots.bots.is_empty() and not game_bots.solo_match:
  return
 if surface == "floor":
  if rules.ended:
   if game_bots.solo_match and game_bots.last_team >= 0:
    game_bots.award(1 - game_bots.last_team)
   if lan.active and lan.round_live:
    lan.award(1 - lan.last_touch_team)
   return
  var service_fault := rules.serving and not rules.serve_crossed
  rules.floor_contact(ball.global_position)
  if service_fault:
   if game_bots.solo_match and game_bots.last_team >= 0:
    game_bots.award(1 - game_bots.last_team)
   if lan.active and lan.round_live:
    lan.award(1 - lan.last_touch_team)
  else:
   game_bots.on_floor(ball.global_position)
   if lan.active and lan.round_live:
    lan.award_floor(ball.global_position)
 elif surface == "antenna":
  rules.net_contact(false, true)
 elif surface in ["boundary", "world"]:
  rules.fault("Аут: касание ограждения")

func repeat_drill() -> void:
 if game_bots.solo_match:
  game_bots.reset_round()
  return
 if lan.active:
  lan.local_action("next")
  return
 lower_serve.cancel_sequence()
 float_serve.cancel_sequence()
 action_owner = ""
 athlete.cancel_input()
 athlete.action = VolleyAthlete.Action.IDLE
 serving = training.selected in [5, 6]
 ball.jump_toss = training.selected == 6
 rules.reset(serving)
 previous_ball_valid = false
 training.launch(ball, athlete)

func start_drill() -> void:
 if lan.active:
  repeat_drill()
  return
 athlete.dive_time = -1
 athlete.dive_cooldown = 0
 athlete.visual.rotation.x = 0
 var shape_node := athlete.get_child(0) as CollisionShape3D
 shape_node.shape.height = 1.75
 shape_node.position.y = 0.875
 athlete.velocity = Vector3.ZERO
 athlete.position = training.start_position()
 athlete.visual.rotation.y = 0
 rig.yaw = 0
 rig.pitch = 0.18
 rig.rendered_yaw = 0
 rig.rendered_pitch = 0.18
 rig.followed = athlete.position + Vector3.UP * 1.45
 repeat_drill()

func reset_player() -> void:
 if lan.active:
  return
 athlete.position = Vector3(0, 0.02, 4)
 athlete.velocity = Vector3.ZERO
 athlete.visual.rotation = Vector3.ZERO
 athlete.cancel_input()
 athlete.dive_time = -1
 athlete.visual.rotation.x = 0
 var shape_node := athlete.get_child(0) as CollisionShape3D
 shape_node.shape.height = 1.75
 shape_node.position.y = 0.875
 athlete.action = VolleyAthlete.Action.IDLE
 action_owner = ""

func running_approach() -> bool:
 return not holding_ball() and not athlete.airborne() and athlete.move_axis.length() > 0.65 and Vector2(athlete.velocity.x, athlete.velocity.z).length() > 1.0

func begin_approach() -> bool:
 if lan.active and not lan.executing:
  return lan.local_action("approach")
 if not action_owner.is_empty() or ball.held or not athlete.arm_approach(VolleyAthlete.Technique.JUMP_SERVE if serving else VolleyAthlete.Technique.SPIKE):
  return false
 action_owner = "approach"
 return true

func begin_primary() -> bool:
 if not action_owner.is_empty():
  return false
 if ball.held:
  if not holding_ball():
   return false
  if ball.held_mode == VolleyBall.HeldMode.THROW:
   ball.throw_held()
   if rules.strict:
    record_fault(athlete, "Бросок удерживаемого мяча")
   return true
  athlete.technique = athlete.delivery_kind(training.selected == 6)
  ball.toss()
  serving = VolleyRules.in_service_zone(athlete.global_position)
  if serving and not rules.strict:
   rules.reset(true)
  return true
 if athlete.attack_ready:
  return athlete.hit_approach()
 if running_approach() and athlete.arm_approach(VolleyAthlete.Technique.JUMP_SERVE if serving else VolleyAthlete.Technique.SPIKE):
  action_owner = "primary"
  return true
 var kind := VolleyAthlete.Technique.SPIKE
 if serving:
  kind = athlete.delivery_kind(athlete.airborne())
 if athlete.begin_action(kind):
  action_owner = "primary"
  return true
 return false

func begin_secondary() -> bool:
 if not action_owner.is_empty():
  return false
 if ball.held:
  if not holding_ball():
   return false
  ball.toggle_held_mode()
  return true
 elif athlete.begin_action(ContextAthlete.BLOCK if athlete.airborne() else VolleyAthlete.Technique.OVERHEAD):
  action_owner = "secondary"
  return true
 return false

func begin_jump_set() -> bool:
 if action_owner.is_empty() and athlete.airborne() and athlete.begin_action(ContextAthlete.JUMP_SET):
  action_owner = "jump_set"
  return true
 return false

func finish_action(role: String) -> void:
 if lan.active and not lan.executing:
  lan.local_action(role, "release")
  return
 if action_owner != role:
  return
 if athlete.block_held:
  athlete.end_block()
  action_owner = ""
  return
 if athlete.approach_armed:
  athlete.launch_approach()
  action_owner = ""
  return
 if ball.held and role == "secondary":
  ball.throw_held()
  if rules.strict:
   record_fault(athlete, "Бросок удерживаемого мяча")
 elif athlete.action == VolleyAthlete.Action.PREPARE:
  if role == "primary":
   athlete.technique = athlete.delivery_kind(athlete.airborne()) if serving else VolleyAthlete.Technique.SPIKE
  athlete.release()
 action_owner = ""

func cancel_action(role: String) -> void:
 if is_instance_valid(lan) and lan.active and not lan.executing:
  lan.local_action("cancel" if role.is_empty() else role, "cancel")
  return
 if role.is_empty() or role == action_owner:
  athlete.cancel_input()
  action_owner = ""

func pickup_or_drop() -> void:
 if ball.held and not holding_ball():
  return
 cancel_action("")
 if ball.held:
  ball.drop()
 else:
  # The last bot to serve may still be the ball's actor. The HUD tests the
  # human's reach; the action must use that same person, including in solo.
  if not ball.can_pick_up_for(athlete):
   return
  ball.athlete = athlete
  if ball.pick_up() and rules.strict and ((lan.match_active and lan.round_live) or (game_bots.solo_match and game_bots.last_team >= 0)):
   record_fault(athlete, "Задержка мяча")

func serve_start() -> void:
 # Explicit training reset, never part of an automatic contact or pickup.
 athlete.position = Vector3(0, 0.02, 9.6)
 athlete.velocity = Vector3.ZERO
 athlete.aim = Vector2(0, -1)
 athlete.visual.rotation = Vector3.ZERO
 athlete.action = VolleyAthlete.Action.IDLE
 ball.feed(Vector3(0.3, 0.2, 9), Vector3.ZERO)
 rules.reset(true)
 serving = true
 athlete.last_result = "Подберите мяч • основная кнопка — подброс"

func show_feedback(text: String, failed: bool) -> void:
 feedback_text = text
 feedback_color = Color("ff987d") if failed else Color("bbf275")
 feedback_left = 0.32 if text.is_empty() else 1.3
 if OS.get_name() in ["Android", "iOS"]:
  Input.vibrate_handheld(35 if failed else 65)

func _on_block_missed(actor: ContextAthlete, id: int) -> void:
 # No contact means no flash or vibration; a miss never claims a hit.
 pass
