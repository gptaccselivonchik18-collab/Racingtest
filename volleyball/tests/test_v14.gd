extends SceneTree
var game: Node3D
var attacker: ContextAthlete
var blocker: ContextAthlete
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, note: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", note)
 else:
  failures += 1
  push_error("FAIL: " + note)

func pose(actor: ContextAthlete, kind: int, at: Vector3, yaw: float) -> void:
 actor.cancel_input()
 actor.action = VolleyAthlete.Action.IDLE
 actor.holding_ball = false
 actor.release_time = 0
 actor.dive_time = -1
 actor.position = at
 actor.velocity = Vector3.ZERO
 actor.visual.rotation = Vector3(0, yaw, 0)
 actor.camera_yaw = yaw
 actor.camera_pitch = 0.4
 actor.approach_jump = kind == 2
 actor.begin_action(kind)
 actor.charged_for = 0.2
 if kind != ContextAthlete.BLOCK:
  actor.release()
 actor.action_time = actor.strike_duration * 0.47
 actor._update_pose(0)
 actor.previous_wrists = actor.wrists.duplicate()
 actor.previous_elbows = actor.elbows.duplicate()

func attack() -> void:
 pose(attacker, 2, Vector3(0, 1.25, 3), 0)
 attacker.try_contact(attacker.wrists[1], Vector3.ZERO)
 game.ball.remember_contact(attacker)

func block_pose() -> void:
 pose(blocker, 6, Vector3(0, 1.25, -3), PI)

func sample_contacts(spike: float, block: float) -> Dictionary:
 attacker.stats.set_stat("spike", spike)
 blocker.stats.set_stat("block", block)
 blocker.reset_seed(14014)
 var count := 0
 var chance := 0.0
 var valid := true
 var incoming := Vector3(0, -8, -20)
 for i in range(1000):
  attack()
  block_pose()
  var outgoing: Vector3 = blocker.try_contact(blocker.wrists[1], incoming, game.ball.attack_for(blocker)) + incoming
  var result: Dictionary = blocker.duel_result
  count += int(result.pierced)
  chance += float(result.pierce_chance) / 1000
  valid = valid and outgoing.is_finite() and (outgoing.z < 0 if result.pierced else outgoing.z > 0)
  if result.pierced:
   valid = valid and outgoing.length() >= incoming.length() * 0.93 and outgoing.length() <= incoming.length() and outgoing.normalized().dot(incoming.normalized()) > 0.97
 return {"rate": count / 1000.0, "chance": chance, "directions": valid}

func trial(want_pierce: bool) -> Dictionary:
 var incoming := Vector3(0, -8, -20)
 block_pose()
 var context: Dictionary
 var selected := -1
 for seed_value in range(100):
  attack()
  block_pose()
  blocker.reset_seed(seed_value)
  blocker.try_contact(blocker.wrists[1], incoming, game.ball.attack_for(blocker))
  if bool(blocker.duel_result.pierced) == want_pierce:
   selected = seed_value
   break
 block_pose()
 blocker.reset_seed(selected)
 var start: Vector3 = blocker.wrists[1] - incoming.normalized() * 0.25
 var before := blocker.contact_count
 game.ball.contact_athletes = [blocker]
 game.ball.feed(start, incoming, Vector3(4, 2, 1))
 while game.ball.pending_feed:
  await physics_frame
 attack()
 # Real ball integration, sweep, impulse and spin, with exactly one block.
 for frame in range(10):
  await physics_frame
  if blocker.contact_count > before:
   return {"hit": true, "pierced": blocker.duel_result.pierced, "velocity": game.ball.linear_velocity, "count": blocker.contact_count - before, "duel": game.ball.last_duel.duplicate()}
 return {"hit": false}

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 game.set_process(false)
 game.set_physics_process(false)
 attacker = game.athlete
 attacker.set_physics_process(false)
 attacker.replica = true
 attacker.court_team = 0
 attacker.style_stats.reset_all()
 blocker = ContextAthlete.new()
 game.add_child(blocker)
 blocker.set_physics_process(false)
 blocker.replica = true
 blocker.court_team = 1
 blocker.style_stats.reset_all()
 check(is_equal_approx(VolleyBlockDuel.pierce_probability(0.5, 0.5, 0.85, 0.85, 20), 0.5), "Equal ratings and conditions give exactly 50/50")
 var monotonic := true
 var previous := -1.0
 for i in range(101):
  var p := VolleyBlockDuel.pierce_probability(i / 100.0, 0.5, 0.85, 0.85, 20)
  monotonic = monotonic and p >= previous
  previous = p
 check(monotonic, "Every increase in Spike improves the pierce probability")
 monotonic = true
 previous = 2.0
 for i in range(101):
  var p := VolleyBlockDuel.pierce_probability(0.5, i / 100.0, 0.85, 0.85, 20)
  monotonic = monotonic and p <= previous
  previous = p
 check(monotonic, "Every increase in Block improves the block probability")
 check(VolleyBlockDuel.pierce_probability(1, 0, 1, 0, 50, 0) <= 0.95 and VolleyBlockDuel.pierce_probability(0, 1, 0, 1, 0) >= 0.05, "Neither extreme stat experiments nor perfect contacts guarantee a win")
 check(VolleyBlockDuel.pierce_probability(0.5, 0.5, 1, 0.4, 20) > 0.6, "Clean spike against a mistimed or edge block gains an advantage")
 check(VolleyBlockDuel.pierce_probability(0.5, 0.5, 0.4, 1, 20) < 0.4, "Good block timing and contact beat a poor attack more often")
 check(VolleyBlockDuel.pierce_probability(0.5, 0.5, 0.8, 0.8, 30) > VolleyBlockDuel.pierce_probability(0.5, 0.5, 0.8, 0.8, 8), "Actual incoming pace reflects charge, airborne power and flight loss")
 check(VolleyBlockDuel.pierce_probability(0.5, 0.5, 0.8, 0.8, 20, 0.1) > VolleyBlockDuel.pierce_probability(0.5, 0.5, 0.8, 0.8, 20, 1), "Glancing contact is harder to seal than square hands")
 check(VolleyBlockDuel.pierce_probability(0.5, 0.5, 0.8, 0.8, 7, 1, true) < 0.3, "A soft tip does not pierce like a full spike")
 var equal := sample_contacts(65, 65)
 var strong := sample_contacts(165, -35)
 var defense := sample_contacts(-35, 165)
 print("Duel samples rate/mean chance: equal=", equal, " attack=", strong, " defense=", defense)
 check(absf(equal.rate - equal.chance) < 0.045 and equal.rate > 0.4 and equal.rate < 0.6, "1000 actual equal-stat contacts contain both outcomes at the expected frequency")
 check(strong.rate > equal.rate + 0.25 and strong.rate < 0.98, "High Spike against low Block wins substantially more often but can be stopped")
 check(defense.rate < equal.rate - 0.25 and defense.rate > 0.02, "High Block against low Spike stops substantially more often but can be pierced")
 check(absf(strong.rate - strong.chance) < 0.045 and absf(defense.rate - defense.chance) < 0.045, "Both asymmetric 1000-contact samples match their probabilities")
 check(equal.directions and strong.directions and defense.directions, "All 3000 contacts rebound or continue forward with finite, dissipative velocities")
 attacker.style_stats.reset_all()
 blocker.style_stats.reset_all()
 attack()
 block_pose()
 var b: VolleyBall = game.ball
 var saved := b.attack_skill
 attacker.stats.set_stat("spike", 999)
 check(is_equal_approx(b.attack_for(blocker).skill, saved), "Changing attacker stats mid-flight cannot rewrite the original hit")
 attacker.stats.set_stat("set", -999)
 blocker.stats.set_stat("serve", 999)
 check(is_equal_approx(b.attack_for(blocker).skill, saved), "Unrelated Set and Serve cannot affect this Spike/Block contest")
 blocker.court_team = 0
 check(b.attack_for(blocker).is_empty(), "A teammate cannot contest its own side's attack")
 blocker.court_team = 1
 attacker.strike_technique = 6
 check(b.attack_for(attacker).is_empty(), "An attacker cannot contest its own spike")
 block_pose()
 var before_state := blocker.rng.state
 var out := blocker.try_contact(blocker.wrists[1] + Vector3(0, 0, 1.5), Vector3(0, -8, -20), b.attack_for(blocker))
 check(out == Vector3.ZERO and blocker.rng.state == before_state and not blocker.hit_used, "Missing the hands never rolls a chance or consumes the action")
 blocker.action_time = 0
 out = blocker.try_contact(blocker.wrists[1], Vector3(0, -8, -20), b.attack_for(blocker))
 check(out == Vector3.ZERO and blocker.rng.state == before_state, "An early block cannot win a probability roll")
 block_pose()
 blocker.try_contact(blocker.wrists[1], Vector3(0, -8, -20), b.attack_for(blocker))
 before_state = blocker.rng.state
 var before_count := blocker.contact_count
 out = blocker.try_contact(blocker.wrists[1], Vector3(0, -8, -20), b.attack_for(blocker))
 check(out == Vector3.ZERO and blocker.rng.state == before_state and blocker.contact_count == before_count, "Holding block over many frames cannot reroll the same contact")
 attack()
 b.replica = true
 check(b.attack_for(blocker).is_empty(), "A network replica cannot calculate a second contest")
 b.replica = false
 b.feed(Vector3(0, 4, 5), Vector3.ZERO)
 check(b.attack_owner == null and b.last_duel.is_empty(), "New training or round feed clears the previous attack")
 attack()
 var floor_body := StaticBody3D.new()
 floor_body.set_meta("surface", "floor")
 b._on_body_entered(floor_body)
 check(b.attack_owner == null, "Landing ends the attack context")
 floor_body.free()
 attack()
 var net := StaticBody3D.new()
 net.set_meta("surface", "net")
 var prior_quality := b.attack_quality
 b._on_body_entered(net)
 check(b.attack_owner != null and b.attack_quality < prior_quality, "A legal net skim weakens the attack rather than creating a new one")
 net.free()
 attacker.style_stats.reset_all()
 blocker.style_stats.reset_all()
 for want in [false, true]:
  var result := await trial(want)
  check(result.hit and result.pierced == want and result.count == 1, "Real rigid body resolves exactly one %s contact" % ("piercing" if want else "blocking"))
  check(result.hit and (result.velocity.z < 0 if want else result.velocity.z > 0) and not result.duel.is_empty(), "Authoritative velocity and stored result agree for outcome %s" % want)
  if not want:
   check(b.attack_owner == null, "Successful block ends the original attack before the next rally touch")
  else:
   check(b.attack_owner != null and b.attack_quality < attacker.quality, "Pierced first block leaves weaker pressure for a second real blocker")
 block_pose()
 blocker.try_contact(blocker.wrists[1], Vector3(0, -8, -20))
 check(blocker.duel_result.is_empty(), "A pass or untagged feed retains ordinary block reflection")
 pose(blocker, 0, Vector3(0, 0.02, -3), PI)
 blocker.try_contact(blocker.wrists[0], Vector3(0, -8, 0))
 b.remember_contact(blocker)
 check(b.attack_owner == null, "A controlled receive or set clears inherited attack pressure")
 var transient := ContextAthlete.new()
 game.add_child(transient)
 transient.set_physics_process(false)
 transient.replica = true
 transient.court_team = 0
 pose(transient, 2, Vector3(0, 1.25, 3), 0)
 transient.try_contact(transient.wrists[1], Vector3.ZERO)
 b.remember_contact(transient)
 transient.free()
 block_pose()
 check(b.attack_for(blocker).is_empty() and b.attack_owner == null, "Disconnected attack source is discarded safely without a strong reference")
 var rules := VolleyRules.new()
 rules.strict = true
 rules.touch(1, 2, 6, 1)
 check(rules.touches == 0 and rules.touch(1, 2, 1, 2) and rules.touches == 1, "A pierced block remains a block touch and allows the next team receive")
 game.hud._cancel()
 game.queue_free()
 await process_frame
 print("V14 TESTS PASSED (%d checks)" % checks if failures == 0 else "V14 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
