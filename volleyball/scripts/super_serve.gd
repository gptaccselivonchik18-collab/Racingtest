class_name VolleySuperServe
extends Node3D

# Adapted from archive/super_serve_v0.34; authored poses, camera cuts and ink FX
# remain intact. Only the owner sees the camera. The host owns real physics.
const HIT := 3.55
const PALM_HOLD := 0.36
const RELEASE := HIT + PALM_HOLD
const FLOOR_HOLD := 0.30
const RESTORE := 6.65
const END := 7.10
const TAKEOFF := 1.30
const APEX := 1.95
const SPEED_MULTIPLIER := 0.90
const ARCHIVED_REFERENCE_SPEED := 70.0 # Cinematic ability pace, unrelated to Serve.
const SUPER_TOPSPIN_ACCEL := 75.0 # Stylized super arc, fixed before release.
const IN_CHANCE := 0.70
const SPIN := Vector3(3, 0, 0)
var game: Node3D
var active := false
var local_cinematic := false
var elapsed := 0.0 # Retimed authoring time, never Engine.time_scale.
var clock := 0.0
var sequence := 0
var finished_sequence := -1
var actor_id := 0
var actor: ContextAthlete
var origin := Vector3.ZERO
var yaw := 0.0
var side := 1.0
var target := Vector3.ZERO
var inside := true # Planned result; actual rules always use the real ball.
var height := 1.0
var flight := 0.8
var hit_clock := 1.8
var land_clock := 2.5
var end_clock := 4.5
var landed := false
var floor_clock := -1.0
var floor_point := Vector3.ZERO
var contact_done := false
var took_off := false
var tossed := false
var impulse_count := 0
var jump_count := 0
var peak_height := 0.0
var launch_velocity := Vector3.ZERO
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
var hidden_helpers: Array = []

func hide_local_helper(node: Node3D) -> void:
 hidden_helpers.append({"node":weakref(node),"visible":node.visible,"physics":node.is_physics_processing()})
 node.hide()
 node.set_physics_process(false)

func local_id() -> int:
 return game.lan.multiplayer.get_unique_id() if game.lan.active else 0

func authority() -> bool:
 return not game.lan.active or game.lan.hosting

func locks(player: ContextAthlete) -> bool:
 return active and actor == player

func preparing() -> bool:
 return active and not contact_done

# Old rally hooks deliberately have no scoring/charging behaviour.
func note_contact(_player: ContextAthlete, _id: int, _kind: int) -> void:
 pass
func clear_credit() -> void:
 pass

func eligible(player: ContextAthlete) -> bool:
 if active or not is_instance_valid(player) or player.character_id != "oikawa" or player.court_team < 0 or player.airborne() or player.dive_time >= 0:
  return false
 if not VolleyRules.in_service_zone(player.global_position) or absf(player.global_position.z) < 9.45:
  return false
 if game.lan.match_active or game.game_bots.solo_match:
  var serving_team: int = game.lan.serve_team if game.lan.match_active else game.game_bots.serve_team
  var live: bool = game.lan.round_live if game.lan.match_active else game.game_bots.last_team >= 0
  var waiting: float = game.lan.round_wait if game.lan.match_active else game.game_bots.round_wait
  var winner: int = game.lan.match_winner if game.lan.match_active else game.game_bots.match_winner
  if live or waiting >= 0 or winner >= 0 or player.court_team != serving_team or game.game_bots.current_server != player:
   return false
 return game.ball.held and game.ball.athlete == player

func request() -> bool:
 if game.lan.active:
  return game.lan.local_action("super")
 return begin(game.athlete, 0)

func choose_target(source: Vector3, success_chance := IN_CHANCE) -> Dictionary:
 var direction := 1.0 if source.z >= 0 else -1.0
 var good := random.randf() < success_chance
 # No receiver avoidance: a well positioned defender can genuinely touch it.
 var at := Vector3(random.randf_range(-3.85, 3.85), VolleyBall.RADIUS, -direction * random.randf_range(7.0, 8.50) if good else -direction * random.randf_range(9.55, 10.65))
 return {"target": at, "inside": good}

func begin(player: ContextAthlete, id: int) -> bool:
 if not authority() or not eligible(player) or game.automatic_serve_busy():
  return false
 var chance:=1.0-float(VolleyBotDifficulty.execution(player.execution_level,true).fault) if player.bot_execution else IN_CHANCE
 var aim := choose_target(player.global_position,chance)
 game.characters.demo = false
 if not game.rules.strict:
  game.rules.reset(true)
 sequence += 1
 var jump: float = player.effective_jump_height()
 packet = {"sequence":sequence,"actor":id,"origin":player.global_position,"yaw":0.0 if player.position.z >= 0 else PI,"target":aim.target,"inside":aim.inside,"height":jump,"flight":0.8}
 _start(packet, player, 0)
 _broadcast()
 return true

func resolve_actor(id: int) -> ContextAthlete:
 if game.lan.players.has(id):
  return game.lan.players[id].actor
 return game.game_bots.bots.get(id)

func _broadcast() -> void:
 if not game.lan.active or not game.lan.hosting:
  return
 for id in game.lan.players:
  if id != 1 and game.lan._peer_ready(id):
   show_scene.rpc_id(id, packet, clock, contact_done, floor_clock, floor_point)

@rpc("authority", "call_remote", "reliable", 3)
func show_scene(data: Dictionary, time: float, hit: bool, impact_time: float, impact: Vector3) -> void:
 if not game.lan.active or game.lan.hosting or not data.has_all(["sequence","actor","origin","yaw","target","inside","height","flight"]) or not is_finite(time) or time < 0 or time > 12:
  return
 var player := resolve_actor(int(data.actor))
 if not is_instance_valid(player) or player.character_id != "oikawa" or not data.origin is Vector3 or not data.target is Vector3 or not data.origin.is_finite() or not data.target.is_finite():
  return
 if int(data.sequence) <= finished_sequence:
  return
 if not active or sequence != int(data.sequence):
  _start(data, player, time)
 else:
  clock = maxf(clock, time) # Reliable checkpoints never rewind animation.
  packet = data.duplicate()
 flight = float(data.flight)
 end_clock = maxf(land_clock+0.45,hit_clock+flight+1.65)
 contact_done = hit
 if impact_time >= 0:
  floor_clock = impact_time
  floor_point = impact
  landed = true

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
 var rise := sqrt(2.0 * height / 9.81)
 hit_clock = TAKEOFF + rise * 0.96
 land_clock = TAKEOFF + rise * 2.0
 end_clock = maxf(land_clock + 0.45, hit_clock + flight + 1.65)
 clock = time
 elapsed = animation_time(clock)
 floor_clock = -1
 landed = false
 contact_done = false
 tossed = false
 took_off = false
 impulse_count = 0
 jump_count = 0
 peak_height = 0
 sync_left = 0.25
 had_network = game.lan.active
 local_cinematic = player == game.athlete and not player is VolleyGameBot
 if local_cinematic:
  old_hud = game.hud.visible
  old_shadow = game.ball_shadow.visible
  old_camera = get_viewport().get_camera_3d()
  game.hud._cancel()
  game.hud.hide()
  game.ball_shadow.hide()
  hidden_helpers.clear()
  for node_name in ["TossPreview","StrikePreview"]:
   var helper := game.get_node_or_null(node_name) as Node3D
   if helper:hide_local_helper(helper)
  var hall := game.get_node_or_null("CourtHall")
  if hall:
   for child in hall.get_children():
    if child is Label3D:hide_local_helper(child)
  overlay.show()
  camera.current = true
  Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 actor.cancel_input()
 actor.action = VolleyAthlete.Action.IDLE
 actor.special_set = ""
 actor.velocity = Vector3.ZERO
 actor.cinema_time = elapsed
 actor.cinema_pose = pose
 if authority():
  game.ball.held = true
  actor.holding_ball = true
  game.ball.pending_feed = false
  game.ball.clear_quick()
  game.ball.clear_float()
  game.ball.clear_attack()
  game.ball.freeze = true
  game.ball.collision_mask = 0 # Held preparation; feed() restores collisions at toss.
  game.ball.linear_velocity = Vector3.ZERO
  game.ball.angular_velocity = Vector3.ZERO
  game.ball.athlete = actor
  game.previous_ball_valid = false
 for child in game.ball.get_children():
  if child is MeshInstance3D:
   ball_visual = child
   ball_visual_rest = child.transform
   break
 trail.clear()
 active = true

func animation_time(time: float) -> float:
 if time <= TAKEOFF:
  return time
 if time <= hit_clock:
  return lerpf(TAKEOFF, HIT, (time - TAKEOFF) / maxf(0.01, hit_clock - TAKEOFF))
 if time <= land_clock + 0.25:
  return lerpf(HIT, RELEASE + 1.80, (time - hit_clock) / maxf(0.01, land_clock + 0.25 - hit_clock))
 return lerpf(RELEASE + 1.80, END, clampf((time - land_clock - 0.25) / maxf(0.01, end_clock - land_clock - 0.25),0,1))

func physical_time(t: float) -> float:
 if t <= TAKEOFF:return t
 if t <= HIT:return lerpf(TAKEOFF,hit_clock,(t-TAKEOFF)/(HIT-TAKEOFF))
 return lerpf(hit_clock,land_clock+0.25,clampf((t-HIT)/(RELEASE+1.80-HIT),0,1))

func jump_at(t: float) -> float:
 var since := maxf(0,physical_time(t)-TAKEOFF)
 return maxf(0,sqrt(19.62*height)*since-4.905*since*since)

func predicted_root(time: float) -> Vector3:
 if time <= TAKEOFF:return ground_at(time)
 var since := minf(time - TAKEOFF,land_clock - TAKEOFF)
 return ground_at(TAKEOFF) + Vector3(0,maxf(0,sqrt(19.62*height)*since-4.905*since*since),-side*air_speed()*since)

func air_speed() -> float:
 return clampf(absf(origin.z)-9.35,0.15,1.4)

func wrist_at(t: float, index: int) -> Vector3:
 var frame := choreography(t)
 var chest := Vector3(0,1.23,0)
 var shoulder: Vector3 = chest + frame.offset + frame.torso * Vector3(-0.3 if index == 0 else 0.3,0.22,0)
 var wrist: Vector3 = chest + frame.offset + frame.torso*(frame.wrists[index]-chest)
 wrist = shoulder+(wrist-shoulder).limit_length(0.855)
 return predicted_root(physical_time(t))+Basis(Vector3.UP,yaw)*wrist*actor.physical_scale

func hit_point() -> Vector3:
 return wrist_at(HIT,1)+Vector3(0,0,-side*0.15)

func timed_launch(start: Vector3,end: Vector3,duration: float,spin: Vector3,curve:=0.0) -> Vector3:
 if curve>0:end.y=maxf(end.y,VolleyBall.RADIUS+0.04)
 var steps := maxi(1,roundi(duration*120))
 var seconds := steps/120.0
 var launch := (end-start)/seconds+Vector3.UP*(9.81+curve)*0.5*seconds
 for iteration in range(5):
  var at := start
  var v := launch
  var w := spin
  var previous_force:=Vector3.ZERO
  for tick in range(steps):
   if curve>0:
    # feed() installs state on the first tick; aerodynamic force begins on
    # the following ordinary integrator tick, exactly as in VolleyBall.
    if tick>0:v+=(Vector3.DOWN*9.81+previous_force)/120.0
   else:
    v+=(Vector3.DOWN*9.81+game.ball.aero_force(v,w)/game.ball.mass)/120.0
   w *= 1.0-game.ball.angular_damp/120.0
   at += v/120.0
   if curve>0 and tick>0:previous_force=Vector3.DOWN*curve+game.ball.aero_force(v,w)/game.ball.mass
  launch += (end-at)/seconds
 return launch

func delivery_flight(start: Vector3,launch: Vector3,curve: float) -> Dictionary:
 var at:=start
 var v:=launch
 var spin:=SPIN
 var net:=INF
 var clearance:=INF
 var previous_force:=Vector3.ZERO
 for tick in range(300):
  var previous:=at
  if tick>0:v+=(Vector3.DOWN*9.81+previous_force)/120.0
  spin*=1.0-game.ball.angular_damp/120.0
  at+=v/120.0
  if tick>0:previous_force=Vector3.DOWN*curve+game.ball.aero_force(v,spin)/game.ball.mass
  if previous.z*at.z<0:net=previous.lerp(at,previous.z/(previous.z-at.z)).y
  for plane in [-VolleyBall.RADIUS-0.04,VolleyBall.RADIUS+0.04]:
   if (previous.z-plane)*(at.z-plane)<0:
    clearance=minf(clearance,previous.lerp(at,(previous.z-plane)/(previous.z-at.z)).y)
  if at.y<=VolleyBall.RADIUS+0.04:break
 return {"landing":at,"net_height":net,"net_clearance":clearance}

func solve_delivery(start: Vector3,destination: Vector3) -> Dictionary:
 # The ability has its own pace. Serve controls only ordinary deliveries.
 # Extra downward curvature is a deliberately stylized super-serve profile,
 # applied from release until first touch, not a late target correction.
 var desired:=ability_speed(actor)
 var curve:=SUPER_TOPSPIN_ACCEL
 var speed:=Vector3.ZERO
 var duration:=0.4
 var state: Dictionary={}
 for attempt in range(6):
  var low:=0.20
  var high:=0.75
  for iteration in range(10):
   duration=(low+high)*0.5
   speed=timed_launch(start,destination,duration,SPIN,curve)
   if speed.length()>desired:low=duration
   else:high=duration
  duration=roundf(duration*120)/120.0
  speed=timed_launch(start,destination,duration,SPIN,curve)
  state=delivery_flight(start,speed,curve)
  if float(state.net_clearance)>=2.66 and float(state.net_height)>=2.70:break
  if attempt<5:curve*=1.15
 return {"velocity":speed,"duration":duration,"curve":curve,"landing":state.get("landing",destination),"net_height":state.get("net_height",0)}

func ability_speed(player: ContextAthlete) -> float:
 var multiplier:=1.0
 if is_instance_valid(player) and player.bot_execution:
  multiplier=(player.style_stats as VolleyCharacterStats).difficulty_multiplier
 return ARCHIVED_REFERENCE_SPEED*SPEED_MULTIPLIER*multiplier

func _physics_process(dt: float) -> void:
 if not active:return
 if not is_instance_valid(actor) or (had_network and not game.lan.active) or actor.character_id != "oikawa" or (is_instance_valid(game.frontend) and game.frontend.in_home):
  finish(false)
  return
 clock += dt
 elapsed = animation_time(clock)
 actor.cinema_time = elapsed
 if authority():
  var previous_ground := ground_at(minf(TAKEOFF,maxf(0,clock-dt)))
  if clock < TAKEOFF:
   actor.velocity = (ground_at(clock)-previous_ground)/dt
   actor.velocity.y = -0.2
  elif not took_off:
   actor.velocity = Vector3(0,0,-side*air_speed())
   actor.jump(true)
   took_off = actor.velocity.y > 0.1
   if took_off:jump_count += 1
   else:finish(false);return
  else:
   if not actor.is_on_floor():actor.velocity.y -= 9.81*dt
   else:
    actor.velocity = Vector3.ZERO
    actor.jump_in_progress = false
  actor.move_and_slide()
  peak_height = maxf(peak_height,actor.position.y-origin.y)
  actor.visual.rotation = Vector3(0,yaw,0)
  actor._update_pose(0)
  if not tossed:
   game.ball.global_position = wrist_at(elapsed,1)+Basis(Vector3.UP,yaw)*Vector3(0,0.13,-0.04)
   if clock >= 0.35:
    tossed = true
    game.ball.feed(game.ball.position,timed_launch(game.ball.position,hit_point(),hit_clock-clock,Vector3.ZERO),Vector3.ZERO)
    actor.service_attempt_active = true
    actor.serve_swing_used = false
  if not contact_done and clock >= hit_clock:
   if clock <= hit_clock+0.12 and game.ball.position.distance_to(actor.wrists[1]) <= actor.serve_contact_radius:
    _strike()
   elif clock > hit_clock+0.12:
    # A real interrupted/missed toss never receives a remote corrective hit.
    contact_done = true
    _broadcast()
  sync_left -= dt
  if sync_left <= 0:
   sync_left = 0.25
   _broadcast()
 if clock >= end_clock:
  if authority() and game.lan.active:
   for id in game.lan.players:
    if id != 1 and game.lan._peer_ready(id):close_scene.rpc_id(id,sequence)
  finish(true)

func _strike() -> void:
 if not authority() or contact_done or actor.serve_swing_used:return
 contact_done = true
 var delivery := solve_delivery(game.ball.position,target)
 launch_velocity = delivery.velocity
 flight = float(delivery.duration)
 packet.flight = flight
 end_clock = maxf(land_clock+0.45,clock+flight+1.65)
 game.ball.launch_super(game.ball.position,launch_velocity,SPIN,float(delivery.curve))
 packet.curve=delivery.curve
 # feed() intentionally starts ordinary new attempts; consume this one AFTER it.
 actor.service_attempt_active = true
 actor.serve_swing_used = true
 actor.air_swing_used = true
 actor.hit_used = true
 actor.strike_count += 1
 actor.contact_count += 1
 actor.strike_technique = VolleyAthlete.Technique.JUMP_SERVE
 actor.action = VolleyAthlete.Action.STRIKE
 actor.last_contact_point = game.ball.position
 actor.quality = 1.0
 actor.contact_flash = 0.16
 impulse_count += 1
 game._on_player_touch(actor,actor_id,VolleyAthlete.Technique.JUMP_SERVE,game.ball.position,launch_velocity)
 if actor is VolleyGameBot:
  actor.contacts += 1
  actor.contact_kinds[VolleyAthlete.Technique.JUMP_SERVE] = int(actor.contact_kinds.get(VolleyAthlete.Technique.JUMP_SERVE,0))+1
 _broadcast()

func record_floor(at: Vector3) -> void:
 if active and authority() and contact_done and not landed:
  landed = true
  floor_clock = clock
  floor_point = at
  _broadcast()

func _process(_dt: float) -> void:
 if not active or not local_cinematic:return
 _deform_ball()
 _camera()
 _effects()
 art.queue_redraw()

func _deform_ball() -> void:
 if not is_instance_valid(ball_visual):return
 var compression := 1.0
 var normal := launch_velocity.normalized() if launch_velocity.length()>0.1 else (target-hit_point()).normalized()
 var after := clock-hit_clock
 if contact_done and after>=0 and after<0.12:
  compression = 1.0-0.28*sin(PI*after/0.12)
 elif floor_clock>=0 and clock-floor_clock<0.16:
  normal = Vector3.UP
  compression = 1.0-0.34*sin(PI*(clock-floor_clock)/0.16)
 var up := Vector3.FORWARD if absf(normal.dot(Vector3.UP))>0.95 else Vector3.UP
 var frame := Basis.looking_at(normal,up)
 var width := 1.0/sqrt(compression)
 ball_visual.global_basis = frame*Basis.from_scale(Vector3(width,width,compression))*frame.inverse()*game.ball.global_basis*ball_visual_rest.basis

@rpc("authority","call_remote","reliable",3)
func close_scene(id: int) -> void:
 if active and sequence==id:finish(true)
 else:finished_sequence=maxi(finished_sequence,id)

func finish(_release_ball := true) -> void:
 if not active:return
 finished_sequence = sequence
 active = false
 if is_instance_valid(actor):
  actor.cinema_time = -1
  actor.cinema_pose = Callable()
  actor.cancel_input()
  actor.action = VolleyAthlete.Action.IDLE
  actor.move_axis = Vector2.ZERO
  # Keep physical position, velocity and the freely flying/rebounding ball.
  actor._update_pose(0)
 if authority() and not tossed and is_instance_valid(game.ball):
  game.ball.feed(game.ball.position,Vector3.ZERO)
 if local_cinematic:
  for saved in hidden_helpers:
   var node: Variant=saved.node.get_ref()
   if is_instance_valid(node):
    node.visible=saved.visible
    node.set_physics_process(saved.physics)
  hidden_helpers.clear()
  if is_instance_valid(ball_visual):ball_visual.transform=ball_visual_rest
  camera.current=false
  if is_instance_valid(old_camera):old_camera.current=true
  else:game.camera.current=true
  game.hud.visible=old_hud
  game.ball_shadow.visible=old_shadow
  game.hud._cancel()
  Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if OS.get_name() in ["iOS","Android"] else Input.MOUSE_MODE_CAPTURED
  game.rig._process(0)
 overlay.hide()
 strokes.clear_surfaces()
 trail.clear()
 local_cinematic=false

func _exit_tree() -> void:
 if active:finish(false)

func ground_at(time: float) -> Vector3:
 # The whole planted approach ends behind the back line, including toes.
 # Forward travel across it begins only after take-off (legal on a serve).
 var run := clampf(absf(origin.z) - 9.50, 0, 2.0)
 var retreat := clampf(VolleyCourt.INNER_Z - 0.45 - absf(origin.z), 0, 0.28)
 var travel := -retreat * smoothstep(0, 0.22, time) + (run + retreat) * smoothstep(0.22, TAKEOFF, time)
 travel += run * 0.55 * smoothstep(TAKEOFF, HIT, time)
 var lateral := (clampf(origin.x,-3.3,3.3)-origin.x)*smoothstep(0,0.95,time)
 return origin + Vector3(lateral, 0, -side * travel)

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

func approach_arm(index: int, t: float) -> Dictionary:
 # Retargeted key poses: FIVB Level II manual p.40, Alberto Cisolla's
 # right-handed jump spin serve (Beijing 2008), frames 1–5. The toss arm
 # drops before both nearly straight arms pendulum back, then forward/up.
 # Shoulder angle and elbow flexion generate a coherent two-segment arm;
 # a separately interpolated wrist target used to fold the elbow backwards.
 var shoulder_angle := 0.20
 var flex := 0.20
 if index == 1:
  shoulder_angle = lerpf(0.65, 2.40, smoothstep(0.02, 0.35, t))
  flex = lerpf(1.15, 0.20, smoothstep(0.02, 0.35, t))
 shoulder_angle = lerpf(shoulder_angle, 0.12, smoothstep(0.40, 0.67, t))
 flex = lerpf(flex, 0.13, smoothstep(0.40, 0.67, t))
 shoulder_angle = lerpf(shoulder_angle, -1.35, smoothstep(0.67, 1.02, t))
 flex = lerpf(flex, 0.10, smoothstep(0.67, 1.02, t))
 # The swing passes under the shoulder, never through the chest.
 shoulder_angle = lerpf(shoulder_angle, 2.64, smoothstep(1.02, 1.49, t))
 flex = lerpf(flex, 0.18, smoothstep(1.18, 1.49, t))
 var s := -1.0 if index == 0 else 1.0
 var shoulder := Vector3(s * 0.30, 1.45, 0)
 var upper := Vector3(s * 0.025, -cos(shoulder_angle), -sin(shoulder_angle)).normalized()
 var lower := Vector3(s * 0.025, -cos(shoulder_angle + flex), -sin(shoulder_angle + flex)).normalized()
 var elbow := shoulder + upper * 0.44
 return {"wrist": elbow + lower * 0.42, "pole": elbow + Vector3(0, -0.04, -0.02)}

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
 var left_arm := approach_arm(0, t)
 var right_arm := approach_arm(1, t)
 var left: Vector3 = left_arm.wrist
 left = left.lerp(Vector3(-0.24, 1.98, -0.46), coil)
 left = left.lerp(Vector3(-0.34, 1.16, -0.08), core)
 left = left.lerp(Vector3(-0.39, 1.04, 0.13), follow)
 var right: Vector3 = right_arm.wrist
 right = right.lerp(Vector3(0.40, 1.98, 0.39), coil)
 right = right.lerp(Vector3(0.43, 2.14, 0.06), elbow)
 right = right.lerp(Vector3(0.25, 2.22, -0.36), wrist_snap)
 right += Vector3(0, -0.02, -0.05) * smoothstep(HIT, RELEASE, t) * (1.0 - follow)
 right = right.lerp(Vector3(-0.27, 1.14, -0.61), follow)
 left = left.lerp(Vector3(-0.29, 1.08, -0.27), recover)
 right = right.lerp(Vector3(0.29, 1.08, -0.27), recover)
 var left_pole: Vector3 = left_arm.pole
 left_pole = left_pole.lerp(Vector3(-0.46, 1.72, -0.16), coil)
 left_pole = left_pole.lerp(Vector3(-0.44, 1.20, 0.08), core)
 var right_pole: Vector3 = right_arm.pole
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
  var palm := Vector3.RIGHT if i == 0 else Vector3.LEFT
  if elapsed < 0.40 and i == 1:
   palm = Vector3.UP
  elif elapsed > TAKEOFF:
   palm = Vector3(0, 0.45, -0.9) if i == 0 else Vector3(0.08, -0.10, -1).normalized()
  motion.cinema_palms.append(palm)
  var flex := 0.0 if elapsed < TAKEOFF else (0.05 if i == 0 else float(frame.flex))
  if elapsed < 0.40 and i == 1:
   flex = lerpf(0.60, 0.20, smoothstep(0.05, 0.35, elapsed))
  motion.cinema_wrist_flex.append(flex)
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
 elif not contact_done or clock < hit_clock + 0.10:
  var u := smoothstep(APEX + 0.20, HIT, elapsed)
  at = actor.position + right * lerpf(3.10, 1.52, u) + forward * lerpf(0.35, 0.95, u) + Vector3.UP * lerpf(1.2, 1.80, u)
  focus = (actor.position + Vector3.UP * 1.12).lerp((actor.wrists[1] + hit_point()) * 0.5 + Vector3.DOWN * 0.12, u)
  focus += Vector3.UP * sin(u * PI) * 0.28
  camera.fov = lerpf(60, 36, u)
 else:
  var tracking := smoothstep(0.20, 0.80, clock-floor_clock) if landed else 0.0
  var framing: Vector3 = floor_point.lerp(game.ball.position, tracking) if landed else game.ball.position
  at = framing + Vector3(1.45 if target.x < 0 else -1.45, 0.24, -side * 1.65)
  focus = framing + Vector3.UP * 0.12
  camera.fov = 62
  var impact := exp(-maxf(0,clock-floor_clock)*14.0) if landed else 0.0
  at += Vector3(sin(elapsed * 137), cos(elapsed * 121), 0) * impact * 0.028
 at.x = clampf(at.x, -7.65, 7.65)
 at.z = clampf(at.z, -11.55, 11.55)
 at.y = clampf(at.y, 0.22, 10.6)
 camera.global_position = at
 camera.look_at(focus, Vector3.UP)
 if clock > end_clock-0.45:
  var blend := smoothstep(end_clock-0.45,end_clock,clock)
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
 if contact_done:
  t = RELEASE + maxf(0,clock-hit_clock)
 if landed:
  t = RELEASE + flight + maxf(0,clock-floor_clock)
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
 if landed and t >= RELEASE + flight and t < RELEASE + flight + 0.80:
  var u := (t - RELEASE - flight) / 0.80
  var floor_point := Vector3(floor_point.x,0.025,floor_point.z)
  _ring(floor_point, 0.12 + u * 0.9, Color(0.92, 0.88, 0.73, (1.0 - u) * 0.7))
  for i in range(16):
   var angle := i * TAU / 16.0
   var dir := Vector3(cos(angle), 0, sin(angle))
   var dust := floor_point + dir * (0.14 + u * (0.45 + (i % 3) * 0.15)) + Vector3.UP * sin(u * PI) * (0.03 + (i % 4) * 0.025)
   _line(dust, dust + dir * 0.10 + Vector3.UP * 0.025, Color(0.86, 0.80, 0.66, (1.0 - u) * 0.65))
 strokes.surface_end()

func _draw_frame() -> void:
 if not active or not local_cinematic:
  return
 var size := art.size
 var letterbox := size.y * 0.075 * (1.0 - smoothstep(end_clock-0.45,end_clock,clock))
 art.draw_rect(Rect2(0, 0, size.x, letterbox), Color("07131d"))
 art.draw_rect(Rect2(0, size.y - letterbox, size.x, letterbox), Color("07131d"))
 if contact_done and clock-hit_clock>=0 and clock-hit_clock<0.09:
  art.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.98, 0.9, 0.16 * (1.0 - (clock-hit_clock) / 0.09)))
 if landed and clock-floor_clock<0.10:
  art.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.97, 0.86, 0.08 * (1.0 - (clock-floor_clock) / 0.10)))
 if contact_done and not landed:
  for i in range(16):
   var a := i * TAU / 16 + 0.04
   var edge := Vector2(cos(a) * size.x * 0.8, sin(a) * size.y * 0.8)
   art.draw_line(size * 0.5 + edge * 0.72, size * 0.5 + edge, Color(0.97, 0.95, 0.89, 0.4), 1.6, true)
