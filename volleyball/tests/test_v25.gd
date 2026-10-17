extends SceneTree
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

func jitter_scenario(fps: int) -> void:
 var motion := VolleyReplicaMotion.new()
 var pending: Array = []
 var jitter := [0.0, 0.025, 0.004, 0.018, 0.008, 0.032, 0.012]
 for packet in range(300):
  var stamp := packet / 30.0
  pending.append({"time": stamp, "arrives": stamp + 0.020 + jitter[packet % jitter.size()]})
 pending.sort_custom(func(a, b): return a.arrives < b.arrives)
 var next := 0
 var before := Vector3.ZERO
 var worst := 0.0
 var legacy := Vector3.ZERO
 var legacy_sample := Vector3.ZERO
 var legacy_age := -1.0
 var legacy_worst := 0.0
 var dt := 1.0 / fps
 for frame in range(fps * 9):
  var now := frame * dt
  while next < pending.size() and pending[next].arrives <= now:
   var sample: Vector3 = Vector3(5, 0, 0) * pending[next].time
   motion.push(sample, Vector3(5, 0, 0), pending[next].time)
   if legacy_age < 0:
    legacy = sample
   legacy_sample = sample
   legacy_age = 0
   next += 1
  if not motion.active:
   continue
  before = motion.position
  var old_legacy := legacy
  motion.advance(dt)
  legacy_age += dt
  legacy += Vector3(5, 0, 0) * dt
  legacy = legacy.lerp(legacy_sample + Vector3(5, 0, 0) * minf(legacy_age, 0.12), 1.0 - exp(-10.0 * dt))
  if frame > fps:
   worst = maxf(worst, absf(motion.position.x - before.x - 5.0 * dt))
   legacy_worst = maxf(legacy_worst, absf(legacy.x - old_legacy.x - 5.0 * dt))
 print("JITTER %dHz old_step_error=%.6f new_step_error=%.6f" % [fps, legacy_worst, worst])
 check(worst < 0.0002, "Constant motion remains steady with irregular 30 Hz delivery at %d Hz" % fps)
 check(worst < legacy_worst * 0.1, "Timestamped motion removes at least 90%% of arrival jitter at %d Hz" % fps)

func run() -> void:
 for fps in [60, 90, 120, 144]:
  jitter_scenario(fps)
 var motion := VolleyReplicaMotion.new()
 motion.push(Vector3.ZERO, Vector3(5, 0, 0), 10)
 motion.advance(0.03)
 var position := motion.position
 check(not motion.push(Vector3(99, 0, 0), Vector3.ZERO, 10) and motion.position == position, "Duplicate chunks cannot rewind a displayed frame")
 check(not motion.push(Vector3(99, 0, 0), Vector3.ZERO, 9.9), "Out-of-order packets are discarded")
 var last_step := 5.0 / 120
 var largest_change := 0.0
 for i in range(120):
  position = motion.position
  motion.advance(1.0 / 120)
  var step := motion.position.x - position.x
  largest_change = maxf(largest_change, absf(step - last_step))
  last_step = step
 check(largest_change < 0.005, "Packet loss eases movement to rest without a hard timeout freeze")
 check(motion.position.x < 1.26, "Missing packets cannot predict a player indefinitely through the court")
 motion.push(Vector3(0.5, 0, 0), Vector3.ZERO, 11.04)
 for i in range(120):
  motion.advance(1.0 / 120)
 check(absf(motion.position.x - 0.5) < 0.001, "Authoritative stopping position is restored after packet loss")
 motion.push(Vector3(-7, 0, 9), Vector3.ZERO, 12.05)
 check(motion.position == Vector3(-7, 0, 9), "A round reset snaps directly to the new spawn position")
 motion.reset()
 check(not motion.active and motion.push(Vector3.ZERO, Vector3.ZERO, 0.1), "Rejoining a different host clears the previous clock")
 check(not motion.push(Vector3.INF, Vector3.ZERO, 0.2), "Nonfinite snapshots cannot corrupt the presentation")
 # Exercise the real replica and first-person camera, including split packets.
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.set_physics_process(false)
 game.hud.set_process(false)
 game.rig.set_process(false)
 var a: ContextAthlete = game.athlete
 a.set_physics_process(false)
 a.set_process(false)
 a.replica = true
 var pose: Array = game.lan.pack_actor(a, 1)
 pose[1] = Vector3(0, 0.02, 4)
 pose[2] = Vector3(2, 0, 0)
 pose[3] = Vector3.ZERO
 game.lan.apply_actor_pose(a, pose, 0, 20.0)
 check(a.network_motion.active, "Real LAN player poses use the timestamped presentation")
 a._process(1.0 / 120)
 game.rig._process(1.0 / 120)
 var camera_before: Vector3 = game.camera.global_position
 for i in range(3):
  a._process(1.0 / 120)
  game.rig._process(1.0 / 120)
 check(game.camera.global_position.x > camera_before.x + 0.04, "The actual eye camera advances between received snapshots")
 var rotation_before := a.visual.rotation.y
 pose[3] = Vector3(0, 0.5, 0)
 pose[1] += Vector3(2, 0, 0) / 30.0
 game.lan.apply_actor_pose(a, pose, 0, 20.0 + 1.0 / 30)
 check(a.visual.rotation.y == rotation_before, "A new body orientation cannot instantly nudge the eye camera")
 a._process(1.0 / 120)
 check(a.visual.rotation.y > rotation_before and a.visual.rotation.y < 0.1, "Replicated body rotation changes smoothly on render frames")
 game.lan.active = true
 game.lan.connected = true
 game.lan.snapshot([], Vector3(0, 2, 4), Vector3(3, 0, 0), Vector3.ZERO, 0, 0, [0, 0], "", Vector3.ZERO, 20.0)
 game.lan.ball_motion.advance(1.0 / 120)
 var ball_before: Vector3 = game.lan.ball_motion.position
 game.lan.snapshot([], Vector3(0, 2, 4), Vector3(3, 0, 0), Vector3.ZERO, 0, 0, [0, 0], "", Vector3.ZERO, 20.0)
 check(game.lan.ball_motion.position == ball_before, "Repeated player chunks do not reset the ball timeline")
 game.lan.leave()
 check(not a.network_motion.active and not game.lan.ball_motion.active, "Leaving clears both player and ball presentation clocks")
 game.queue_free()
 await process_frame
 print("V25 TESTS PASSED (%d checks)" % checks if failures == 0 else "V25 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
