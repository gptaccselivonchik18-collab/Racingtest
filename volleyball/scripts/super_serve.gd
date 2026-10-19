class_name VolleySuperServe
extends Node3D

# Disposable prototype: local choreography and cameras, host-selected outcome.
# No audio or global slow motion. Charge belongs to the scoring human only.
const HIT := 2.86
const LAND := 3.12
const END := 4.30
var game: Node3D
var active := false
var elapsed := 0.0
var sequence := 0
var finished_sequence := -1
var actor_id := 0
var actor: ContextAthlete
var origin := Vector3.ZERO
var yaw := 0.0
var side := 1.0
var target := Vector3.ZERO
var inside := true
var height := 4.3
var flight := 0.26
var landed := false
var had_network := false
var old_hud := true
var old_shadow := true
var old_camera: Camera3D
var camera: Camera3D
var overlay: CanvasLayer
var art: Control
var mesh: MeshInstance3D
var strokes := ImmediateMesh.new()
var trail: Array[Vector3] = []
var trail_clock := 0.0
var sync_left := 0.0
var random := RandomNumberGenerator.new()
var packet := {}
const KILLS_REQUIRED := 7
var charges: Dictionary = {}
var last_scorer: WeakRef
var last_scorer_id := 0
var last_scorer_side := 1.0
var floor_consumed := true
var charge_sync := 0.0

func local_id() -> int:
 return game.lan.multiplayer.get_unique_id() if game.lan.active else 0

func percent(id: int) -> int:
 return roundi(clampi(int(charges.get(id, 0)), 0, KILLS_REQUIRED) * 100.0 / KILLS_REQUIRED)

func ready_for(id: int) -> bool:
 return int(charges.get(id, 0)) >= KILLS_REQUIRED

func note_contact(player: ContextAthlete, id: int, kind: int) -> void:
 if not authority() or active:
  return
 floor_consumed = false
 last_scorer = weakref(player) if kind != VolleyAthlete.Technique.THROW else null
 last_scorer_id = id
 last_scorer_side = 1.0 if (player.court_team == 0 if player.court_team >= 0 else player.position.z >= 0) else -1.0

func record_floor(at: Vector3) -> void:
 if not authority() or active or floor_consumed:
  return
 floor_consumed = true
 if last_scorer == null or ((game.lan.match_active or game.game_bots.solo_match) and game.rules.ended):
  return
 var player: Variant = last_scorer.get_ref()
 if not is_instance_valid(player) or player is VolleyGameBot or player is VolleyPracticeBot:
  return
 if absf(at.x) <= 4.5 + VolleyBall.RADIUS and absf(at.z) <= 9.0 + VolleyBall.RADIUS and at.z * last_scorer_side < -0.15:
  _earn(last_scorer_id)

func _earn(id: int) -> void:
 charges[id] = mini(KILLS_REQUIRED, int(charges.get(id, 0)) + 1)
 _send_charges()

func _send_charges() -> void:
 if not game.lan.active or not game.lan.hosting:
  return
 for id in game.lan.players:
  if id != 1 and game.lan._peer_ready(id):
   # Only the owner receives their percentage, never a team-wide pool.
   set_charge.rpc_id(id, int(charges.get(id, 0)))

@rpc("authority", "call_remote", "reliable", 3)
func set_charge(kills: int) -> void:
 if game.lan.active and not game.lan.hosting and kills >= 0 and kills <= KILLS_REQUIRED:
  charges[local_id()] = kills

func ground_at(time: float) -> Vector3:
 var run := clampf(absf(origin.z) - 0.6, 0, 0.95)
 var travel := run * smoothstep(0.05, 1.10, time) + run * 0.15 * smoothstep(1.10, HIT, time)
 return origin + Vector3(0, 0, -side * travel)

func _ready() -> void:
 name = "SuperServe"
 process_priority = 100
 process_physics_priority = 100
 random.randomize()
 camera = Camera3D.new()
 camera.near = 0.06
 add_child(camera)
 mesh = MeshInstance3D.new()
 mesh.mesh = strokes
 var ink := StandardMaterial3D.new()
 ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 ink.vertex_color_use_as_albedo = true
 ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 ink.no_depth_test = false
 mesh.material_override = ink
 add_child(mesh)
 overlay = CanvasLayer.new()
 overlay.layer = 15
 add_child(overlay)
 art = Control.new()
 art.mouse_filter = Control.MOUSE_FILTER_IGNORE
 art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 overlay.add_child(art)
 art.draw.connect(_draw_frame)
 overlay.hide()

func authority() -> bool:
 return not game.lan.active or game.lan.hosting

func request() -> bool:
 if active:
  return false
 if game.lan.active:
  return game.lan.local_action("super")
 return begin(game.athlete, 0)

func choose_target(source: Vector3) -> Dictionary:
 var direction := 1.0 if source.z >= 0 else -1.0
 var good := random.randf() < 0.5
 var at := Vector3.ZERO
 var best := -INF
 var safe: Array[Vector3] = []
 var opponents: Array = game.game_bots.members(1 if direction > 0 else 0)
 var contact := source + Vector3(0, 6.5, -direction * 1.35)
 for candidate in range(80):
  var point := Vector3(random.randf_range(-4.15, 4.15), VolleyBall.RADIUS, -direction * (random.randf_range(8.70, 9.03) if good else random.randf_range(9.48, 10.12)))
  var clearance := 100.0
  for opponent: ContextAthlete in opponents:
   var observed := opponent.position + Vector3(opponent.velocity.x, 0, opponent.velocity.z).limit_length(3) * 0.15
   var reach := opponent.contact_ball_radius * float(opponent.mechanic(VolleyAthlete.Technique.UNDERHAND).radius) + 0.55
   for step in range(15):
    var u := step / 14.0
    var ball_position := contact.lerp(point, u)
    ball_position.y = lerpf(contact.y, point.y, pow(u, 4.2))
    var body := Vector3(observed.x, clampf(ball_position.y, observed.y + 0.15, observed.y + 2.55), observed.z)
    clearance = minf(clearance, ball_position.distance_to(body) - reach)
  if clearance > best:
   best = clearance
   at = point
  if clearance > 0.12:
   safe.append(point)
 if not safe.is_empty():
  at = safe[random.randi_range(0, safe.size() - 1)]
 return {"target": at, "inside": good}

func begin(player: ContextAthlete, id: int) -> bool:
 if not authority() or active or not is_instance_valid(player) or player is VolleyGameBot or player is VolleyPracticeBot:
  return false
 if not ready_for(id):
  if player == game.athlete:
   game.show_feedback("Суперподача · %d%% · нужно 7 ваших забитых мячей" % percent(id), false)
  return false
 if player.airborne() or (game.ball.held and game.ball.athlete != player):
  if player == game.athlete:
   game.show_feedback("Суперподача: встаньте на пол; мяч должен быть свободен или у вас", false)
  return false
 game.lower_serve.cancel_sequence()
 game.float_serve.cancel_sequence()
 var aim := choose_target(player.global_position)
 sequence += 1
 var facing := 0.0 if player.position.z >= 0 else PI
 var jump := clampf(4.0 + sqrt(float(player.style_stats.movement().jump_height)) * 0.25, 4.0, 5.0)
 var duration := clampf(0.31 / sqrt(player.style_stats.factor("serve")), 0.20, 0.30)
 packet = {"sequence": sequence, "actor": id, "origin": player.global_position, "yaw": facing, "target": aim.target, "inside": aim.inside, "height": jump, "flight": duration}
 _start(packet, player, 0.0)
 charges[id] = 0
 _send_charges()
 _broadcast(0.0)
 return true

func _broadcast(time: float) -> void:
 if not game.lan.active or not game.lan.hosting:
  return
 for id in game.lan.players:
  if id != 1 and game.lan._peer_ready(id):
   show_scene.rpc_id(id, packet, time)

@rpc("authority", "call_remote", "reliable", 3)
func show_scene(data: Dictionary, time: float) -> void:
 if not game.lan.active or game.lan.hosting or not data.has_all(["sequence", "actor", "origin", "yaw", "target", "inside", "height", "flight"]):
  return
 if not game.lan.players.has(data.actor) or not data.origin is Vector3 or not data.target is Vector3 or not data.origin.is_finite() or not data.target.is_finite() or not is_finite(time) or time < 0 or time > END:
  return
 if int(data.sequence) == finished_sequence:
  return
 if active and sequence == int(data.sequence):
  # Reliable checkpoints also catch up a late joiner, without rewinding cuts.
  elapsed = maxf(elapsed, lerpf(elapsed, time, 0.35))
  return
 _start(data, game.lan.players[data.actor].actor, time)

func _start(data: Dictionary, player: ContextAthlete, time: float) -> void:
 if active:
  finish(false)
 packet = data.duplicate()
 sequence = int(data.sequence)
 actor_id = int(data.actor)
 actor = player
 origin = data.origin
 yaw = float(data.yaw)
 side = 1.0 if origin.z >= 0 else -1.0
 target = data.target
 inside = bool(data.inside)
 height = float(data.height)
 flight = float(data.flight)
 elapsed = time
 floor_consumed = true
 landed = time >= HIT + flight
 sync_left = 0.35
 had_network = game.lan.active
 old_hud = game.hud.visible
 old_shadow = game.ball_shadow.visible
 old_camera = get_viewport().get_camera_3d()
 game.hud._cancel()
 game.hud.hide()
 game.ball_shadow.hide()
 actor.cancel_input()
 actor.action = VolleyAthlete.Action.IDLE
 actor.holding_ball = false
 actor.velocity = Vector3.ZERO
 actor.cinema_time = elapsed
 actor.cinema_pose = pose
 game.ball.held = false
 game.ball.freeze = true
 game.ball.collision_mask = 0
 game.ball.pending_feed = false
 game.ball.clear_float()
 game.ball.clear_attack()
 game.previous_ball_valid = false
 trail.clear()
 active = true
 overlay.show()
 camera.current = true
 _sample()

func _process(dt: float) -> void:
 if authority() and game.lan.active:
  charge_sync -= dt
  if charge_sync <= 0:
   charge_sync = 0.75
   _send_charges()
 if not active:
  return
 if not is_instance_valid(actor) or (had_network and not game.lan.active) or (is_instance_valid(game.frontend) and game.frontend.in_home):
  finish(false)
  return
 elapsed += minf(dt, 0.10)
 _sample()
 sync_left -= dt
 if authority() and sync_left <= 0:
  sync_left = 0.35
  _broadcast(elapsed)
 if not landed and elapsed >= HIT + flight:
  landed = true
  if authority():
   if inside:
    _earn(actor_id)
   var winner := (0 if side > 0 else 1) if inside else (1 if side > 0 else 0)
   if game.game_bots.solo_match:
    game.game_bots.award(winner)
   if game.lan.match_active:
    game.lan.award(winner)
 if elapsed >= END:
  if authority() and game.lan.active:
   for id in game.lan.players:
    if id != 1 and game.lan._peer_ready(id):
     close_scene.rpc_id(id, sequence)
  finish(true)

func _physics_process(_dt: float) -> void:
 if active and is_instance_valid(actor):
  actor.velocity = Vector3.ZERO

@rpc("authority", "call_remote", "reliable", 3)
func close_scene(id: int) -> void:
 if active and sequence == id:
  finish(true)
 else:
  finished_sequence = id

func jump_at(time: float) -> float:
 if time < 1.10:
  return 0
 if time < 1.63:
  var u := clampf((time - 1.10) / 0.53, 0, 1)
  return height * (1.0 - pow(1.0 - u, 2.2))
 if time < HIT:
  return height - 0.12 * smoothstep(1.63, HIT, time)
 return (height - 0.12) * (1.0 - pow(smoothstep(HIT, 3.72, time), 1.4))

func hit_point() -> Vector3:
 var chest := Vector3(0, 1.23, 0)
 var hit_basis := Basis.from_euler(Vector3(0.12, 0.22, 0))
 return ground_at(HIT) + Vector3.UP * (height - 0.12) + Basis(Vector3.UP, yaw) * (chest + Vector3(0, -0.035, 0) + hit_basis * (Vector3(0.25, 2.22, -0.36) - chest)) + Vector3(0, 0, -side * 0.15)

func ball_at(time: float) -> Vector3:
 var facing := Basis(Vector3.UP, yaw)
 var start := ground_at(minf(time, 0.35)) + facing * Vector3(-0.12, 1.57, -0.48)
 var contact := hit_point()
 if time < 0.35:
  return start - Vector3.UP * ((1.0 - smoothstep(0, 0.35, time)) * 0.15)
 if time < 1.63:
  var u := smoothstep(0.35, 1.63, time)
  var control := origin + Vector3.UP * (height + 7.0) + facing * Vector3(0.1, 0, -1.75)
  return (1.0 - u) * (1.0 - u) * start + 2.0 * (1.0 - u) * u * control + u * u * (contact + Vector3.UP * 0.16)
 if time < HIT:
  return contact + Vector3.UP * (0.16 * (1.0 - smoothstep(1.63, HIT, time)))
 if time < HIT + flight:
  var u := clampf((time - HIT) / flight, 0, 1)
  var point := contact.lerp(target, u)
  point.y = lerpf(contact.y, target.y, pow(u, 4.2))
  return point
 var after := maxf(0, time - HIT - flight)
 return target + Vector3.UP * maxf(0, 1.9 * after - 2.6 * after * after) + Vector3((target.x - origin.x) * after * 0.09, 0, -side * after * 0.28)

func _sample() -> void:
 actor.cinema_time = elapsed
 actor.global_position = ground_at(elapsed) + Vector3.UP * jump_at(elapsed)
 actor.visual.rotation = Vector3(0, yaw, 0)
 actor.camera_yaw = yaw
 actor.velocity = Vector3.ZERO
 actor._update_pose(0)
 game.ball.global_position = ball_at(elapsed)
 game.ball.rotation = Vector3(elapsed * (18 if elapsed >= HIT else 2), 0.3, elapsed * 1.2)
 _camera()
 _effects()
 art.queue_redraw()

func pose(motion: VolleyMotion) -> void:
 var t := elapsed
 var draw := smoothstep(0.70, 1.80, t)
 var reach := smoothstep(1.95, HIT, t)
 var follow := smoothstep(HIT, 3.15, t)
 var recover := smoothstep(3.4, 4.1, t)
 var twist := lerpf(-0.44 * draw, 0.22, reach)
 twist = lerpf(twist, 0.48, follow) * (1.0 - recover)
 var bend := lerpf(-0.18 * draw, 0.12, reach)
 bend = lerpf(bend, 0.26, follow) * (1.0 - recover)
 var crouch := 0.035 + 0.19 * sin(smoothstep(0.75, 1.10, t) * PI) if t < 1.10 else 0.035 + 0.20 * sin(smoothstep(3.55, 4.1, t) * PI)
 motion.body_offset = Vector3(0, -crouch, 0)
 motion.torso_basis = Basis.from_euler(Vector3(bend, twist, 0))
 var left := Vector3(-0.19, 1.40, -0.48).lerp(Vector3(-0.20, 2.05, -0.40), smoothstep(0.18, 0.75, t))
 left = left.lerp(Vector3(-0.35, 1.22, -0.10), reach)
 var right := Vector3(0.29, 1.17, -0.22).lerp(Vector3(0.46, 2.00, 0.25), draw)
 right = right.lerp(Vector3(0.25, 2.22, -0.36), reach)
 right = right.lerp(Vector3(-0.20, 1.25, -0.66), follow)
 var chest := Vector3(0, 1.23, 0)
 motion.wrists.clear()
 motion.poles.clear()
 motion.feet.clear()
 for i in range(2):
  var s := -1.0 if i == 0 else 1.0
  var wrist := left if i == 0 else right
  wrist = wrist.lerp(Vector3(s * 0.29, 1.08, -0.27), recover)
  motion.wrists.append(chest + motion.body_offset + motion.torso_basis * (wrist - chest))
  var pole := Vector3(-0.40, 1.55, -0.15) if i == 0 else Vector3(0.65, 1.78, 0.28).lerp(Vector3(0.4, 1.65, -0.34), reach)
  motion.poles.append(chest + motion.body_offset + motion.torso_basis * (pole - chest))
  var tuck := smoothstep(1.1, 1.65, t) * (1.0 - smoothstep(3.0, 3.65, t))
  var foot := Vector3(s * 0.20, 0.11 + tuck * (0.23 if i == 0 else 0.10), tuck * (0.23 if i == 0 else -0.15))
  if t < 1.10:
   var stride := sin(t * TAU * 2.0 + i * PI)
   foot.z += stride * 0.17
   foot.y += maxf(0, stride) * 0.09
  motion.feet.append(foot)
 motion.initialized = true

func _camera() -> void:
 var forward := Vector3(0, 0, -side)
 var right := Vector3(side, 0, 0)
 var view := -signf(origin.x) * side if absf(origin.x) > 1.5 else 1.0
 var at: Vector3
 var focus: Vector3
 if elapsed < 1.63:
  at = origin + right * view * 6.0 + forward * 0.8 + Vector3.UP * (4.1 + jump_at(elapsed) * 0.18)
  focus = origin + Vector3.UP * (3.5 + jump_at(elapsed) * 0.35 + smoothstep(0.35, 1.10, elapsed) * 0.45)
  camera.fov = 85
 elif elapsed < HIT:
  var u := smoothstep(1.63, HIT, elapsed)
  at = actor.position + right * lerpf(2.05, 1.52, u) + forward * lerpf(0.35, 0.95, u) + Vector3.UP * lerpf(1.55, 1.80, u)
  focus = (actor.wrists[1] + hit_point()) * 0.5 + Vector3.DOWN * 0.12
  camera.fov = lerpf(53, 40, u)
 else:
  at = Vector3(clampf(target.x + (2.0 if target.x < 0 else -2.0), -6.7, 6.7), 0.48, -side * 11.25)
  focus = target + Vector3.UP * 0.55
  camera.fov = 72
  var impact := exp(-maxf(0, elapsed - HIT - flight) * 18.0) if elapsed >= HIT + flight else 0.0
  at += Vector3(sin(elapsed * 137), cos(elapsed * 121), 0) * impact * 0.028
 at.x = clampf(at.x, -7.65, 7.65)
 at.z = clampf(at.z, -11.55, 11.55)
 at.y = clampf(at.y, 0.22, 10.6)
 camera.global_position = at
 camera.look_at(focus, Vector3.UP)
 if elapsed > 3.95:
  var blend := smoothstep(3.95, END, elapsed)
  camera.global_transform = camera.global_transform.interpolate_with(game.camera.global_transform, blend)
  camera.fov = lerpf(camera.fov, game.camera.fov, blend)

func _line(a: Vector3, b: Vector3, color: Color) -> void:
 strokes.surface_set_color(color)
 strokes.surface_add_vertex(a)
 strokes.surface_add_vertex(b)

func _ring(center: Vector3, radius: float, color: Color, vertical := false) -> void:
 for i in range(36):
  var a := i * TAU / 36
  var b := (i + 1) * TAU / 36
  var p := Vector3(cos(a), sin(a), 0) if vertical else Vector3(cos(a), 0, sin(a))
  var q := Vector3(cos(b), sin(b), 0) if vertical else Vector3(cos(b), 0, sin(b))
  _line(center + p * radius, center + q * radius, color)

func _effects() -> void:
 strokes.clear_surfaces()
 strokes.surface_begin(Mesh.PRIMITIVE_LINES)
 _line(Vector3.ZERO, Vector3.ZERO, Color(0, 0, 0, 0))
 var t := elapsed
 var ball_at_now: Vector3 = game.ball.position
 if t > 0.35 and t < HIT + flight:
  trail.append(ball_at_now)
  if trail.size() > 16:
   trail.pop_front()
  for i in range(1, trail.size()):
   var alpha := float(i) / trail.size()
   _line(trail[i - 1], trail[i], Color(1, 0.91, 0.64, alpha * 0.75))
 if t > 1.10 and t < 1.65:
  var u := (t - 1.10) / 0.55
  _ring(origin + Vector3.UP * 0.04, 0.35 + u * 1.1, Color(0.92, 0.87, 0.71, (1.0 - u) * 0.8))
  for i in range(14):
   var angle := i * TAU / 14
   var dir := Vector3(cos(angle), 0, sin(angle))
   _line(origin + dir * u * 0.7 + Vector3.UP * 0.08, origin + dir * (u * 0.9 + 0.12) + Vector3.UP * (0.12 + sin(u * PI) * 0.35), Color(0.8, 0.76, 0.64, (1.0 - u) * 0.65))
 if t >= 1.10 and t < 1.63:
  for i in range(9):
   var a := i * TAU / 9
   var offset := Vector3(cos(a) * 0.45, -0.3, sin(a) * 0.45)
   _line(actor.position + offset, actor.position + offset + Vector3.DOWN * 0.8, Color(0.95, 0.95, 0.91, 0.45))
 if t > HIT - 0.03 and t < HIT + 0.18:
  var u := clampf((t - HIT) / 0.18, 0, 1)
  var center := hit_point()
  for i in range(18):
   var a := i * TAU / 18
   var direction := Vector3(cos(a), sin(a), -side * 0.15).normalized()
   _line(center + direction * (0.18 + u * 0.25), center + direction * (0.28 + u * 0.75), Color(1, 0.96, 0.76, 1.0 - u))
 if t >= HIT and t < HIT + flight:
  var direction := (target - hit_point()).normalized()
  for i in range(7):
   var offset := Vector3((i - 3) * 0.035, (i % 2) * 0.04, 0)
   _line(ball_at_now + offset, ball_at_now - direction * (1.8 + i * 0.18) + offset, Color(1, 0.97, 0.85, 0.8 - i * 0.07))
 if t >= HIT + flight and t < HIT + flight + 0.45:
  var u := (t - HIT - flight) / 0.45
  _ring(target + Vector3.UP * 0.02, 0.12 + u * 0.8, Color(0.92, 0.88, 0.73, (1.0 - u) * 0.8))
 strokes.surface_end()

func _draw_frame() -> void:
 if not active:
  return
 var size := art.size
 var letterbox := size.y * 0.075 * (1.0 - smoothstep(3.95, END, elapsed))
 art.draw_rect(Rect2(0, 0, size.x, letterbox), Color("07131d"))
 art.draw_rect(Rect2(0, size.y - letterbox, size.x, letterbox), Color("07131d"))
 if elapsed >= HIT and elapsed < HIT + 0.07:
  art.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.98, 0.9, 0.16 * (1.0 - (elapsed - HIT) / 0.07)))
 if elapsed >= HIT and elapsed < HIT + flight:
  for i in range(16):
   var a := i * TAU / 16 + 0.04
   var edge := Vector2(cos(a) * size.x * 0.8, sin(a) * size.y * 0.8)
   art.draw_line(size * 0.5 + edge * 0.72, size * 0.5 + edge, Color(0.97, 0.95, 0.89, 0.4), 1.6, true)
 if elapsed > HIT + flight + 0.15 and elapsed < 3.95:
  var text := "IN" if inside else "OUT"
  var font := ThemeDB.fallback_font
  var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
  art.draw_string(font, Vector2(size.x * 0.5 - width * 0.5, size.y - letterbox - 24), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("e8e3cb") if inside else Color("efa68b"))

func finish(release_ball := true) -> void:
 if not active:
  return
 finished_sequence = sequence
 active = false
 if is_instance_valid(actor):
  actor.cinema_time = -1
  actor.cinema_pose = Callable()
  actor.global_position = ground_at(END)
  actor.velocity = Vector3.ZERO
  actor.network_motion.reset()
  actor.network_age = -1
  actor.cancel_input()
  actor.action = VolleyAthlete.Action.IDLE
  actor._update_pose(0)
 if is_instance_valid(game.ball):
  if authority():
   game.ball.freeze = false
   game.ball.collision_mask = 1
   game.ball.feed(ball_at(END) if release_ball else origin + Vector3(0, 0.5, -side), Vector3(0.3, 0, -side * 0.25), Vector3.ZERO)
  else:
   game.lan.ball_motion.reset()
   game.lan.ball_age = -1
 game.previous_ball_valid = false
 camera.current = false
 if is_instance_valid(old_camera):
  old_camera.current = true
 else:
  game.camera.current = true
 game.hud.visible = old_hud
 game.ball_shadow.visible = old_shadow
 game.hud._cancel()
 game.rig._process(0)
 overlay.hide()
 strokes.clear_surfaces()
 trail.clear()

func _exit_tree() -> void:
 if active:
  finish(false)
