extends SceneTree
var checks := 0
var failures := 0
var game: Node3D
func _initialize() -> void:
 call_deferred("run")
func check(ok: bool, text: String) -> void:
 checks += 1
 print("PASS: " if ok else "FAIL: ", text)
 if not ok:
  failures += 1
  push_error(text)
func roster(human: String, partner: String, both := false) -> Array:
 var teams: Array = game.characters.default_teams()
 teams[0][0] = {"kind": "bot" if both else "human", "character": human, "human": 0}
 teams[0][1] = {"kind": "bot", "character": partner, "human": 0}
 if both:
  teams[1][0] = {"kind": "human", "character": "hinata", "human": 0}
 return teams
func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 var cm: VolleyCharacters = game.characters
 cm.set_physics_process(false)
 var original := FileAccess.get_file_as_string(cm.SAVE) if FileAccess.file_exists(cm.SAVE) else ""
 check(VolleyCharacterDatabase.IDS.size() == 2, "Only Hinata and Kageyama are available")
 var expected := {"hinata": [69,62,85,100,45,35,100,85], "kageyama": [83,75,70,89,95,100,88,85]}
 for hero in VolleyCharacterDatabase.IDS:
  cm.choose_local(hero)
  check(game.athlete.character_id == hero, "Selection applies " + hero)
  var values := []
  for key in VolleyStyleStats.KEYS:
   values.append(int(game.athlete.stats.values[key]))
  check(values == expected[hero], "Exact fixed eight-stat sheet for " + hero)
  game.athlete.stats.set_stat("jump", 999)
  check(int(game.athlete.stats.values.jump) == (100 if hero == "hinata" else 89), "Runtime/editor ratings cannot overwrite " + hero)
 check(JSON.parse_string(FileAccess.get_file_as_string(cm.SAVE)).selected == "kageyama", "Selected hero persists to user data")
 check(not game.hud.buttons.has("super") and not game.hud.settings.keys.has("super") and not game.super_serve.begin(game.athlete, 0), "Archived super serve has no button, key or callable activation")
 check(cm.apply_teams(roster("kageyama", "hinata"), 0, false), "One human, one bot and ten empty slots work")
 var h: ContextAthlete = game.game_bots.bots[-100]
 var k: ContextAthlete = game.athlete
 h.move_axis = Vector2.ZERO
 for i in range(8):
  await physics_frame
 h.set_physics_process(false)
 k.set_physics_process(false)
 h.position = Vector3(1.8, 0.02, 3)
 k.position = Vector3(0, 0.02, 3)
 h._update_pose(0)
 k._update_pose(0)
 check(h.height_cm == 164.2 and k.height_cm == 181.9 and h.head_position().y < k.head_position().y, "Physical head height follows each hero's height")
 check(h.get_child(0).shape.height < k.get_child(0).shape.height and h.wrists[0].y < k.wrists[0].y, "Colliders and actual wrists scale with the original model instance")
 var low_stats := h.stats.values.duplicate()
 game.game_bots.configure({"difficulty":4}, false)
 check(h.stats.values == low_stats and h.execution_level == 4, "Bot difficulty changes execution decisions without rewriting fixed stats")
 h.set_physics_process(false)
 var mover := ContextAthlete.new()
 game.add_child(mover)
 mover.set_character("hinata")
 mover.set_physics_process(false)
 await physics_frame
 await physics_frame
 mover.position = Vector3(5,0,6)
 mover.velocity = Vector3.DOWN
 mover._physics_process(1.0/120)
 mover.move_axis = Vector2(1,0)
 mover._physics_process(1.0/120)
 check(absf(mover.velocity.x - mover.effective_speed()) < 0.01, "Hinata starts at full ground speed")
 mover.move_axis = Vector2(-1,0)
 mover._physics_process(1.0/120)
 check(absf(mover.velocity.x + mover.effective_speed()) < 0.01, "Hinata reverses immediately on the ground")
 mover.move_axis = Vector2.ZERO
 mover._physics_process(1.0/120)
 check(Vector2(mover.velocity.x,mover.velocity.z).length() < 0.001, "Hinata stops immediately when the ground stick is released")
 mover.position.y = 1
 mover.velocity = Vector3(4,2,0)
 mover._physics_process(1.0/120)
 mover._physics_process(1.0/120)
 check(mover.velocity.x > 3.9 and mover.velocity.y < 2, "Airborne Hinata keeps momentum and gravity")
 mover.queue_free()
 var base := VolleyStyleStats.new()
 base.values = k.stats.values.duplicate()
 check(is_equal_approx(k.mechanic(0).accuracy / base.profile(0).accuracy, 0.30) and is_equal_approx(k.mechanic(0).windup / base.profile(0).windup, 1.0/1.20), "Kageyama's passive improves actual set accuracy and hand preparation")
 h.action = VolleyAthlete.Action.IDLE
 h.position.y = 1
 h.velocity.y = 2
 h.jump_in_progress = true
 h.air_swing_used = false
 check(h.begin_action(2), "First airborne attack may prepare")
 h.release()
 h.action = VolleyAthlete.Action.IDLE
 check(not h.begin_action(2), "A second ordinary swing in the same jump is rejected")
 k.position.y = 0.02
 k.action = VolleyAthlete.Action.IDLE
 k.service_attempt_active = true
 k.serve_swing_used = false
 k.begin_action(3)
 k.release()
 k.action = VolleyAthlete.Action.IDLE
 check(not k.begin_action(3), "A single toss cannot be attacked twice")
 k.service_attempt_active = false
 k.camera_yaw = PI
 k.camera_pitch = 0.5
 k.visual.rotation = Vector3.ZERO
 check(cm.begin_special(k,"no_look"), "No-Look Set uses its own action")
 k.release()
 k.action_time = k.strike_duration * 0.47
 k._update_pose(0)
 var point: Vector3 = (k.wrists[0]+k.wrists[1])*0.5
 var miss: Vector3 = k.try_contact(point+Vector3(5,0,0),Vector3.DOWN)
 check(miss == Vector3.ZERO and not k.hit_used, "No-Look still misses without physical hand contact")
 var delta: Vector3 = k.try_contact(point,Vector3.DOWN)
 check(delta.z > 0 and absf(k.visual.rotation.y) < 0.001 and k.camera_yaw == PI, "A real backward set leaves feet/body facing forward and does not auto-turn the view")
 check(k.wrists[0].distance_to(k.position) < 2.1, "No-Look arm reach remains anatomically bounded")
 for scenario in range(3):
  check(cm.apply_teams(roster("hinata" if scenario == 1 else "kageyama", "kageyama" if scenario == 1 else "hinata", scenario == 2), 2, false), "Configure controller combination %d" % scenario)
  var teammates: Array = cm.actors().filter(func(a): return a.court_team == 0)
  k = teammates.filter(func(a): return a.character_id == "kageyama")[0]
  h = teammates.filter(func(a): return a.character_id == "hinata")[0]
  for a in cm.actors():
   a.set_physics_process(false)
   a.cancel_input()
   a.action = VolleyAthlete.Action.IDLE
  k.position = Vector3(0,0.02,3)
  k.visual.rotation.y = PI
  k.camera_yaw = PI
  h.position = Vector3(1.6,1.0,3)
  h.jump_in_progress = true
  h.velocity = Vector3(0,2,-0.1)
  h.camera_yaw = 0
  h.visual.rotation.y = 0
  check(cm.partners(k).size() == 1, "Same-team airborne Hinata enables Freak Quick for combination %d" % scenario)
  check(cm.begin_special(k,"freak"), "Human/bot setter can request Freak Quick for combination %d" % scenario)
  k.release()
  k.action_time = k.strike_duration * 0.47
  k._update_pose(0)
  point = (k.wrists[0]+k.wrists[1])*0.5
  var preview_count: int = cm.quick_launches
  var old_contacts: int = h.contact_count
  VolleyShotModel.solve(k,0,point,Vector3.DOWN,Vector3.ZERO,1,0.8)
  check(cm.quick_launches == preview_count and not game.ball.quick_pending, "A private preview cannot arm the physical braking effect")
  delta = k.try_contact(point,Vector3.DOWN)
  check(delta.length() > 5 and game.ball.quick_pending and cm.quick_launches == preview_count+1, "Freak Quick launches only from real hand contact for combination %d" % scenario)
  check(h.action == VolleyAthlete.Action.IDLE and h.contact_count == old_contacts, "Freak Quick does not auto-attack or auto-touch Hinata")
  check(k.try_contact(point,Vector3.DOWN) == Vector3.ZERO, "Repeated contact cannot add a second impulse")
  game.ball.clear_quick()
  h.position.y = 0
  h.velocity = Vector3.DOWN
  h.move_axis = Vector2.ZERO
  h._physics_process(1.0/120)
  check(cm.partners(k).is_empty(), "Freak Quick eligibility closes on landing")
  h.position.y = 1
  h.court_team = 1
  k.cancel_input()
  k.action = VolleyAthlete.Action.IDLE
  check(cm.partners(k).is_empty() and not cm.begin_special(k,"freak"), "Opponent Hinata never enables team synergy (scenario D)")
 check(FileAccess.file_exists("res://archive/super_serve_v0.34/super_serve.gd.txt"), "Complete future-character super serve source remains archived")
 var full := cm.default_teams()
 for t in range(2):
  for s in range(6):
   if t == 0 and s == 0:
    continue
   full[t][s] = {"kind":"bot","character":"hinata" if s % 2 == 0 else "kageyama","human":0}
 check(cm.apply_teams(full,1,false) and cm.actors().size() == 12, "Two six-slot teams support twelve actual participants")
 var identities := {}
 for actor in cm.actors():
  identities[actor.instance_uid] = true
 check(identities.size() == 12, "Repeated hero copies have distinct instance identities")
 cm.choose_local("hinata")
 cm.apply_teams(cm.teams,1,false)
 check(game.athlete.character_id == "hinata", "Starting a saved team respects a newly selected hero")
 cm.choose_local("kageyama")
 game.frontend.enter_court()
 game.athlete.cancel_input()
 game.athlete.action = VolleyAthlete.Action.IDLE
 game.athlete.visual.rotation.y = 0
 game.rig.yaw = 0
 game.rig.pitch = 0.4
 game.action_owner = ""
 game.hud._refresh_context()
 var touch: Vector2 = game.hud.buttons.no_look.rect.get_center()
 game.hud._touch_down(77,touch)
 game.hud._touch_move(77,touch+Vector2(90,0),Vector2(90,0))
 cm._physics_process(1.0/120)
 check(game.hud.role_owners.has("no_look") and absf(game.rig.yaw) > 0.1 and absf(game.athlete.visual.rotation.y) < 0.001, "A held No-Look finger turns aim without rotating feet/body")
 game.hud._touch_down(78,game.hud.left_center)
 game.hud._touch_move(78,game.hud.left_center+Vector2(40,0),Vector2(40,0))
 check(game.athlete.move_axis.length() > 0.1 and game.hud.role_owners.has("no_look"), "Movement and special-button fingers work together")
 game.hud._touch_up(78)
 game.hud._touch_up(77)
 check(game.athlete.action == VolleyAthlete.Action.STRIKE and game.hud.role_owners.is_empty() and game.athlete.move_axis.length() < 0.01, "Releasing both fingers clears input and executes one set")
 cm.ui.open_characters()
 check(game.frontend.page == "characters", "Character cards open in the existing main menu")
 cm.ui.open_teams()
 check(game.frontend.page == "teams", "Two six-slot team editors open without requiring full teams")
 if original.is_empty():
  DirAccess.remove_absolute(cm.SAVE)
 else:
  var file := FileAccess.open(cm.SAVE,FileAccess.WRITE)
  file.store_string(original)
 game.queue_free()
 await process_frame
 print("CHARACTERS PASSED (%d checks)" % checks if failures == 0 else "CHARACTERS FAILED (%d)" % failures)
 quit(0 if failures == 0 else 1)
