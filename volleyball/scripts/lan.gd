class_name VolleyLAN
extends Node

signal changed
const PORT := 24680
const LIMIT := 12
const PROTOCOL := 25
const CONNECT_TIMEOUT := 30.0
var game: Node3D
var active := false
var hosting := false
var executing := false
var round_live := false
var match_active := false
var ready_message := "Свободная игра • зоны выбора команд справа от площадки"
var ready_seconds := 0.0
var ready_signature := ""
var state_tick := 0.0
var ball_target := Vector3.ZERO
var ball_speed := Vector3.ZERO
var ball_age := -1.0
var ball_motion := VolleyReplicaMotion.new()
var selection_zone: Node3D
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
var sets := [0, 0]
var match_winner := -1
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
 if is_instance_valid(game.game_bots):
  for id in game.game_bots.bots:
   if game.game_bots.bots[id] == actor:
    return id
 return 0

func _ready() -> void:
 discovery = VolleyRoomDiscovery.new()
 discovery.lan = self
 add_child(discovery)
 # All gameplay messages go through the host; no client relay mesh is needed.
 multiplayer.server_relay = false
 name = "LAN"
 process_priority = -10
 ball_motion.correction = 12.0
 ball_motion.teleport_distance = 4.0
 process_mode = Node.PROCESS_MODE_ALWAYS
 multiplayer.peer_connected.connect(_peer_joined)
 multiplayer.peer_disconnected.connect(_peer_left)
 multiplayer.connected_to_server.connect(_connected)
 multiplayer.connection_failed.connect(_failed)
 multiplayer.server_disconnected.connect(_lost_host)

func addresses() -> String:
 var result := VolleyNetworkInfo.local_addresses()
 return ", ".join(result) if not result.is_empty() else "Подключитесь к Wi-Fi или включите точку доступа"

func host_room(port := PORT) -> Error:
 if port < 1 or port > 65534:
  status = "Неверный порт комнаты"
  changed.emit()
  return ERR_INVALID_PARAMETER
 leave()
 var peer := ENetMultiplayerPeer.new()
 peer.set_bind_ip("0.0.0.0")
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
 start_free_play()
 var discovery_error := discovery.advertise(port, port + 1)
 status = "Комната создана • " + addresses()
 if discovery_error != OK:
  status += " • Поиск недоступен, войдите по IP"
 changed.emit()
 return OK

func join_room(address: String, port := PORT) -> Error:
 address = normalize_address(address)
 if not VolleyNetworkInfo.usable_ipv4(address) or port < 1 or port > 65535:
  status = "Введите IP создателя комнаты, например 192.168.1.10"
  changed.emit()
  return ERR_INVALID_PARAMETER
 leave()
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
 game.ball.pending_feed = false
 game.ball.freeze = true
 game.athlete.replica = true
 game.athlete.set_physics_process(false)
 changed.emit()
 return OK

func leave() -> void:
 if is_instance_valid(game.float_serve):
  game.float_serve.cancel_sequence()
 if is_instance_valid(game.lower_serve):
  game.lower_serve.cancel_sequence()
 game.ball.clear_float()
 game.ball.clear_attack()
 if is_instance_valid(discovery):
  discovery.stop_advertising()
  discovery.stop_search()
 if is_instance_valid(game.practice):
  game.practice.configure({"enabled": false}, false)
 if is_instance_valid(game.game_bots):
  game.game_bots.end_solo()
  game.game_bots.configure({"counts": [0, 0]}, false)
 active = false
 match_active = false
 round_live = false
 ready_seconds = 0
 ready_signature = ""
 ball_age = -1
 ball_motion.reset()
 if is_instance_valid(selection_zone):
  selection_zone.hide()
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
 game.athlete.float_serve_active = false
 game.athlete.lower_serve_active = false
 game.athlete.replica = false
 game.athlete.network_age = -1
 game.athlete.network_motion.reset()
 game.athlete.court_team = -1
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
  actor.block_missed.connect(func(): game._on_block_missed(actor, id))
 var side := 1.0 if team == 0 else -1.0
 actor.court_team = team if match_active else -1
 actor.position = Vector3((slot % 3 - 1) * 2.5, 0.02, side * (4.0 + (slot / 3) * 3.0))
 actor.visual.rotation.y = 0 if team == 0 else PI
 actor.camera_yaw = actor.visual.rotation.y
 actor.shift_lock = true
 actor.collision_layer = 2
 actor.collision_mask = 1
 actor.serve_solver = game.ball.solve_launch
 actor.power_serve_solver = game.ball.solve_power_serve
 actor.lifted_attack_solver = game.ball.solve_lifted_hit
 actor.replica = not hosting
 actor.set_physics_process(hosting)
 var tag := Label3D.new()
 tag.visible = actor != game.athlete
 tag.position.y = 2.05
 tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 tag.font_size = 48
 tag.pixel_size = 0.006
 tag.modulate = Color("69d6e0") if team == 0 else Color("ffba73")
 tag.name = "TeamTag"
 actor.add_child(tag)
 players[id] = {"actor": actor, "team": team, "slot": slot, "nickname": game.hud.settings.nickname if actor == game.athlete else "Игрок"}
 refresh_name(id)
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
func hello(version: int, skills: Dictionary, nickname := "Игрок") -> void:
 if not hosting:
  return
 var id := multiplayer.get_remote_sender_id()
 if players.has(id):
  _broadcast_roster()
  return
 if version != PROTOCOL or players.size() >= LIMIT:
  reject_join.rpc_id(id, "Разные версии игры: всем нужна 0.25." if version != PROTOCOL else "Комната заполнена: уже 12 игроков.")
  get_tree().create_timer(0.3).timeout.connect(func():
   if hosting and id in multiplayer.get_peers():
    multiplayer.multiplayer_peer.disconnect_peer(id))
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
 if match_active:
  start_free_play()
 _spawn(id, team, slot)
 players[id].nickname = VolleySettings.clean_nickname(nickname)
 refresh_name(id)
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
  entries.append([id, players[id].team, players[id].slot, players[id].actor.stats.values, players[id].get("nickname", "Игрок")])
 for peer_id in players:
  if peer_id != 1 and _peer_ready(peer_id):
   roster.rpc_id(peer_id, entries)
 refresh_contacts()
 _send_room_state()

@rpc("authority", "call_remote", "reliable")
func roster(entries: Array) -> void:
 if hosting or entries.size() > LIMIT:
  return
 var ids := []
 for entry in entries:
  if entry is Array and entry.size() in [4, 5]:
   ids.append(entry[0])
   _spawn(entry[0], entry[1], entry[2])
   players[entry[0]].team = entry[1]
   players[entry[0]].slot = entry[2]
   _apply_skills(players[entry[0]].actor, entry[3])
   players[entry[0]].nickname = VolleySettings.clean_nickname(str(entry[4])) if entry.size() == 5 else "Игрок"
   refresh_name(entry[0])
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
 if game.float_serve.busy_actor == actor:
  game.float_serve.cancel_sequence()
 if game.lower_serve.busy_actor == actor:
  game.lower_serve.cancel_sequence()
 if game.ball.athlete == actor:
  if game.ball.held:
   game.ball.drop()
  game.ball.athlete = game.athlete
 if game.ball.attack_owner != null and game.ball.attack_owner.get_ref() == actor:
  game.ball.clear_attack()
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
 hello.rpc_id(1, PROTOCOL, game.athlete.stats.values, game.hud.settings.nickname)

func refresh_name(id: int) -> void:
 if not players.has(id):
  return
 var entry: Dictionary = players[id]
 var tag: Label3D = entry.actor.get_node("TeamTag")
 tag.text = str(entry.get("nickname", "Игрок")) + (" · " + ("A" if entry.team == 0 else "Б") if match_active else "")
 tag.visible = entry.actor != game.athlete

func rename_local(value: String) -> void:
 if not active or not connected:
  return
 if hosting:
  players[1].nickname = VolleySettings.clean_nickname(value)
  refresh_name(1)
  _broadcast_roster()
 else:
  rename_player.rpc_id(1, value.left(96))

@rpc("any_peer", "call_remote", "reliable")
func rename_player(value: String) -> void:
 var id := multiplayer.get_remote_sender_id()
 if hosting and players.has(id):
  players[id].nickname = VolleySettings.clean_nickname(value)
  refresh_name(id)
  _broadcast_roster()

func _failed() -> void:
 leave()
 status = rejected_reason if not rejected_reason.is_empty() else "Нет ответа. Проверьте IP и общую Wi-Fi сеть / точку доступа. На iPhone разрешите локальную сеть в Настройках. Гостевая сеть может запрещать связь между устройствами. После разрешения попробуйте снова."
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
 actor.camera_pitch = clampf(pitch, -1.48, 1.48)
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
 if not hosting or not players.has(id) or role not in ["primary", "secondary", "bump", "jump", "dive", "jump_set", "approach", "pickup", "context", "next", "cancel", "lower_serve", "float_serve", "stats"] or phase not in ["press", "release", "cancel"]:
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
   if match_active:
    reset_round()
   else:
    game.ball.feed(game.athlete.position + Vector3(0, 0.3, -0.6), Vector3.ZERO)
  return id == 1
 if role in ["lower_serve", "float_serve"]:
  if game.ball.held and game.ball.athlete == actor and payload.get("aim") is Vector3:
   var controller: VolleyLowerServe = game.float_serve if role == "float_serve" else game.lower_serve
   return controller.launch(actor, payload.aim, float(payload.get("apex", controller.height)))
  return false
 if game.lower_serve.busy_actor == actor or game.float_serve.busy_actor == actor:
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
   game.ball.throw_target.y = VolleyBall.RADIUS
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
 if not hosting or not match_active or match_winner >= 0:
  return
 game.lower_serve.cancel_sequence()
 game.float_serve.cancel_sequence()
 round_live = false
 game.rules.reset()
 game.serving = false
 game.rules.strict = true
 for id in players:
  var actor: ContextAthlete = players[id].actor
  actor.cancel_input()
  actor.action = VolleyAthlete.Action.IDLE
  actor.holding_ball = false
  owners[id] = ""
  serve_flags[id] = false
 game.game_bots.reset_rally()
 var server: ContextAthlete = game.game_bots.serving_actor(serve_team)
 if not is_instance_valid(server):
  return
 var side := 1.0 if serve_team == 0 else -1.0
 server.position = Vector3(0, 0.02, side * 9.6)
 server.velocity = Vector3.ZERO
 server.visual.rotation.y = 0 if side > 0 else PI
 server.camera_yaw = server.visual.rotation.y
 if server == game.athlete:
  game.rig.yaw = server.camera_yaw
 elif not server is VolleyGameBot:
  var id := player_id(server)
  if _peer_ready(id):
   orient_player.rpc_id(id, server.camera_yaw)
 server.last_result = "Ваша подача • подберите мяч за задней линией"
 game.ball.athlete = server
 game.ball.feed(server.position + Vector3(0, 0.25, -side * 0.55), Vector3.ZERO)
 game.previous_ball_valid = false
 round_wait = -1
 if server is VolleyGameBot:
  server.prepare_serve()

func award_floor(at: Vector3) -> void:
 if not hosting or not match_active or round_wait >= 0:
  return
 var winner: int
 if absf(at.x) <= 4.5 + VolleyBall.RADIUS and absf(at.z) <= 9 + VolleyBall.RADIUS:
  winner = 1 if at.z >= 0 else 0
 else:
  winner = 1 - last_touch_team
 award(winner)

func award(winner: int) -> void:
 if not hosting or not match_active or round_wait >= 0 or match_winner >= 0:
  return
 match_winner = VolleyMatchScore.point(scores, sets, winner)
 game.game_bots.advance_service(winner, serve_team)
 serve_team = winner
 round_wait = 3.0
 _send_room_state(false)
 changed.emit()

func _process(dt: float) -> void:
 if not active:
  return
 if not connected:
  connecting_for += dt
  if connecting_for > CONNECT_TIMEOUT:
   _failed()
  return
 if not hosting and ball_motion.active:
  game.ball.position = ball_motion.advance(dt)
 elif not hosting and ball_age >= 0:
  ball_age += dt
  if ball_age <= 0.12:
   game.ball.position += ball_speed * dt
  var target := ball_target + ball_speed * minf(ball_age, 0.12)
  game.ball.position = game.ball.position.lerp(target, 1.0 - exp(-12.0 * dt))
 tick += dt
 if hosting:
  _update_readiness(dt)
  state_tick += dt
  if state_tick >= 0.25:
   state_tick = 0
   _send_room_state(false)
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
  if match_active and round_live and game.rules.ended and round_wait < 0:
   award(1 - last_touch_team)
  if match_active and match_winner < 0 and round_wait >= 0:
   round_wait -= dt
   if round_wait < 0:
    reset_round()
 if tick < 1.0 / 30.0:
  return
 tick = fmod(tick, 1.0 / 30.0)
 if hosting:
  var poses := []
  # Positions come from fixed physics steps, not the arbitrary render/send phase.
  var stamp := float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
  var held_by := 0
  for id in players:
   var a: ContextAthlete = players[id].actor
   if game.ball.held and game.ball.athlete == a:
    held_by = id
   poses.append(pack_actor(a, id))
  if is_instance_valid(game.practice.bot) and game.practice.enabled:
   for peer_id in players:
    if peer_id != 1 and _peer_ready(peer_id):
     bot_snapshot.rpc_id(peer_id, pack_actor(game.practice.bot), stamp)
  var bot_poses := []
  var bot_holder := 0
  for bot in game.game_bots.bots.values():
   bot_poses.append(pack_actor(bot, bot.bot_id))
   if game.ball.held and game.ball.athlete == bot:
    bot_holder = bot.bot_id
  for first in range(0, bot_poses.size(), 2):
   for peer_id in players:
    if peer_id != 1 and _peer_ready(peer_id):
     game_bot_snapshot.rpc_id(peer_id, bot_poses.slice(first, first + 2), bot_holder, stamp)
  # Stay below the ENet MTU at 12 players; one large unreliable packet
  # would fragment and magnify loss on mobile Wi-Fi.
  for first in range(0, poses.size(), 2):
   for peer_id in players:
    if peer_id != 1 and _peer_ready(peer_id):
     snapshot.rpc_id(peer_id, poses.slice(first, first + 2), game.ball.position, game.ball.linear_velocity, game.ball.rotation, held_by, game.ball.held_mode, scores, game.rules.message, game.ball.angular_velocity, stamp)
 elif _peer_ready(1):
  input_state.rpc_id(1, game.athlete.move_axis, game.athlete.tilt, game.rig.yaw, game.rig.pitch)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func snapshot(poses: Array, at: Vector3, speed: Vector3, spin_pose: Vector3, held_by: int, mode: int, score: Array, message: String, ball_spin := Vector3.ZERO, stamp := -1.0) -> void:
 if hosting or not connected:
  return
 snapshot_count += 1
 for pose in poses:
  if not players.has(pose[0]):
   continue
  var a: ContextAthlete = players[pose[0]].actor
  apply_actor_pose(a, pose, held_by, stamp)
 # All player chunks carry the same ball frame. Apply it only once.
 if stamp >= 0:
  if not ball_motion.push(at, speed if held_by == 0 else Vector3.ZERO, stamp):
   return
  game.ball.position = ball_motion.position
 elif ball_age < 0 or game.ball.position.distance_to(at) > 4.0:
  game.ball.position = at
 ball_target = at
 ball_speed = speed if held_by == 0 else Vector3.ZERO
 ball_age = 0
 game.ball.rotation = spin_pose
 game.ball.last_velocity = speed
 game.ball.angular_velocity = ball_spin
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

func pack_actor(a: ContextAthlete, id := 0) -> Array:
 return [id, a.position, a.velocity, a.visual.rotation, a.action, a.technique, a.strike_technique, a.action_time, a.power, a.strike_power, a.strike_duration, a.energy, a.move_axis, a.tilt, a.attack_ready, a.approach_armed, a.approach_blend, a.dive_time, a.last_result, a.jump_windup, a.release_time, a.contact_flash, a.lower_serve_active, a.air_attack, a.camera_yaw, a.camera_pitch, a.lean, a.landing_load, a.charged_for, serve_flags.get(id, false), a.float_serve_active, a.approach_jump]

func apply_actor_pose(a: ContextAthlete, pose: Array, held_by := 0, stamp := -1.0) -> void:
 if stamp >= 0 and a.network_motion.active and stamp <= a.network_motion.stamp:
  return
 var first_pose := a.network_age < 0
 a.velocity = pose[2]
 a.accept_network_position(pose[1], stamp)
 a.network_rotation = pose[3]
 if stamp < 0 or first_pose:
  a.visual.rotation = pose[3]
 a.action = pose[4]
 a.technique = pose[5]
 a.strike_technique = pose[6]
 a.approach_jump = pose[31]
 a.block_held = a.action == VolleyAthlete.Action.STRIKE and a.strike_technique == ContextAthlete.BLOCK
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
 a.float_serve_active = pose[30]
 a.air_attack = pose[23]
 if a != game.athlete:
  a.camera_yaw = pose[24]
  a.camera_pitch = pose[25]
 a.lean = pose[26]
 a.landing_load = pose[27]
 a.charged_for = pose[28]
 if a == game.athlete:
  game.serving = pose[29]
 a.holding_ball = held_by == pose[0]
 a.previous_wrists = a.wrists.duplicate()
 a.previous_elbows = a.elbows.duplicate()

func refresh_contacts() -> void:
 if active and not hosting:
  game.ball.contact_athletes.clear()
  return
 game.ball.contact_athletes = players.values().map(func(entry: Dictionary): return entry.actor) if active else [game.athlete]
 if is_instance_valid(game.practice) and game.practice.enabled and is_instance_valid(game.practice.bot):
  game.ball.contact_athletes.append(game.practice.bot)
 if is_instance_valid(game.game_bots):
  game.ball.contact_athletes.append_array(game.game_bots.bots.values())

func start_free_play() -> void:
 if not hosting:
  return
 game.lower_serve.cancel_sequence()
 game.float_serve.cancel_sequence()
 match_active = false
 game.game_bots.reset_rally()
 round_live = false
 round_wait = -1
 ready_seconds = 0
 ready_signature = ""
 scores = [0, 0]
 sets = [0, 0]
 match_winner = -1
 game.rules.reset()
 game.rules.strict = false
 game.serving = false
 for id in players:
  var entry: Dictionary = players[id]
  serve_flags[id] = false
  owners[id] = ""
  entry.actor.cancel_input()
  entry.actor.action = VolleyAthlete.Action.IDLE
  entry.actor.court_team = -1
  refresh_name(id)
 if not is_instance_valid(selection_zone):
  _make_selection_zone()
 selection_zone.show()
 _send_room_state()
 changed.emit()

static func selection_team(actor: ContextAthlete) -> int:
 var at := actor.position
 # Two separate halves outside the right touchline. Standing is required:
 # jumping/running through a zone cannot silently consent to a match.
 if at.x < 5.35 or at.x > 7.75 or absf(at.z) < 0.35 or absf(at.z) > 5.9 or at.y > 0.18 or Vector2(actor.velocity.x, actor.velocity.z).length() > 0.65:
  return -1
 return 0 if at.z > 0 else 1

func readiness() -> Dictionary:
 var teams := [[], []]
 var selected := 0
 var signature := ""
 for id in players:
  var team := selection_team(players[id].actor)
  signature += "%d:%d;" % [id, team]
  if team >= 0:
   selected += 1
   teams[team].append(id)
 var totals := [teams[0].size() + game.game_bots.counts[0], teams[1].size() + game.game_bots.counts[1]]
 signature += str(game.game_bots.counts)
 return {"teams": teams, "totals": totals, "selected": selected, "signature": signature, "valid": players.size() >= 1 and selected == players.size() and totals[0] >= 1 and totals[1] >= 1 and totals[0] <= 6 and totals[1] <= 6}

func _update_readiness(dt: float) -> void:
 if match_active:
  return
 var ready := readiness()
 if not ready.valid or ready.signature != ready_signature:
  ready_seconds = 0
 ready_signature = ready.signature
 ready_message = "Свободная игра • выбор команд справа: %d/%d" % [ready.selected, players.size()]
 if not ready.valid:
  if ready.selected == players.size() and players.size() > 1:
   ready_message += " • нужны две команды по 1–6 игроков"
  return
 ready_seconds += dt
 ready_message = "Все готовы • A %d / Б %d • матч через %d" % [ready.totals[0], ready.totals[1], ceili(3.0 - ready_seconds)]
 if ready_seconds >= 3.0:
  begin_match()

func begin_match() -> bool:
 # This is the only transition into a match, including host requests.
 # Re-check live authoritative positions at the moment of commitment.
 if not hosting or match_active:
  return false
 var ready := readiness()
 if not ready.valid or ready_seconds < 3.0:
  return false
 match_active = true
 scores = [0, 0]
 sets = [0, 0]
 match_winner = -1
 serve_team = 0
 game.game_bots.reset_service(serve_team)
 for team in range(2):
  var slot := 0
  for id in ready.teams[team]:
   var actor: ContextAthlete = players[id].actor
   players[id].team = team
   players[id].slot = slot
   actor.court_team = team
   actor.position = Vector3((slot % 3 - 1) * 2.5, 0.02, (1.0 if team == 0 else -1.0) * (4.0 + (slot / 3) * 3.0))
   actor.velocity = Vector3.ZERO
   actor.camera_yaw = 0 if team == 0 else PI
   actor.visual.rotation.y = actor.camera_yaw
   refresh_name(id)
   if actor == game.athlete:
    game.rig.yaw = actor.camera_yaw
   elif _peer_ready(id):
    orient_player.rpc_id(id, actor.camera_yaw)
   slot += 1
 for bot in game.game_bots.bots.values():
  bot.reset_plan()
  bot.position = game.game_bots.home(bot.court_team, bot.slot)
 if is_instance_valid(game.practice.bot):
  game.practice.bot.cancel_input()
  game.practice.bot.action = VolleyAthlete.Action.IDLE
 reset_round()
 selection_zone.hide()
 _broadcast_roster()
 return true

func _make_selection_zone() -> void:
 selection_zone = Node3D.new()
 selection_zone.name = "TeamSelection"
 game.add_child(selection_zone)
 for side in [1, -1]:
  var color := Color("43c8d2") if side > 0 else Color("ffa66d")
  VolleyGeometry.box(selection_zone, Vector3(6.55, 0.035, side * 3.1), Vector3(2.4, 0.025, 5.5), color)
  var label := Label3D.new()
  label.position = Vector3(6.55, 1.3, side * 3.1)
  label.text = "КОМАНДА A" if side > 0 else "КОМАНДА Б"
  label.text += "\nВстаньте сюда всей командой"
  label.font_size = 38
  label.pixel_size = 0.006
  label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
  label.modulate = color
  selection_zone.add_child(label)

func _send_room_state(with_bot := true) -> void:
 if not hosting:
  return
 for peer_id in players:
  if peer_id != 1 and _peer_ready(peer_id):
   room_state.rpc_id(peer_id, match_active, round_live, ready_message, game.practice.settings_state() if with_bot and is_instance_valid(game.practice) else {}, sets, match_winner)
   if with_bot and is_instance_valid(game.game_bots):
    game_bots_state.rpc_id(peer_id, game.game_bots.settings_state())

@rpc("authority", "call_remote", "reliable")
func room_state(in_match: bool, live: bool, message: String, practice_state: Dictionary, set_scores: Array, winner: int) -> void:
 if hosting:
  return
 match_active = in_match
 round_live = live
 ready_message = message
 sets = set_scores
 match_winner = winner
 if not practice_state.is_empty():
  game.practice.configure(practice_state, false)
 if not is_instance_valid(selection_zone):
  _make_selection_zone()
 selection_zone.visible = not match_active
 for id in players:
  var entry: Dictionary = players[id]
  entry.actor.court_team = entry.team if match_active else -1
  refresh_name(id)

@rpc("authority", "call_remote", "reliable")
func orient_player(yaw: float) -> void:
 if not hosting:
  game.rig.yaw = yaw
  game.athlete.camera_yaw = yaw

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func bot_snapshot(pose: Array, stamp := -1.0) -> void:
 if not hosting and game.practice.enabled and is_instance_valid(game.practice.bot) and pose.size() == 32:
  apply_actor_pose(game.practice.bot, pose, -1, stamp)

@rpc("authority", "call_remote", "reliable")
func contact_feedback(text: String, failed: bool) -> void:
 if not hosting:
  game.show_feedback(text, failed)


func send_game_bots() -> void:
 if not hosting:
  return
 for peer_id in players:
  if peer_id != 1 and _peer_ready(peer_id):
   game_bots_state.rpc_id(peer_id, game.game_bots.settings_state())

@rpc("authority", "call_remote", "reliable")
func game_bots_state(state: Dictionary) -> void:
 if not hosting and connected:
  game.game_bots.configure(state, false)

@rpc("authority", "call_remote", "unreliable_ordered", 4)
func game_bot_snapshot(poses: Array, holder: int, stamp := -1.0) -> void:
 if hosting or not connected:
  return
 for pose in poses:
  if pose.size() == 32 and game.game_bots.bots.has(pose[0]):
   apply_actor_pose(game.game_bots.bots[pose[0]], pose, holder, stamp)
