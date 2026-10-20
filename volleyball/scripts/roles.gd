class_name VolleyRoles
extends RefCounted

const IDS := ["S", "MB", "OH", "OP", "L"]
const NAMES := {"S":"Связующий", "MB":"Центральный", "OH":"Доигровщик", "OP":"Диагональный", "L":"Либеро"}
const ALIASES := {"S":"setter", "MB":"middle", "OH":"outside", "OP":"opposite", "L":"libero"}
enum State { PRE_SERVE, SERVE, RECEIVE, DEFENSE, SETUP, ATTACK, BLOCK, COVER, TRANSITION, ROTATION, BENCH }

static func default_role(character: String) -> String:
 var data := VolleyCharacterDatabase.get_character(character)
 var role: String = data.get("role", "")
 if role in IDS:
  return role
 # Older/custom catalog entries participate without a hero-specific AI.
 return {"Setter":"S", "Middle Blocker":"MB", "Outside Hitter":"OH", "Opposite Hitter":"OP", "Libero":"L"}.get(str(data.get("position","")), "OH")

static func attack_capable(a: ContextAthlete) -> bool:
 return not a.benched and a.volley_role != "L"

static func can_block(a: ContextAthlete) -> bool:
 return attack_capable(a) and (not a.strict_positions or a.rotation_slot in [2,3,4])

static func can_serve(a: ContextAthlete) -> bool:
 return not a.benched and a.volley_role != "L"

static func base(a: ContextAthlete, offense: bool) -> Vector3:
 var side := 1.0 if a.court_team == 0 else -1.0
 var back := a.strict_positions and a.rotation_slot in [1,5,6]
 var x := 0.0
 var z := 5.8
 match a.volley_role:
  "S":
   x = 1.3
   z = 2.5 if offense else 5.5 if back else 2.4
  "MB":
   x = 0
   z = 5.8 if back else 2.6 if offense else 1.25
  "OH":
   x = -2.8
   z = 5.8 if back else 3.8 if offense else 2.2
  "OP":
   x = 2.8
   z = 5.8 if back else 3.8 if offense else 2.2
  "L":
   x = -0.5
   z = 5.8 if offense else 6.3
 return Vector3(x*side,0.02,z*side)
