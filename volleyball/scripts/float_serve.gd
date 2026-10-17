class_name VolleyFloatServe
extends VolleyLowerServe

var delivery := {}

func _ready() -> void:
 height = 1.8
 super._ready()

func serve_title() -> String:
 return "ПОДАЧА ПЛАНЕР"

func network_role() -> String:
 return "float_serve"

func height_hint() -> String:
 return "Малое вращение, непредсказуемый уход мяча. Serve улучшает точность. Низкая дуга может попасть в сетку."

func sample_delivery(aim: Vector3, skill: float) -> Dictionary:
 var spread := lerpf(2.7, 0.85, skill)
 var mishit := rng.randf() < lerpf(0.20, 0.025, skill)
 var error := Vector3(rng.randfn(0, spread), 0, rng.randfn(0, spread * 1.18))
 if mishit:
  error += Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
 var spin := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * lerpf(0.95, 0.18, skill)
 return {"target": aim + error, "mishit": mishit, "scale": rng.randf_range(1.0 - lerpf(0.07, 0.012, skill), 1.0 + lerpf(0.07, 0.012, skill)), "spin": spin, "seed": rng.randi(), "skill": skill}

func launch(actor: ContextAthlete, aim: Vector3, apex: float) -> bool:
 var side := 1.0 if actor.position.z >= 0 else -1.0
 if game.automatic_serve_busy() or not game.ball.held or game.ball.athlete != actor or actor.airborne() or not opposite_target(aim, side) or not is_finite(apex):
  return false
 height = clampf(apex, 0.8, 5.0)
 delivery = sample_delivery(aim, actor.style_stats.n("serve" if VolleyRules.in_service_zone(actor.service_origin()) else "spike"))
 busy_actor = actor
 actor.cancel_input()
 actor.move_axis = Vector2.ZERO
 actor.velocity.x = 0
 actor.velocity.z = 0
 var delta := aim - actor.position
 actor.visual.rotation.y = atan2(-delta.x, -delta.z)
 actor.camera_yaw = actor.visual.rotation.y
 if actor == game.athlete:
  game.rig.yaw = actor.camera_yaw
 actor.action = VolleyAthlete.Action.PREPARE
 actor.technique = actor.delivery_kind()
 actor.strike_technique = actor.technique
 actor.action_time = 0
 actor.hit_used = false
 actor.float_serve_active = true
 actor.last_result = "Планер • подброс и короткий замах"
 game.serving = VolleyRules.in_service_zone(actor.service_origin())
 if not game.rules.strict:
  game.rules.reset(game.serving)
 elapsed = 0
 released = false
 struck = false
 return true

func cancel_sequence() -> void:
 if is_instance_valid(busy_actor):
  busy_actor.float_serve_active = false
 super.cancel_sequence()

func _physics_process(dt: float) -> void:
 if not is_instance_valid(busy_actor) or (get_tree().paused and not game.lan.active):
  return
 var actor := busy_actor
 elapsed += dt
 actor.move_axis = Vector2.ZERO
 actor.velocity.x = 0
 actor.velocity.z = 0
 if elapsed >= 0.12 and not released:
  released = true
  var release_at := actor.hold_position()
  actor.animate_release()
  game.ball.feed(release_at, Vector3.UP * 4.2, Vector3.ZERO)
 if elapsed >= 0.40 and not struck:
  struck = true
  actor.action = VolleyAthlete.Action.STRIKE
  actor.strike_duration = actor.mechanic(actor.strike_technique).duration
  actor.strike_power = 0.72
  actor.action_time = 0
  actor.strike_count += 1
 # The automatic overhead swing meets the free toss using the visible hands.
 if released and struck and not actor.hit_used and actor.contact_active() and actor.overlap_at(game.ball.position, 1.0):
  var velocity: Vector3 = game.ball.solve_launch(game.ball.position, delivery.target, height, Vector3.ZERO) * float(delivery.scale)
  actor.hit_used = true
  actor.contact_count += 1
  actor.contact_flash = 0.16
  actor.last_result = "Планер • неточное касание" if delivery.mishit else "Планер • мяч в игре"
  game.ball.launch_float(game.ball.position, velocity, delivery.spin, delivery.skill, delivery.seed)
  game._on_player_touch(actor, game.lan.player_id(actor), actor.delivery_kind(), game.ball.position, velocity)
 if elapsed >= 1.1:
  if not actor.hit_used:
   actor.last_result = "Планер • промах при подбросе"
  actor.float_serve_active = false
  busy_actor = null
