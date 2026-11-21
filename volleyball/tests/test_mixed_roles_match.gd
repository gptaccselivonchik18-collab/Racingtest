extends SceneTree
var game: Node3D
var failures := 0
func _initialize() -> void:call_deferred("run")
func run() -> void:
 for grade in range(3):
  game=load("res://scenes/Main.tscn").instantiate()
  root.add_child(game)
  game.frontend.start_solo()
  game.hud.set_process(false)
  game.rig.set_process(false)
  var cm: VolleyCharacters=game.characters
  var teams:=cm.default_teams()
  var roles: Array=["S","OP","MB","OH","MB","OH"]
  var heroes: Array=["kageyama","oikawa","hinata","oikawa","hinata","kageyama"]
  for t in range(2):
   for s in range(6):teams[t][s]={"kind":"bot","character":heroes[s],"human":0,"role":roles[s],"rotation":s+1}
  var settings:=cm.default_lineup_settings()
  for t in range(2):settings.liberos[t]={"kind":"bot","character":"yu_nishinoya","human":0}
  assert(cm.apply_teams(teams,grade,false,settings))
  cm.demo=false
  game.athlete.set_physics_process(false)
  game.lower_serve.rng.seed=452001+grade
  game.float_serve.rng.seed=452101+grade
  game.super_serve.random.seed=452201+grade
  var bots: VolleyGameBots=game.game_bots
  assert(bots.start_solo())
  var observed: Dictionary={}
  var old_positions: Dictionary={}
  var first_half := 0
  var second_half := 0
  var nishinoya_contacts := 0
  var setter_contacts := 0
  var attacks := 0
  var rolls := 0
  var legal := true
  var no_warp := true
  var old_live := false
  var old_revision := 0
  var bench_max := 0
  for frame in range(120*150):
   await physics_frame
   var live: bool=game.formation.rally_live()
   if bots.members(0).size()!=6 or bots.members(1).size()!=6:legal=false
   var on_bench := 0
   for a: VolleyGameBot in bots.bots.values():
    if a.benched:
     on_bench+=1
    if a.block_held and not VolleyRoles.can_block(a):legal=false
    if a.designated_libero and not a.benched and a.rotation_slot not in [1,5,6]:legal=false
    if a.volley_role=="L" and a.is_server:legal=false
    if live and old_live and old_revision==game.formation.revision and old_positions.has(a.bot_id) and not a.benched:
     if VolleyBotTactics.flat(a.position,old_positions[a.bot_id])>0.42:no_warp=false
    old_positions[a.bot_id]=a.position
    if a.rolling_active:rolls+=1
    if a.contacts>int(observed.get(a.bot_id,0)):
     var delta: int=a.contacts-int(observed.get(a.bot_id,0))
     observed[a.bot_id]=a.contacts
     if frame<120*75:first_half+=delta
     else:second_half+=delta
     if a.character_id=="yu_nishinoya":nishinoya_contacts+=delta
     if a.volley_role=="S" and a.strike_technique in [0,8]:setter_contacts+=delta
     if a.strike_technique in [2,9]:attacks+=delta
   old_live=live
   old_revision=game.formation.revision
   bench_max=maxi(bench_max,on_bench)
  var points: int=game.formation.rallies_completed
  print("MIXED ROLES grade=",grade," rallies=",points," first_half=",first_half," second_half=",second_half," Nishinoya_contacts=",nishinoya_contacts," setter_sets=",setter_contacts," attacks=",attacks," quick=",cm.quick_launches," rolling_frames=",rolls," legal=",legal," no_warp=",no_warp," replacements=",game.formation.libero.history.size()," max_bench=",bench_max)
  if not legal or not no_warp or points<4 or first_half<4 or second_half<4 or nishinoya_contacts<1 or setter_contacts<2 or attacks<2 or game.formation.libero.history.size()<4 or bench_max<2:
   failures+=1
   push_error("Mixed-role teams must keep playing legal real-contact volleyball across many rotations")
  game.queue_free()
  for i in range(4):await physics_frame
 print("MIXED ROLES MATCH PASSED" if failures==0 else "MIXED ROLES MATCH FAILED")
 quit(0 if failures==0 else 1)
