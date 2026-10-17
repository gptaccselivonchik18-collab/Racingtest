extends SceneTree
var game: Node3D
var a: ContextAthlete
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, label: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", label)
 else:
  failures += 1
  push_error("FAIL: " + label)

func frames(count: int) -> void:
 for i in range(count):
  await physics_frame

func flight(kind: int, tilt: Vector2, side := 1.0) -> Vector3:
 game.hud._cancel()
 a.set_physics_process(false)
 a.position = Vector3(0, 0.02 if kind == 3 else 1.4, side * (9.6 if kind == 3 else 1.0))
 a.visual.rotation = Vector3(0, 0 if side > 0 else PI, 0)
 a.camera_yaw = a.visual.rotation.y
 a.velocity = Vector3.ZERO
 a.dive_time = -1
 a.action = VolleyAthlete.Action.IDLE
 a.holding_ball = false
 a.tilt = tilt
 a.approach_jump = kind == 2
 a.begin_action(kind)
 a.charged_for = 0.2
 a.release()
 a.action_time = a.strike_duration * 0.47
 a._update_pose(0)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()
 a.reset_seed(412)
 var hand := a.wrists[1]
 var outgoing := a.try_contact(hand, Vector3.ZERO)
 var spin := a.outgoing_spin(Vector3.ZERO, outgoing)
 a.action = VolleyAthlete.Action.IDLE
 game.ball.feed(hand, outgoing)
 while game.ball.pending_feed:
  await physics_frame
 game.ball.angular_velocity = spin
 for i in range(480):
  await physics_frame
  if game.ball.position.y < 0.17:
   print("Landing kind=%d tilt=%s side=%s at=%s" % [kind, tilt, side, game.ball.position])
   return game.ball.position
 return Vector3(99, 99, 99)

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 a = game.athlete
 a.style_stats.reset_all()
 game.frontend.show_network()
 game.frontend._set_manual(true)
 check(game.frontend.address.virtual_keyboard_type == LineEdit.KEYBOARD_TYPE_DEFAULT, "IP uses the full keyboard with punctuation")
 game.frontend.address.text = "192"
 game.frontend.address.caret_column = 3
 for row in game.frontend.content.get_children():
  if row is HBoxContainer:
   for child in row.get_children():
    if child is Button and child.text == ".":
     child.pressed.emit()
 check(game.frontend.address.text == "192.", "Dedicated dot button inserts a dot without replacing entered digits")
 check(VolleyLAN.normalize_address("IP: 192,168,1,25") == "192.168.1.25", "Pasted IP and decimal commas are normalized")
 check(not VolleyLAN.normalize_address("999.12.1.2").is_valid_ip_address(), "Invalid addresses remain invalid")
 var targets := VolleyRoomDiscovery.scan_targets(PackedStringArray(["192.168.5.7", "172.20.10.2", "8.8.8.8"]))
 check("192.168.5.1" in targets and "172.20.10.1" in targets and "8.8.8.1" not in targets, "Discovery searches local Wi-Fi/hotspot subnets only")
 var port := 24818
 check(game.lan.host_room(port) == OK, "Room starts with discovery responder")
 var seeker := VolleyRoomDiscovery.new()
 seeker.lan = game.lan
 root.add_child(seeker)
 var explicit: Array[String] = ["127.0.0.1"]
 seeker.search(explicit, port + 1)
 await frames(120)
 check(seeker.rooms.has("127.0.0.1") and seeker.rooms["127.0.0.1"].port == port and seeker.rooms["127.0.0.1"].players == 1, "Actual UDP query discovers room and connection endpoint")
 game.lan.leave()
 seeker.queue_free()
 game.frontend.start_solo()
 game.hud.set_process(false)
 await frames(30)
 a.set_physics_process(false)
 a.position = Vector3(0, 0.02, 5)
 a.velocity = Vector3.ZERO
 a.visual.rotation = Vector3.ZERO
 a.camera_yaw = 0
 a.look_target_valid = false
 a.release_time = 0
 var signatures := []
 for kind in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]:
  a.position.z = 9.6 if kind in [3, 4] else 5.0
  a.jump_origin = Vector3(0, 0, a.position.z)
  a.holding_ball = false
  a.action = VolleyAthlete.Action.IDLE
  a.dive_time = -1
  a.approach_jump = kind == 2
  a.begin_action(kind)
  for i in range(30):
   a.action_time += 1.0 / 120
   a._update_pose(1.0 / 120)
  a.charged_for = 0.2
  if kind != ContextAthlete.BLOCK:
   a.release()
  var previous := a.wrists[1]
  var max_step := 0.0
  var anatomy := true
  var start := previous
  for i in range(60):
   a.action_time = 0.25 + float(i) / 120 if kind == ContextAthlete.BLOCK else minf(float(i) / 120, a.strike_duration)
   a._update_pose(1.0 / 120)
   max_step = maxf(max_step, previous.distance_to(a.wrists[1]))
   previous = a.wrists[1]
   for hand in range(2):
    var shoulder := a.visual.to_global(a.limb_rig.motion.shoulder(hand))
    anatomy = anatomy and absf(shoulder.distance_to(a.elbows[hand]) - 0.44) < 0.002 and absf(a.elbows[hand].distance_to(a.wrists[hand]) - 0.42) < 0.002
  check(anatomy and max_step < 0.16, "Continuous anatomical swing: " + ContextAthlete.NAMES[kind])
  var finish := a.wrists[1]
  signatures.append(start.distance_to(finish))
  a.action = VolleyAthlete.Action.RECOVER
  a.action_time = 1.0 / 120
  a._update_pose(1.0 / 120)
  check(finish.distance_to(a.wrists[1]) < 0.10, "Follow-through blends into recovery: " + ContextAthlete.NAMES[kind])
 check(absf(signatures[0] - signatures[2]) > 0.1 and absf(signatures[1] - signatures[6]) > 0.1, "Set, spike, platform and block use distinct trajectories")
 # Compare the same spike at the same phase from the floor and in the air.
 a.replica = true
 a.position = Vector3(0, 0.02, 5)
 a.action = VolleyAthlete.Action.IDLE
 a.tilt = Vector2.ZERO
 a.approach_jump = a.position.y > 0.12
 a.begin_action(2)
 for i in range(40):
  a._update_pose(1.0 / 120)
 var ground_draw := a.visual.to_local(a.wrists[1])
 var ground_basis := a.limb_rig.motion.torso_basis
 a.charged_for = 0.2
 a.release()
 check(not a.air_attack, "A floor spike stays a standing attack")
 a.action_time = a.strike_duration * 0.47
 a._update_pose(0.1)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()
 a.reset_seed(42)
 var ground_hit := a.try_contact(a.wrists[1], Vector3.ZERO)
 var ground_angle := ground_hit.normalized().y
 a.position.y = 1.2
 a.action = VolleyAthlete.Action.IDLE
 a.velocity = Vector3(3, 1, -2)
 a.takeoff_speed = 4
 a.approach_jump = a.position.y > 0.12
 a.begin_action(2)
 for i in range(40):
  a._update_pose(1.0 / 120)
 var air_draw := a.visual.to_local(a.wrists[1])
 check(air_draw.distance_to(ground_draw) > 0.20 and air_draw.y > ground_draw.y + 0.10, "Jump spike loads the striking arm higher and farther back")
 check(absf(a.limb_rig.motion.torso_basis.get_euler().x - ground_basis.get_euler().x) > 0.08, "Jump spike arches the torso instead of reusing standing motion")
 check(a.limb_rig.motion.feet[1].y > a.limb_rig.motion.feet[0].y + 0.10, "Jump spike uses asymmetric knee tuck")
 a.charged_for = 0.2
 a.release()
 check(a.air_attack, "Airborne contact selects the jump attack")
 a.action_time = a.strike_duration * 0.47
 a._update_pose(0.1)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()
 a.reset_seed(42)
 var air_hit := a.try_contact(a.wrists[1], Vector3.ZERO)
 check(air_hit.length() > ground_hit.length() * 1.08 and air_hit.normalized().y < ground_angle - 0.10, "Jump attack changes real ball speed and downward contact angle")
 var remote_hand := a.wrists[1]
 a._process(1.0 / 120)
 check(a.wrists[1].distance_to(remote_hand) > 0.001, "Remote player swing advances between network snapshots")
 a.replica = false
 a.position.y = 0.02
 a.velocity = Vector3.ZERO
 a.air_attack = false
 a.action = VolleyAthlete.Action.IDLE
 a.holding_ball = true
 for i in range(40):
  a._update_pose(1.0 / 120)
 check(a.hold_position().distance_to((a.wrists[0] + a.wrists[1]) * 0.5) < 0.04, "Held ball is attached between the actual rendered palms")
 var held_y := a.wrists[0].y
 a.holding_ball = false
 a.animate_release()
 for i in range(15):
  a.release_time -= 1.0 / 120
  a._update_pose(1.0 / 120)
 check(a.wrists[0].y > held_y + 0.10, "Toss release follows through with the guiding arm")
 a.release_time = 0
 var left := await flight(3, Vector2(-0.65, 0))
 var right := await flight(3, Vector2(0.65, 0))
 check(right.x - left.x > 3.5, "Tilt changes actual serve landing across the court")
 var near := await flight(3, Vector2(0, -0.8))
 var deep := await flight(3, Vector2(0, 0.8))
 check(absf(deep.z) - absf(near.z) > 3.4 and near.z < 0 and deep.z < 0, "Tilt changes actual serve depth without redirecting it in flight")
 var reverse_left := await flight(3, Vector2(-0.65, 0), -1)
 var reverse_right := await flight(3, Vector2(0.65, 0), -1)
 check(reverse_left.x - reverse_right.x > 3.5 and reverse_left.z > 0 and reverse_right.z > 0, "Serve steering mirrors correctly on the opposite side")
 var cross_left := await flight(2, Vector2(-0.55, 0))
 var cross_right := await flight(2, Vector2(0.55, 0))
 check(cross_right.x - cross_left.x > 2.0, "Tilt changes the physical attack landing left/right")
 var sharp := await flight(2, Vector2(0, -0.65))
 var flat := await flight(2, Vector2(0, 0.65))
 check(absf(flat.z) > absf(sharp.z) + 1.5, "Tilt changes physical attack depth through angle and topspin")
 a.position = Vector3(0, 0.02, 6)
 a.velocity = Vector3.ZERO
 a.action = VolleyAthlete.Action.IDLE
 a.tilt = Vector2.ZERO
 a.lean = Vector2.ZERO
 a.gait = 0
 a.visual.rotation = Vector3.ZERO
 a.camera_yaw = 0
 a.move_axis = Vector2.ZERO
 a.set_physics_process(true)
 a.limb_rig.motion.stance = [false, false]
 await frames(20)
 a.move_axis = Vector2.RIGHT
 var previous_feet: Array[Vector3] = [a.limb_rig.shoes[0].global_position, a.limb_rig.shoes[1].global_position]
 var previous_stance := [false, false]
 var planted_frames := 0
 var slide := 0.0
 for i in range(60):
  await physics_frame
  for foot in range(2):
   var current: Vector3 = a.limb_rig.shoes[foot].global_position
   if a.limb_rig.motion.stance[foot] and previous_stance[foot]:
    planted_frames += 1
    slide = maxf(slide, current.distance_to(previous_feet[foot]))
   previous_stance[foot] = a.limb_rig.motion.stance[foot]
   previous_feet[foot] = current
 check(planted_frames > 10 and slide < 0.02, "Running feet stay planted during stance instead of skating")
 a.move_axis = Vector2.ZERO
 a.set_physics_process(false)
 a.landing_load = 0
 a._update_pose(0.1)
 var standing_knee := a.limb_rig.knees[0].global_position.y
 a.landing_load = 0.7
 a._update_pose(0.1)
 check(a.limb_rig.knees[0].global_position.y < standing_knee - 0.03, "Landing absorbs impact through hips and knees")
 game.hud._cancel()
 game.queue_free()
 await process_frame
 print("V8 TESTS PASSED (%d checks)" % checks if failures == 0 else "V8 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
