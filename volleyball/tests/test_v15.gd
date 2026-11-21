extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
 call_deferred("run")

func check(ok: bool, note: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error("FAIL: " + note)
 else:
  print("PASS: ", note)

func run() -> void:
 var adapters := [
  {"name": "utun0", "addresses": ["10.0.0.2"]},
  {"name": "pdp_ip0", "addresses": ["10.55.1.2"]},
  {"name": "en0", "addresses": ["fe80::1", "192.168.4.12"]},
  {"name": "bridge100", "addresses": ["172.20.10.1"]},
  {"name": "lo0", "addresses": ["127.0.0.1"]},
  {"name": "eth0", "addresses": ["169.254.1.2", "192.168.4.12"]}]
 var ips := VolleyNetworkInfo.ordered_addresses(adapters)
 check(ips[0] == "172.20.10.1" and ips[1] == "192.168.4.12", "iPhone hotspot / Wi-Fi precede cellular and VPN")
 check(ips.size() == 4, "Unusable addresses and duplicate interfaces are excluded")
 adapters = [{"name": "rmnet_data0", "addresses": ["10.22.1.1"]}, {"name": "wlan0", "addresses": ["192.168.43.1"]}]
 check(VolleyNetworkInfo.ordered_addresses(adapters)[0] == "192.168.43.1", "Android Wi-Fi / hotspot precedes cellular")
 check(VolleyNetworkInfo.interface_rank({"friendly": "Беспроводная сеть"}) < VolleyNetworkInfo.interface_rank({"name": "VPN"}), "Localized Windows Wi-Fi has priority")
 check(VolleyNetworkInfo.ordered_addresses([]).is_empty(), "No adapters does not invent a room IP")
 for ip in ["0.0.0.0", "255.255.255.255", "224.0.0.1", "::1", "999.0.1.1"]:
  check(not VolleyNetworkInfo.usable_ipv4(ip), "Reject unsupported endpoint " + ip)
 check(VolleyNetworkInfo.usable_ipv4("172.20.10.1") and VolleyNetworkInfo.usable_ipv4("192.168.43.1"), "Both common mobile hotspot address ranges are accepted")
 var targets := VolleyRoomDiscovery.scan_targets(PackedStringArray(["172.20.10.3", "192.168.43.42", "10.42.0.5", "172.20.10.4"]))
 check("172.20.10.1" in targets and "192.168.43.1" in targets and "10.42.0.1" in targets and targets.size() == 762, "Hotspot subnet search includes host and deduplicates prefixes")
 var token := "test15"
 var valid := {"magic": VolleyRoomDiscovery.MAGIC, "token": token, "protocol": VolleyLAN.PROTOCOL, "port": 24915, "players": 2}
 check(VolleyRoomDiscovery.valid_response(valid, token), "Shared platform-independent discovery contract is accepted")
 check(not VolleyRoomDiscovery.valid_request({"magic": VolleyRoomDiscovery.MAGIC}), "Missing token is ignored without a property access error")
 check(not VolleyRoomDiscovery.valid_request({"magic": VolleyRoomDiscovery.MAGIC, "token": 12}), "Wrong token type is ignored")
 check(not VolleyRoomDiscovery.valid_response(valid, "old-search"), "Old discovery responses cannot populate new search")
 for change in [{"protocol": -1}, {"port": 0}, {"port": 65536}, {"port": "invalid"}, {"players": 13}, {"players": 1.5}]:
  var invalid := valid.duplicate()
  invalid.merge(change, true)
  check(not VolleyRoomDiscovery.valid_response(invalid, token), "Malformed / incompatible discovery field rejected " + str(change))
 var game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 var seeker := VolleyRoomDiscovery.new()
 seeker.lan = game.lan
 root.add_child(seeker)
 seeker.set_process(false)
 var explicit: Array[String] = ["127.0.0.1"]
 check(seeker.search(explicit, 24916) == OK, "Search can start before room / permission is available")
 seeker._process(7.0)
 check(seeker.searching and seeker.next_target > 2, "Search still probes after the old two-pass / six-second cutoff")
 check(game.lan.host_room(24915) == OK, "IPv4 room binds all local interfaces")
 for i in range(60):
  seeker._process(0.05)
  await process_frame
 check(seeker.rooms.has("127.0.0.1") and seeker.rooms["127.0.0.1"].port == 24915, "Late room appears after permission / hotspot startup delay")
 var malformed := PacketPeerUDP.new()
 malformed.set_dest_address("127.0.0.1", 24916)
 malformed.put_packet(JSON.stringify({"magic": VolleyRoomDiscovery.MAGIC}).to_utf8_buffer())
 for i in range(5):
  await process_frame
 check(game.lan.hosting, "Malformed UDP packet leaves host operational")
 malformed.close()
 check(game.lan.join_room("bad IP") == ERR_INVALID_PARAMETER and game.lan.hosting, "Mistyped endpoint does not destroy an existing room")
 check(game.lan.host_room(65535) == ERR_INVALID_PARAMETER and game.lan.hosting, "Invalid discovery port does not destroy an existing room")
 seeker._process(VolleyRoomDiscovery.SEARCH_DURATION)
 check(not seeker.searching and not seeker.seeker.is_bound(), "Search timeout releases socket")
 check(seeker.search(explicit, 24916) == OK and seeker.rooms.is_empty(), "Search can restart without stale results")
 seeker.stop_search()
 check(game.lan.join_room("127.0.0.1", 24917) == OK, "Manual join starts for the same protocol on both mobile platforms")
 game.lan._process(12.0)
 check(game.lan.active and not game.lan.connected, "Connection survives more than ten seconds awaiting network permission")
 game.lan._process(20.0)
 check(not game.lan.active and game.lan.status.contains("локальную сеть"), "Unreachable host times out with actionable permission guidance")
 game.frontend.start_solo()
 check(not game.ball.replica and not game.athlete.replica and game.athlete.is_physics_processing(), "Solo play restores after failed connection")
 seeker.queue_free()
 game.queue_free()
 await process_frame
 print("V15 TESTS PASSED (%d checks)" % checks if failures == 0 else "V15 FAILED")
 quit(0 if failures == 0 else 1)
