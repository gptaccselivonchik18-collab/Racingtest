class_name VolleyBotTactics
extends RefCounted

var manager: VolleyGameBots
const SPACE := 1.45
var assignments := [0, 0]
var assigned_at := [0.0, 0.0]
var plans: Dictionary = {}

func reset() -> void:
 assignments = [0, 0]
 assigned_at = [0.0, 0.0]
 plans.clear()

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

func choose_receivers() -> void:
 var difficulty := VolleyBotDifficulty.profile(manager.difficulty)
 for team in range(2):
  var side := 1.0 if team == 0 else -1.0
  var candidates: Dictionary = {}
  for actor: ContextAthlete in manager.members(team):
   if actor == manager.last_actor and manager.last_kind != ContextAthlete.BLOCK:
    continue
   if actor is VolleyGameBot and (actor.cooldown > 0 or actor.action == VolleyAthlete.Action.RECOVER or (actor.action == VolleyAthlete.Action.STRIKE and actor.hit_used)):
    continue
   var id: int = actor.bot_id if actor is VolleyGameBot else manager.game.lan.player_id(actor) if manager.game.lan.active else 1
   for sample in manager.samples:
    var point: Vector3 = sample.at
    if point.z * side < 0.48 or point.y < 0.4 or point.y > 3.6 or sample.v.y > 2:
     continue
    var target := point + Vector3(0, 0, side * 0.34)
    target.y = 0.02
    var distance := flat(target, actor.position)
    var reaction: float = float(difficulty.reaction) if actor is VolleyGameBot else 0.12
    var speed: float = float(actor.style_stats.movement().speed)
    var movement := float(difficulty.anticipation) if actor is VolleyGameBot else 0.8 if actor.move_axis.length() > 0.15 else 0.0
    var reachable := maxf(0, float(sample.time) - reaction) * speed * movement + (0.75 if actor is VolleyGameBot else 1.45)
    if distance > reachable:
     continue
    var high := manager.last_team == team and manager.touches >= 2 and absf(point.z) < 4.5
    var preferred := 2.95 if high else 2.05 if manager.last_team == team else 1.35
    var cost := absf(point.y - preferred) * 0.8 + distance * 0.22 + float(sample.time) * 0.12
    if not actor is VolleyGameBot:
     cost -= 0.85 # A human already in reach gets room to play.
    if not candidates.has(id) or cost < float(candidates[id].cost):
     candidates[id] = {"cost": cost, "target": target, "arrival": manager.clock + float(sample.time), "actor": actor}
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
   var receiver: ContextAthlete = candidates[selected].actor
   if receiver is VolleyGameBot:
    var kind := VolleyAthlete.Technique.OVERHEAD if manager.last_team == team and manager.touches > 0 else VolleyAthlete.Technique.UNDERHAND
    if manager.last_team != team or manager.touches < 2:
     pass_plan(receiver, kind)

func pass_point(recipient: ContextAthlete, setter: ContextAthlete, attacking: bool) -> Vector3:
 var team: int = setter.court_team
 var side := 1.0 if team == 0 else -1.0
 var until_contact := clampf(manager.arrival[team] - manager.clock, 0, 1.3)
 var lead := Vector3(recipient.velocity.x, 0, recipient.velocity.z) * minf(0.75, until_contact + 0.35)
 lead = lead.limit_length(2.0)
 var point := recipient.position + lead
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
   score += minf(open, 3) * 0.45
   score += clampf(-teammate.velocity.z * side, -2, 2) * 0.12
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
 target.x = clampf(target.x + manager.game.ball.position.x * 0.12, -3.9, 3.9)
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
