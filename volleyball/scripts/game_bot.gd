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
 var braking: float = maxf(stop, Vector2(velocity.x, velocity.z).length() * 0.12)
 move_axis = offset.normalized() * clampf((offset.length() - stop) / maxf(braking, 0.3), 0, 1)
 sprint = offset.length() > 2.5
 if offset.length() > 0.6 and action == Action.IDLE:
  camera_yaw = atan2(-offset.x, -offset.y)

func decide(_dt: float) -> void:
 var game := manager.game
 var ball: VolleyBall = game.ball
 var side := 1.0 if court_team == 0 else -1.0
 look_target = ball.position
 look_target_valid = true
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
    if serves % 4 == 3:
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
    var controller: VolleyLowerServe = game.float_serve if serves % 3 == 2 else game.lower_serve
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
 if action == Action.RECOVER:
  planned_kind = -1
  move_axis *= 0.5
  return
 if action == Action.STRIKE:
  move_axis = Vector2.ZERO
  return
 var dead := ball.position.y < 0.65 and ball.linear_velocity.length() < 3.0 and not ball.pending_feed
 if dead and cooldown <= 0 and not game.automatic_serve_busy():
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
     serve_wait = 0.55
     manager.reset_rally()
     is_server = nominated_server
   return
 if attempt_block(side):
  return
 if manager.receivers[court_team] == bot_id:
  state = "intercept"
  var at: Vector3 = manager.intercepts[court_team]
  at.x = clampf(at.x, -7.6, 7.6)
  at.z = side * clampf(absf(at.z), 0.65, 11.6)
  steer(at, 0.10)
  var remaining: float = manager.arrival[court_team] - manager.clock
  var offset := ball.position - position
  var horizontal := Vector2(offset.x, offset.z).length()
  if action == Action.IDLE and remaining < 0.65 and horizontal < 2.5 and cooldown <= 0:
   var kind := Technique.UNDERHAND
   if manager.last_team == court_team and manager.touches > 0:
    kind = Technique.OVERHEAD
   if manager.last_team == court_team and manager.touches >= 2 and absf(at.z) < 4.5 and ball.position.y > 2.5:
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
   var aim := manager.target_for(self, planned_kind)
   var toward := aim - position
   camera_yaw = atan2(-toward.x, -toward.z)
   camera_pitch = deg_to_rad(55 if planned_kind == Technique.OVERHEAD else 20)
   if planned_kind == Technique.SPIKE and not airborne() and remaining < 0.45:
    jump()
    if velocity.y > 0:
     jumps += 1
   var local_height := ball.position.y - position.y
   var reachable := local_height < (3.0 if planned_kind == Technique.SPIKE else 2.65) and local_height > (1.85 if planned_kind == Technique.SPIKE else 0.4)
   if horizontal < 1.0 and reachable and (remaining < 0.17 or local_height < 1.0) and charged_for >= 0.13:
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
  var support := manager.home(court_team, slot)
  if manager.last_team == court_team:
   support.z = side * (1.9 if manager.touches < 2 else 3.0)
  support.x = clampf(support.x + ball.position.x * 0.18, -3.7, 3.7)
  steer(support)
  camera_yaw = 0 if side > 0 else PI

func attempt_block(side: float) -> bool:
 var ball: VolleyBall = manager.game.ball
 if absf(position.z) > 2.5 or ball.position.z * side >= 0 or absf(ball.position.z) > 4.0 or ball.position.y < 2.5:
  return false
 if manager.last_team != 1 - court_team or manager.last_kind not in [Technique.SPIKE, Technique.JUMP_SERVE] or cooldown > 0 or action != Action.IDLE:
  return false
 var blocker: ContextAthlete = null
 var best := INF
 for teammate in manager.members(court_team):
  var distance: float = teammate.position.distance_squared_to(Vector3(ball.position.x, 0, side * 0.7))
  if distance < best:
   best = distance
   blocker = teammate
 if blocker != self:
  return false
 state = "block"
 steer(Vector3(clampf(ball.position.x, -4, 4), 0.02, side * 0.7))
 camera_yaw = 0 if side > 0 else PI
 if absf(position.z) < 1.25:
  jump()
  if velocity.y > 0.1 and begin_action(BLOCK):
   charged_for = 0.16
   release()
   jumps += 1
 return true

func try_swept_contact(from: Vector3, center: Vector3, incoming: Vector3, attack: Dictionary = {}) -> Vector3:
 var delta := super.try_swept_contact(from, center, incoming, attack)
 if delta == Vector3.ZERO:
  return delta
 contacts += 1
 jump_serving = false
 contact_kinds[strike_technique] = int(contact_kinds.get(strike_technique, 0)) + 1
 cooldown = 0.65
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
 if strike_technique in [Technique.SPIKE, TIP] and air_attack:
  outgoing = manager.game.ball.solve_power_serve(last_contact_point, target, lerpf(14, 27, style_stats.n("spike")) * lerpf(0.8, 1.0, quality), spin)
 elif strike_technique == Technique.JUMP_SERVE:
  outgoing = manager.game.ball.solve_power_serve(last_contact_point, target, power_serve_speed() * lerpf(0.84, 1.0, quality), spin)
 # Touch is emitted here only after planning the actual outgoing ball. The
 # base signal has no subscribers, avoiding duplicate rules/contact events.
 manager.game._on_player_touch(self, bot_id, strike_technique, last_contact_point, outgoing)
 return outgoing - incoming
