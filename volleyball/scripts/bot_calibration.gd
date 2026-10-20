class_name VolleyBotCalibration
extends RefCounted

# Sample the SAME motion/arm clamp used by real contacts. This is prediction
# only: no contact, pose, action time or ball state is changed by a sample.
var cache_key := ""
var samples: Array = []

func prepare(a: ContextAthlete,kind: int) -> void:
 var key:="%s:%d:%s:%s:%.4f:%s:%d"%[a.character_id,kind,a.airborne(),a.special_set,(a.style_stats as VolleyCharacterStats).difficulty_multiplier,a.approach_jump,roundi(a.velocity.length()*2.0)]
 if key==cache_key:return
 cache_key=key
 samples.clear()
 var saved:=[a.action,a.strike_technique,a.strike_duration,a.action_time,a.air_attack]
 var p:=a.mechanic(kind)
 a.action=VolleyAthlete.Action.STRIKE
 a.strike_technique=kind
 a.strike_duration=float(p.duration)
 a.air_attack=a.airborne() and a.approach_jump
 # Aim at the middle of the swing. A possible overlap at the very end of
 # recovery is not a reliable reason to release a third of a second early.
 var first:=maxf(float(p.start),0.30)
 var last:=minf(float(p.end),0.65)
 for i in range(9):
  var phase:=lerpf(first,last,i/8.0)
  a.action_time=phase*a.strike_duration
  var motion:=VolleyMotion.new()
  motion.athlete=a
  motion.update(0)
  VolleyCharacterAbilities.pose(motion)
  var hands: Array[Vector3]=[]
  var elbows: Array[Vector3]=[]
  for hand in range(2):
   var shoulder:=motion.shoulder(hand)
   hands.append(shoulder+(motion.wrists[hand]-shoulder).limit_length(0.855))
   elbows.append(VolleyLimbRig.joint(shoulder,hands[hand],motion.poles[hand],0.44,0.42))
  samples.append({"time":phase*a.strike_duration,"hands":hands,"elbows":elbows})
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
 var point:=ball.position
 var incoming:=ball.linear_velocity
 var spin:=ball.angular_velocity
 var drift:=Vector3.ZERO
 var root_speed:=a.velocity
 var air:=a.airborne()
 var movement:=a.style_stats.movement()
 var elapsed:=0.0
 var first_sample:=true
 for sample: Dictionary in samples:
  var time: float=sample.time
  var previous:=point
  while elapsed<time-0.00001:
   var dt:=minf(1.0/120.0,time-elapsed)
   incoming+=(Vector3.DOWN*(9.81+ball.super_curve)+ball.aero_force(incoming,spin)/ball.mass)*dt
   point+=incoming*dt
   spin*=1.0-ball.angular_damp*dt
   var horizontal:=Vector2(root_speed.x,root_speed.z)
   if air:
    horizontal*=1.0/(1.0+0.018*horizontal.length()*dt)
    root_speed.y-=9.81*dt
   else:
    horizontal=Vector2.ZERO if a.character_id=="hinata" else horizontal.move_toward(Vector2.ZERO,float(movement.braking)*dt)
    root_speed.y=0
   root_speed.x=horizontal.x
   root_speed.z=horizontal.y
   drift+=root_speed*dt
   elapsed+=dt
  if air and a.position.y+drift.y<0.02:continue
  # Do not match a ball that passed the hands before this sampled pose.
  if first_sample:previous=point
  first_sample=false
  if kind in [VolleyAthlete.Technique.UNDERHAND,ContextAthlete.DIVE] and a.character_id!="yu_nishinoya":
   var spine:=a.position+drift+Vector3.UP*clampf(point.y-a.position.y-drift.y,0.20*a.physical_scale,1.65*a.physical_scale)
   if point.distance_to(spine)<radius+0.30:return true
  else:
   var turn:=float(a.style_stats.movement().turn)*time*(0.45 if a.airborne() else 1.0)
   var yaw:=0.0 if not a.special_set.is_empty() else clampf(angle_difference(a.visual.global_rotation.y,a.camera_yaw),-turn,turn)
   var basis:=a.visual.global_basis.rotated(Vector3.UP,yaw)
   for index in range(2):
    if kind in [VolleyAthlete.Technique.SPIKE,ContextAthlete.TIP] and index==0:continue
    var local: Vector3=sample.hands[index]
    var hand:=a.position+drift+basis*local
    if hand.distance_to(Geometry3D.get_closest_point_to_segment(hand,previous,point))<radius+VolleyAthlete.HAND_RADIUS*0.65-0.04:
     return true
    if a.character_id=="yu_nishinoya" and kind in [VolleyAthlete.Technique.UNDERHAND,ContextAthlete.DIVE]:
     var elbow: Vector3=a.position+drift+basis*Vector3(sample.elbows[index])
     if point.distance_to(Geometry3D.get_closest_point_to_segment(point,elbow,hand))<radius+VolleyAthlete.FOREARM_RADIUS-0.04:
      return true
 return false
