class_name VolleyMatchScore
extends RefCounted

# Best of five sets, win by two; the deciding fifth set is played to 15.
# The caller keeps the final set's score visible when a match is finished.
static func point(scores: Array, sets: Array, side: int) -> int:
 scores[side] += 1
 var target := 15 if int(sets[0]) + int(sets[1]) == 4 else 25
 if int(scores[side]) >= target and int(scores[side]) - int(scores[1 - side]) >= 2:
  sets[side] += 1
  if int(sets[side]) >= 3:
   return side
  scores[0] = 0
  scores[1] = 0
 return -1

static func label(scores: Array, sets: Array, winner: int) -> String:
 var text := "A %d : %d Б · сеты %d:%d" % [scores[0], scores[1], sets[0], sets[1]]
 if winner >= 0:
  text += " · победа %s" % ("A" if winner == 0 else "Б")
 return text
