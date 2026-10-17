extends SceneTree
var game: Node3D
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

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 game.rig.set_process(false)
 game.set_process(false)
 game.set_physics_process(false)
 var local: ContextAthlete = game.athlete
 local.set_physics_process(false)
 var remote := ContextAthlete.new()
 game.add_child(remote)
 remote.set_physics_process(false)
 remote.position = Vector3(2, 0.02, -4)
 remote._update_pose(0.1)
 var toss: VolleyTossPreview = game.get_node("TossPreview")
 var strike: VolleyStrikePreview = game.get_node("StrikePreview")
 check(toss.viewer == local and strike.viewer == local, "Both 3D helpers are bound to this device's player")
 var b: VolleyBall = game.ball
 b.held = true
 b.athlete = local
 local.holding_ball = true
 b.held_mode = VolleyBall.HeldMode.THROW
 b.throw_target = Vector3(1, 0.105, 6)
 toss._physics_process(1)
 check(toss.is_visible_in_tree() and toss.dots[0].is_visible_in_tree(), "Local holder sees the trajectory")
 check(toss.landing.is_visible_in_tree(), "Local holder sees the throw landing marker")
 # Host representation: shared ball remains held by a different actor.
 b.athlete = remote
 local.holding_ball = false
 remote.holding_ball = true
 toss._physics_process(0)
 check(not toss.is_visible_in_tree(), "Host cannot see the remote holder's trajectory")
 check(not toss.landing.is_visible_in_tree() and not toss.dots[0].is_visible_in_tree(), "Cached landing marker and every path dot hide with the foreign ball")
 # Client representation: held is local-only, remote possession lives in pose.
 b.held = false
 b.athlete = local
 toss._physics_process(1)
 check(not toss.is_visible_in_tree(), "Observing client sees no foreign toss despite remote holding pose")
 # Reacquiring possession refreshes immediately, without displaying old aim.
 b.held = true
 local.holding_ball = true
 remote.holding_ball = false
 b.throw_target = Vector3(-2, 0.105, 7)
 toss._physics_process(0)
 check(toss.is_visible_in_tree() and toss.landing.global_position.x == -2, "Reacquiring the ball instantly restores only the new local target")
 b.held = false
 local.holding_ball = false
 toss._physics_process(0)
 check(not toss.is_visible_in_tree(), "Releasing the ball immediately removes its preparation helpers")
 local.action = VolleyAthlete.Action.IDLE
 remote.action = VolleyAthlete.Action.PREPARE
 remote.technique = VolleyAthlete.Technique.SERVE
 strike._physics_process(1)
 check(not strike.is_visible_in_tree(), "Remote serve preparation cannot display a strike guide")
 remote.action = VolleyAthlete.Action.STRIKE
 strike._physics_process(1)
 check(not strike.is_visible_in_tree(), "Remote strike cannot display a strike guide")
 game.athlete = remote
 strike._physics_process(1)
 check(not strike.is_visible_in_tree() and strike.viewer == local, "Temporary host action routing cannot transfer preview ownership")
 game.athlete = local
 local.action = VolleyAthlete.Action.PREPARE
 local.technique = VolleyAthlete.Technique.OVERHEAD
 local.power = 0.6
 local.camera_pitch = 0.5
 local._update_pose(0.1)
 strike._physics_process(0)
 check(strike.is_visible_in_tree() and strike.dots[0].is_visible_in_tree(), "Local pass displays its own prediction immediately")
 game.athlete = remote
 strike._physics_process(1)
 check(strike.is_visible_in_tree() and strike.dots[0].global_position.distance_to(local.wrists[1]) < 0.001, "Preview still starts at the local wrist during host routing")
 game.athlete = local
 local.action = VolleyAthlete.Action.IDLE
 strike._physics_process(0)
 check(not strike.is_visible_in_tree() and not strike.title.is_visible_in_tree() and not strike.landing.is_visible_in_tree(), "Local action end removes trajectory, caption and landing mark together")
 toss.viewer = null
 b.held = true
 b.athlete = local
 local.holding_ball = true
 toss._physics_process(1)
 check(not toss.is_visible_in_tree(), "Unbound toss helper fails closed")
 strike.viewer = null
 local.action = VolleyAthlete.Action.PREPARE
 strike._physics_process(1)
 check(not strike.is_visible_in_tree(), "Unbound strike helper fails closed")
 toss.viewer = local
 strike.viewer = local
 b.held = false
 local.holding_ball = false
 local.action = VolleyAthlete.Action.IDLE
 game.hud._cancel()
 game.queue_free()
 await process_frame
 print("V13 TESTS PASSED (%d checks)" % checks if failures == 0 else "V13 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
