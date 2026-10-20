class_name VolleyBotCalibration
extends RefCounted

# Sample the SAME motion/arm clamp used by real contacts. This is prediction
# only: no contact, pose, action time or ball state is changed by a sample.
var cache_key := ""
var samples: Array = []

func prepare(a: ContextAthlete,kind: int) -> void:
 var key:="%s:%d:%s:%s:%.4f"%[a.character_id,kind,a.airborne(),a.special_set,(a.style_stats as VolleyCharacterStats).difficulty_multiplier]
 if key==cache_key:return
 cache_key=key
 samples.clear()
 var saved:=[a.action,a.strike_technique,a.strike_duration,a.action_time,a.air_attack]
 var p:=a.mechanic(kind)
 a.action=VolleyAthlete.Action.STRIKE
 a.strike_technique=kind
 a.strike_duration=float(p.duration)
 a.air_attack=a.airborne() and a.approach_jump
 var first:=maxf(float(p.start),0.01)
 var last:=minf(float(p.end),0.95)
 for i in range(13):
  var phase:=lerpf(first,last,i/12.0)
  a.action_time=phase*a.strike_duration
  var motion:=VolleyMotion.new()
  motion.athlete=a
  motion.update(0)
  VolleyCharacterAbilities.pose(motion)
  var hands: Array[Vector3]=[]
  for hand in range(2):
   var shoulder:=motion.shoulder(hand)
   hands.append(shoulder+(motion.wrists[hand]-shoulder).limit_length(0.855))
  samples.append({"time":phase*a.strike_duration,"hands":hands})
 a.action=saved[0]
 a.strike_technique=saved[1]
 a.strike_duration=saved[2]
 a.action_time=saved[3]
 a.air_attack=saved[4]

func contact_due(a: ContextAthlete,ball: VolleyBall,kind: int) -> bool:
 if kind<0:kind=a.technique
 prepare(a,kind)
 var p:=a.mechanic(kind)
 var radius:=a.contact_ball_radius*float(p.radius)
 var previous:=ball.position
 for sample: Dictionary in samples:
  var time: float=sample.time
  var point:=ball.position+ball.linear_velocity*time+Vector3.DOWN*4.905*time*time
  if ball.super_curve>0:
   point=ball.position
   var incoming:=ball.linear_velocity
   var spin:=ball.angular_velocity
   var ticks:=maxi(1,ceili(time*120.0))
   var dt:=time/ticks
   for tick in range(ticks):
    incoming+=(Vector3.DOWN*(9.81+ball.super_curve)+ball.aero_force(incoming,spin)/ball.mass)*dt
    point+=incoming*dt
    spin*=1.0-ball.angular_damp*dt
  var drift:=a.velocity*time
  if a.airborne():drift+=Vector3.DOWN*4.905*time*time
  else:drift*=0.65
  if kind in [VolleyAthlete.Technique.UNDERHAND,ContextAthlete.DIVE]:
   var spine:=a.position+drift+Vector3.UP*clampf(point.y-a.position.y-drift.y,0.20*a.physical_scale,1.65*a.physical_scale)
   if point.distance_to(spine)<radius+0.30:return true
  else:
   var turn:=float(a.style_stats.movement().turn)*time*(0.45 if a.airborne() else 1.0)
   var yaw:=0.0 if not a.special_set.is_empty() else clampf(angle_difference(a.visual.global_rotation.y,a.camera_yaw),-turn,turn)
   var basis:=a.visual.global_basis.rotated(Vector3.UP,yaw)
   for local: Vector3 in sample.hands:
    var hand:=a.position+drift+basis*local
    if hand.distance_to(Geometry3D.get_closest_point_to_segment(hand,previous,point))<radius+VolleyAthlete.HAND_RADIUS*0.85:
     return true
  previous=point
 return false
