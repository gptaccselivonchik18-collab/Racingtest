extends SceneTree
var checks := 0
var failures := 0
var game: Node3D
var a: ContextAthlete
var b: VolleyBall

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, text: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", text)
 else:
  failures += 1
  push_error("FAIL: " + text)

func frames(count: int) -> void:
 for i in range(count):
  await physics_frame

func swing(kind: int) -> void:
 a.action = VolleyAthlete.Action.IDLE
 a.holding_ball = false
 a.begin_action(kind)
 a.charged_for = 0.20
 a.release()
 a.action_time = a.strike_duration * 0.47
 a._update_pose(0.0)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 a = game.athlete
 b = game.ball
 game.hud.set_process(false)
 await frames(20)
 check(a.is_on_floor(), "Player stands on court")
 check(game.camera.current and game.rig != null, "First-person camera is active")
 var wall := VolleyGeometry.collider(game, Vector3(0, 1.6, 6), Vector3(4, 4, 0.2))
 await frames(3)
 game.rig._process(0.05)
 check(game.camera.global_position.distance_to(a.eye_transform().origin) < 0.001, "Camera remains attached to the eyes beside solid geometry")
 wall.queue_free()
 await frames(3)
 # Compare original and extended controller's actual resource properties.
 var original := VolleyAthlete.new()
 root.add_child(original)
 original.set_physics_process(false)
 check(original.visual.get_child_count() == a.visual.get_child_count(), "Original player node count preserved")
 for i in range(original.visual.get_child_count()):
  var old_node := original.visual.get_child(i)
  var new_node := a.visual.get_child(i)
  if old_node is MeshInstance3D:
   check(old_node.mesh.get_class() == new_node.mesh.get_class() and old_node.material_override.albedo_color == new_node.material_override.albedo_color, "Original mesh and material %d preserved" % i)
 original.queue_free()
 check(is_equal_approx(b.mass, 0.27) and b.continuous_cd, "Real ball mass and CCD")
 check(PhysicsServer3D.area_get_param(root.world_3d.space, PhysicsServer3D.AREA_PARAM_GRAVITY) > 0, "Physics world gravity is active")
 # Empty swings, strict geometry, single contact, timing and seeded errors.
 for kind in [0, 1, 2, 3, 4, ContextAthlete.JUMP_SET, ContextAthlete.TIP]:
  swing(kind)
  var hand: Vector3 = a.wrists[1] if kind in [2, 3, 4, ContextAthlete.TIP] else a.wrists[0]
  var incoming := Vector3(0, -4, 3)
  check(a.try_contact(hand + Vector3(0, 0, 1.0), incoming) == Vector3.ZERO, "Outside enlarged contact area remains a miss: %d" % kind)
  a.action_time = 0
  check(a.try_contact(hand, incoming) == Vector3.ZERO, "Early overlap does not hit: %d" % kind)
  a.action_time = a.strike_duration * 0.47
  check(a.try_contact(hand, incoming).length() > 0.1, "Real hand overlap transfers impulse: %d" % kind)
  check(a.try_contact(hand, incoming) == Vector3.ZERO, "One impulse per action: %d" % kind)
 swing(VolleyAthlete.Technique.UNDERHAND)
 var forearm := (a.elbows[0] + a.wrists[0]) * 0.5
 check(a.try_contact(forearm, Vector3.DOWN * 8).length() > 0, "Bump contacts the visible forearm platform")
 swing(0)
 var center := a.wrists[0]
 check(a.try_swept_contact(center + Vector3(0, 0, -0.6), center + Vector3(0, 0, 0.6), Vector3(0, 0, 40)).length() > 0, "Fast ball sweep catches a real hand crossing")
 swing(0)
 a.reset_seed(123)
 var first := a.try_contact(a.wrists[0], Vector3(0, -8, 2))
 a.hit_used = false
 a.reset_seed(123)
 check(first.is_equal_approx(a.try_contact(a.wrists[0], Vector3(0, -8, 2))), "Random error applied once reproducibly")
 # Pass direction now follows the view independently of the bounded body turn.
 a.visual.rotation = Vector3.ZERO
 for direction in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
  a.tilt = Vector2.ZERO
  a.camera_yaw = atan2(-direction.x, -direction.y)
  var result := a.direction_for(0)
  check(Vector2(result.x, result.z).normalized().dot(direction) > 0.99, "Forward/back/side set: " + str(direction))
 a.camera_yaw = 0
 a.tilt = Vector2(0, -1)
 a.position.y = 1
 var steep := a.direction_for(2).y
 a.tilt = Vector2(0, 1)
 check(a.direction_for(2).y > steep + 0.2, "W attack steeper than S attack")
 a.camera_yaw = PI
 var body_before := a.visual.rotation.y
 a._physics_process(1.0 / 120)
 check(absf(angle_difference(body_before, a.visual.rotation.y)) < 0.06, "Body turn is bounded after instant camera input")
 a.camera_yaw = 0
 a.tilt = Vector2.ZERO
 a.position = Vector3(0, 0.02, 4)
 a.velocity = Vector3.ZERO
 a.action = VolleyAthlete.Action.IDLE
 await frames(20)
 # Whole physics: floor and net cannot be passed through.
 b.feed(Vector3(2, 0.4, 4), Vector3(0, -6, 0))
 var bounced := false
 for i in range(35):
  await physics_frame
  if b.linear_velocity.y > 1:
   bounced = true
 check(bounced, "Ball bounces off the floor")
 b.feed(Vector3(2, 1.9, -0.5), Vector3(0, 0, 30))
 var net_bounce := false
 for i in range(20):
  await physics_frame
  if b.linear_velocity.z < -0.5:
   net_bounce = true
 check(net_bounce, "CCD net collision rejects a fast ball")
 b.feed(Vector3(3, 8, 4), Vector3(20, 0, 0))
 await frames(4)
 var speed_before := b.linear_velocity.x
 await frames(20)
 check(b.linear_velocity.x < speed_before and b.linear_velocity.y < -1, "Aerodynamic drag and gravity act during free flight")
 # Block reflects incoming velocity; dedicated jump set stays a set.
 a.action = VolleyAthlete.Action.IDLE
 a.jump()
 await frames(12)
 swing(ContextAthlete.BLOCK)
 var incoming := Vector3(1, -3, 20)
 var outgoing := incoming + a.try_contact(a.wrists[0], incoming)
 check(outgoing.z < 0 and outgoing.length() > 5, "Airborne block rebounds the incoming ball")
 swing(ContextAthlete.JUMP_SET)
 check(a.strike_technique == ContextAthlete.JUMP_SET, "Dedicated Jump Set cannot become block")
 a.action = VolleyAthlete.Action.IDLE
 await frames(130)
 a.move_axis = Vector2(1, 0)
 check(a.dive(), "Grounded dive starts")
 check(a.dive_direction.x > 0.9 and not a.dive(), "Dive uses chosen direction and cannot repeat immediately")
 await frames(24)
 check(a.visual.rotation.x < -0.8 and a.wrists[0].y < 1.1, "Dive lowers the actual visible hands")
 await frames(150)
 check(a.dive_time < 0 and absf(a.visual.rotation.x) < 0.001, "Dive finishes with recovery to standing")
 # Context actions select on ground / in air, charging clamps monotonically.
 a.position = Vector3(0, 0.02, 4)
 a.velocity = Vector3.ZERO
 a.move_axis = Vector2.ZERO
 a.action = VolleyAthlete.Action.IDLE
 await frames(20)
 game.begin_primary()
 check(a.technique == 2, "Ground primary is Attack; receive is separate")
 await frames(20)
 var initial_power := a.power
 await frames(50)
 check(a.power < initial_power and a.power >= 0.16, "Holding lowers power without oscillation")
 game.cancel_action("primary")
 game.begin_secondary()
 check(a.technique == 0, "Ground secondary is Set")
 game.cancel_action("secondary")
 a.jump()
 game.begin_secondary()
 check(a.technique == ContextAthlete.BLOCK, "Air secondary is Block")
 game.cancel_action("secondary")
 game.begin_jump_set()
 check(a.technique == ContextAthlete.JUMP_SET, "E is explicit Jump Set")
 game.cancel_action("jump_set")
 game.begin_primary()
 game.finish_action("primary")
 check(a.strike_technique == ContextAthlete.TIP, "Short airborne tap is distinct Tip")
 a.action = VolleyAthlete.Action.IDLE
 game.begin_primary()
 a.charged_for = 0.2
 game.finish_action("primary")
 check(a.strike_technique == 2, "Held airborne action is power Spike")
 # Rules are independent of the single-player training controller.
 var rules := VolleyRules.new()
 rules.strict = true
 check(rules.touch(0, 1, 0, 1), "First team touch allowed")
 check(not rules.touch(0, 1, 0, 2) and rules.ended, "Separate consecutive contacts are a fault")
 rules.reset()
 for i in range(3):
  check(rules.touch(0, i, 0, i), "Team touch %d allowed" % (i + 1))
 check(not rules.touch(0, 4, 0, 4), "Fourth team touch fault")
 rules.reset()
 rules.touch(0, 1, ContextAthlete.BLOCK, 1)
 check(rules.touches == 0 and rules.touch(0, 1, 0, 2), "Block excluded from count and blocker can play next")
 check(rules.touch(0, 1, 0, 2), "Same first action is not counted twice")
 rules.reset()
 rules.floor_contact(Vector3(4.55, 0, 9.02))
 check(rules.message == "Мяч в площадке", "Ball touching boundary is in")
 rules.reset()
 rules.floor_contact(Vector3(5, 0, 2))
 check(rules.message == "Аут", "Outside ball is out")
 rules.reset(true)
 rules.serve_contact(Vector3(0, 0, 8.9))
 check(rules.ended, "Service foot fault")
 rules.reset(true)
 rules.net_contact(false)
 check(not rules.ended, "Ball net touch alone is legal")
 rules.crossing(Vector3(0, 3, 1), Vector3(0, 3, -1))
 check(rules.serve_crossed and not rules.ended, "Valid service crosses above net")
 rules.reset()
 rules.crossing(Vector3(4.7, 3, 1), Vector3(4.7, 3, -1))
 check(rules.ended, "Crossing outside antennas is a fault")
 rules.reset()
 rules.net_contact(true)
 check(rules.ended, "Player net contact is a fault")
 # All drills are physically launched from fixed world coordinates.
 for i in range(VolleyTraining.NAMES.size()):
  game.training.selected = i
  game.repeat_drill()
  var origin := b.feed_position
  a.position.x += 1
  game.repeat_drill()
  check(b.feed_position == origin, "Drill %d never follows player" % i)
 print("ALL TESTS PASSED (%d checks)" % checks if failures == 0 else "FAILED %d / %d" % [failures, checks])
 game.queue_free()
 await process_frame
 quit(0 if failures == 0 else 1)
