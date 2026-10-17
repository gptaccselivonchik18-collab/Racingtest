class_name VolleyPracticeBot
extends ContextAthlete

var practice: VolleyPractice
var selected_mode := 0
var waiting := 0.0
var scheduled := false
var supplied := false
var cycles := 0
var contacts := 0

func _ready() -> void:
 super._ready()
 var tag := Label3D.new()
 tag.text = "ТРЕНЕР"
 tag.position.y = 2.15
 tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 tag.font_size = 42
 tag.pixel_size = 0.006
 tag.modulate = Color("bbf275")
 add_child(tag)

func _physics_process(dt: float) -> void:
 if replica:
  return
 super._physics_process(dt)
 if not is_instance_valid(practice) or not practice.enabled or practice.game.lan.match_active:
  return
 var ball: VolleyBall = practice.game.ball
 # A held ball belongs to its holder. Never steal it for a practice feed.
 if ball.held or practice.game.automatic_serve_busy():
  waiting = 0
  return
 var side := 1.0 if practice.anchor.z >= 0 else -1.0
 camera_yaw = 0 if side > 0 else PI
 camera_pitch = 0.25
 var offset := ball.position - position
 var arriving := offset.y > 0.25 and offset.y < 3.8 and Vector2(offset.x, offset.z).length() < 2.0 and ball.linear_velocity.y < 3
 if arriving and action == Action.IDLE and not scheduled:
  begin_cycle(false)
 if not scheduled:
  waiting += dt
  var idle_ball := ball.position.y < 0.65 and ball.linear_velocity.length() < 3.5
  var escaped := absf(ball.position.x) > 8 or absf(ball.position.z) > 12
  if waiting >= practice.interval and (idle_ball or escaped):
   begin_cycle(true)
 if scheduled:
  if action == Action.PREPARE and (selected_mode != 4 or position.y > 0.55):
   if charged_for >= 0.20:
    release()
  if supplied and action == Action.STRIKE and not hit_used:
   # The feeder supplies a real incoming ball to the current palm/body
   # contact window. The normal swept collision produces exactly one hit.
   if action_time / strike_duration >= 0.24:
    supplied = false
    var at := wrists[1] if selected_mode >= 4 else (wrists[0] + wrists[1]) * 0.5
    ball.feed(at + Vector3.UP * 0.06, Vector3.DOWN * 1.1, Vector3.ZERO)
  if action == Action.IDLE:
   scheduled = false
   waiting = 0

func begin_cycle(with_feed: bool) -> void:
 if practice.modes.is_empty() or not can_act():
  return
 selected_mode = practice.modes[cycles % practice.modes.size()]
 cycles += 1
 var kind := Technique.UNDERHAND if selected_mode < 2 else Technique.OVERHEAD if selected_mode < 4 else Technique.SPIKE if selected_mode == 4 else Technique.SERVE
 if selected_mode == 4:
  jump(true)
 begin_action(kind)
 scheduled = true
 supplied = with_feed
 waiting = 0

func try_swept_contact(from: Vector3, center: Vector3, incoming: Vector3, attack: Dictionary = {}) -> Vector3:
 var delta := super.try_swept_contact(from, center, incoming, attack)
 if delta == Vector3.ZERO:
  return delta
 contacts += 1
 var ball: VolleyBall = practice.game.ball
 var target := practice.target_for(selected_mode)
 var key := "bump" if selected_mode < 2 else "set" if selected_mode < 4 else "spike" if selected_mode == 4 else "serve"
 var accuracy := style_stats.n(key)
 var spread := lerpf(1.1, 0.08, accuracy) * (1.25 - quality)
 target += Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
 var peak := 3.8 if selected_mode < 4 else 3.3
 var spin := outgoing_spin(ball.angular_velocity, delta)
 var outgoing := ball.solve_launch(last_contact_point, target, maxf(peak, last_contact_point.y + 0.3), spin)
 if selected_mode == 4:
  outgoing = ball.solve_power_serve(last_contact_point, target, lerpf(14, 26, accuracy), spin)
 # The base contact signal is deliberately disconnected for this actor:
 # practice remains outside scored match rules.
 return outgoing - incoming
