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

func run() -> void:
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 var a: ContextAthlete = game.athlete
 a.set_physics_process(false)
 a.set_process(false)
 a.replica = true
 a.position = Vector3(0, 0.02, 5)
 a.velocity = Vector3.ZERO
 a.action = VolleyAthlete.Action.IDLE
 a.holding_ball = false
 a.visual.rotation = Vector3.ZERO
 for frame in range(120):
  a._update_pose(1.0 / 120)
 for i in range(2):
  var elbow := a.visual.to_local(a.elbows[i])
  var wrist := a.visual.to_local(a.wrists[i])
  check(absf(elbow.x) < 0.40 and elbow.y < 1.15, "Resting elbow stays beside the ribs %d" % i)
  check(elbow.z > wrist.z + 0.15, "Forearm bends forward rather than backward %d" % i)
  var palm := a.limb_rig.palm_frames[i]
  check(palm.z.dot(Vector3(-1 if i == 0 else 1, 0, 0)) > 0.9, "Neutral palm faces inward %d" % i)
  var thumb_axis := palm * Vector3(1 if i == 0 else -1, 0, 0)
  check(thumb_axis.y > 0.7, "Mirrored thumb points upward %d" % i)
 for axis in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD]:
  var palm := VolleyLimbRig.palm_frame(Vector3.ZERO, axis, axis)
  var joint := VolleyLimbRig.joint(Vector3.ZERO, axis * 0.6, axis, 0.44, 0.42)
  check(palm.is_finite() and is_equal_approx(palm.determinant(), 1.0) and joint.is_finite(), "Collinear anatomical axes remain finite " + str(axis))
 var final_gaits: Array[float] = []
 var final_wrists: Array[Vector3] = []
 for fps in [30, 60, 120]:
  a.gait = 0
  a.velocity = Vector3(0, 0, -5)
  var elapsed_phase := 0.0
  for frame in range(fps * 2):
   var before := a.gait
   a.advance_gait(1.0 / fps)
   elapsed_phase += fposmod(a.gait - before, TAU)
   a._update_pose(1.0 / fps)
  var steps_per_second := elapsed_phase / TAU
  check(steps_per_second > 4.0 and steps_per_second < 5.0, "Running uses human-scale cadence at %d FPS" % fps)
  final_gaits.append(a.gait)
  final_wrists.append(a.wrists[1])
 check(absf(final_gaits[0] - final_gaits[2]) < 0.001, "Stride timing is independent of frame rate")
 check(final_wrists[0].distance_to(final_wrists[2]) < 0.04, "Running arm pose is stable across frame rates")
 check(VolleyMotion.stride_frequency(100) * 2 <= 5.6, "Extreme Speed stats cannot create vibrating limbs")
 var last_foot := a.limb_rig.motion.feet[0]
 var last_wrist := a.visual.to_local(a.wrists[0])
 var max_foot := 0.0
 var max_wrist := 0.0
 var frozen_phase := a.gait
 a.position.y = 1.0
 a.velocity.y = 5
 for frame in range(90):
  a.advance_gait(1.0 / 120)
  a._update_pose(1.0 / 120)
  var foot := a.limb_rig.motion.feet[0]
  var wrist := a.visual.to_local(a.wrists[0])
  max_foot = maxf(max_foot, foot.distance_to(last_foot))
  max_wrist = maxf(max_wrist, wrist.distance_to(last_wrist))
  last_foot = foot
  last_wrist = wrist
 check(a.gait == frozen_phase, "Horizontal jump momentum does not cycle legs in the air")
 check(max_foot < 0.07 and max_wrist < 0.04, "Take-off blends hands and feet without snapping")
 var settled := a.visual.to_local(a.wrists[0])
 for frame in range(60):
  a._process(1.0 / 120)
 check(settled.distance_to(a.visual.to_local(a.wrists[0])) < 0.003, "Replica idle jump arms stop oscillating")
 a.position.y = 0.02
 a.velocity.y = 0
 a.landing_load = 0.7
 max_foot = 0
 for frame in range(30):
  var foot := a.limb_rig.motion.feet[0]
  a.advance_gait(1.0 / 120)
  a._update_pose(1.0 / 120)
  max_foot = maxf(max_foot, foot.distance_to(a.limb_rig.motion.feet[0]))
 check(max_foot < 0.07, "Landing returns feet smoothly to support")
 game.queue_free()
 await process_frame
 print("V16 TESTS PASSED (%d checks)" % checks if failures == 0 else "V16 TESTS FAILED %d / %d" % [failures, checks])
 quit(0 if failures == 0 else 1)
