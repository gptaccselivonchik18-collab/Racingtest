class_name VolleySound
extends Node

const CLIPS := ["bump", "set", "spike", "serve", "block", "ball_floor", "ball_wall", "ball_net", "step_1", "step_2", "step_3", "land", "pickup", "toss", "throw", "jump", "dive", "skid", "swing", "ui_tap", "ui_open", "ui_close", "ui_tick", "whistle", "point", "join", "leave"]
const WORLD_CLIPS := ["bump", "set", "spike", "serve", "block", "ball_floor", "ball_wall", "ball_net", "pickup", "toss", "throw", "whistle", "point"]
const PATH := "user://sound.cfg"
const COURT_BUS := "VolleyCourt"
const UI_BUS := "VolleyInterface"
const VOICES := 24
var game: Node3D
var clips: Dictionary = {}
var world_voices: Array[AudioStreamPlayer3D] = []
var ui_voices: Array[AudioStreamPlayer] = []
var master := 0.85
var effects := 0.90
var interface := 0.65
var save_left := -1.0
var clock := 0.0
var played: Dictionary = {}
var actors: Dictionary = {}
var cooldowns: Dictionary = {}
var random := RandomNumberGenerator.new()
var world_cursor := 0
var audible_device := true
var received_events := 0
var sent_events := 0
var last_round := false
var last_winner := -1
var last_room := false
var last_peers := 0
var menu_open := false
var was_paused := false

func _ready() -> void:
 name = "Sound"
 process_mode = Node.PROCESS_MODE_ALWAYS
 random.randomize() # Never consume a gameplay RNG or change bot decisions.
 audible_device = AudioServer.get_driver_name() != "Dummy"
 for key in CLIPS:
  clips[key] = load("res://audio/%s.wav" % key)
 for title in [COURT_BUS, UI_BUS]:
  if AudioServer.get_bus_index(title) < 0:
   AudioServer.add_bus()
   AudioServer.set_bus_name(AudioServer.bus_count - 1, title)
   AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
 load_preferences()
 for i in range(VOICES):
  var player := AudioStreamPlayer3D.new()
  player.bus = COURT_BUS
  player.unit_size = 4.0
  player.max_distance = 32.0
  player.max_db = -2
  add_child(player)
  world_voices.append(player)
 for i in range(4):
  var player := AudioStreamPlayer.new()
  player.bus = UI_BUS
  add_child(player)
  ui_voices.append(player)
 game.ball.surface_contact.connect(surface)
 game.ball.handled.connect(func(kind: String, at: Vector3): world(kind, at, 0.55))
 get_tree().node_added.connect(_new_node)
 _hook_buttons(game)
 add_settings()

func load_preferences(path := PATH) -> void:
 var config := ConfigFile.new()
 if config.load(path) == OK:
  for key in ["master", "effects", "interface"]:
   var value: Variant = config.get_value("sound", key, get(key))
   if (value is float or value is int) and is_finite(float(value)):
    set(key, clampf(float(value), 0, 1))
 apply_volumes()

func save_preferences(path := PATH) -> Error:
 var config := ConfigFile.new()
 for key in ["master", "effects", "interface"]:
  config.set_value("sound", key, get(key))
 return config.save(path)

func apply_volumes() -> void:
 for entry in [[COURT_BUS, master * effects], [UI_BUS, master * interface]]:
  var index := AudioServer.get_bus_index(entry[0])
  if index >= 0:
   AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, entry[1])))
   AudioServer.set_bus_mute(index, entry[1] <= 0.0001)

func add_settings() -> void:
 var tab: VBoxContainer = game.hud._tab("Звук")
 var note := Label.new()
 note.text = "Звуки игры без фоновой музыки. Наушники помогают слышать направление мяча и других игроков."
 note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 tab.add_child(note)
 for entry in [["master", "Общая громкость"], ["effects", "Площадка и игроки"], ["interface", "Интерфейс"]]:
  var key: String = entry[0]
  game.hud._slider(tab, entry[1], 0, 100, get(key) * 100, func(value: float):
   set(key, value / 100)
   apply_volumes()
   save_left = 0.35, 1)
 game.hud._native_button(tab, "Послушать звук мяча", func(): _play_world("bump", game.camera.global_position + -game.camera.global_basis.z * 2, 0.65, true))
 game.hud.refresh_navigation()

func _new_node(node: Node) -> void:
 if node is BaseButton:
  _hook_button.call_deferred(node)

func _hook_buttons(node: Node) -> void:
 if node is BaseButton:
  _hook_button(node)
 for child in node.get_children():
  _hook_buttons(child)

func _hook_button(button: BaseButton) -> void:
 if not is_instance_valid(button) or not game.is_ancestor_of(button) or button.has_meta("volley_sound"):
  return
 button.set_meta("volley_sound", true)
 button.pressed.connect(func(): ui("ui_tap"))

func ui(kind := "ui_tap", strength := 1.0) -> void:
 if not clips.has(kind) or master * interface <= 0.0001:
  return
 if not _allow("ui:" + kind, 0.045):
  return
 for player in ui_voices:
  if not player.playing:
   player.stream = clips[kind]
   player.volume_db = linear_to_db(clampf(strength, 0.01, 1)) - 2
   player.pitch_scale = random.randf_range(0.97, 1.03)
   if audible_device:
    player.play()
   played[kind] = int(played.get(kind, 0)) + 1
   return

func court_active() -> bool:
 return not (is_instance_valid(game.frontend) and game.frontend.in_home) and not get_tree().paused

func _allow(key: String, interval: float) -> bool:
 if float(cooldowns.get(key, -100.0)) + interval > clock:
  return false
 cooldowns[key] = clock
 return true

func _play_world(kind: String, at: Vector3, strength: float, preview := false) -> void:
 if not clips.has(kind) or not at.is_finite() or not is_finite(strength) or (not preview and not court_active()) or master * effects <= 0.0001:
  return
 if not preview and is_instance_valid(game.camera) and at.distance_to(game.camera.global_position) > 32:
  return
 var voice: AudioStreamPlayer3D
 for candidate in world_voices:
  if not candidate.playing:
   voice = candidate
   break
 if voice == null:
  if kind.begins_with("step") or kind in ["swing", "skid"]:
   return # Footsteps never evict a real ball contact.
  voice = world_voices[world_cursor % VOICES]
  world_cursor += 1
  voice.stop()
 voice.position = at
 voice.stream = clips[kind]
 voice.pitch_scale = random.randf_range(0.96, 1.04)
 voice.volume_db = linear_to_db(clampf(strength, 0.015, 1))
 if audible_device:
  voice.play()
 played[kind] = int(played.get(kind, 0)) + 1

func world(kind: String, at: Vector3, strength := 1.0) -> void:
 if game.lan.active and not game.lan.hosting:
  return
 if kind not in WORLD_CLIPS or not court_active():
  return
 _play_world(kind, at, strength)
 # Only discrete ball/referee events travel over the network. Movement
 # sounds are reconstructed locally from the smoothed visible actor poses.
 if game.lan.active and game.lan.hosting:
  for id in game.lan.players:
   if id != 1 and game.lan._peer_ready(id):
    receive_world.rpc_id(id, kind, at, clampf(strength, 0, 1))
    sent_events += 1

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func receive_world(kind: String, at: Vector3, strength: float) -> void:
 if not game.lan.active or game.lan.hosting or kind not in WORLD_CLIPS or not at.is_finite() or at.length() > 1000 or not is_finite(strength) or strength < 0 or strength > 1:
  return
 received_events += 1
 _play_world(kind, at, strength)

func contact(kind: int, at: Vector3, speed: Vector3, actor: ContextAthlete) -> void:
 var key := "bump"
 match kind:
  VolleyAthlete.Technique.OVERHEAD, ContextAthlete.JUMP_SET: key = "set"
  VolleyAthlete.Technique.SPIKE, ContextAthlete.TIP: key = "spike"
  VolleyAthlete.Technique.SERVE, VolleyAthlete.Technique.JUMP_SERVE: key = "serve"
  ContextAthlete.BLOCK: key = "block"
  VolleyAthlete.Technique.THROW: key = "throw"
 if actor.float_serve_active:
  key = "serve"
 world(key, at, clampf(0.32 + speed.length() / 30, 0.32, 1))

func surface(material: String) -> void:
 var speed: Vector3 = game.ball.last_velocity
 var impact := absf(speed.y) if material == "floor" else absf(speed.z) if material in ["net", "antenna"] else maxf(absf(speed.x), absf(speed.z))
 # Ignore rolling/resting contacts and prevent rapid collision chatter.
 if impact < 0.7 or not _allow("surface:" + material, 0.085):
  return
 var key := "ball_floor" if material == "floor" else "ball_net" if material in ["net", "antenna"] else "ball_wall"
 world(key, game.ball.global_position, clampf(impact / 14, 0.08, 1))

func _process(dt: float) -> void:
 clock += dt
 if save_left >= 0:
  save_left -= dt
  if save_left < 0:
   save_preferences()
 if is_instance_valid(game.hud.menu) and menu_open != game.hud.menu.visible:
  menu_open = game.hud.menu.visible
  ui("ui_open" if menu_open else "ui_close", 0.75)
 var connected: bool = game.lan.connected or (game.lan.active and game.lan.hosting)
 var peers: int = game.lan.players.size()
 if connected != last_room or (connected and peers != last_peers):
  ui("join" if connected and (not last_room or peers > last_peers) else "leave", 0.8)
 last_room = connected
 last_peers = peers
 var active := court_active()
 if not active:
  if not was_paused:
   for voice in world_voices:
    voice.stop()
  actors.clear()
  was_paused = true
  last_round = false
  last_winner = -1
  return
 was_paused = false
 var roster: Array = game.lan.players.values().map(func(p: Dictionary): return p.actor) if game.lan.active else [game.athlete]
 if is_instance_valid(game.game_bots):
  roster.append_array(game.game_bots.bots.values())
 if is_instance_valid(game.practice) and game.practice.enabled and is_instance_valid(game.practice.bot):
  roster.append(game.practice.bot)
 var alive := {}
 for actor: ContextAthlete in roster:
  var id := actor.get_instance_id()
  alive[id] = true
  _actor(actor, dt)
 for id in actors.keys():
  if not alive.has(id):
   actors.erase(id)
 var ended: bool = game.rules.ended or (game.game_bots.solo_match and game.game_bots.round_wait >= 0) or (game.lan.match_active and game.lan.round_wait >= 0)
 if ended and not last_round:
  world("whistle", Vector3(0, 2, 0), 0.65)
 last_round = ended
 var winner: int = game.lan.match_winner if game.lan.match_active else game.game_bots.match_winner if game.game_bots.solo_match else -1
 if winner >= 0 and last_winner < 0:
  world("point", game.camera.global_position, 0.7)
 last_winner = winner
 # Keep debounce memory bounded even across repeated room/player changes.
 if cooldowns.size() > 128:
  for key in cooldowns.keys():
   if clock - float(cooldowns[key]) > 2:
    cooldowns.erase(key)

func _actor(actor: ContextAthlete, _dt: float) -> void:
 var id := actor.get_instance_id()
 var at := actor.global_position
 var grounded := at.y < 0.13 and actor.velocity.y < 0.5
 var diving := actor.dive_time >= 0
 if not actors.has(id):
  actors[id] = {"at": at, "vy": actor.velocity.y, "ground": grounded, "dive": diving, "strikes": actor.strike_count, "action": actor.action, "phase": actor.action_time, "distance": 0.0, "step": 0}
  return
 var state: Dictionary = actors[id]
 var moved := Vector2(at.x - Vector3(state.at).x, at.z - Vector3(state.at).z).length()
 if moved > 1.5: # Reposition, feed reset and reconnect are silent teleports.
  state.distance = 0.0
 elif grounded and state.ground and not diving and actor.action != VolleyAthlete.Action.STRIKE:
  state.distance += moved
  var pace := Vector2(actor.velocity.x, actor.velocity.z).length()
  var stride := lerpf(0.58, 1.05, clampf(pace / 8, 0, 1))
  if state.distance >= stride and pace > 0.45:
   state.distance = fmod(float(state.distance), stride)
   state.step = int(state.step) + 1
   _play_world("step_%d" % (int(state.step) % 3 + 1), at + Vector3.UP * 0.1, clampf(0.18 + pace * 0.025, 0.18, 0.42))
  if pace > 2 and actor.move_axis.length() < 0.15 and _allow("skid:%d" % id, 0.65):
   _play_world("skid", at, 0.25)
 if not grounded and state.ground and actor.velocity.y > 1:
  _play_world("jump", at, 0.42)
 if grounded and not state.ground and float(state.vy) < -0.8:
  _play_world("land", at, clampf(absf(float(state.vy)) / 10, 0.25, 0.8))
 if diving and not state.dive:
  _play_world("dive", at, 0.55)
 var new_strike: bool = actor.action == VolleyAthlete.Action.STRIKE and (state.action != VolleyAthlete.Action.STRIKE or actor.action_time + 0.03 < float(state.phase))
 if new_strike and actor.strike_technique != ContextAthlete.BLOCK:
  _play_world("swing", at + Vector3.UP * 1.4, 0.35)
 state.at = at
 state.vy = actor.velocity.y
 state.ground = grounded
 state.dive = diving
 state.strikes = actor.strike_count
 state.action = actor.action
 state.phase = actor.action_time

func _exit_tree() -> void:
 for player in world_voices:
  player.stop()
  player.stream = null
 for player in ui_voices:
  player.stop()
  player.stream = null
 clips.clear()
