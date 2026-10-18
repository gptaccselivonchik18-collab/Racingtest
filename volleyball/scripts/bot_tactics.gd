class_name VolleyBotTactics
extends RefCounted

var manager: VolleyGameBots
const SPACE := 1.45
var assignments := [0, 0]
var assigned_at := [0.0, 0.0]
var plans: Dictionary = {}
var shots: Dictionary = {}

func reset() -> void:
 assignments = [0, 0]
 assigned_at = [0.0, 0.0]
 plans.clear()
 shots.clear()

static func flat(a: Vector3, b: Vector3) -> float:
 return Vector2(a.x - b.x, a.z - b.z).length()

func humans() -> Array:
 if manager.game.lan.active:
  return manager.game.lan.players.values().map(func(p: Dictionary): return p.actor)
 return [manager.game.athlete]

func human_pickup_near() -> bool:
 for human in humans():
  if manager.game.ball.can_pick_up_for(human):
   return true
 return false

func jump_set_useful(actor: VolleyGameBot) -> bool:
 var ball: VolleyBall = manager.game.ball
 # Take high balls early near the net or on a fast lateral pass. A calm,
 # deep set is safer on the floor; jumping is not an automatic upgrade.
 return manager.difficulty >= 2 and manager.last_team == actor.court_team and manager.touches == 1 and (absf(ball.position.z) < 2.0 or Vector2(ball.linear_velocity.x, ball.linear_velocity.z).length() > 2.5)

func choose_receivers() -> void:
 var difficulty := manager.decision_profile()
 for team in range(2):
  if manager.last_team == team and (manager.last_kind in [3, 4] or manager.touches >= 3):
   # Yield an outgoing serve/third touch. Extra teammates near the flight
   # path must not chase their own serve or add an illegal fourth touch.
   continue
  var side := 1.0 if team == 0 else -1.0
  var teammates := manager.members(team)
  var solo_attack := teammates.size() == 1 and manager.last_team != team and manager.last_kind not in [3, 4]
  var candidates: Dictionary = {}
  for actor: ContextAthlete in teammates:
   if actor == manager.last_actor and manager.last_kind != ContextAthlete.BLOCK:
    continue
   if actor is VolleyGameBot and (actor.cooldown > 0 or actor.action == VolleyAthlete.Action.RECOVER or (actor.action == VolleyAthlete.Action.STRIKE and actor.hit_used)):
    continue
   var id: int = actor.bot_id if actor is VolleyGameBot else manager.game.lan.player_id(actor) if manager.game.lan.active else 1
   var physical := actor.style_stats.movement()
   for sample in manager.samples:
    if float(sample.time) > float(difficulty.lookahead):
     continue
    var point: Vector3 = sample.at
    if point.z * side < 0.48 or point.y < 0.18 or point.y > 3.6 or sample.v.y > 2:
     continue
    var target := point + Vector3(0, 0, side * 0.34)
    target.y = 0.02
    var distance := flat(target, actor.position)
    var reaction: float = float(difficulty.reaction) if actor is VolleyGameBot else 0.12
    var speed: float = float(physical.speed)
    var movement := float(difficulty.anticipation) if actor is VolleyGameBot else 0.8 if actor.move_axis.length() > 0.15 else 0.0
    var available := maxf(0, float(sample.time) - reaction)
    var initial := maxf(0, Vector2(actor.velocity.x, actor.velocity.z).dot(Vector2(target.x - actor.position.x, target.z - actor.position.z).normalized()))
    var acceleration: float = float(physical.acceleration)
    var accelerating := minf(available, maxf(0, speed - initial) / acceleration)
    var running := initial * accelerating + 0.5 * acceleration * accelerating * accelerating + speed * maxf(0, available - accelerating)
    var reachable := running * movement + (0.75 if actor is VolleyGameBot else 1.45)
    var diving := false
    if distance > reachable:
     if not actor is VolleyGameBot or actor.dive_cooldown > 0 or actor.position.y > 0.12 or actor.velocity.y > 0.2 or point.y > 1.45:
      continue
     var dive := actor.mechanic(ContextAthlete.DIVE)
     var time := minf(float(sample.time) - reaction, float(dive.contact_to))
     if time < float(dive.contact_from) or time <= 0:
      continue
     var run_time := maxf(0, float(sample.time) - reaction - float(dive.contact_to))
     var slide := float(dive.speed) * time * (1.0 - 0.5 * time / float(dive.travel))
     if distance > run_time * speed * movement + slide + 0.75:
      continue
     diving = true
    var high := (manager.last_team == team and manager.touches >= 2 and absf(point.z) < 4.5) or solo_attack
    var preferred := 2.95 if high else 2.05 if manager.last_team == team else 1.35
    if actor is VolleyGameBot and jump_set_useful(actor):
     var lift := maxf(0, point.y - 2.15)
     var time := minf(0.50, available)
     var needed := (lift + 4.905 * time * time) / maxf(0.01, time)
     if point.y > 2.55 and (time < 0.20 or needed > sqrt(19.62 * float(physical.jump_height))):
      continue
     preferred = minf(2.95, 2.15 + float(physical.jump_height) * 0.75)
    var cost := absf(point.y - preferred) * 0.8 + distance * 0.22 + float(sample.time) * 0.12
    cost += 0.55 if diving else 0.0
    if not actor is VolleyGameBot:
     cost -= 0.85 # A human already in reach gets room to play.
    if not candidates.has(id) or cost < float(candidates[id].cost):
     candidates[id] = {"cost": cost, "target": target, "arrival": manager.clock + float(sample.time), "actor": actor, "dive": diving, "height": point.y}
  var selected := 0
  var cost := INF
  for id in candidates:
   if float(candidates[id].cost) < cost:
    cost = float(candidates[id].cost)
    selected = id
  # Keep a reachable player on this ball. Small fluctuations cannot send
  # the whole team alternately rushing into the same reception corridor.
  var previous: int = assignments[team]
  if candidates.has(previous) and (manager.clock - assigned_at[team] < 0.55 or float(candidates[previous].cost) < cost + 0.85):
   selected = previous
  if selected != previous:
   assignments[team] = selected
   assigned_at[team] = manager.clock
  if selected != 0:
   manager.receivers[team] = selected
   manager.intercepts[team] = candidates[selected].target
   manager.arrival[team] = candidates[selected].arrival
   manager.receive_dives[team] = candidates[selected].dive
   manager.contact_heights[team] = candidates[selected].height
   var receiver: ContextAthlete = candidates[selected].actor
   if receiver is VolleyGameBot:
    var kind := VolleyAthlete.Technique.OVERHEAD if manager.last_team == team and manager.touches > 0 else VolleyAthlete.Technique.UNDERHAND
    if manager.last_team != team or manager.touches < 2:
     pass_plan(receiver, kind)

func serve_target(actor: VolleyGameBot) -> Vector3:
 if actor.serve_aim.is_finite():
  return actor.serve_aim
 actor.serve_aim = choose_shot(actor, true)
 actor.serve_history.append(actor.serve_aim)
 if actor.serve_history.size() > 3:
  actor.serve_history.pop_front()
 return actor.serve_aim

func coverage_at(point: Vector3, opponents: Array, reading: float) -> float:
 var nearest := 6.0
 var second := 6.0
 for opponent: ContextAthlete in opponents:
  # Only visible position and movement: no human identity or hidden input.
  var observed := opponent.position + Vector3(opponent.velocity.x, 0, opponent.velocity.z).limit_length(3) * reading * 0.35
  var distance := flat(point, observed)
  if distance < nearest:
   second = nearest
   nearest = distance
  elif distance < second:
   second = distance
 # A seam between receivers is useful, but never outweighs a truly open lane.
 return nearest + maxf(0, 1.0 - absf(second - nearest)) * 0.25 * reading

func block_obstruction(origin: Vector3, target: Vector3, opponents: Array) -> float:
 var fraction := absf(origin.z) / maxf(0.1, absf(target.z - origin.z))
 var crossing := lerpf(origin.x, target.x, fraction)
 var obstruction := 0.0
 for opponent: ContextAthlete in opponents:
  if absf(opponent.position.z) < 1.6:
   var ready := 1.0 if opponent.block_held or opponent.airborne() else 0.55
   obstruction = maxf(obstruction, maxf(0, 1.5 - absf(crossing - opponent.position.x)) * ready)
 return obstruction

func choose_shot(actor: VolleyGameBot, serving: bool) -> Vector3:
 var profile := manager.decision_profile()
 var reading := float(profile.court_read)
 var opponents := manager.members(1 - actor.court_team)
 var side := -1.0 if actor.court_team == 0 else 1.0
 var best := Vector3(0, VolleyBall.RADIUS, side * 6)
 var best_score := -INF
 var xs := [-3.3, 0.0, 3.3] if manager.difficulty < 3 else [-3.3, -1.65, 0.0, 1.65, 3.3]
 for x in xs:
  for depth in [3.2, 5.5, 7.7]:
   var target := Vector3(x, VolleyBall.RADIUS, side * depth)
   # At reception height the ball is still short of its floor target.
   var receive_at := target - Vector3(0, 0, side * (0.8 if serving else 0.3))
   var score := coverage_at(receive_at, opponents, reading) * reading
   score -= absf(x) * (1.0 - reading) * 0.08
   if not serving:
    score -= block_obstruction(actor.position, target, opponents) * reading * 1.8
   else:
    for previous in actor.serve_history:
     score -= maxf(0, 2.8 - flat(target, previous)) * (0.18 + reading * 0.45)
   # Sample once per decision, not every frame or during the ball toss.
   score += actor.rng.randf_range(-float(profile.decision_noise), float(profile.decision_noise))
   if score > best_score:
    best_score = score
    best = target
 return best

func attack_target(actor: VolleyGameBot, kind: int) -> Vector3:
 var key := "%d:%d" % [actor.bot_id, kind]
 var saved: Dictionary = shots.get(key, {})
 if not saved.is_empty() and float(saved.epoch) == manager.last_touch_time:
  return saved.target
 var target := choose_shot(actor, false)
 shots[key] = {"epoch": manager.last_touch_time, "target": target}
 return target

func block_plan(actor: VolleyGameBot) -> Dictionary:
 var ball: VolleyBall = manager.game.ball
 var side := 1.0 if actor.court_team == 0 else -1.0
 if ball.held or ball.position.z * side > 0.5 or absf(ball.position.x) > 5.2:
  return {}
 if manager.last_team == 1 - actor.court_team and manager.last_kind in [VolleyAthlete.Technique.SERVE, VolleyAthlete.Technique.JUMP_SERVE]:
  return {}
 var target := Vector3(ball.position.x, 0.02, side * 0.65)
 var time := INF
 var commit := false
 var attack := manager.last_team == 1 - actor.court_team and manager.last_kind in [VolleyAthlete.Technique.SPIKE, ContextAthlete.TIP]
 if not attack and manager.difficulty < 2:
  # Beginners react to the hit; experienced defenders read the preparation.
  return {}
 if attack and ball.linear_velocity.z * side > 0:
  # A new strike may precede the next shared 10 Hz prediction. Read its
  # current velocity immediately rather than the previous shot's samples.
  time = (side * 0.15 - ball.position.z) / ball.linear_velocity.z
  var point := ball.position + ball.linear_velocity * time + Vector3.DOWN * 4.905 * time * time
  if time < 0 or time > 1.1 or point.y < 2.2 or point.y > 2.4 + float(actor.style_stats.movement().jump_height):
   return {}
  target.x = point.x
  commit = true
 if not is_finite(time):
  if ball.position.z * side >= 0 or absf(ball.position.z) > 4.8 or ball.position.y < 2.1:
   return {}
  for opponent: ContextAthlete in manager.members(1 - actor.court_team):
   var kind := opponent.planned_technique() if opponent.action == VolleyAthlete.Action.PREPARE else opponent.strike_technique
   if kind not in [VolleyAthlete.Technique.SPIKE, ContextAthlete.TIP] or opponent.action not in [VolleyAthlete.Action.PREPARE, VolleyAthlete.Action.STRIKE] or flat(opponent.position, ball.position) > 2.1:
    continue
   target.x = opponent.position.x + opponent.velocity.x * 0.15
   time = clampf(0.18 + flat(opponent.position, ball.position) / maxf(3, ball.linear_velocity.length()), 0.18, 0.8)
   commit = opponent.airborne() or opponent.action == VolleyAthlete.Action.STRIKE
   break
  if not is_finite(time):
   if manager.last_team != 1 - actor.court_team or manager.touches < 1 or ball.linear_velocity.y > 4:
    return {}
   # Move a front defender into the lane while the opponent builds the attack.
   time = 0.8
 target.x = clampf(target.x, -4, 4)
 var chosen: ContextAthlete
 var best := INF
 for teammate: ContextAthlete in manager.members(actor.court_team):
  if not teammate is VolleyGameBot:
   if teammate.block_held and flat(teammate.position, target) < 1.1:
    return {}
   continue
  if teammate.cooldown > 0 or teammate.action != VolleyAthlete.Action.IDLE or teammate.dive_time >= 0:
   continue
  var distance := flat(teammate.position, target)
  var arrival := distance / maxf(1, float(teammate.style_stats.movement().speed))
  if arrival > time + 0.38:
   continue
  if arrival < best:
   best = arrival
   chosen = teammate
 if chosen != actor:
  return {}
 return {"target": target, "time": time, "commit": commit, "height": clampf(ball.position.y, 2.8, 4.2)}

func pass_point(recipient: ContextAthlete, setter: ContextAthlete, attacking: bool) -> Vector3:
 var team: int = setter.court_team
 var side := 1.0 if team == 0 else -1.0
 var until_contact := clampf(manager.arrival[team] - manager.clock, 0, 1.3)
 var reading := float(manager.decision_profile().court_read)
 var lead := Vector3(recipient.velocity.x, 0, recipient.velocity.z) * minf(0.75, until_contact + 0.35) * lerpf(0.15, 1.0, reading)
 lead = lead.limit_length(2.0)
 var point := recipient.position + lead
 if recipient is VolleyGameBot:
  # A fixed receiving lane avoids chasing a target that is recomputed from
  # the recipient's own support movement on every frame.
  point = manager.home(team, recipient.slot)
  point.z = side * (2.15 if attacking else 3.0)
  point.x = clampf(point.x, -3.2, 3.2)
 # Offer a forward approach that the recipient can actually reach; a deep
 # human is still a teammate, not an invisible spectator outside a bot grid.
 var forward := 0.70 if attacking else 0.40
 point.z -= side * forward
 point.x = clampf(point.x, -3.8, 3.8)
 point.z = side * clampf(point.z * side, 1.35, 8.5)
 point.y = 2.75 if attacking else 2.05
 return point

func pass_plan(actor: VolleyGameBot, kind: int) -> Dictionary:
 var own_touches := manager.touches if manager.last_team == actor.court_team else 0
 var attacking := kind in [VolleyAthlete.Technique.OVERHEAD, ContextAthlete.JUMP_SET]
 var key := "%d:%d:%s" % [actor.bot_id, own_touches, attacking]
 var previous: Dictionary = plans.get(key, {})
 if not previous.is_empty() and float(previous.epoch) == manager.last_touch_time and is_instance_valid(previous.recipient) and previous.recipient in manager.members(actor.court_team):
  if not previous.recipient is VolleyGameBot:
   previous.target = pass_point(previous.recipient, actor, attacking)
  return previous
 var friend: ContextAthlete
 var best := -INF
 var side := 1.0 if actor.court_team == 0 else -1.0
 for teammate: ContextAthlete in manager.members(actor.court_team):
  if teammate == actor or teammate.holding_ball or teammate.dive_time >= 0:
   continue
  var point := pass_point(teammate, actor, attacking)
  var depth := point.z * side
  var score := -absf(depth - (2.6 if attacking else 3.1)) * 0.70
  score -= absf(point.x) * (0.06 if attacking else 0.16)
  score -= flat(actor.position, point) * 0.045
  score -= flat(teammate.position, point) * 0.22
  score += teammate.style_stats.n("spike" if attacking else "set") * 0.45
  if not teammate is VolleyGameBot:
   score += 0.55
  if attacking:
   var open := 4.5
   for opponent: ContextAthlete in manager.members(1 - actor.court_team):
    if absf(opponent.position.z) < 3.3:
     open = minf(open, absf(point.x - opponent.position.x))
   score += minf(open, 3) * 0.45 * float(manager.decision_profile().court_read)
   score += clampf(-teammate.velocity.z * side, -2, 2) * 0.12
  if manager.difficulty == 0:
   # A beginner can perform the same techniques, but usually chooses the
   # closest available partner instead of planning the next attack lane.
   score = -flat(actor.position, teammate.position)
  elif manager.difficulty == 1:
   score = score * 0.35 - flat(actor.position, teammate.position) * 0.25
  if score > best:
   best = score
   friend = teammate
 if not is_instance_valid(friend):
  return {}
 var plan := {"epoch": manager.last_touch_time, "recipient": friend, "target": pass_point(friend, actor, attacking), "attacking": attacking}
 plans[key] = plan
 return plan

func support(actor: VolleyGameBot) -> Vector3:
 for plan: Dictionary in plans.values():
  if float(plan.epoch) == manager.last_touch_time and is_instance_valid(plan.recipient) and plan.recipient == actor:
   var point: Vector3 = plan.target
   point.y = 0.02
   return point
 var target := manager.home(actor.court_team, actor.slot)
 var reading := float(manager.decision_profile().coverage)
 target.x = clampf(target.x + manager.game.ball.position.x * lerpf(0.02, 0.18, reading), -3.9, 3.9)
 var side := 1.0 if actor.court_team == 0 else -1.0
 if reading > 0.2 and manager.last_team == 1 - actor.court_team:
  for teammate: ContextAthlete in manager.members(actor.court_team):
   if teammate != actor and teammate.block_held:
    # Rear defenders cover beside the block; front teammates protect tips.
    if target.z * side > 4:
     var direction := signf(target.x - teammate.position.x)
     target.x = clampf(target.x + direction * reading * 0.55, -3.9, 3.9)
     target.z += side * reading * 0.35
    else:
     target.z = side * lerpf(absf(target.z), 2.1, reading)
    break
 return target

func spaced_axis(actor: VolleyGameBot, desired: Vector2) -> Vector2:
 var avoidance := Vector2.ZERO
 var receiving: bool = manager.receivers[actor.court_team] == actor.bot_id
 for other: ContextAthlete in manager.members(actor.court_team):
  if other == actor:
   continue
  var offset := Vector2(actor.position.x - other.position.x, actor.position.z - other.position.z)
  var distance := offset.length()
  var radius := SPACE if not receiving else 0.85
  if distance >= radius:
   continue
  if distance < 0.02:
   offset = Vector2.RIGHT if actor.get_instance_id() < other.get_instance_id() else Vector2.LEFT
  var priority := 0.75 if receiving else 1.35
  avoidance += offset.normalized() * (1.0 - distance / radius) * priority
 var axis := desired + avoidance
 # Yield sideways as well as slowing down, so opposite paths don't deadlock.
 if desired.length() > 0.1 and avoidance.dot(desired) < -0.1:
  axis += Vector2(-desired.y, desired.x) * (0.20 if actor.slot % 2 == 0 else -0.20)
 return axis.limit_length()
