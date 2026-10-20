extends SceneTree
var game: Node3D
var failures:=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var count:=2 if OS.get_cmdline_user_args().is_empty() else int(OS.get_cmdline_user_args()[0])
 for grade in range(3):
  game=load("res://scenes/Main.tscn").instantiate()
  root.add_child(game)
  game.frontend.start_solo()
  game.hud.set_process(false)
  game.rig.set_process(false)
  var cm: VolleyCharacters=game.characters
  var teams:=cm.default_teams()
  for t in range(2):
   for slot in range(count):
    teams[t][slot]={"kind":"bot","character":"hinata" if slot%2==1 else "kageyama","human":0}
  cm.apply_teams(teams,grade,false)
  cm.demo=false
  game.athlete.set_physics_process(false)
  game.lower_serve.rng.seed=842701+grade
  game.float_serve.rng.seed=842801+grade
  var bots: VolleyGameBots=game.game_bots
  bots.start_solo()
  var events:={}
  var observed:={}
  var swings:={}
  var checked_swings:={}
  var pass_attempts:=0
  var pass_misses:=0
  var hard_hits:=0
  var tip_hits:=0
  var attack_paces: Array[float]=[]
  var launch_times:={}
  var was_jumping:={}
  var minimum_quick_lead:=INF
  var attack_team:=-1
  var attacks:=0
  var cleared:=0
  var net_hits:=0
  var failed_attacks:=0
  var blocked:=0
  var quick_spikes:=0
  var pending_quick:={}
  var previous_quick:=cm.quick_launches
  var floors:=0
  var quick:=cm.quick_launches
  game.ball.surface_contact.connect(func(surface: String):events[surface]=int(events.get(surface,0))+1)
  for frame in range(120*(60 if count==6 else 90)):
   await physics_frame
   for a: VolleyGameBot in bots.bots.values():
    if a.jump_in_progress and not bool(was_jumping.get(a.bot_id,false)):launch_times[a.get_instance_id()]=bots.clock
    was_jumping[a.bot_id]=a.jump_in_progress
    if int(swings.get(a.bot_id,0))!=a.strike_count:
     swings[a.bot_id]=a.strike_count
     if a.strike_technique in [0,8]:pass_attempts+=1
    if a.action==VolleyAthlete.Action.RECOVER and int(checked_swings.get(a.bot_id,0))!=a.strike_count:
     checked_swings[a.bot_id]=a.strike_count
     if a.strike_technique in [0,8] and not a.hit_used:pass_misses+=1
    if a.contacts>int(observed.get(a.bot_id,0)):
     observed[a.bot_id]=a.contacts
     print("MATCH_TOUCH grade=",grade," clock=",snappedf(bots.clock,0.01)," hero=",a.character_id," team=",a.court_team," kind=",a.strike_technique," at=",a.last_contact_point," v=",game.ball.linear_velocity," quick=",a.special_set)
     if a.strike_technique in [VolleyAthlete.Technique.SPIKE,ContextAthlete.TIP]:
      if a.strike_technique==ContextAthlete.TIP:tip_hits+=1
      elif a.air_attack:hard_hits+=1
      attack_paces.append(game.ball.linear_velocity.length())
      attacks+=1
      attack_team=a.court_team
      if pending_quick.has(a.get_instance_id()) and bots.clock-float(pending_quick[a.get_instance_id()])<0.8:
       quick_spikes+=1
       pending_quick.erase(a.get_instance_id())
     elif a.strike_technique==ContextAthlete.BLOCK and attack_team>=0 and a.court_team!=attack_team:
      blocked+=1
      attack_team=-1
     if cm.quick_launches>previous_quick and a.special_recipient!=null:
      var receiver: Variant=a.special_recipient.get_ref()
      if is_instance_valid(receiver):
       pending_quick[receiver.get_instance_id()]=bots.clock
       if launch_times.has(receiver.get_instance_id()):minimum_quick_lead=minf(minimum_quick_lead,bots.clock-float(launch_times[receiver.get_instance_id()]))
     previous_quick=cm.quick_launches
   if attack_team>=0:
    if game.ball.position.z*(1 if attack_team==0 else -1)<-0.4:
     cleared+=1
     attack_team=-1
    elif int(events.get("net",0))>net_hits or int(events.get("floor",0))>floors:
     failed_attacks+=1
     attack_team=-1
   net_hits=int(events.get("net",0))
   floors=int(events.get("floor",0))
  print("AUTONOMOUS MATCH players=",count," grade=",grade," scores=",bots.scores," attacks=",attacks," cleared=",cleared," blocked=",blocked," failed_attacks=",failed_attacks," quick=",cm.quick_launches-quick," quick_spikes=",quick_spikes," surfaces=",events," total_contacts=",observed)
  var firm_hits:=attack_paces.filter(func(p):return p>=13.0).size()
  print("EXECUTION players=",count," grade=",grade," pass_attempts=",pass_attempts," pass_misses=",pass_misses," hard_hits=",hard_hits," tips=",tip_hits," firm_hits=",firm_hits," quick_lead=",minimum_quick_lead," paces=",attack_paces)
  if pass_misses>maxi(1,floori(pass_attempts*0.08)) or hard_hits<attacks*0.70 or tip_hits>maxi(1,floori(attacks*0.15)) or firm_hits<attacks*0.60:
   push_error("Ordinary sets must not release early; normal attacks must not become repeated soft tips")
   failures+=1
  if attacks<4 or (cleared+blocked)<attacks*0.80 or quick_spikes<(2 if count==2 else 1):
   push_error("Ordinary matches must produce real quick attacks and mostly clear the net")
   failures+=1
  game.queue_free()
  for i in range(4):await physics_frame
 print("AUTONOMOUS MATCHES PASSED" if failures==0 else "AUTONOMOUS MATCHES FAILED")
 quit(0 if failures==0 else 1)
