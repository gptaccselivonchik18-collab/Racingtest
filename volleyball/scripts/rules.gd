class_name VolleyRules
extends RefCounted

var strict := false
var team := -1
var touches := 0
var last_player := -1
var last_block := false
var last_action := -1
var ended := false
var message := ""
var serving := false
var serve_crossed := false

func reset(is_serve := false) -> void:
 team = -1
 touches = 0
 last_player = -1
 last_block = false
 last_action = -1
 ended = false
 serving = is_serve
 serve_crossed = false
 message = ""

func fault(text: String) -> void:
 if not ended:
  ended = true
  message = text

func touch(side: int, player: int, kind: int, action_id: int) -> bool:
 if ended:
  return false
 if team != side:
  team = side
  touches = 0
  last_player = -1
  last_block = false
  last_action = -1
 var block := kind == ContextAthlete.BLOCK
 # Multiple simultaneous parts in the same action are not two new actions.
 if last_player == player and last_action == action_id and (touches == 1 or block):
  return true
 if block:
  last_block = true
  last_player = player
  last_action = action_id
  return true
 if strict and last_player == player and not last_block:
  fault("Двойное касание")
  return false
 touches += 1
 if touches > 3 and strict:
  fault("Четыре касания команды")
  return false
 last_player = player
 last_action = action_id
 last_block = false
 return true

func floor_contact(point: Vector3) -> void:
 # A ball touching a boundary line is in. Its radius matters.
 var inside := absf(point.x) <= 4.5 + VolleyBall.RADIUS and absf(point.z) <= 9 + VolleyBall.RADIUS
 if serving and not serve_crossed:
  fault("Ошибка подачи: мяч не пересёк сетку")
 else:
  fault("Мяч в площадке" if inside else "Аут")

func crossing(from: Vector3, to: Vector3) -> void:
 if from.z * to.z >= 0 or ended:
  return
 var t := from.z / (from.z - to.z)
 var crossing_point := from.lerp(to, t)
 if absf(crossing_point.x) > 4.5 - VolleyBall.RADIUS:
  fault("Мяч вне антенн")
 elif crossing_point.y < 2.43 + VolleyBall.RADIUS:
  # A ball crossing underneath the net is not a valid crossing.
  fault("Под сеткой")
 else:
  serve_crossed = true

func serve_contact(origin: Vector3) -> void:
 if absf(origin.x) > 4.5 or absf(origin.z) <= 9.0:
  fault("Ошибка подачи: заступ")

func net_contact(player_contact: bool, antenna := false) -> void:
 if antenna:
  fault("Касание антенны")
 elif player_contact:
  fault("Касание сетки игроком")
 # A ball touching the net is legal; physics determines whether it crosses.
