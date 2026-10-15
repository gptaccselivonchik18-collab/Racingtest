class_name VolleyLAN
extends Node

signal changed
const PORT := 24680
const LIMIT := 12
const PROTOCOL := 8
var game: Node3D
var active := false
var hosting := false
var executing := false
var round_live := false
var connected := false
var status := ""
var players: Dictionary = {}
var owners: Dictionary = {}
var serve_flags: Dictionary = {}
var last_input: Dictionary = {}
var command_windows: Dictionary = {}
var tick := 0.0
var connecting_for := 0.0
var scores := [0, 0]
var round_wait := -1.0
var last_touch_team := 0
var serve_team := 0
var snapshot_count := 0
var discovery: VolleyRoomDiscovery
var join_address := ""
var rejected_reason := ""

func player_id(actor: ContextAthlete) -> int:
 for id in players:
  if players[id].actor == actor:
   return id
 return 0

func _ready() -> void:
 discovery = VolleyRoomDiscovery.new()
 discovery.lan = self
 add_child(discovery)
 # All gameplay messages go through the host; no client relay mesh is needed.
 multiplayer.server_relay = false
 name = "LAN"
 process_mode = Node.PROCESS_MODE_ALWAYS
 multiplayer.peer_connected.connect(_peer_joined)
 multiplayer.peer_disconnected.connect(_peer_left)
 multiplayer.connected_to_server.connect(_connected)
 multiplayer.connection_failed.connect(_failed)
 multiplayer.server_disconnected.connect(_lost_host)

func addresses() -> String:
 var result := PackedStringArray()
 for address in IP.get_local_addresses():
  if address.is_valid_ip_address() and ":" not in address and not address.begins_with("127.") and not address.begins_with("169.254."):
   result.append(address)
 return ", ".join(result) if not result.is_empty() else "Проверьте подключение к Wi-Fi"

func host_room(port := PORT) -> Error:
 leave()
 var peer := ENetMultiplayerPeer.new()
 var error := peer.create_server(port, LIMIT - 1)
 if error != OK:
  status = "Не удалось создать комнату. Порт занят или сеть недоступна."
  changed.emit()
  return error
 multiplayer.multiplayer_peer = peer
 active = true
 hosting = true
 connected = true
 _spawn(1, 0, 0)
 game.ball.replica = false
 game.ball.contact_athletes = [game.athlete]
 reset_round()
 discovery.advertise(port, port + 1)
 status = "Комната создана • " + addresses()
 changed.emit()
 return OK

func join_room(address: String, port := PORT) -> Error:
 leave()
 address = normalize_address(address)
 if not address.is_valid_ip_address():
  status = "Введите IP создателя комнаты, например 192.168.1.10"
  changed.emit()
  return ERR_INVALID_PARAMETER
 var peer := ENetMultiplayerPeer.new()
 var error := peer.create_client(address, port)
 if error != OK:
  status = "Не удалось подключиться к сети"
  changed.emit()
  return error
 multiplayer.multiplayer_peer = peer
 active = true
 join_address = address
 rejected_reason = ""
 status = "Подключение к " + address + "…"
 connecting_for = 0
 game.ball.replica = true
 game.ball.freeze = true
 game.athlete.replica = true
 game.athlete.set_physics_process(false)
 changed.emit()
 return OK

func leave() -> void:
 if is_instance_valid(discovery):
  discovery.stop_advertising()
  discovery.stop_search()
 active = false
 hosting = false
 connected = false
 if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
  multiplayer.multiplayer_peer.close()
 multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
 for entry in players.values():
  if is_instance_valid(entry.actor) and entry.actor != game.athlete:
   entry.actor.queue_free()
 players.clear()
 owners.clear()
 serve_flags.clear()
 last_input.clear()
 command_windows.clear()
 game.ball.contact_athletes.clear()
 game.ball.replica = false
 game.ball.athlete = game.athlete
 game.ball.held = false
 game.ball.freeze = false
 game.ball.collision_mask = 1
 game.athlete.holding_ball = false
 game.athlete.replica = false
 game.athlete.set_physics_process(true)
 if game.athlete.has_node("TeamTag"):
  game.athlete.get_node("TeamTag").queue_free()
 scores = [0, 0]
 serve_team = 0
 round_wait = -1
 snapshot_count = 0
 game.action_owner = ""
 changed.emit()

func _spawn(id: int, team: int, slot: int) -> void:
 if players.has(id):
  return
 var actor: ContextAthlete
 if id == multiplayer.get_unique_id():
  actor = game.athlete
 else:
  actor = ContextAthlete.new()
  actor.name = "Player_%d" % id
  add_child(actor)
  actor.touched.connect(func(kind: int, point: Vector3, outgoing: Vector3): game._on_player_touch(actor, id, kind, point, outgoing))
 var side := 1.0 if team == 0 else -1.0
 actor.position = Vector3((slot % 3 - 1) * 2.5, 0.02, side * (4.0 + (slot / 3) * 3.0))
 actor.visual.rotation.y = 0 if team == 0 else PI
 actor.camera_yaw = actor.visual.rotation.y
 actor.shift_lock = true
 actor.collision_layer = 2
 actor.collision_mask = 1
 actor.serve_solver = game.ball.solve_launch
 actor.replica = not hosting
 actor.set_physics_process(hosting)
 var tag := Label3D.new()
 tag.text = "%s %d" % ["A" if team == 0 else "Б", slot + 1]
 tag.position.y = 2.05
 tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 tag.font_size = 48
 tag.pixel_size = 0.006
 tag.modulate = Color("69d6e0") if team == 0 else Color("ffba73")
 tag.name = "TeamTag"
 actor.add_child(tag)
 players[id] = {"actor": actor, "team": team, "slot": slot}
 owners[id] = ""
 serve_flags[id] = false
 last_input[id] = Time.get_ticks_msec()
 if actor == game.athlete:
  game.rig.yaw = actor.camera_yaw
  game.rig.rendered_yaw = actor.camera_yaw
  game.rig.followed = actor.position + Vector3.UP * 1.45

func _peer_joined(id: int) -> void:
 if not hosting:
  return
 # Admission follows a version handshake, not the transport connection alone.
 last_input[id] = Time.get_ticks_msec()

@rpc("any_peer", "call_remote", "reliable")
func hello(version: int, skills: Dictionary) -> void:
 if not hosting:
  return
 var id := multiplayer.get_remote_sender_id()
 if version != PROTOCOL or players.size() >= LIMIT:
  reject_join.rpc_id(id, "Разные версии игры: всем нужна 0.8." if version != PROTOCOL else "Комната заполнена: уже 12 игроков.")
  get_tree().create_timer(0.3).timeout.connect(func():
   if hosting and id in multiplayer.get_peers():
    multiplayer.multiplayer_peer.disconnect_peer(id))
  return
 if players.has(id):
  return
 var count := [0, 0]
 for entry in players.values():
  count[entry.team] += 1
 var team := 0 if count[0] <= count[1] else 1
 var occupied := []
 for entry in players.values():
  if entry.team == team:
   occupied.append(entry.slot)
 var slot := 0
 while slot in occupied:
  slot += 1
 _spawn(id, team, slot)
 _apply_skills(players[id].actor, skills)
 _broadcast_roster()
 changed.emit()

func _peer_ready(id: int) -> bool:
 if id not in multiplayer.get_peers() or multiplayer.multiplayer_peer is not ENetMultiplayerPeer:
  return false
 var transport: ENetMultiplayerPeer = multiplayer.multiplayer_peer
 return transport.get_peer(id).get_state() == ENetPacketPeer.STATE_CONNECTED

func _broadcast_roster() -> void:
 var entries := []
 for id in players:
  entries.append([id, players[id].team, players[id].slot, players[id].actor.stats.values])
 for peer_id in players:
  if peer_id != 1 and _peer_ready(peer_id):
   roster.rpc_id(peer_id, entries)
 game.ball.contact_athletes = players.values().map(func(entry: Dictionary): return entry.actor)

@rpc("authority", "call_remote", "reliable")
func roster(entries: Array) -> void:
 if hosting or entries.size() > LIMIT:
  return
 var ids := []
 for entry in entries:
  if entry is Array and entry.size() == 4:
   ids.append(entry[0])
   _spawn(entry[0], entry[1], entry[2])
   _apply_skills(players[entry[0]].actor, entry[3])
 for id in players.keys():
  if id not in ids:
   _remove(id)
 connected = players.has(multiplayer.get_unique_id())
 status = "В комнате %d / 12" % players.size()
 changed.emit()

func _remove(id: int) -> void:
 if not players.has(id):
  return
 var actor: ContextAthlete = players[id].actor
 if game.ball.held and game.ball.athlete == actor:
  game.ball.drop()
  game.ball.athlete = game.athlete
 if actor != game.athlete:
  actor.queue_free()
 players.erase(id)
 owners.erase(id)
 serve_flags.erase(id)
 last_input.erase(id)
 command_windows.erase(id)

func _peer_left(id: int) -> void:
 _remove(id)
 last_input.erase(id)
 if hosting:
  _broadcast_roster()
 changed.emit()

func _connected() -> void:
 hello.rpc_id(1, PROTOCOL, game.athlete.stats.values)

func _failed() -> void:
 leave()
 status = rejected_reason if not rejected_reason.is_empty() else "Нет ответа. Откройте комнату у создателя, проверьте общую Wi-Fi сеть и разрешение локальной сети."
 game.frontend.show_home()
 changed.emit()

func _lost_host() -> void:
 if not connected:
  _failed()
  return
 leave()
 status = "Создатель вышел из комнаты. Можно подключиться снова или играть одному."
 game.frontend.show_home()
 changed.emit()

func local_action(role: String, phase := "press", payload: Dictionary = {}) -> bool:
 if not active or not connected:
  return false
 # Send current aim with reliable actions so a tap cannot overtake its aim.
 payload = payload.duplicate()
 payload.axis = game.athlete.move_axis
 payload.tilt = game.athlete.tilt
 payload.yaw = game.rig.yaw
 payload.pitch = game.rig.pitch
 payload.height = game.ball.release_height()
 payload.target = game.ball.throw_target
 payload.toss_yaw = game.ball.toss_yaw
 if hosting:
  return execute(1, role, phase, payload)
 command.rpc_id(1, role, phase, payload)
 if phase == "press" and role in ["primary", "secondary", "bump", "jump_set", "approach"]:
  game.action_owner = role
 elif phase != "press":
  game.action_owner = ""
 return true

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func input_state(axis: Vector2, tilt: Vector2, yaw: float, pitch: float) -> void:
 if hosting:
  _apply_input(multiplayer.get_remote_sender_id(), axis, tilt, yaw, pitch)

func _apply_input(id: int, axis: Vector2, tilt: Vector2, yaw: float, pitch: float) -> void:
 if not players.has(id) or not axis.is_finite() or not tilt.is_finite() or not is_finite(yaw) or not is_finite(pitch):
  return
 var actor: ContextAthlete = players[id].actor
 actor.move_axis = axis.limit_length()
 actor.tilt = tilt.limit_length()
 actor.camera_yaw = wrapf(yaw, -PI, PI)
 actor.camera_pitch = clampf(pitch, -0.85, 0.95)
 last_input[id] = Time.get_ticks_msec()

@rpc("any_peer", "call_remote", "reliable")
func command(role: String, phase: String, payload: Dictionary) -> void:
 if not hosting or payload.size() > 12:
  return
 var id := multiplayer.get_remote_sender_id()
 var now := Time.get_ticks_msec()
 var window: Dictionary = command_windows.get(id, {"start": now, "count": 0})
 if now - int(window.start) > 1000:
  window = {"start": now, "count": 0}
 window.count += 1
 command_windows[id] = window
 if phase == "press" and window.count > 64:
  return
 execute(id, role, phase, payload)

func execute(id: int, role: String, phase: String, payload: Dictionary = {}) -> bool:
 if not hosting or not players.has(id) or role not in ["primary", "secondary", "bump", "jump", "dive", "jump_set", "approach", "pickup", "context", "next", "cancel", "lower_serve", "stats"] or phase not in ["press", "release", "cancel"]:
  return false
 var actor: ContextAthlete = players[id].actor
 if role == "stats":
  var key: String = str(payload.get("skill", ""))
  var value: Variant = payload.get("value")
  if key not in VolleyStyleStats.KEYS or not (value is float or value is int) or not is_finite(float(value)):
   return false
  actor.stats.set_stat(key, float(value))
  for peer_id in players:
   if peer_id != 1 and _peer_ready(peer_id):
    style_state.rpc_id(peer_id, id, actor.stats.values)
  return true
 _apply_input(id, payload.get("axis", actor.move_axis), payload.get("tilt", actor.tilt), payload.get("yaw", actor.camera_yaw), payload.get("pitch", actor.camera_pitch))
 if role == "next":
  if id == 1:
   reset_round()
  return id == 1
 if role == "lower_serve":
  if game.ball.held and game.ball.athlete == actor and payload.get("aim") is Vector3:
   return game.lower_serve.launch(actor, payload.aim, float(payload.get("apex", 3.0)))
  return false
 if game.lower_serve.busy_actor == actor:
  return false
 if role in ["pickup", "context"] and game.ball.held and game.ball.athlete != actor:
  return false
 var local_actor: ContextAthlete = game.athlete
 var local_owner: String = game.action_owner
 var local_serving: bool = game.serving
 var was_held: bool = game.ball.held
 var holder: VolleyAthlete = game.ball.athlete
 game.athlete = actor
 game.action_owner = owners.get(id, "")
 game.serving = serve_flags.get(id, false)
 # Every action sees only the acting player's possession.
 game.ball.held = was_held and holder == actor
 if not was_held:
  game.ball.athlete = actor
 if game.ball.held:
  var h: float = float(payload.get("height", 1.5))
  if is_finite(h):
   game.ball.set_release_height(h)
  var target: Vector3 = payload.get("target", actor.hold_position())
  if target.is_finite():
   var offset := (target - actor.hold_position()).limit_length(14)
   game.ball.throw_target = actor.hold_position() + offset
   game.ball.throw_target.y = VolleyAthlete.BALL_RADIUS
  var yaw: float = float(payload.get("toss_yaw", 0))
  if is_finite(yaw):
   game.ball.toss_yaw = clampf(yaw, -PI / 3, PI / 3)
 var accepted := true
 executing = true
 if phase == "cancel" or role == "cancel":
  game.cancel_action("" if role == "cancel" else role)
 elif phase == "release":
  game.finish_action(role)
 else:
  match role:
   "primary": accepted = game.begin_primary()
   "secondary": accepted = game.begin_secondary()
   "bump": accepted = game.begin_bump()
   "approach": accepted = game.begin_approach()
   "jump_set": accepted = game.begin_jump_set()
   "jump": actor.jump()
   "dive": accepted = actor.dive()
   "pickup", "context": game.pickup_or_drop()
 executing = false
 owners[id] = game.action_owner
 serve_flags[id] = game.serving
 if was_held and holder != actor:
  game.ball.held = true
  game.ball.athlete = holder
 game.athlete = local_actor
 game.action_owner = owners.get(1, "") if id == 1 else local_owner
 game.serving = serve_flags.get(1, false) if id == 1 else local_serving
 return accepted

func reset_round() -> void:
 if not hosting:
  return
 game.lower_serve.cancel_sequence()
 round_live = false
 game.rules.reset()
 game.rules.strict = true
 for id in players:
  var actor: ContextAthlete = players[id].actor
  actor.cancel_input()
  actor.action = VolleyAthlete.Action.IDLE
  actor.holding_ball = false
  owners[id] = ""
 var server: ContextAthlete = game.athlete
 for entry in players.values():
  if entry.team == serve_team:
   server = entry.actor
   break
 var side := 1.0 if serve_team == 0 else -1.0
 server.position = Vector3(0, 0.02, side * 9.6)
 server.velocity = Vector3.ZERO
 server.visual.rotation.y = 0 if side > 0 else PI
 server.camera_yaw = server.visual.rotation.y
 if server == game.athlete:
  game.rig.yaw = server.camera_yaw
 game.ball.athlete = server
 game.ball.feed(server.position + Vector3(0, 0.25, -side * 0.55), Vector3.ZERO)
 game.previous_ball_valid = false
 round_wait = -1

func award_floor(at: Vector3) -> void:
 if not hosting or round_wait >= 0:
  return
 var winner: int
 if absf(at.x) <= 4.5 and absf(at.z) <= 9:
  winner = 1 if at.z >= 0 else 0
 else:
  winner = 1 - last_touch_team
 scores[winner] += 1
 serve_team = winner
 round_wait = 3.0
 changed.emit()

func _process(dt: float) -> void:
 if not active:
  return
 if not connected:
  connecting_for += dt
  if connecting_for > 10:
   _failed()
  return
 tick += dt
 if hosting:
  var now := Time.get_ticks_msec()
  for id in players:
   if id != 1 and now - int(last_input.get(id, now)) > 450:
    players[id].actor.cancel_input()
    owners[id] = ""
  # Remove peers that never complete the protocol handshake.
  for id in last_input.keys():
   if not players.has(id) and now - int(last_input[id]) > 5000:
    multiplayer.multiplayer_peer.disconnect_peer(id)
    last_input.erase(id)
  if round_live and game.rules.ended and round_wait < 0:
   serve_team = 1 - last_touch_team
   scores[serve_team] += 1
   round_wait = 3.0
  if round_wait >= 0:
   round_wait -= dt
   if round_wait < 0:
    reset_round()
 if tick < 1.0 / 30.0:
  return
 tick = 0
 if hosting:
  var poses := []
  var held_by := 0
  for id in players:
   var a: ContextAthlete = players[id].actor
   if game.ball.held and game.ball.athlete == a:
    held_by = id
   poses.append([id, a.position, a.velocity, a.visual.rotation, a.action, a.technique, a.strike_technique, a.action_time, a.power, a.strike_power, a.strike_duration, a.energy, a.move_axis, a.tilt, a.attack_ready, a.approach_armed, a.approach_blend, a.dive_time, a.last_result, a.jump_windup, a.release_time, a.contact_flash, a.lower_serve_active, a.air_attack])
  # Stay below the ENet MTU at 12 players; one large unreliable packet
  # would fragment and magnify loss on mobile Wi-Fi.
  for first in range(0, poses.size(), 2):
   for peer_id in players:
    if peer_id != 1 and _peer_ready(peer_id):
     snapshot.rpc_id(peer_id, poses.slice(first, first + 2), game.ball.position, game.ball.linear_velocity, game.ball.rotation, held_by, game.ball.held_mode, scores, game.rules.message)
 elif _peer_ready(1):
  input_state.rpc_id(1, game.athlete.move_axis, game.athlete.tilt, game.rig.yaw, game.rig.pitch)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func snapshot(poses: Array, at: Vector3, speed: Vector3, spin_pose: Vector3, held_by: int, mode: int, score: Array, message: String) -> void:
 if hosting or not connected:
  return
 snapshot_count += 1
 for pose in poses:
  if not players.has(pose[0]):
   continue
  var a: ContextAthlete = players[pose[0]].actor
  a.position = pose[1]
  a.velocity = pose[2]
  a.visual.rotation = pose[3]
  a.action = pose[4]
  a.technique = pose[5]
  a.strike_technique = pose[6]
  a.action_time = pose[7]
  a.power = pose[8]
  a.strike_power = pose[9]
  a.strike_duration = pose[10]
  a.energy = pose[11]
  if a != game.athlete:
   a.move_axis = pose[12]
   a.tilt = pose[13]
  a.attack_ready = pose[14]
  a.approach_armed = pose[15]
  a.approach_blend = pose[16]
  a.dive_time = pose[17]
  a.last_result = pose[18]
  a.jump_windup = pose[19]
  a.release_time = pose[20]
  a.contact_flash = pose[21]
  a.lower_serve_active = pose[22]
  a.air_attack = pose[23]
  a.holding_ball = held_by == pose[0]
  a.previous_wrists = a.wrists.duplicate()
  a.previous_elbows = a.elbows.duplicate()
 game.ball.position = at
 game.ball.rotation = spin_pose
 game.ball.last_velocity = speed
 game.ball.held = held_by == multiplayer.get_unique_id()
 game.ball.athlete = game.athlete
 game.ball.held_mode = mode
 scores = score
 game.rules.message = message

func _apply_skills(actor: ContextAthlete, skills: Dictionary) -> void:
 for key in VolleyStyleStats.KEYS:
  var value: Variant = skills.get(key)
  if (value is float or value is int) and is_finite(float(value)):
   actor.stats.set_stat(key, float(value))

@rpc("authority", "call_remote", "reliable")
func style_state(id: int, skills: Dictionary) -> void:
 if not hosting and players.has(id):
  _apply_skills(players[id].actor, skills)

static func normalize_address(raw: String) -> String:
 var text := raw.strip_edges().replace(",", ".").replace("，", ".").replace("。", ".")
 var pattern := RegEx.new()
 pattern.compile("(?:[0-9]{1,3}\\.){3}[0-9]{1,3}")
 for match_value in pattern.search_all(text):
  var value := match_value.get_string()
  if value.is_valid_ip_address():
   return value
 return text

@rpc("authority", "call_remote", "reliable")
func reject_join(reason: String) -> void:
 if not connected:
  rejected_reason = reason.left(160)
  status = rejected_reason
  changed.emit()
