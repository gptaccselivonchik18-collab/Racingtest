extends SceneTree
var game: Node3D
var failures := 0
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 var cm: VolleyCharacters = game.characters
 for scenario in range(3):
  var teams := cm.default_teams()
  teams[0][0] = {"kind":"human" if scenario < 2 else "bot", "character":"hinata" if scenario == 1 else "kageyama", "human":0}
  teams[0][1] = {"kind":"bot", "character":"kageyama" if scenario == 1 else "hinata", "human":0}
  if scenario == 2:
   teams[1][0] = {"kind":"human","character":"hinata","human":0}
  cm.apply_teams(teams,2,false)
  cm.start_demo()
  var before := cm.quick_launches
  var brakes: int = game.ball.quick_brakes
  var spikes := 0
  var jumped := false
  var human: ContextAthlete = game.athlete
  var attackers: Array = cm.actors().filter(func(a): return a.character_id == "hinata" and a.court_team == 0)
  var hinata: ContextAthlete = attackers[0]
  var initial_contacts: int = hinata.contact_count
  var observed_contacts := initial_contacts
  for frame in range(2400):
   if scenario == 0:
    if not cm.partners(human).is_empty() and human.action == VolleyAthlete.Action.IDLE and game.ball.position.distance_to(human.position + Vector3.UP * human.natural_reach()) < 1.5:
     game.begin_special("freak")
    if human.action == VolleyAthlete.Action.PREPARE:
     var offset: Vector3 = game.ball.position - (human.wrists[0]+human.wrists[1])*0.5
     if offset.length() < 1.0 and human.charged_for > float(human.mechanic(0).windup):
      game.finish_action("freak")
   elif scenario == 1:
    if not human.airborne() and not human.approach_armed and human.jump_windup <= 0:
     human.move_axis = Vector2.ZERO
    var setters := cm.actors().filter(func(a): return a.character_id == "kageyama" and a.court_team == 0)
    var setter: ContextAthlete = setters[0]
    var ball_offset: Vector3 = game.ball.position - setter.position
    if not human.airborne() and human.can_act() and ball_offset.y > setter.natural_reach()+0.9 and ball_offset.y < setter.natural_reach()+1.5 and game.ball.linear_velocity.y < -0.1:
     human.move_axis = Vector2(0,-0.35)
     human.arm_approach()
     human.launch_approach()
    if human.attack_ready:
     var predicted: Vector3 = game.ball.position + game.ball.linear_velocity*0.09
     var hand: Vector3 = human.position + human.velocity*0.09 + Vector3.UP*human.natural_reach() - human.visual.global_basis.z*0.35
     if game.ball.quick_braked and predicted.distance_to(hand) < 0.90:
      human.hit_approach()
   await physics_frame
   jumped = jumped or hinata.jump_in_progress
   if hinata.contact_count > observed_contacts:
    if hinata.strike_technique in [2,9]:
     spikes += hinata.contact_count - observed_contacts
    observed_contacts = hinata.contact_count
   if cm.quick_launches >= before + 3 and game.ball.quick_brakes >= brakes + 3 and spikes >= 3:
    break
  print("LIVE SCENARIO ",scenario," jumps=",jumped," quick=",cm.quick_launches-before," brakes=",game.ball.quick_brakes-brakes," spikes=",spikes," setter/hinata ",hinata.position)
  if not jumped or cm.quick_launches < before+3 or game.ball.quick_brakes < brakes+3 or spikes < 3:
   failures += 1
  cm.demo = false
  game.ball.clear_quick()
  game.ball.held = false
  for actor in cm.actors():
   actor.cancel_input()
   actor.action = VolleyAthlete.Action.IDLE
   actor.velocity = Vector3.ZERO
   actor.position.y = 0.02
  await physics_frame
 game.queue_free()
 await process_frame
 print("SYNERGY LIVE PASSED" if failures == 0 else "SYNERGY LIVE FAILED %d" % failures)
 quit(0 if failures == 0 else 1)
