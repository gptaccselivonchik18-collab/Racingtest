class_name VolleyNetworkInfo
extends RefCounted

static func usable_ipv4(address: String) -> bool:
 if not address.is_valid_ip_address() or ":" in address:
  return false
 var first := int(address.get_slice(".", 0))
 return first > 0 and first < 224 and address != "255.255.255.255"

static func interface_rank(adapter: Dictionary) -> int:
 var label := (str(adapter.get("name", "")) + " " + str(adapter.get("friendly", ""))).to_lower()
 for word in ["utun", "tun", "tap", "vpn", "wireguard", "tailscale", "zerotier"]:
  if word in label:
   return 100
 for word in ["pdp_ip", "rmnet", "wwan", "cellular", "мобильн"]:
  if word in label:
   return 80
 for word in ["bridge", "softap", "swlan", "ap0", "rndis"]:
  if word in label:
   return 0
 for word in ["wlan", "wi-fi", "wifi", "wireless", "беспровод", "en0"]:
  if word in label:
   return 1
 if "ethernet" in label or "eth" in label:
  return 10
 return 30

static func ordered_addresses(interfaces: Array) -> PackedStringArray:
 var ranked := interfaces.duplicate()
 ranked.sort_custom(func(a: Dictionary, b: Dictionary): return interface_rank(a) < interface_rank(b))
 var result := PackedStringArray()
 for adapter in ranked:
  for value in adapter.get("addresses", []):
   var address := str(value)
   if VolleyRoomDiscovery.private_ipv4(address) and address not in result:
    result.append(address)
 return result

static func local_addresses() -> PackedStringArray:
 var result := ordered_addresses(IP.get_local_interfaces())
 if result.is_empty():
  for address in IP.get_local_addresses():
   if VolleyRoomDiscovery.private_ipv4(address) and address not in result:
    result.append(address)
 return result
