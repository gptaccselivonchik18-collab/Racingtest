extends SceneTree
var game: Node3D
var checks := 0
var failures := 0
func _initialize() -> void:
 call_deferred("run")
func frames(n: int) -> void:
 for i in range(n):
  await physics_frame
func trial(drill: int, release_frame: int) -> bool:
 var a: ContextAthlete = game.athlete
 game.hud._cancel()
 a.energy = 1
 a.action = VolleyAthlete.Action.IDLE
 a.holding_ball = false
 a.move_axis = Vector2.ZERO
 game.training.selected = drill
 game.start_drill()
 await frames(3)
 var count_before := a.contact_count
 var closest := 99.0
 var closest_note := ""
 for frame in range(150):
  if drill in [2, 3, 4] and frame == 10:
   a.jump()
  if drill == 7 and frame == release_frame:
   a.dive()
  if frame == maxi(0, release_frame - 24):
   if drill == 0:
    game.begin_bump()
   elif drill == 3:
    game.begin_primary()
   elif drill in [1, 4]:
    game.begin_secondary()
   elif drill == 2:
    game.begin_jump_set()
  if frame == release_frame and drill != 7:
   game.finish_action("bump" if drill == 0 else "jump_set" if drill == 2 else "secondary" if drill in [1, 4] else "primary")
  for wrist in a.wrists:
   if wrist.distance_to(game.ball.position) < closest:
    closest_note = " frame=%d ball=%s wrist=%s" % [frame, game.ball.position, wrist]
   closest = minf(closest, wrist.distance_to(game.ball.position))
  await physics_frame
  if a.contact_count > count_before:
   print("Playable drill %d release %d" % [drill, release_frame])
   return true
 print("Miss drill %d release %d closest %.3f%s" % [drill, release_frame, closest, closest_note])
 return false

func serve_trial(jumping: bool, release_frame: int) -> bool:
 var a: ContextAthlete = game.athlete
 game.training.selected = 6 if jumping else 5
 game.start_drill()
 a.energy = 1
 await frames(15)
 if not game.ball.pick_up():
  return false
 var count_before := a.contact_count
 game.begin_primary()
 for frame in range(170):
  if jumping and frame == 34:
   a.jump()
  if frame == release_frame - 24:
   game.begin_primary()
  if frame == release_frame:
   game.finish_action("primary")
  await physics_frame
  if a.contact_count > count_before:
   print("Playable serve jump=%s release=%d" % [jumping, release_frame])
   return true
 return false

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 await frames(20)
 for drill in [0, 1, 2, 3, 4, 7]:
  var success := false
  for timing in ([0, 8, 16, 24, 32] if drill == 7 else [42, 50, 58, 66, 74, 82]):
   if await trial(drill, timing):
    success = true
    break
  checks += 1
  if not success:
   failures += 1
   push_error("Unplayable drill %d" % drill)
 for jumping in [false, true]:
  var success := false
  for timing in ([70, 78, 86, 94, 102] if jumping else [14, 20, 26, 82, 90, 98]):
   if await serve_trial(jumping, timing):
    success = true
    break
  checks += 1
  if not success:
   failures += 1
   push_error("Unplayable serve jump=%s" % jumping)
 print("PLAYABILITY PASSED (%d exercises)" % checks if failures == 0 else "PLAYABILITY FAILED %d" % failures)
 game.queue_free()
 await process_frame
 quit(0 if failures == 0 else 1)
