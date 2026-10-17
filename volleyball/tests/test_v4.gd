extends SceneTree

var game: Node3D
var a: ContextAthlete
var b: VolleyBall
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func frames(n: int) -> void:
 for i in range(n):
  await physics_frame

func check(ok: bool, note: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", note)
 else:
  failures += 1
  push_error("FAIL: " + note)

func swing() -> void:
 a.action = VolleyAthlete.Action.IDLE
 a.holding_ball = false
 a.tilt = Vector2.ZERO
 a.visual.rotation = Vector3.ZERO
 a.begin_action(VolleyAthlete.Technique.SPIKE)
 a.charged_for = 0.2
 a.release()
 a.action_time = a.strike_duration * 0.47
 a._update_pose(0)
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 a = game.athlete
 a.style_stats.reset_all()
 b = game.ball
 game.hud.set_process(false)
 await frames(20)
 a.move_axis = Vector2(0, -1)
 await frames(60)
 var running := -a.velocity.z
 a.move_axis = Vector2.ZERO
 await frames(6)
 check(-a.velocity.z > running * 0.75 and a.velocity.z < -1, "Ground release coasts instead of stopping immediately")
 await frames(100)
 check(Vector2(a.velocity.x, a.velocity.z).length() < 0.05, "Ground friction eventually stops the player")
 a.position = Vector3(0, 0.02, 4)
 a.move_axis = Vector2(0, -1)
 await frames(60)
 a.jump()
 var takeoff := a.velocity.z
 a.move_axis = Vector2(0, 1)
 game.rig.yaw = 1.0
 var yaw_before := a.visual.rotation.y
 await frames(24)
 check(a.airborne() and a.velocity.z < takeoff + 0.35 and a.velocity.z < -1, "Opposite airborne input cannot reverse takeoff momentum")
 check(a.visual.rotation.y > yaw_before + 0.1, "Airborne body can still turn to aim at a bounded rate")
 var air_speed := a.velocity.z
 a.move_axis = Vector2.ZERO
 await frames(12)
 check(absf(a.velocity.z - air_speed) < 0.05, "Releasing the stick in flight retains horizontal momentum")
 await frames(120)
 game.reset_player()
 await frames(20)
 a.set_physics_process(false)
 swing()
 var near := a.wrists[1] + Vector3(0, 0, 0.28)
 check(a.try_contact(near, Vector3.DOWN * 4).length() > 0.1, "Previously missed 28 cm offset now produces contact")
 swing()
 check(a.try_contact(a.wrists[1] + Vector3(0, 0, 0.8), Vector3.DOWN * 4) == Vector3.ZERO, "80 cm offset still misses without attraction")
 swing()
 var hand := a.wrists[1]
 var obstacle := VolleyGeometry.collider(game, hand + Vector3(0, 0, 0.14), Vector3(1, 1, 0.035))
 await frames(3)
 check(a.try_contact(hand + Vector3(0, 0, 0.28), Vector3.DOWN * 4) == Vector3.ZERO, "Forgiving hitbox cannot strike through solid net geometry")
 obstacle.queue_free()
 await frames(3)
 swing()
 a.tilt = Vector2(1, 0)
 a.reset_seed(12)
 var incoming := Vector3(0, -4, 0)
 var right_hit := incoming + a.try_contact(a.wrists[1], incoming)
 swing()
 a.tilt = Vector2(-1, 0)
 a.reset_seed(12)
 var left_hit := incoming + a.try_contact(a.wrists[1], incoming)
 check(right_hit.x > 2 and left_hit.x < -2, "Tilt changed after button release still steers the actual hit")
 a.action = VolleyAthlete.Action.IDLE
 a.tilt = Vector2(1, -1).normalized()
 a._physics_process(0.15)
 check(Vector2(a.visual.rotation.x, a.visual.rotation.z).length() > 0.12, "Camera-relative Tilt visibly leans the body")
 check(a.limb_rig.fingers.size() == 10 and a.limb_rig.shins.size() == 2, "Refined model includes fingers and articulated lower legs")
 var upper := a.visual.to_local(a.elbows[1]).distance_to(a.limb_rig.motion.shoulder(1))
 var lower := a.elbows[1].distance_to(a.wrists[1])
 check(absf(upper - 0.44) < 0.005 and absf(lower - 0.42) < 0.005, "Arm joints keep anatomical segment lengths")
 var axes := a.arms[2].basis
 check(absf(axes.x.dot(axes.y)) < 0.001 and absf(axes.y.length() - 0.44) < 0.001 and axes.x.length() < 0.08, "Rendered arm has correct length and thickness without transform shear")
 a.visual.rotation = Vector3.ZERO
 a.velocity = Vector3.ZERO
 a.tilt = Vector2.ZERO
 a.lean = Vector2.ZERO
 a.action = VolleyAthlete.Action.IDLE
 a._update_pose(0)
 b.feed(a.position + Vector3(0.1, 0.25, -0.4), Vector3.ZERO)
 await frames(4)
 check(b.pick_up(), "Ball can be picked up for aimed toss")
 a._update_pose(0)
 b.jump_toss = false
 var initial := b.toss_velocity()
 var yaw: float = game.rig.yaw
 var hud: VolleyHUD = game.hud
 hud._touch_down(70, hud.left_center + Vector2(0, -30))
 hud._touch_down(71, Vector2(600, 200))
 hud._touch_move(71, Vector2(730, 280), Vector2(130, 80))
 var aimed := b.toss_velocity()
 check(aimed.x > initial.x + 0.1 and is_equal_approx(aimed.y, initial.y), "Free screen swipe aims direction without fighting the height slider")
 check(game.rig.yaw != yaw and hud.move_id == 70, "First-person toss aiming turns the view while preserving the movement finger")
 hud._touch_up(70)
 hud._touch_up(71)
 var points := b.preview_points()
 check(points.size() > 12 and points[6].y > points[0].y + 0.35, "Held ball displays a rising ballistic preview")
 var expected := points[6]
 a.technique = VolleyAthlete.Technique.SERVE
 b.toss()
 while b.pending_feed:
  await physics_frame
 await frames(30)
 check(b.position.distance_to(expected) < 0.13, "Actual free toss follows the preview within 13 cm at 0.25 seconds")
 b.feed(a.position + Vector3(0.1, 0.25, -0.4), Vector3.ZERO)
 await frames(4)
 b.pick_up()
 game.begin_secondary()
 var throw_before := b.throw_velocity()
 hud._look_or_aim(Vector2(120, -80))
 game.rig._process(0.1)
 a.visual.rotation.y = game.rig.yaw
 check(b.aiming_throw() and b.throw_velocity().distance_to(throw_before) > 1, "Throw mode supports independent landing target aiming")
 game.begin_primary()
 check(not b.held and b.pending_feed, "Primary launches the aimed throw with one tap")
 check(hud.buttons.size() == 12, "Explicit lower receive and contextual lower serve are present")
 game.queue_free()
 await process_frame
 print("V4 TESTS PASSED (%d checks)" % checks if failures == 0 else "V4 TESTS FAILED %d" % failures)
 quit(0 if failures == 0 else 1)
