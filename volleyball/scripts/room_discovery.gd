class_name VolleyRoomDiscovery
extends Node

signal changed
const PORT := 24681
const SEARCH_DURATION := 15.0
const PROBE_INTERVAL := 0.05
const PROBE_BATCH := 8
const MAGIC := "VOLLEYLAB18"
var lan: VolleyLAN
var responder := PacketPeerUDP.new()
var seeker := PacketPeerUDP.new()
var rooms: Dictionary = {}
var searching := false
var search_time := 0.0
var probe_time := 0.0
var targets: Array[String] = []
var next_target := 0
var token := ""
var game_port := VolleyLAN.PORT
var discovery_port := PORT
var message := ""

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS

static func private_ipv4(address: String) -> bool:
 if not address.is_valid_ip_address() or ":" in address:
  return false
 var parts := address.split(".")
 return parts[0] == "10" or (parts[0] == "192" and parts[1] == "168") or (parts[0] == "172" and int(parts[1]) >= 16 and int(parts[1]) <= 31)

static func scan_targets(addresses: PackedStringArray) -> Array[String]:
 var result: Array[String] = []
 var prefixes := []
 for address in addresses:
  if not private_ipv4(address):
   continue
  var prefix := address.get_slice(".", 0) + "." + address.get_slice(".", 1) + "." + address.get_slice(".", 2) + "."
  if prefix not in prefixes and prefixes.size() < 4:
   prefixes.append(prefix)
   # The common Wi-Fi / hotspot subnet; manual IP remains available for
   # routed networks and larger subnets. Unicast needs no multicast entitlement.
   for suffix in range(1, 255):
    result.append(prefix + str(suffix))
 return result

func advertise(port := VolleyLAN.PORT, probe_port := PORT) -> Error:
 responder.close()
 game_port = port
 discovery_port = probe_port
 if port < 1 or port > 65535 or probe_port < 1 or probe_port > 65535:
  return ERR_INVALID_PARAMETER
 return responder.bind(probe_port, "0.0.0.0")

func stop_advertising() -> void:
 responder.close()

func search(explicit_targets: Array[String] = [], probe_port := PORT) -> Error:
 stop_search()
 rooms.clear()
 targets = explicit_targets.duplicate() if not explicit_targets.is_empty() else scan_targets(VolleyNetworkInfo.local_addresses())
 discovery_port = probe_port
 token = str(Time.get_ticks_usec())
 next_target = 0
 search_time = 0
 probe_time = 0
 if probe_port < 1 or probe_port > 65535:
  return ERR_INVALID_PARAMETER
 var error := seeker.bind(0, "0.0.0.0")
 if error != OK:
  message = "Не удалось начать поиск. Можно подключиться по IP ниже."
 elif targets.is_empty():
  message = "Подключитесь к Wi-Fi / точке доступа или введите IP ниже."
  seeker.close()
 else:
  searching = true
  message = "Ищу комнаты в вашей сети…"
 changed.emit()
 return error

func stop_search() -> void:
 searching = false
 seeker.close()

func _process(dt: float) -> void:
 if responder.is_bound():
  for i in range(mini(responder.get_available_packet_count(), 64)):
   var data := responder.get_packet()
   var ip := responder.get_packet_ip()
   var port := responder.get_packet_port()
   if data.size() > 256:
    continue
   var request: Variant = JSON.parse_string(data.get_string_from_utf8())
   if valid_request(request) and is_instance_valid(lan) and lan.hosting:
    responder.set_dest_address(ip, port)
    responder.put_packet(JSON.stringify({"magic": MAGIC, "token": request.token, "port": game_port, "players": lan.players.size(), "limit": 12, "protocol": VolleyLAN.PROTOCOL, "version": "0.17"}).to_utf8_buffer())
 if not searching:
  return
 search_time += dt
 probe_time += dt
 if probe_time >= PROBE_INTERVAL:
  probe_time = 0
  for i in range(PROBE_BATCH):
   seeker.set_dest_address(targets[next_target % targets.size()], discovery_port)
   seeker.put_packet(JSON.stringify({"magic": MAGIC, "token": token}).to_utf8_buffer())
   next_target += 1
 for i in range(mini(seeker.get_available_packet_count(), 64)):
  var data := seeker.get_packet()
  var ip := seeker.get_packet_ip()
  if data.size() > 512:
   continue
  var response: Variant = JSON.parse_string(data.get_string_from_utf8())
  if not valid_response(response, token):
   continue
  var port := int(response.get("port", 0))
  var count := int(response.get("players", 0))
  if port < 1 or port > 65535 or count < 1 or count > 12:
   continue
  var different: bool = not rooms.has(ip) or rooms[ip].players != count or rooms[ip].port != port
  rooms[ip] = {"ip": ip, "port": port, "players": count, "limit": 12}
  if different:
   changed.emit()
 if search_time >= SEARCH_DURATION:
  stop_search()
  message = "Комнаты найдены — нажмите «Войти»." if not rooms.is_empty() else "Комнат не видно. Проверьте общую Wi-Fi сеть / точку доступа и разрешение локальной сети на iPhone. Можно повторить поиск или вставить IP создателя."
  changed.emit()

func _exit_tree() -> void:
 responder.close()
 seeker.close()

static func valid_request(value: Variant) -> bool:
 return value is Dictionary and value.get("magic") == MAGIC and value.get("token") is String and not value.token.is_empty() and value.token.length() <= 32

static func valid_response(value: Variant, expected_token: String) -> bool:
 if not valid_request(value) or value.token != expected_token:
  return false
 for key in ["protocol", "port", "players"]:
  var number: Variant = value.get(key)
  if not (number is int or number is float) or not is_finite(float(number)) or float(number) != floorf(float(number)):
   return false
 return int(value.protocol) == VolleyLAN.PROTOCOL and int(value.port) > 0 and int(value.port) <= 65535 and int(value.players) > 0 and int(value.players) <= 12
