extends SceneTree
var game: Node3D
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1;push_error(label)
func run() -> void:
 game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 game.hud.set_process(false)
 var cm: VolleyCharacters=game.characters
 var teams:=cm.default_teams()
 for i in range(3):teams[1][i]={"kind":"bot","character":VolleyCharacterDatabase.IDS[i],"human":0}
 var old_speeds:={}
 var old_jumps:={}
 for grade in range(3):
  cm.apply_teams(teams,grade,false)
  var multiplier: float=[0.8,0.9,1.0][grade]
  for bot: VolleyGameBot in game.game_bots.bots.values():
   bot.set_physics_process(false)
   var id:=bot.character_id
   var sheet: Dictionary=VolleyCharacterDatabase.get_character(id).stats
   var exact:=true
   for key in VolleyStyleStats.KEYS:exact=exact and is_equal_approx(float(bot.stats.values[key]),float(sheet[key])*multiplier)
   check(exact,"All eight %s ratings are exactly %d%%"%[id,roundi(multiplier*100)])
   var speed:=bot.effective_speed()
   var jump:=bot.effective_jump_height()
   check(grade==0 or (speed>float(old_speeds[id]) and jump>float(old_jumps[id])),"Movement/jump scale with effective ratings: "+id)
   old_speeds[id]=speed
   old_jumps[id]=jump
   bot.calibration.prepare(bot,VolleyAthlete.Technique.OVERHEAD)
   var key:=bot.calibration.cache_key
   bot.set_character(id)
   check(is_equal_approx(float(bot.stats.values.jump),float(sheet.jump)*multiplier),"Character reinstall preserves difficulty: "+id)
   bot.calibration.prepare(bot,VolleyAthlete.Technique.OVERHEAD)
   check(bot.calibration.cache_key==key,"Contact cache matches effective sheet: "+id)
   if id=="oikawa":
    check(is_equal_approx(game.super_serve.ability_speed(bot),63*multiplier),"Bot Super Serve pace scales by difficulty")
  check(game.athlete.stats.values==VolleyCharacterDatabase.get_character(game.athlete.character_id).stats,"Human sheet remains original")
  var random:=RandomNumberGenerator.new()
  random.seed=902300+grade
  var faults:=0
  for sample in range(100000):
   var error:=VolleyBotDifficulty.contact_error(random,[0,2,4][grade],0.75,3.0,0.05,true)
   if error.fault:faults+=1
  check(faults>0 and faults<160,"Rare but nonzero bot mishits: %d / 100000"%faults)
 check(is_equal_approx(float(VolleyBotDifficulty.execution(2).fault),0.025),"Human club error policy unchanged")
 var bot: VolleyGameBot=game.game_bots.bots[-108]
 bot.set_character("oikawa")
 for grade in range(3):
  game.game_bots.configure({"difficulty":[0,2,4][grade]},false)
  for other in game.game_bots.bots.values():other.set_physics_process(false)
  bot.court_team=0
  bot.position=Vector3(0,0.02,10.4)
  bot.velocity=Vector3.ZERO
  bot.cancel_input()
  bot.action=VolleyAthlete.Action.IDLE
  bot.jump_in_progress=false
  bot.set_physics_process(false)
  # Settle using actual root physics before activating the real ability.
  for i in range(12):bot._physics_process(1.0/120)
  bot.position=Vector3(0,0.02,10.4)
  game.ball.athlete=bot
  game.ball.feed(bot.position+Vector3(0,0.25,-0.5),Vector3.ZERO)
  for i in range(5):await physics_frame
  check(game.ball.pick_up(),"Super Serve fixture owns a real held ball")
  var s: VolleySuperServe=game.super_serve
  var floor_at:=[Vector3.INF]
  var capture:=func(surface: String):
   if surface=="floor" and s.contact_done and floor_at[0]==Vector3.INF:floor_at[0]=game.ball.position
  game.ball.surface_contact.connect(capture)
  var begun:=s.begin(bot,bot.bot_id)
  check(begun,"Oikawa bot can activate at every level")
  if begun:
   s.target=Vector3(1.4,VolleyBall.RADIUS,-8.1)
   s.inside=true
   for i in range(800):
    await physics_frame
    if not s.active:break
   var expected: float=63*[0.8,0.9,1.0][grade]
   print("BOT SUPER grade=",grade," pace=",s.launch_velocity.length()," expected=",expected," floor=",floor_at[0]," peak=",s.peak_height)
   check(absf(s.launch_velocity.length()-expected)<2.0,"Real Super Serve impulse follows the level")
   check(floor_at[0]!=Vector3.INF and Vector3(floor_at[0]).distance_to(s.target)<0.45,"Scaled jump and fast trajectory still land in the chosen area")
  game.ball.surface_contact.disconnect(capture)
 print("BOT LEVELS PASSED (%d checks)"%checks if failures==0 else "BOT LEVELS FAILED %d"%failures)
 quit(0 if failures==0 else 1)
