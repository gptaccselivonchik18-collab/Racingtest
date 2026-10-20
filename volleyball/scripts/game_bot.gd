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
var calibration := VolleyBotCalibration.new()
var last_pass_recipient := 0

func _init() -> void:
 super()
 fatigue_enabled = false
 bot_execution = true

func _ready() -> void:
 random_seed = 20261019 + absi(bot_id) * 77
 super._ready()
 var tag := Label3D.new()
 tag.name = "TeamTag"
 tag.text = "%s · БОТ %d" % ["A" if court_team == 0 else "Б", slot + 1]
 tag.position.y = 2.12
 tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 tag.font_size = 36
 tag.pixel_size = 0.006
 tag.modulate = Color("64dce1") if court_team == 0 else Color("ffad79")
 add_child(tag)
 VolleyCharacterPhysicalProfile.apply(self)
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
 noticed_touch = -INF
 reaction_until = 0
 toss_time = 0
 dive_time = -1
 dive_cooldown = 0
 landing_cooldown = 0
 move_axis = Vector2.ZERO
 look_target_valid = false
 contact_error.clear()
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
 energy = 1.0
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
 var braking_margin := 0.65 if manager.counts[court_team] <= 1 else 0.82
 var pace := minf(float(movement.speed), sqrt(2.0 * float(movement.braking) * distance) * braking_margin)
 if character_id == "hinata" and not airborne():
  # Instant acceleration is a physical ability, not an instruction to use
  # full throttle through every destination. The controller eases its input.
  pace = minf(float(movement.speed),distance/0.12)
 var desired := offset.normalized() * pace / float(movement.speed)
 move_axis = manager.tactics.spaced_axis(self, desired)
 var side := 1.0 if court_team == 0 else -1.0
 if not airborne() and move_axis.y*side < 0:
  var margin := 0.60 if block_held or planned_kind == BLOCK or state == "block" else 1.15
  var toward := minf(-move_axis.y*side,maxf(0,position.z*side-margin)/(maxf(1,effective_speed())*0.14))
  move_axis.y = -side*toward
 if offset.length() < stop + 0.12 and Vector2(velocity.x, velocity.z).length() < 0.25:
  move_axis = Vector2.ZERO
 sprint = offset.length() > 2.5
 if offset.length() > 0.6 and action == Action.IDLE:
  camera_yaw = atan2(-offset.x, -offset.y)

func jump(from_approach := false) -> void:
 super.jump(from_approach)
 if from_approach and velocity.y > 0.1:
  # Reserve the whole airborne path plus arm clearance, not just takeoff.
  # This changes bot intent only; human Hinata keeps his original mechanics.
  var side := 1.0 if court_team == 0 else -1.0
  var duration := (velocity.y+sqrt(velocity.y*velocity.y+19.62*maxf(0,position.y)))/9.81
  var toward := -velocity.z*side
  var available := maxf(0,position.z*side-1.45)
  if toward > available/maxf(0.1,duration):
   velocity.z = -side*available/maxf(0.1,duration)
  velocity.x = clampf(velocity.x,-2.5,2.5)

func decide(_dt: float) -> void:
 if cinema_time >= 0:
  move_axis = Vector2.ZERO
  return
 var game := manager.game
 var ball: VolleyBall = game.ball
 var side := 1.0 if court_team == 0 else -1.0
 if (game.characters.demo or character_id=="hinata") and game.characters.ai_step(self,_dt):
  return
 if noticed_touch != manager.last_touch_time:
  noticed_touch = manager.last_touch_time
  reaction_until = manager.clock + float(VolleyBotDifficulty.profile(manager.difficulty).reaction) * (0.82 + fposmod(absi(bot_id) * 0.173, 0.36))
 look_target = ball.position
 look_target_valid = true
 if ball.pending_feed:
  return
 if game.characters.demo and ball.position.y < 1.0 and not is_server:
  if action == Action.PREPARE:
   cancel_input()
  move_axis = Vector2.ZERO
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
    if character_id == "oikawa":
     if game.super_serve.begin(self,bot_id):
      serves += 1
     # Wait for a real grounded/eligible serve, rather than replacing an
     # airborne first frame with an unrelated automatic underhand sequence.
     return
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
   steer(manager.tactics.support(self))
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
  at.z = side * clampf(absf(at.z), 1.05, 11.6)
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
    if manager.tactics.jump_set_useful(self) and float(manager.contact_heights[court_team]) > natural_reach() + 0.35:
     kind = JUMP_SET
   var solo_attack := manager.members(court_team).size() == 1 and manager.last_team != court_team and manager.last_kind not in [3, 4]
   if ((manager.last_team == court_team and manager.touches >= 2 and absf(at.z) < 4.5 and float(manager.contact_heights[court_team]) > 2.35) or (solo_attack and float(manager.contact_heights[court_team]) > 2.65)):
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
   if planned_kind == Technique.OVERHEAD and manager.tactics.jump_set_useful(self) and float(manager.contact_heights[court_team]) > natural_reach() + 0.35 and remaining > 0.20 and not airborne():
    planned_kind = JUMP_SET
    technique = JUMP_SET
   elif planned_kind == JUMP_SET and not airborne() and remaining < 0.20 and float(manager.contact_heights[court_team]) < natural_reach() + 0.35:
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
    var lift := maxf(0.15, float(manager.contact_heights[court_team]) - natural_reach())
    var needed := (lift + 4.905 * remaining * remaining) / remaining
    if needed <= sqrt(19.62 * effective_jump_height()) and horizontal < 0.85:
     jump()
     if velocity.y > 0:
      velocity.y = minf(velocity.y, needed)
      jumps += 1
   var attack_lift := clampf(float(manager.contact_heights[court_team])-natural_reach(),0.25,effective_jump_height())
   var attack_rise := sqrt(2.0*attack_lift/9.81)
   if planned_kind == Technique.SPIKE and not airborne() and remaining <= attack_rise+0.08 and horizontal < 1.8:
    jump(true)
    if velocity.y > 0:
     # Jump to this ball, not to the maximum stat apex every time.
     velocity.y = minf(velocity.y, sqrt(19.62 * attack_lift))
     jumps += 1
   var windup := float(mechanic(planned_kind).windup)
   var receive := planned_kind in [Technique.UNDERHAND, Technique.OVERHEAD, JUMP_SET]
   var height := ball.position.y - position.y
   var spike_due := planned_kind == Technique.SPIKE and horizontal < 1.0 and height > natural_reach() - 0.35 and height < natural_reach() + 0.8 and remaining < float(mechanic(planned_kind).duration) * 0.50
   if charged_for >= windup and (planned_kind != JUMP_SET or airborne()) and ((receive and contact_due()) or spike_due):
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
 return calibration.contact_due(self,manager.game.ball,planned_kind)

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
 var lift := clampf(float(plan.get("height", 3.0)) - natural_reach(), 0.45, effective_jump_height())
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
 if not special_set.is_empty():
  if special_recipient!=null:
   var recipient: Variant=special_recipient.get_ref()
   if is_instance_valid(recipient):last_pass_recipient=recipient.get_instance_id()
  manager.game._on_player_touch(self, bot_id, strike_technique, last_contact_point, incoming + delta)
  return delta
 var target := manager.target_for(self, strike_technique)
 var profile := mechanic(strike_technique)
 # Reuse the contact's single execution sample, including for planned passes.
 # A second independent roll used to replace the base athlete's error.
 var error_angle: Vector2 = contact_error.get("angle", Vector2.ZERO)
 var heading := target - last_contact_point
 heading.y = 0
 strike_direction=heading.normalized()
 var sideways := heading.normalized().cross(Vector3.UP)
 target += sideways * heading.length() * tan(deg_to_rad(error_angle.x))
 var spin := outgoing_spin(manager.game.ball.angular_velocity, delta)
 var own_side := target.z * (1.0 if court_team == 0 else -1.0) > 0
 var apex := 2.8 if own_side else maxf(2.0, 3.7 - last_contact_point.y * 0.4)
 apex *= float(profile.get("arc", profile.get("lift", 1.0)))
 apex *= clampf(1.0 + error_angle.y * 0.04, 0.7, 1.3)
 var outgoing: Vector3 = manager.game.ball.solve_launch(last_contact_point, target, apex, spin)
 if own_side:
  var plan := manager.tactics.pass_plan(self, strike_technique)
  if not plan.is_empty() and bool(plan.attacking):
   var recipient: ContextAthlete = plan.recipient
   last_pass_recipient=recipient.get_instance_id()
   var travel := VolleyBotTactics.flat(recipient.position, target) / maxf(1.0, recipient.speed_toward(Vector2(target.x-recipient.position.x,target.z-recipient.position.z)) * 0.75)
   apex = maxf(apex, 1.2 + travel * 1.6)
  outgoing = manager.game.ball.solve_pass(last_contact_point, target, apex, spin)
 if strike_technique in [Technique.SPIKE, TIP] and air_attack:
  outgoing = manager.game.ball.solve_power_serve(last_contact_point, target, lerpf(14, 27, style_stats.n("spike")) * lerpf(0.8, 1.0, quality), spin)
 elif strike_technique == Technique.JUMP_SERVE:
  outgoing = manager.game.ball.solve_power_serve(last_contact_point, target, power_serve_speed() * lerpf(0.84, 1.0, quality), spin)
 outgoing *= float(contact_error.get("pace", 1.0))
 if not own_side:
  # Validate the FINAL impulse/spin after execution variation, at the actual
  # contact height. A too-low hit needs lift, not an impossible hard spike.
  spin=outgoing_spin(manager.game.ball.angular_velocity,outgoing-incoming)
  var flight: Dictionary=manager.game.ball.power_serve_flight(last_contact_point,outgoing,spin)
  if float(flight.net_clearance)<2.85 or float(flight.net_height)<2.90:
   var lift:=0.65
   for attempt in range(10):
    outgoing=manager.game.ball.solve_lifted_hit(last_contact_point,target,lift,spin)
    flight=manager.game.ball.power_serve_flight(last_contact_point,outgoing,spin)
    if float(flight.net_clearance)>=2.85 and float(flight.net_height)>=2.90:break
    lift=lift*1.35+0.20
 # Touch is emitted here only after planning the actual outgoing ball. The
 # base signal has no subscribers, avoiding duplicate rules/contact events.
 manager.game._on_player_touch(self, bot_id, strike_technique, last_contact_point, outgoing)
 return outgoing - incoming
