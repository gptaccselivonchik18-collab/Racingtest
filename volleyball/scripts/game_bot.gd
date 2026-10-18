class_name VolleyGameBot
extends ContextAthlete

var manager: VolleyGameBots
var bot_id := -100
var slot := 0
var state := "cover"
var cooldown := 0.0
var serve_wait := 0.0
var is_server := false
var destination := Vector3.ZERO
var contacts := 0
var serves := 0
var jumps := 0
var dives := 0
var contact_kinds: Dictionary = {}
var planned_kind := -1
var jump_serving := false
var toss_time := 0.0
var noticed_touch := -INF
var reaction_until := 0.0
var serve_aim := Vector3.INF
var serve_history: Array[Vector3] = []

func _ready() -> void:
 random_seed = 20261019 + absi(bot_id) * 77
 super._ready()
 var tag := Label3D.new()
 tag.text = "%s · БОТ %d" % ["A" if court_team == 0 else "Б", slot + 1]
 tag.position.y = 2.12
 tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 tag.font_size = 36
 tag.pixel_size = 0.006
 tag.modulate = Color("64dce1") if court_team == 0 else Color("ffad79")
 add_child(tag)
 # Team shirts refine the existing model without replacing its limbs.
 var shirt := visual.get_child(0) as MeshInstance3D
 if shirt:
  var material := StandardMaterial3D.new()
  material.albedo_color = tag.modulate
  shirt.material_override = material
 camera_yaw = 0 if court_team == 0 else PI
 visual.rotation.y = camera_yaw
 last_result = "Страховка"

func reset_plan() -> void:
 serve_aim = Vector3.INF
 cancel_input()
 action = Action.IDLE
 holding_ball = false
 planned_kind = -1
 is_server = false
 jump_serving = false
 cooldown = 0
 state = "cover"

func prepare_serve() -> void:
 reset_plan()
 var side := 1.0 if court_team == 0 else -1.0
 position = Vector3(rng.randf_range(-2.5, 2.5), 0.02, side * 9.65)
 velocity = Vector3.ZERO
 camera_yaw = 0 if side > 0 else PI
 visual.rotation.y = camera_yaw
 manager.game.ball.feed(position + Vector3(0, 0.25, -side * 0.5), Vector3.ZERO)
 is_server = true
 serve_wait = 0.7
 state = "retrieve"

func _physics_process(dt: float) -> void:
 if replica:
  return
 cooldown = maxf(0, cooldown - dt)
 serve_wait = maxf(0, serve_wait - dt)
 decide(dt)
 super._physics_process(dt)

func steer(target: Vector3, stop := 0.20) -> void:
 destination = target
 var offset := Vector2(target.x - position.x, target.z - position.z)
 var movement := style_stats.movement()
 var distance := maxf(0, offset.length() - stop)
 var pace := minf(float(movement.speed), sqrt(2.0 * float(movement.braking) * distance) * 0.82)
 var desired := offset.normalized() * pace / float(movement.speed)
 move_axis = manager.tactics.spaced_axis(self, desired)
 sprint = offset.length() > 2.5
 if offset.length() > 0.6 and action == Action.IDLE:
  camera_yaw = atan2(-offset.x, -offset.y)

func decide(_dt: float) -> void:
 var game := manager.game
 var ball: VolleyBall = game.ball
 var side := 1.0 if court_team == 0 else -1.0
 if noticed_touch != manager.last_touch_time:
  noticed_touch = manager.last_touch_time
  reaction_until = manager.clock + float(VolleyBotDifficulty.profile(manager.difficulty).reaction) * (0.82 + fposmod(absi(bot_id) * 0.173, 0.36))
 look_target = ball.position
 look_target_valid = true
 if ball.pending_feed:
  return
 if (manager.solo_match and manager.round_wait >= 0) or (game.lan.match_active and game.lan.round_wait >= 0):
  move_axis = Vector2.ZERO
  return
 if game.lower_serve.busy_actor == self or game.float_serve.busy_actor == self:
  move_axis = Vector2.ZERO
  return
 if ball.held:
  if ball.athlete == self:
   state = "serve"
   steer(Vector3(clampf(position.x, -3, 3), 0.02, side * 9.65))
   if absf(position.z) > 9.3 and velocity.length() < 0.6 and serve_wait <= 0:
    var target := manager.target_for(self, Technique.SERVE)
    if manager.difficulty >= 3 and serves % 4 == 3:
     var toward := target - position
     camera_yaw = atan2(-toward.x, -toward.z)
     visual.rotation.y = camera_yaw
     technique = Technique.JUMP_SERVE
     ball.jump_toss = true
     ball.set_release_height(2.6)
     ball.toss()
     begin_action(Technique.JUMP_SERVE)
     hit_used = false
     jump_serving = true
     toss_time = 0
     serves += 1
     game.rules.reset(true)
     return
    var controller: VolleyLowerServe = game.float_serve if manager.difficulty >= 2 and serves % 3 == 2 else game.lower_serve
    if controller.launch(self, target, lerpf(3.8, 2.8, style_stats.n("serve"))):
     serves += 1
  else:
   state = "cover"
   steer(manager.home(court_team, slot))
  return
 if jump_serving:
  toss_time += _dt
  state = "jump_serve"
  move_axis = Vector2.ZERO
  if not airborne() and ball.position.y > position.y + 2.8 and ball.linear_velocity.y > 0 and toss_time > 0.18:
   jump()
   if velocity.y > 0:
    jumps += 1
  if action == Action.PREPARE and airborne() and charged_for > 0.13 and ball.position.y - position.y < 3.1 and toss_time > 0.42:
   release()
  if toss_time > 2.5 or hit_used:
   jump_serving = false
   if action == Action.PREPARE:
    cancel_input()
   cooldown = 0.4
  return
 if block_held:
  move_axis = Vector2.ZERO
  if hit_used or not airborne() or ball.position.z * side > 1.2 or action_time > 1.3:
   end_block()
  return
 if action == Action.RECOVER:
  planned_kind = -1
  move_axis *= 0.5
  return
 if action == Action.STRIKE:
  move_axis = Vector2.ZERO
  return
 var dead := ball.position.y < 0.65 and ball.linear_velocity.length() < 3.0 and not ball.pending_feed
 if dead and cooldown <= 0 and not game.automatic_serve_busy():
  if not is_server and manager.tactics.human_pickup_near():
   state = "cover"
   steer(manager.tactics.support(self))
   return
  var closest: ContextAthlete = null
  var best := INF
  # In scored play only the nominated server retrieves before a serve.
  if manager.is_match() and ((game.lan.match_active and not game.lan.round_live) or (manager.solo_match and manager.last_team < 0)):
   if not is_server:
    steer(manager.home(court_team, slot))
    return
   closest = self
  else:
   for teammate in manager.members(court_team):
    var d: float = teammate.position.distance_to(ball.position)
    if d < best:
     closest = teammate
     best = d
   if ball.position.z * side < 0 and not is_server:
    closest = null
  if closest == self:
   state = "retrieve"
   if action == Action.PREPARE:
    cancel_input()
   steer(Vector3(clampf(ball.position.x, -7.75, 7.75), 0.02, clampf(ball.position.z, -11.75, 11.75)), 0.7)
   if ball.can_pick_up_for(self):
    ball.athlete = self
    var nominated_server := is_server
    if ball.pick_up():
     serve_wait = float(VolleyBotDifficulty.profile(manager.difficulty).tempo) + rng.randf_range(0.05, 0.25)
     manager.reset_rally()
     is_server = nominated_server
   return
 if attempt_block(side):
  return
 if manager.receivers[court_team] == bot_id:
  if manager.clock < reaction_until and action == Action.IDLE:
   steer(manager.tactics.support(self))
   return
  state = "intercept"
  var at: Vector3 = manager.intercepts[court_team]
  at.x = clampf(at.x, -7.6, 7.6)
  at.z = side * clampf(absf(at.z), 0.65, 11.6)
  steer(at, 0.10)
  var remaining: float = manager.arrival[court_team] - manager.clock
  var offset := ball.position - position
  var horizontal := Vector2(offset.x, offset.z).length()
  if attempt_dive(at, remaining, manager.receive_dives[court_team]):
   return
  if action == Action.IDLE and remaining < 0.65 and horizontal < 2.5 and cooldown <= 0:
   var kind := Technique.UNDERHAND
   if manager.last_team == court_team and manager.touches > 0:
    kind = Technique.OVERHEAD
    if manager.tactics.jump_set_useful(self) and float(manager.contact_heights[court_team]) > 2.55:
     kind = JUMP_SET
   var solo_attack := manager.members(court_team).size() == 1 and manager.last_team != court_team and manager.last_kind not in [3, 4]
   if ((manager.last_team == court_team and manager.touches >= 2 and absf(at.z) < 4.5) or solo_attack) and float(manager.contact_heights[court_team]) > 2.35:
    kind = Technique.SPIKE
   if kind == Technique.UNDERHAND and horizontal > 1.6 and ball.position.y < 1.15 and remaining < 0.2:
    if dive():
     dives += 1
     planned_kind = DIVE
    elif dive_cooldown > 0 and begin_action(kind):
     planned_kind = kind
   elif begin_action(kind):
    planned_kind = kind
  if action == Action.PREPARE:
   if planned_kind == Technique.OVERHEAD and manager.tactics.jump_set_useful(self) and float(manager.contact_heights[court_team]) > 2.55 and remaining > 0.20 and not airborne():
    planned_kind = JUMP_SET
    technique = JUMP_SET
   elif planned_kind == JUMP_SET and not airborne() and remaining < 0.20 and float(manager.contact_heights[court_team]) < 2.55:
    planned_kind = Technique.OVERHEAD
    technique = Technique.OVERHEAD
   var aim := manager.target_for(self, planned_kind)
   var toward := aim - position
   camera_yaw = atan2(-toward.x, -toward.z)
   camera_pitch = deg_to_rad(55 if planned_kind in [Technique.OVERHEAD, JUMP_SET] else 20)
   # Hands face the intended pass, which may be sideways or behind us.
   # Align the body behind that contact rather than always behind the net.
   if planned_kind in [Technique.OVERHEAD, JUMP_SET]:
    var contact := at - Vector3(0, 0, side * 0.34)
    var forward := -visual.global_basis.z
    forward.y = 0
    forward = forward.normalized()
    steer(contact - forward * 0.45, 0.05)
   if planned_kind == JUMP_SET and not airborne() and remaining > 0.16 and remaining < 0.55:
    var lift := maxf(0.15, float(manager.contact_heights[court_team]) - 2.15)
    var needed := (lift + 4.905 * remaining * remaining) / remaining
    if needed <= sqrt(19.62 * float(style_stats.movement().jump_height)) and horizontal < 0.85:
     jump()
     if velocity.y > 0:
      velocity.y = minf(velocity.y, needed)
      jumps += 1
   if planned_kind == Technique.SPIKE and not airborne() and remaining < 0.45:
    jump(true)
    if velocity.y > 0:
     # Jump to this ball, not to the maximum stat apex every time.
     var lift := clampf(float(manager.contact_heights[court_team]) - 2.25, 0.25, float(style_stats.movement().jump_height))
     velocity.y = minf(velocity.y, sqrt(19.62 * lift))
     jumps += 1
   var windup := float(mechanic(planned_kind).windup)
   var receive := planned_kind in [Technique.UNDERHAND, Technique.OVERHEAD, JUMP_SET]
   if charged_for >= windup and (planned_kind != JUMP_SET or airborne()) and ((receive or planned_kind == Technique.SPIKE) and contact_due()):
    release()
   elif charged_for > 1.05:
    cancel_input()
    planned_kind = -1
    cooldown = 0.12
  return
 if action == Action.PREPARE:
  cancel_input()
  planned_kind = -1
 if action == Action.IDLE:
  state = "cover"
  var support := manager.tactics.support(self)
  steer(support)
  camera_yaw = 0 if side > 0 else PI

func contact_due() -> bool:
 # Time the real animation window using this player's current skill profile.
 # This only decides when to release; normal swept collision still decides hits.
 var p := mechanic(planned_kind)
 var ball: VolleyBall = manager.game.ball
 var radius := contact_ball_radius * float(p.radius)
 for phase in [maxf(float(p.start), 0.22), 0.47, minf(float(p.end), 0.80)]:
  var time: float = float(p.duration) * float(phase)
  var point := ball.position + ball.linear_velocity * time + Vector3.DOWN * 4.905 * time * time
  var drift := Vector3(velocity.x, 0, velocity.z) * time * 0.5
  if airborne():
   drift = velocity * time + Vector3.DOWN * 4.905 * time * time
  if planned_kind == Technique.UNDERHAND:
   var spine := position + drift + Vector3.UP * clampf(point.y - position.y - drift.y, 0.20, 1.65)
   if point.distance_to(spine) < radius + 0.25:
    return true
  elif planned_kind == Technique.SPIKE:
   var turn := float(style_stats.movement().turn) * time * (0.45 if airborne() else 1.0)
   var yaw := clampf(angle_difference(visual.rotation.y, camera_yaw), -turn, turn)
   var hand := Vector3(0.2, 2.05 + sin(float(phase) * PI) * 0.25, 0.12 - float(phase) * 1.15)
   var offset := (visual.to_global(hand) - position).rotated(Vector3.UP, yaw)
   if point.distance_to(position + offset + drift) < radius + HAND_RADIUS * 0.75:
    return true
  else:
   var turn := float(style_stats.movement().turn) * time * (0.45 if airborne() else 1.0)
   var yaw := clampf(angle_difference(visual.rotation.y, camera_yaw), -turn, turn)
   var offset := (wrists[0] + wrists[1]) * 0.5 - position
   offset -= visual.global_basis.z * (0.35 * float(phase))
   var hands := position + offset.rotated(Vector3.UP, yaw) + drift + Vector3.UP * (0.35 * sin(float(phase) * PI * 0.5))
   if point.distance_to(hands) < radius + HAND_RADIUS * 0.65:
    return true
 return false

func attempt_dive(at: Vector3, remaining: float, planned: bool) -> bool:
 if action not in [Action.IDLE, Action.PREPARE] or cooldown > 0 or dive_cooldown > 0 or airborne():
  return false
 var p := mechanic(DIVE)
 var distance := VolleyBotTactics.flat(at, position)
 var low: bool = manager.game.ball.position.y < 1.6
 if not planned and not (low and distance > 1.3):
  return false
 if remaining > float(p.contact_to) * 0.85 or remaining < -0.12 or distance < 0.9:
  return false
 move_axis = Vector2(at.x - position.x, at.z - position.z).normalized()
 camera_yaw = atan2(-move_axis.x, -move_axis.y)
 if action == Action.PREPARE:
  cancel_input()
 if not dive():
  return false
 var time := clampf(remaining, float(p.contact_from) + 0.04, float(p.contact_to))
 var needed := maxf(0.8, distance - 0.45) / (time * (1.0 - 0.5 * time / float(p.travel)))
 dive_speed = minf(dive_speed, maxf(2, needed))
 dives += 1
 planned_kind = DIVE
 state = "dive"
 return true

func attempt_block(side: float) -> bool:
 if cooldown > 0 or action != Action.IDLE or dive_time >= 0:
  return false
 var plan := manager.tactics.block_plan(self)
 if plan.is_empty():
  return false
 state = "block"
 steer(plan.target, 0.08)
 camera_yaw = 0 if side > 0 else PI
 # Jump from the predicted contact time, not only after the ball is struck.
 var lift := clampf(float(plan.get("height", 3.0)) - 2.25, 0.45, float(style_stats.movement().jump_height))
 var rise := sqrt(2.0 * lift / 9.81)
 if bool(plan.commit) and float(plan.time) <= rise + 0.10 and absf(position.z) < 1.35 and absf(position.x - Vector3(plan.target).x) < 0.85:
  jump()
  if velocity.y > 0.1:
   velocity.y = minf(velocity.y, sqrt(19.62 * lift))
   velocity.x *= 0.15
   velocity.z = 0
  if velocity.y > 0.1 and begin_action(BLOCK):
   jumps += 1
 return true

func try_swept_contact(from: Vector3, center: Vector3, incoming: Vector3, attack: Dictionary = {}) -> Vector3:
 var delta := super.try_swept_contact(from, center, incoming, attack)
 if delta == Vector3.ZERO:
  return delta
 contacts += 1
 jump_serving = false
 contact_kinds[strike_technique] = int(contact_kinds.get(strike_technique, 0)) + 1
 cooldown = float(VolleyBotDifficulty.profile(manager.difficulty).tempo) * 0.45
 if strike_technique == BLOCK:
  manager.game._on_player_touch(self, bot_id, strike_technique, last_contact_point, incoming + delta)
  return delta
 var target := manager.target_for(self, strike_technique)
 var profile := mechanic(strike_technique)
 var spread: float = lerpf(0.95, 0.10, float(profile.control)) * (1.2 - quality)
 target += Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
 var spin := outgoing_spin(manager.game.ball.angular_velocity, delta)
 var own_side := target.z * (1.0 if court_team == 0 else -1.0) > 0
 var apex := 2.8 if own_side else maxf(2.0, 3.7 - last_contact_point.y * 0.4)
 apex *= float(profile.get("arc", profile.get("lift", 1.0)))
 var outgoing: Vector3 = manager.game.ball.solve_launch(last_contact_point, target, apex, spin)
 if own_side:
  var plan := manager.tactics.pass_plan(self, strike_technique)
  if not plan.is_empty() and bool(plan.attacking):
   var recipient: ContextAthlete = plan.recipient
   var travel := VolleyBotTactics.flat(recipient.position, target) / maxf(1.0, float(recipient.style_stats.movement().speed) * 0.75)
   apex = maxf(apex, 1.2 + travel * 1.6)
  outgoing = manager.game.ball.solve_pass(last_contact_point, target, apex, spin)
 if strike_technique in [Technique.SPIKE, TIP] and air_attack:
  outgoing = manager.game.ball.solve_power_serve(last_contact_point, target, lerpf(14, 27, style_stats.n("spike")) * lerpf(0.8, 1.0, quality), spin)
 elif strike_technique == Technique.JUMP_SERVE:
  outgoing = manager.game.ball.solve_power_serve(last_contact_point, target, power_serve_speed() * lerpf(0.84, 1.0, quality), spin)
 # Touch is emitted here only after planning the actual outgoing ball. The
 # base signal has no subscribers, avoiding duplicate rules/contact events.
 manager.game._on_player_touch(self, bot_id, strike_technique, last_contact_point, outgoing)
 return outgoing - incoming
