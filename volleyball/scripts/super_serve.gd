class_name VolleySuperServe
extends Node3D

# Disposable prototype: local choreography and cameras, host-selected outcome.
# No audio or global slow motion. Charge belongs to the scoring human only.
const HIT := 3.55
const PALM_HOLD := 0.36
const RELEASE := HIT + PALM_HOLD
const FLOOR_HOLD := 0.30
const RESTORE := 6.65
const END := 7.10
const TAKEOFF := 1.30
const APEX := 1.95
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
var ball_visual: MeshInstance3D
var ball_visual_rest := Transform3D.IDENTITY
var strokes := ImmediateMesh.new()
var trail: Array[Vector3] = []
var trail_clock := 0.0
var sync_left := 0.0
var random := RandomNumberGenerator.new()
var packet := {}
const KILLS_REQUIRED := 7
var charges: Dictionary = {}
var scoring_contacts: Dictionary = {}
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
 if floor_consumed:
  scoring_contacts.clear()
 floor_consumed = false
 var team := player.court_team if player.court_team >= 0 else (0 if player.position.z >= 0 else 1)
 scoring_contacts[team] = {"actor": weakref(player), "id": id, "eligible": kind != VolleyAthlete.Technique.THROW}

func clear_credit() -> void:
 floor_consumed = true
 scoring_contacts.clear()

func record_floor(at: Vector3) -> void:
 if not authority() or active or floor_consumed:
  return
 floor_consumed = true
 if ((game.lan.match_active or game.game_bots.solo_match) and game.rules.ended):
  return
 var winner := 0 if at.z < 0 else 1
 var contact: Dictionary = scoring_contacts.get(winner, {})
 if contact.is_empty() or not contact.eligible:
  return
 var player: Variant = contact.actor.get_ref()
 if not is_instance_valid(player) or player is VolleyGameBot or player is VolleyPracticeBot:
  return
 if absf(at.x) <= 4.5 + VolleyBall.RADIUS and absf(at.z) <= 9.0 + VolleyBall.RADIUS and absf(at.z) > 0.15:
  # A failed defensive touch does not steal the attacker's personal credit.
  _earn(int(contact.id))

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
 # The whole planted approach ends behind the back line, including toes.
 # Forward travel across it begins only after take-off (legal on a serve).
 var run := clampf(absf(origin.z) - 9.50, 0, 2.0)
 var retreat := clampf(VolleyCourt.INNER_Z - 0.45 - absf(origin.z), 0, 0.28)
 var travel := -retreat * smoothstep(0, 0.22, time) + (run + retreat) * smoothstep(0.22, TAKEOFF, time)
 travel += run * 0.55 * smoothstep(TAKEOFF, HIT, time)
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
 var good := random.randf() < 0.9
 var at := Vector3.ZERO
 var best := -INF
 var safe: Array[Vector3] = []
 var opponents: Array = game.game_bots.members(1 if direction > 0 else 0)
 var approach := clampf(absf(source.z) - 9.50, 0, 2.0)
 var contact := source + Vector3(0, 6.5, -direction * (approach * 1.55 + 0.55))
 for candidate in range(80):
  var point := Vector3(random.randf_range(-4.15, 4.15), VolleyBall.RADIUS, -direction * (random.randf_range(8.70, 9.03) if good else random.randf_range(9.48, 10.12)))
  var clearance := 100.0
  for opponent: ContextAthlete in opponents:
   var observed := opponent.position + Vector3(opponent.velocity.x, 0, opponent.velocity.z).limit_length(3) * 0.15
   var reach := opponent.contact_ball_radius * float(opponent.mechanic(VolleyAthlete.Technique.UNDERHAND).radius) + 0.55
   for step in range(15):
    var u := step / 14.0
    var ball_position := flight_position(contact, point, u)
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
 if absf(player.global_position.z) < 10.05:
  if player == game.athlete:
   game.show_feedback("Для разбега отойдите за заднюю линию ещё на %.1f м · заряд сохранён" % (10.05 - absf(player.global_position.z)), false)
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
 clear_credit()
 landed = time >= RELEASE + flight
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
 for child in game.ball.get_children():
  if child is MeshInstance3D:
   ball_visual = child
   ball_visual_rest = child.transform
   break
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
 if not landed and elapsed >= RELEASE + flight:
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
 if time < TAKEOFF:
  return 0
 if time < APEX:
  var u := clampf((time - TAKEOFF) / (APEX - TAKEOFF), 0, 1)
  return height * (1.0 - pow(1.0 - u, 2.2))
 if time < RELEASE:
  return height - 0.12 * smoothstep(APEX, HIT, time)
 return (height - 0.12) * (1.0 - pow(smoothstep(RELEASE, RELEASE + 0.95, time), 1.4))

func hit_point() -> Vector3:
 # Use the exact same shoulder, arm-length clamp and wrist as the visible rig.
 var frame := choreography(HIT)
 var chest := Vector3(0, 1.23, 0)
 var shoulder: Vector3 = chest + frame.offset + frame.torso * Vector3(0.3, 0.22, 0)
 var wrist: Vector3 = chest + frame.offset + frame.torso * (frame.wrists[1] - chest)
 wrist = shoulder + (wrist - shoulder).limit_length(0.855)
 return ground_at(HIT) + Vector3.UP * jump_at(HIT) + Basis(Vector3.UP, yaw) * wrist + Vector3(0, 0, -side * 0.15)

func flight_position(start: Vector3, end: Vector3, u: float) -> Vector3:
 # A shallow ballistic bend, rather than carrying high and diving vertically.
 return start.lerp(end, u) + Vector3.UP * (0.18 * 4.0 * u * (1.0 - u))

func release_point() -> Vector3:
 return hit_point() + (target - hit_point()).normalized() * 0.07

func rebound_state(time: float) -> Dictionary:
 # Local cinematic time eases out of the floor close-up. Release the real
 # body with this same position and velocity so momentum survives the cut.
 var q := maxf(0, time - RELEASE - flight - FLOOR_HOLD)
 var remaining := 0.20 * q + 0.80 * (q - 0.55 * (1.0 - exp(-q / 0.55)))
 var direction := target - release_point()
 direction.y = 0
 var speed := direction.normalized() * 6.0 + Vector3.UP * 3.6
 var at := target
 while remaining > 0.00001:
  var dt := minf(remaining, 1.0 / 120.0)
  speed.y -= 9.81 * dt
  at += speed * dt
  if at.y < VolleyBall.RADIUS:
   at.y = VolleyBall.RADIUS
   speed.y = absf(speed.y) * 0.60 if speed.y < -0.5 else 0.0
   speed.x *= 0.97
   speed.z *= 0.97
  for axis in [0, 2]:
   var bound := VolleyCourt.INNER_X if axis == 0 else VolleyCourt.INNER_Z
   if absf(at[axis]) > bound:
    at[axis] = signf(at[axis]) * (2.0 * bound - absf(at[axis]))
    speed[axis] = -speed[axis] * 0.65
  remaining -= dt
 return {"position": at, "velocity": speed}

func ball_at(time: float) -> Vector3:
 var facing := Basis(Vector3.UP, yaw)
 var start := ground_at(minf(time, 0.35)) + facing * Vector3(-0.12, 1.57, -0.48)
 var contact := hit_point()
 if time < 0.35:
  return start - Vector3.UP * ((1.0 - smoothstep(0, 0.35, time)) * 0.15)
 if time < APEX:
  var u := smoothstep(0.35, APEX, time)
  var control := origin + Vector3.UP * (height + 7.0) + facing * Vector3(0.1, 0, -1.75)
  return (1.0 - u) * (1.0 - u) * start + 2.0 * (1.0 - u) * u * control + u * u * (contact + Vector3.UP * 0.16)
 if time < HIT:
  return contact + Vector3.UP * (0.16 * (1.0 - smoothstep(APEX, HIT, time)))
 if time < RELEASE:
  return contact.lerp(release_point(), smoothstep(HIT, RELEASE, time))
 if time < RELEASE + flight:
  return flight_position(release_point(), target, clampf((time - RELEASE) / flight, 0, 1))
 var after := time - RELEASE - flight
 if after < FLOOR_HOLD:
  # Keep the underside planted while the shell compresses and springs back.
  var squash := 1.0 - 0.34 * sin(PI * after / FLOOR_HOLD)
  return target + Vector3.DOWN * (VolleyBall.RADIUS * (1.0 - squash))
 return rebound_state(time).position

func _deform_ball() -> void:
 if not is_instance_valid(ball_visual):
  return
 var compression := 1.0
 var normal := (target - hit_point()).normalized()
 if elapsed >= HIT and elapsed < RELEASE:
  compression = 1.0 - 0.28 * sin(PI * (elapsed - HIT) / PALM_HOLD)
 elif elapsed >= RELEASE + flight and elapsed < RELEASE + flight + FLOOR_HOLD:
  normal = Vector3.UP
  compression = 1.0 - 0.34 * sin(PI * (elapsed - RELEASE - flight) / FLOOR_HOLD)
 var up := Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.95 else Vector3.UP
 var frame := Basis.looking_at(normal, up)
 var width := 1.0 / sqrt(compression)
 var deform := frame * Basis.from_scale(Vector3(width, width, compression)) * frame.inverse()
 ball_visual.global_basis = deform * game.ball.global_basis * ball_visual_rest.basis

func _sample() -> void:
 actor.cinema_time = elapsed
 actor.global_position = ground_at(elapsed) + Vector3.UP * jump_at(elapsed)
 actor.visual.rotation = Vector3(0, yaw, 0)
 actor.camera_yaw = yaw
 actor.velocity = Vector3.ZERO
 actor._update_pose(0)
 game.ball.global_position = ball_at(elapsed)
 var turn := minf(elapsed, HIT) * 2.0 + clampf(elapsed - HIT, 0, PALM_HOLD) * 0.4
 turn += clampf(elapsed - RELEASE, 0, flight) * 24.0 + clampf(elapsed - RELEASE - flight, 0, FLOOR_HOLD) * 0.5
 turn += maxf(0, elapsed - RELEASE - flight - FLOOR_HOLD) * 9.0
 game.ball.rotation = Vector3(turn, 0.3, turn * 0.2)
 _deform_ball()
 _camera()
 _effects()
 art.queue_redraw()

func foot_advance(t: float) -> float:
 return (origin - ground_at(t)).z * side

func planted_foot(index: int, t: float) -> Vector3:
 var body := foot_advance(t)
 var initial := 0.08 if index == 0 else -0.06
 var step_start := 0.26 if index == 0 else 0.02
 var step_end := 0.63 if index == 0 else 0.24
 var next := foot_advance(0.73) + 0.12 if index == 0 else foot_advance(0.22) - 0.06
 var progress := smoothstep(step_start, step_end, t)
 var advance := lerpf(initial, next, progress)
 var lift := sin(progress * PI) * (0.17 if index == 0 else 0.07)
 var last_start := 1.01 if index == 0 else 0.60
 var last_end := 1.28 if index == 0 else 1.00
 if t >= last_start:
  var plant := foot_advance(TAKEOFF) + 0.06 if index == 0 else foot_advance(1.17) - 0.03
  progress = smoothstep(last_start, last_end, t)
  advance = lerpf(next, plant, progress)
  lift = sin(progress * PI) * (0.12 if index == 0 else 0.20)
 return Vector3(-0.17 if index == 0 else 0.19, 0.11 + lift, body - advance)

func choreography(t: float) -> Dictionary:
 # Feet plant in court space. The penultimate step loads knees/hips, the
 # two arms swing up, then pelvis/chest lead shoulder, elbow and wrist.
 var run := smoothstep(0.25, 0.80, t)
 var load := smoothstep(0.88, 1.12, t) * (1.0 - smoothstep(1.12, TAKEOFF + 0.14, t))
 var lift := smoothstep(1.05, APEX - 0.12, t)
 var coil := smoothstep(APEX - 0.10, 2.38, t)
 var core := smoothstep(2.58, HIT - 0.12, t)
 var elbow := smoothstep(2.86, HIT - 0.10, t)
 var wrist_snap := smoothstep(HIT - 0.32, HIT, t)
 var follow := smoothstep(RELEASE, RELEASE + 0.45, t)
 var recover := smoothstep(RELEASE + 1.02, RELEASE + 1.80, t)
 var landing := sin(smoothstep(RELEASE + 0.80, RELEASE + 1.60, t) * PI)
 var twist := lerpf(-0.10 * run, -0.63, coil)
 twist = lerpf(twist, 0.22, core)
 twist = lerpf(twist, 0.62, follow) * (1.0 - recover)
 var bend := lerpf(-0.18 * run, 0.40, lift * coil)
 bend = lerpf(bend, 0.10, core)
 bend = lerpf(bend, -0.26, follow) * (1.0 - recover)
 var roll := lerpf(-0.08 * coil, 0.05, core) * (1.0 - recover)
 var crouch := 0.09 + load * 0.24 - lift * 0.05 + landing * 0.25
 var offset := Vector3(0.025 * sin(run * PI), -crouch, -0.045 * load)
 var torso := Basis.from_euler(Vector3(bend, twist, roll))
 var left := Vector3(-0.19, 1.40, -0.48).lerp(Vector3(-0.20, 1.96, -0.44), smoothstep(0.08, 0.35, t))
 left = left.lerp(Vector3(-0.34, 1.00, 0.38), smoothstep(0.42, 1.03, t))
 left = left.lerp(Vector3(-0.23, 2.08, -0.30), lift)
 left = left.lerp(Vector3(-0.24, 1.98, -0.46), coil)
 left = left.lerp(Vector3(-0.34, 1.16, -0.08), core)
 left = left.lerp(Vector3(-0.39, 1.04, 0.13), follow)
 var right := Vector3(0.29, 1.17, -0.22).lerp(Vector3(0.36, 1.00, 0.41), smoothstep(0.22, 1.05, t))
 right = right.lerp(Vector3(0.33, 2.04, -0.16), lift)
 right = right.lerp(Vector3(0.40, 1.98, 0.39), coil)
 right = right.lerp(Vector3(0.43, 2.14, 0.06), elbow)
 right = right.lerp(Vector3(0.25, 2.22, -0.36), wrist_snap)
 right += Vector3(0, -0.02, -0.05) * smoothstep(HIT, RELEASE, t) * (1.0 - follow)
 right = right.lerp(Vector3(-0.27, 1.14, -0.61), follow)
 left = left.lerp(Vector3(-0.29, 1.08, -0.27), recover)
 right = right.lerp(Vector3(0.29, 1.08, -0.27), recover)
 var left_pole := Vector3(-0.42, 1.05, 0.14).lerp(Vector3(-0.46, 1.72, -0.16), lift)
 left_pole = left_pole.lerp(Vector3(-0.44, 1.20, 0.08), core)
 var right_pole := Vector3(0.44, 1.05, 0.20).lerp(Vector3(0.49, 1.78, -0.07), lift)
 right_pole = right_pole.lerp(Vector3(0.68, 1.83, 0.25), coil)
 right_pole = right_pole.lerp(Vector3(0.47, 1.94, -0.28), elbow)
 right_pole = right_pole.lerp(Vector3(0.16, 1.39, -0.36), follow)
 left_pole = left_pole.lerp(Vector3(-0.3, 1.02, 0.24), recover)
 right_pole = right_pole.lerp(Vector3(0.3, 1.02, 0.24), recover)
 var feet: Array[Vector3] = []
 var shoe_pitch: Array[float] = []
 var airborne := smoothstep(TAKEOFF, TAKEOFF + 0.20, t) * (1.0 - smoothstep(RELEASE + 0.60, RELEASE + 0.93, t))
 for i in range(2):
  var s := -1.0 if i == 0 else 1.0
  var foot := planted_foot(i, minf(t, TAKEOFF))
  var flying := Vector3(s * 0.19, 0.11 + (0.18 if i == 0 else 0.32), 0.16 if i == 0 else 0.36)
  flying = flying.lerp(Vector3(s * 0.18, 0.18, -0.06 if i == 0 else 0.12), core)
  foot = foot.lerp(flying, airborne)
  if t >= RELEASE + 0.93:
   foot = Vector3(s * 0.22, 0.11, -0.06 if i == 0 else 0.08)
  feet.append(foot)
  shoe_pitch.append(-0.46 * airborne + 0.10 * landing)
 var head_pitch := lerpf(0.12, 0.52, smoothstep(0.15, 0.80, t))
 head_pitch = lerpf(head_pitch, 0.32, coil)
 head_pitch = lerpf(head_pitch, -0.10, wrist_snap) * (1.0 - recover)
 return {"offset": offset, "torso": torso, "wrists": [left, right], "poles": [left_pole, right_pole], "feet": feet, "shoes": shoe_pitch, "head": Basis.from_euler(Vector3(head_pitch, twist * 0.22, 0)), "flex": 0.12 * coil - 0.24 * smoothstep(HIT, RELEASE + 0.18, t) * (1.0 - recover)}

func pose(motion: VolleyMotion) -> void:
 var frame := choreography(elapsed)
 var chest := Vector3(0, 1.23, 0)
 motion.body_offset = frame.offset
 motion.torso_basis = frame.torso
 motion.wrists.clear()
 motion.poles.clear()
 motion.feet.clear()
 for i in range(2):
  var wrist: Vector3 = frame.wrists[i]
  motion.wrists.append(chest + motion.body_offset + motion.torso_basis * (wrist - chest))
  var pole: Vector3 = frame.poles[i]
  motion.poles.append(chest + motion.body_offset + motion.torso_basis * (pole - chest))
  motion.feet.append(frame.feet[i])
  motion.cinema_palms.append(Vector3(0, 0.45, -0.9) if i == 0 else Vector3(0.08, -0.10, -1).normalized())
  motion.cinema_wrist_flex.append(0.05 if i == 0 else float(frame.flex))
  motion.cinema_shoe_pitch.append(frame.shoes[i])
 motion.cinema_head = frame.head
 motion.initialized = true

func _camera() -> void:
 var forward := Vector3(0, 0, -side)
 var right := Vector3(side, 0, 0)
 var view := -signf(origin.x) * side if absf(origin.x) > 1.5 else 1.0
 var at: Vector3
 var focus: Vector3
 if elapsed < APEX + 0.20:
  var widen := smoothstep(0.20, 1.10, elapsed)
  at = origin + right * view * lerpf(4.2, 6.0, widen) + forward * 0.8 + Vector3.UP * (lerpf(1.95, 4.1, widen) + jump_at(elapsed) * 0.18)
  focus = origin + Vector3.UP * (lerpf(1.25, 3.95, widen) + jump_at(elapsed) * 0.35)
  camera.fov = lerpf(58, 85, widen)
 elif elapsed < RELEASE + 0.045:
  var u := smoothstep(APEX + 0.20, HIT, elapsed)
  at = actor.position + right * lerpf(3.10, 1.52, u) + forward * lerpf(0.35, 0.95, u) + Vector3.UP * lerpf(1.2, 1.80, u)
  focus = (actor.position + Vector3.UP * 1.12).lerp((actor.wrists[1] + hit_point()) * 0.5 + Vector3.DOWN * 0.12, u)
  focus += Vector3.UP * sin(u * PI) * 0.28
  camera.fov = lerpf(60, 36, u)
 else:
  var tracking := smoothstep(RELEASE + flight + FLOOR_HOLD, RELEASE + flight + 0.80, elapsed)
  var framing := target.lerp(game.ball.position, tracking)
  at = framing + Vector3(1.45 if target.x < 0 else -1.45, 0.24, -side * 1.65)
  focus = framing + Vector3.UP * 0.12
  camera.fov = 62
  var impact := exp(-maxf(0, elapsed - RELEASE - flight) * 14.0) if elapsed >= RELEASE + flight else 0.0
  at += Vector3(sin(elapsed * 137), cos(elapsed * 121), 0) * impact * 0.028
 at.x = clampf(at.x, -7.65, 7.65)
 at.z = clampf(at.z, -11.55, 11.55)
 at.y = clampf(at.y, 0.22, 10.6)
 camera.global_position = at
 camera.look_at(focus, Vector3.UP)
 if elapsed > RESTORE:
  var blend := smoothstep(RESTORE, END, elapsed)
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
 if t > 0.35 and t < RELEASE + flight:
  trail.append(ball_at_now)
  if trail.size() > 16:
   trail.pop_front()
  for i in range(1, trail.size()):
   var alpha := float(i) / trail.size()
   _line(trail[i - 1], trail[i], Color(1, 0.91, 0.64, alpha * 0.75))
 if t > TAKEOFF and t < TAKEOFF + 0.55:
  var u := (t - TAKEOFF) / 0.55
  var takeoff_at := ground_at(TAKEOFF)
  _ring(takeoff_at + Vector3.UP * 0.04, 0.35 + u * 1.1, Color(0.92, 0.87, 0.71, (1.0 - u) * 0.8))
  for i in range(14):
   var angle := i * TAU / 14
   var dir := Vector3(cos(angle), 0, sin(angle))
   _line(takeoff_at + dir * u * 0.7 + Vector3.UP * 0.08, takeoff_at + dir * (u * 0.9 + 0.12) + Vector3.UP * (0.12 + sin(u * PI) * 0.35), Color(0.8, 0.76, 0.64, (1.0 - u) * 0.65))
 if t >= TAKEOFF and t < APEX:
  for i in range(9):
   var a := i * TAU / 9
   var offset := Vector3(cos(a) * 0.45, -0.3, sin(a) * 0.45)
   _line(actor.position + offset, actor.position + offset + Vector3.DOWN * 0.8, Color(0.95, 0.95, 0.91, 0.45))
 if t > HIT and t < RELEASE + 0.22:
  var u := clampf((t - HIT) / (PALM_HOLD + 0.22), 0, 1)
  var center := hit_point()
  var normal := (target - center).normalized()
  var frame := Basis.looking_at(normal)
  for i in range(18):
   var a := i * TAU / 18
   var direction := frame * Vector3(cos(a), sin(a), 0)
   _line(center + direction * (0.18 + u * 0.25), center + direction * (0.28 + u * 0.62), Color(1, 0.96, 0.76, sin(u * PI) * 0.85))
  # Pale curved pressure strokes wrap the palm, not a magical projectile.
  for arc in range(3):
   for step in range(10):
    var a := -1.1 + step * 0.22
    var b := a + 0.22
    var r := 0.22 + arc * 0.08 + u * 0.12
    _line(center + frame * Vector3(cos(a) * r, sin(a) * r, 0.03 * arc), center + frame * Vector3(cos(b) * r, sin(b) * r, 0.03 * arc), Color(1, 0.98, 0.89, sin(u * PI) * 0.55))
 if t >= RELEASE and t < RELEASE + flight:
  var direction := (target - hit_point()).normalized()
  for i in range(7):
   var offset := Vector3((i - 3) * 0.035, (i % 2) * 0.04, 0)
   _line(ball_at_now + offset, ball_at_now - direction * (1.8 + i * 0.18) + offset, Color(1, 0.97, 0.85, 0.8 - i * 0.07))
 if t >= RELEASE + flight and t < RELEASE + flight + 0.80:
  var u := (t - RELEASE - flight) / 0.80
  var floor_point := Vector3(target.x, 0.025, target.z)
  _ring(floor_point, 0.12 + u * 0.9, Color(0.92, 0.88, 0.73, (1.0 - u) * 0.7))
  for i in range(16):
   var angle := i * TAU / 16.0
   var dir := Vector3(cos(angle), 0, sin(angle))
   var dust := floor_point + dir * (0.14 + u * (0.45 + (i % 3) * 0.15)) + Vector3.UP * sin(u * PI) * (0.03 + (i % 4) * 0.025)
   _line(dust, dust + dir * 0.10 + Vector3.UP * 0.025, Color(0.86, 0.80, 0.66, (1.0 - u) * 0.65))
 strokes.surface_end()

func _draw_frame() -> void:
 if not active:
  return
 var size := art.size
 var letterbox := size.y * 0.075 * (1.0 - smoothstep(RESTORE, END, elapsed))
 art.draw_rect(Rect2(0, 0, size.x, letterbox), Color("07131d"))
 art.draw_rect(Rect2(0, size.y - letterbox, size.x, letterbox), Color("07131d"))
 if elapsed >= RELEASE and elapsed < RELEASE + 0.09:
  art.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.98, 0.9, 0.16 * (1.0 - (elapsed - RELEASE) / 0.09)))
 if elapsed >= RELEASE + flight and elapsed < RELEASE + flight + 0.10:
  art.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.97, 0.86, 0.08 * (1.0 - (elapsed - RELEASE - flight) / 0.10)))
 if elapsed >= RELEASE and elapsed < RELEASE + flight:
  for i in range(16):
   var a := i * TAU / 16 + 0.04
   var edge := Vector2(cos(a) * size.x * 0.8, sin(a) * size.y * 0.8)
   art.draw_line(size * 0.5 + edge * 0.72, size * 0.5 + edge, Color(0.97, 0.95, 0.89, 0.4), 1.6, true)
 if elapsed > RELEASE + flight + FLOOR_HOLD + 0.15 and elapsed < RESTORE:
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
  if is_instance_valid(ball_visual):
   ball_visual.transform = ball_visual_rest
  if authority():
   game.ball.freeze = false
   game.ball.collision_mask = 1
   var rebound := rebound_state(END)
   game.ball.feed(rebound.position if release_ball else origin + Vector3(0, 0.5, -side), rebound.velocity if release_ball else Vector3.ZERO, Vector3(9, 2, -side * 4) if release_ball else Vector3.ZERO)
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
