extends Node

var screen
var current_track := "city_night"
var garage_idx := 0
var track_idx := 0

class CarVisual:
	extends Node3D
	var car_id := "street_starter"
	func _ready():
		var d := GameState.get_car(car_id)
		var col: Color = d.get("color", Color.CYAN)
		var acc: Color = d.get("accent", Color.YELLOW)
		var shape := str(d.get("shape", "hatch"))
		var body := Vector3(2.0, .55, 3.3)
		var cabin := Vector3(1.25, .48, 1.1)
		if shape == "super":
			body = Vector3(2.1, .45, 3.75)
			cabin = Vector3(1.1, .38, .95)
		if shape == "muscle":
			body = Vector3(2.35, .68, 3.75)
			cabin = Vector3(1.55, .55, 1.25)
		if shape == "hyper":
			body = Vector3(2.18, .40, 4.05)
			cabin = Vector3(1.05, .35, .9)
		_box(Vector3(0, .55, 0), body, col, false)
		_box(Vector3(0, 1.02, -.18), cabin, col.lightened(.15), false)
		_box(Vector3(0, 1.08, -.22), cabin * Vector3(.7, .35, .7), Color(.02, .03, .05), false)
		_box(Vector3(0, .78, -body.z * .52), Vector3(body.x * .7, .12, .16), acc, true)
		_box(Vector3(0, .78, body.z * .52), Vector3(body.x * .72, .12, .16), Color(1, .05, .03), true)
		if shape == "super" or shape == "hyper" or shape == "drift":
			_box(Vector3(0, .86, body.z * .56), Vector3(2.2, .11, .2), acc, true)
		for x in [-.95, .95]:
			for z in [-1.12, 1.12]:
				_wheel(Vector3(x, .32, z))
	func _box(p, s, c, em):
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = s
		m.mesh = b
		m.position = p
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.roughness = .55
		if em:
			mat.emission_enabled = true
			mat.emission = c
			mat.emission_energy_multiplier = .9
		m.material_override = mat
		add_child(m)
	func _wheel(p):
		var m := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = .32
		cy.bottom_radius = .32
		cy.height = .28
		cy.radial_segments = 16
		m.mesh = cy
		m.position = p
		m.rotation.z = PI * .5
		m.material_override = _mat(Color(.015, .015, .018))
		add_child(m)
	func _mat(c):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		return mat

class Car:
	extends CharacterBody3D
	signal stats_changed(stats)
	signal hard_collision
	var car_id := "street_starter"
	var data := {}
	var forward := 0.0
	var side := 0.0
	var nitro := 100.0
	var drift_score := 0
	var top := 0.0
	var cd := 0.0
	var touch := {"left": false, "right": false, "gas": false, "brake": false, "drift": false, "nitro": false}
	var nitro_fx
	var drift_l
	var drift_r
	func _ready():
		data = GameState.get_car(car_id)
		var v := CarVisual.new()
		v.car_id = car_id
		add_child(v)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(2, 1.05, 3.45)
		cs.shape = bs
		cs.position = Vector3(0, .62, 0)
		add_child(cs)
		nitro_fx = _particles(Color(0, .9, 1), 120, 1.0)
		nitro_fx.position = Vector3(0, .45, 2.0)
		add_child(nitro_fx)
		drift_l = _particles(Color(.9, .85, .78), 70, .55)
		drift_l.position = Vector3(-.95, .18, 1.25)
		add_child(drift_l)
		drift_r = _particles(Color(.9, .85, .78), 70, .55)
		drift_r.position = Vector3(.95, .18, 1.25)
		add_child(drift_r)
	func _physics_process(delta):
		cd = max(0, cd - delta)
		var gas := touch["gas"] or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
		var brake := touch["brake"] or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
		var drift := touch["drift"] or Input.is_key_pressed(KEY_SPACE)
		var boost := touch["nitro"] or Input.is_key_pressed(KEY_SHIFT)
		var steer := 0.0
		if touch["left"] or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			steer -= 1
		if touch["right"] or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			steer += 1
		var maxs := float(data["max_speed"])
		var mass := float(data["mass"])
		if gas:
			forward += float(data["acceleration"]) / mass * delta
		else:
			forward = move_toward(forward, 0, 7.5 * delta)
		if brake:
			forward = move_toward(forward, -12, float(data["braking"]) / sqrt(mass) * delta)
		var using_nitro := boost and nitro > 0 and forward > 8
		if using_nitro:
			forward += float(data["nitro_power"]) * delta
			nitro = max(0, nitro - 34 * delta)
		else:
			nitro = min(100, nitro + (7 + (8 if drift and abs(side) > 2 else 0)) * delta)
		forward = clamp(forward, -18, maxs + (float(data["nitro_power"]) * .45 if using_nitro else 0))
		var ratio := clamp(abs(forward) / maxs, 0, 1)
		var turn := float(data["handling"]) * float(GameState.settings["steering_sensitivity"]) * lerp(1.0, .42, ratio)
		if drift:
			turn *= lerp(1.2, 1.65, float(data["drift_control"]))
		if abs(forward) > 1:
			rotation.y -= steer * turn * delta * sign(forward)
		var target := 0.0
		var grip := 7.5
		if drift and abs(forward) > 12 and abs(steer) > .05:
			target = steer * abs(forward) * lerp(.32, .68, float(data["drift_control"]))
			grip = lerp(2.6, 4.2, float(data["drift_control"]))
			drift_score += int(abs(side) * abs(forward) * delta * 1.8)
		else:
			grip = lerp(7.5, 12.0, float(data["handling"]) / 3.0)
		side = lerp(side, target, clamp(grip * delta, 0, 1))
		velocity = -global_transform.basis.z * forward + global_transform.basis.x * side
		move_and_slide()
		if get_slide_collision_count() > 0 and cd <= 0:
			forward *= .52
			side *= .25
			cd = .35
			emit_signal("hard_collision")
		top = max(top, abs(forward))
		nitro_fx.emitting = using_nitro
		drift_l.emitting = drift and abs(side) > 2
		drift_r.emitting = drift and abs(side) > 2
		emit_signal("stats_changed", {"speed_kmh": abs(forward) * 3.6, "nitro": nitro, "drift_score": drift_score, "max_speed_kmh": top * 3.6, "using_nitro": using_nitro})
	func _particles(c, amount, lifetime):
		var p := GPUParticles3D.new()
		p.amount = amount
		p.lifetime = lifetime
		p.emitting = false
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(0, 0, 1)
		mat.initial_velocity_min = 3
		mat.initial_velocity_max = 8
		mat.spread = 22
		mat.gravity = Vector3(0, .8, 0)
		mat.scale_min = .08
		mat.scale_max = .22
		mat.color = c
		p.process_material = mat
		var mesh := SphereMesh.new()
		mesh.radius = .09
		mesh.height = .18
		p.draw_pass_1 = mesh
		return p

class Cam:
	extends Camera3D
	var target
	var speed := 0.0
	var boost := false
	var trauma := 0.0
	var rng := RandomNumberGenerator.new()
	func _ready():
		rng.randomize()
		current = true
		fov = 70
	func _process(delta):
		if target == null:
			return
		trauma = max(0, trauma - delta * 2.4)
		var r := clamp(speed / 260.0, 0, 1)
		var wanted := target.global_position + target.global_transform.basis.z * lerp(8.5, 12.5, r) + Vector3(0, lerp(4.1, 5.4, r), 0)
		var shake := (trauma * trauma + (0.035 if speed > 190 else 0) + (0.035 if boost else 0)) * Vector3(rng.randf_range(-1, 1), rng.randf_range(-.55, .55), 0)
		global_position = global_position.lerp(wanted + shake, 1 - pow(.001, delta))
		look_at(target.global_position + Vector3(0, 1.2, 0) - target.global_transform.basis.z * 2, Vector3.UP)
		fov = lerp(fov, 70 + r * 12 + (7 if boost else 0), delta * 3)
	func set_stats(s):
		speed = float(s.get("speed_kmh", 0))
		boost = bool(s.get("using_nitro", false))
	func hit():
		trauma = clamp(trauma + .55, 0, 1)

class Race:
	extends Node3D
	signal done(track_id, result)
	signal main
	signal garage
	signal restart
	var track_id := "city_night"
	var car_id := "street_starter"
	var path := []
	var cp := []
	var car
	var cam
	var hud
	var touch
	var pause_layer
	var cp_i := 0
	var elapsed := 0.0
	var score := 0
	var active := false
	var countdown := 2.2
	var finished := false
	var stats := {}
	func _ready():
		path = _path(track_id)
		_world()
		_car()
		_ui()
		_pause()
	func _process(delta):
		if Input.is_key_pressed(KEY_ESCAPE) and not finished:
			_pause_show()
		if countdown > 0:
			countdown -= delta
			if hud:
				hud.get_node("msg").text = str(int(ceil(countdown))) if countdown > 0 else "GO!"
			if countdown <= 0:
				active = true
			return
		if not active or finished:
			return
		elapsed += delta
		score = int(elapsed * 3) + cp_i * 200 + int(stats.get("speed_kmh", 0)) + int(stats.get("drift_score", 0))
		_hud()
	func _car():
		car = Car.new()
		car.car_id = car_id
		car.global_position = path[0] + Vector3(0, .6, 0)
		var dir = (path[1] - path[0]).normalized()
		car.rotation.y = atan2(-dir.x, -dir.z)
		car.stats_changed.connect(_on_stats)
		car.hard_collision.connect(_on_hit)
		add_child(car)
		cam = Cam.new()
		cam.target = car
		cam.global_position = car.global_position + Vector3(0, 5, 10)
		add_child(cam)
	func _on_stats(s):
		stats = s
		if countdown > 0:
			car.forward = 0
		if cam:
			cam.set_stats(s)
	func _on_hit():
		if cam:
			cam.hit()
		if hud:
			hud.get_node("msg").text = "IMPACT"
	func _world():
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.ambient_light_energy = .6
		e.background_color = Color(.67, .49, .29) if track_id == "desert_highway" else (Color(.08, .12, .13) if track_id == "mountain_road" else Color(.01, .02, .06))
		env.environment = e
		add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-48, -32, 0)
		light.light_energy = 1.4 if track_id != "city_night" else .65
		add_child(light)
		_box(Vector3(0, -.25, -370), Vector3(250, .3, 920), _ground(), 0, true)
		var w := 13.5 if track_id == "desert_highway" else (10.0 if track_id == "mountain_road" else 12.0)
		for i in range(path.size() - 1):
			var a = path[i]
			var b = path[i + 1]
			var mid = (a + b) * .5
			var length = a.distance_to(b)
			var dir = (b - a).normalized()
			var yaw = atan2(dir.x, dir.z)
			var side_v = Vector3(dir.z, 0, -dir.x)
			_box(mid, Vector3(w, .18, length + 1.5), Color(.07, .07, .08), yaw, false)
			_box(mid + Vector3(0, .09, 0), Vector3(.34, .08, length * .55), Color(1, .92, .35), yaw, false)
			_box(mid + side_v * (w * .5 + .62) + Vector3(0, .62, 0), Vector3(.8, 1.25, length + 1.5), Color(.13, .15, .18), yaw, true)
			_box(mid - side_v * (w * .5 + .62) + Vector3(0, .62, 0), Vector3(.8, 1.25, length + 1.5), Color(.13, .15, .18), yaw, true)
		for i in range(1, path.size()):
			cp.append(path[i])
			_checkpoint(path[i], i - 1)
		_decor()
	func _path(id):
		if id == "desert_highway":
			return [Vector3(0, 0, 0), Vector3(0, 0, -90), Vector3(28, 0, -170), Vector3(28, 0, -285), Vector3(-18, 0, -370), Vector3(-18, 0, -505), Vector3(35, 0, -620), Vector3(35, 0, -760)]
		if id == "mountain_road":
			return [Vector3(0, 0, 0), Vector3(0, 0, -60), Vector3(-38, 0, -115), Vector3(34, 0, -165), Vector3(10, 0, -230), Vector3(-45, 0, -292), Vector3(42, 0, -350), Vector3(2, 0, -430), Vector3(0, 0, -520)]
		return [Vector3(0, 0, 0), Vector3(0, 0, -75), Vector3(34, 0, -135), Vector3(34, 0, -215), Vector3(-28, 0, -290), Vector3(-28, 0, -380), Vector3(25, 0, -455), Vector3(0, 0, -535)]
	func _decor():
		for i in range(28):
			var side_sign = -1 if i % 2 == 0 else 1
			var z = -18.0 - i * 20.0
			if track_id == "city_night":
				_box(Vector3(side_sign * randf_range(22, 46), randf_range(4, 12), z), Vector3(randf_range(8, 16), randf_range(8, 25), randf_range(8, 16)), Color(.04, .05, .09), 0, true)
			elif track_id == "desert_highway":
				_box(Vector3(side_sign * randf_range(22, 48), 1.2, z), Vector3(.7, 2.4, .7), Color(.11, .36, .18), 0, true)
			else:
				_box(Vector3(side_sign * randf_range(16, 38), 1.4, z), Vector3(randf_range(2, 5), randf_range(2, 5), randf_range(2, 5)), Color(.18, .22, .21), 0, true)
		for i in range(5):
			_box(path[min(i + 2, path.size() - 1)] + Vector3(((-1) if i % 2 == 0 else 1) * 2.4, .55, 0), Vector3(.9, 1.1, .9), Color(1, .38, .12), 0, true)
	func _checkpoint(p, idx):
		var a := Area3D.new()
		a.position = p + Vector3(0, 1.5, 0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(14, 4, 5)
		cs.shape = bs
		a.add_child(cs)
		var v := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(13, 3, .22)
		v.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(.1, .9, 1, .28) if idx < path.size() - 2 else Color(1, .18, .45, .45)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(.1, .9, 1)
		v.material_override = mat
		a.add_child(v)
		a.body_entered.connect(_on_checkpoint.bind(idx))
		add_child(a)
	func _on_checkpoint(b, idx):
		if b == car and active and idx == cp_i:
			cp_i += 1
			if cp_i >= cp.size():
				_finish()
	func _ui():
		var canvas := CanvasLayer.new()
		add_child(canvas)
		hud = Control.new()
		hud.set_anchors_preset(Control.PRESET_FULL_RECT)
		canvas.add_child(hud)
		for n in ["time", "speed", "cp", "score", "drift", "car", "msg"]:
			var l := Label.new()
			l.name = n
			l.add_theme_font_size_override("font_size", 20 if n != "msg" else 34)
			hud.add_child(l)
		hud.get_node("time").position = Vector2(24, 18)
		hud.get_node("speed").position = Vector2(220, 18)
		hud.get_node("cp").position = Vector2(380, 18)
		hud.get_node("score").position = Vector2(520, 18)
		hud.get_node("drift").position = Vector2(700, 18)
		hud.get_node("car").position = Vector2(860, 18)
		hud.get_node("msg").position = Vector2(0, 120)
		hud.get_node("msg").size = Vector2(1280, 60)
		hud.get_node("msg").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var bar := ProgressBar.new()
		bar.name = "nitro"
		bar.position = Vector2(24, 82)
		bar.size = Vector2(390, 28)
		bar.max_value = 100
		hud.add_child(bar)
		touch = Control.new()
		touch.set_anchors_preset(Control.PRESET_FULL_RECT)
		canvas.add_child(touch)
		for b in [["◀", 30, 518, 120, 120, "left"], ["▶", 165, 518, 120, 120, "right"], ["BRAKE", 825, 548, 125, 92, "brake"], ["DRIFT", 960, 548, 125, 92, "drift"], ["GAS", 1095, 505, 150, 135, "gas"], ["NITRO", 960, 440, 125, 92, "nitro"]]:
			_touch_btn(b)
		_btn(touch, "Ⅱ", Vector2(1188, 22), Vector2(62, 54), Callable(self, "_pause_show"))
	func _touch_btn(b):
		var bt = _btn(touch, b[0], Vector2(b[1], b[2]), Vector2(b[3], b[4]), Callable(self, "_noop"))
		var key = b[5]
		bt.button_down.connect(_set_touch.bind(key, true))
		bt.button_up.connect(_set_touch.bind(key, false))
	func _set_touch(key, value):
		car.touch[key] = value
	func _noop():
		pass
	func _hud():
		hud.get_node("time").text = GameState.format_time(elapsed)
		hud.get_node("speed").text = "%d km/h" % int(stats.get("speed_kmh", 0))
		hud.get_node("cp").text = "CP %d/%d" % [cp_i, cp.size()]
		hud.get_node("score").text = "Score %d" % score
		hud.get_node("drift").text = "Drift %d" % int(stats.get("drift_score", 0))
		hud.get_node("car").text = GameState.get_car(car_id)["name"]
		hud.get_node("nitro").value = float(stats.get("nitro", 0))
	func _pause():
		pause_layer = CanvasLayer.new()
		pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		pause_layer.visible = false
		add_child(pause_layer)
		var panel := PanelContainer.new()
		panel.position = Vector2(460, 170)
		panel.size = Vector2(360, 360)
		pause_layer.add_child(panel)
		var box := VBoxContainer.new()
		panel.add_child(box)
		_pbtn(box, "RESUME", Callable(self, "_resume"))
		_pbtn(box, "RESTART", Callable(self, "_restart"))
		_pbtn(box, "GARAGE", Callable(self, "_garage"))
		_pbtn(box, "MAIN MENU", Callable(self, "_main"))
	func _pbtn(parent, text, cb):
		var bt := Button.new()
		bt.text = text
		bt.custom_minimum_size = Vector2(310, 56)
		bt.pressed.connect(cb)
		parent.add_child(bt)
	func _pause_show():
		if not pause_layer.visible:
			pause_layer.visible = true
			get_tree().paused = true
	func _resume():
		get_tree().paused = false
		pause_layer.visible = false
	func _restart():
		get_tree().paused = false
		emit_signal("restart")
	func _garage():
		get_tree().paused = false
		emit_signal("garage")
	func _main():
		get_tree().paused = false
		emit_signal("main")
	func _finish():
		finished = true
		active = false
		var r = {"finished": true, "time": elapsed, "score": score, "drift_score": int(stats.get("drift_score", 0)), "max_speed_kmh": float(stats.get("max_speed_kmh", 0)), "checkpoints": cp.size(), "car_id": car_id, "track_id": track_id}
		r["earned"] = GameState.award_race(track_id, r)
		emit_signal("done", track_id, r)
	func _box(p, s, c, yaw, coll):
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = s
		m.mesh = b
		m.material_override = _mat(c)
		if coll:
			var body := StaticBody3D.new()
			body.position = p
			body.rotation.y = yaw
			body.add_child(m)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = s
			cs.shape = bs
			body.add_child(cs)
			add_child(body)
		else:
			m.position = p
			m.rotation.y = yaw
			add_child(m)
	func _mat(c):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.roughness = .72
		return mat
	func _ground():
		return Color(.55, .38, .20) if track_id == "desert_highway" else (Color(.10, .16, .12) if track_id == "mountain_road" else Color(.025, .026, .035))

func _ready():
	Engine.max_fps = 60
	show_menu()

func set_screen(n):
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = n
	add_child(screen)

func base(title):
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(.012, .016, .03)
	c.add_child(bg)
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 46)
	l.position = Vector2(0, 35)
	l.size = Vector2(1280, 70)
	c.add_child(l)
	return c

func _btn(parent, text, pos, size, cb):
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func show_menu():
	var c := base("NEON ASPHALT RUSH")
	var sub := Label.new()
	sub.text = "Offline Android 3D arcade street racing"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0, 105)
	sub.size = Vector2(1280, 40)
	c.add_child(sub)
	_btn(c, "PLAY", Vector2(500, 190), Vector2(280, 64), Callable(self, "show_tracks"))
	_btn(c, "GARAGE", Vector2(500, 275), Vector2(280, 64), Callable(self, "show_garage"))
	_btn(c, "SETTINGS", Vector2(500, 360), Vector2(280, 64), Callable(self, "show_settings"))
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		_btn(c, "QUIT", Vector2(500, 445), Vector2(280, 64), Callable(get_tree(), "quit"))
	set_screen(c)

func show_tracks():
	var ids := GameState.track_ids()
	var id = ids[track_idx]
	var d := GameState.get_track(id)
	var c := base("TRACK SELECT")
	var l := Label.new()
	var best = GameState.format_time(float(GameState.best_times[id])) if GameState.best_times.has(id) else "--:--.---"
	l.text = "%s\nDifficulty: %d/3\n%s\nBest: %s" % [d["name"], int(d["difficulty"]), d["mood"], best]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(260, 170)
	l.size = Vector2(760, 170)
	l.add_theme_font_size_override("font_size", 26)
	c.add_child(l)
	_btn(c, "◀ PREV", Vector2(300, 435), Vector2(180, 60), Callable(self, "_prev_track"))
	_btn(c, "START", Vector2(520, 435), Vector2(240, 60), Callable(self, "show_race").bind(id))
	_btn(c, "NEXT ▶", Vector2(800, 435), Vector2(180, 60), Callable(self, "_next_track"))
	_btn(c, "GARAGE", Vector2(385, 540), Vector2(230, 58), Callable(self, "show_garage"))
	_btn(c, "MAIN MENU", Vector2(665, 540), Vector2(230, 58), Callable(self, "show_menu"))
	set_screen(c)
func _prev_track():
	var ids := GameState.track_ids()
	track_idx = (track_idx - 1 + ids.size()) % ids.size()
	show_tracks()
func _next_track():
	var ids := GameState.track_ids()
	track_idx = (track_idx + 1) % ids.size()
	show_tracks()

func show_garage():
	var ids := GameState.car_ids()
	var id = ids[garage_idx]
	var d := GameState.get_car(id)
	var c := base("GARAGE")
	var money := Label.new()
	money.text = "Money: $%d" % GameState.money
	money.position = Vector2(820, 45)
	money.size = Vector2(390, 40)
	c.add_child(money)
	var vpcon := SubViewportContainer.new()
	vpcon.position = Vector2(70, 132)
	vpcon.size = Vector2(535, 380)
	vpcon.stretch = true
	c.add_child(vpcon)
	var vp := SubViewport.new()
	vp.size = Vector2i(535, 380)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vpcon.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var vis := CarVisual.new()
	vis.car_id = id
	world.add_child(vis)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 4.2, 8)
	camera.look_at(Vector3(0, .8, 0), Vector3.UP)
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 45, 0)
	light.light_energy = 2.2
	world.add_child(light)
	var info := Label.new()
	info.text = "%s\n%s\nStatus: %s\nMax speed %.0f  Accel %.0f  Handling %.2f\nBraking %.0f  Drift %.2f  Nitro %.0f  Mass %.2f\nPrice: $%d" % [d["name"], d["tagline"], "UNLOCKED" if GameState.is_car_unlocked(id) else "LOCKED", float(d["max_speed"]), float(d["acceleration"]), float(d["handling"]), float(d["braking"]), float(d["drift_control"]), float(d["nitro_power"]), float(d["mass"]), int(d["price"])]
	info.position = Vector2(660, 145)
	info.size = Vector2(540, 250)
	info.add_theme_font_size_override("font_size", 22)
	c.add_child(info)
	_btn(c, "◀ PREV", Vector2(680, 590), Vector2(155, 58), Callable(self, "_prev_car"))
	_btn(c, "NEXT ▶", Vector2(850, 590), Vector2(155, 58), Callable(self, "_next_car"))
	if GameState.is_car_unlocked(id):
		_btn(c, "SELECT", Vector2(1020, 590), Vector2(170, 58), Callable(self, "_select_car").bind(id))
	else:
		var buy = _btn(c, "BUY $%d" % int(d["price"]), Vector2(1020, 590), Vector2(170, 58), Callable(self, "_buy_car").bind(id))
		buy.disabled = GameState.money < int(d["price"])
	_btn(c, "BACK", Vector2(70, 615), Vector2(170, 58), Callable(self, "show_menu"))
	_btn(c, "TRACK SELECT", Vector2(260, 615), Vector2(220, 58), Callable(self, "show_tracks"))
	set_screen(c)
func _prev_car():
	var ids := GameState.car_ids()
	garage_idx = (garage_idx - 1 + ids.size()) % ids.size()
	show_garage()
func _next_car():
	var ids := GameState.car_ids()
	garage_idx = (garage_idx + 1) % ids.size()
	show_garage()
func _select_car(id):
	GameState.select_car(id)
	show_garage()
func _buy_car(id):
	GameState.buy_car(id)
	show_garage()

func show_settings():
	var c := base("SETTINGS")
	_slider(c, "Music volume", "music_volume", 170, 0, 1)
	_slider(c, "SFX volume", "sfx_volume", 250, 0, 1)
	_slider(c, "Steering sensitivity", "steering_sensitivity", 330, .55, 1.45)
	for i in range(3):
		var q = ["Low", "Medium", "High"][i]
		_btn(c, q, Vector2(380 + i * 170, 450), Vector2(145, 54), Callable(self, "_set_quality").bind(q))
	_btn(c, "RESET PROGRESS", Vector2(380, 555), Vector2(250, 58), Callable(self, "_reset_and_settings"))
	_btn(c, "BACK", Vector2(670, 555), Vector2(180, 58), Callable(self, "show_menu"))
	set_screen(c)
func _set_quality(q):
	GameState.set_setting("graphics_quality", q)
	show_settings()
func _reset_and_settings():
	GameState.reset_progress()
	show_settings()
func _slider(c, title, key, y, minv, maxv):
	var l := Label.new()
	l.text = "%s: %.2f" % [title, float(GameState.settings[key])]
	l.position = Vector2(330, y)
	l.size = Vector2(290, 40)
	c.add_child(l)
	var s := HSlider.new()
	s.position = Vector2(630, y)
	s.size = Vector2(320, 40)
	s.min_value = minv
	s.max_value = maxv
	s.step = .05
	s.value = float(GameState.settings[key])
	c.add_child(s)
	s.value_changed.connect(_slider_changed.bind(l, title, key))
func _slider_changed(v, l, title, key):
	GameState.set_setting(key, v)
	l.text = "%s: %.2f" % [title, v]

func show_race(id = ""):
	if id != "":
		current_track = id
	var r := Race.new()
	r.track_id = current_track
	r.car_id = GameState.selected_car
	r.done.connect(Callable(self, "show_results"))
	r.restart.connect(Callable(self, "_restart_race"))
	r.garage.connect(Callable(self, "show_garage"))
	r.main.connect(Callable(self, "show_menu"))
	set_screen(r)
func _restart_race():
	show_race(current_track)
func show_results(track_id, result):
	var c := base("RESULTS")
	var d := GameState.get_track(track_id)
	var car := GameState.get_car(result["car_id"])
	var l := Label.new()
	l.text = "Track: %s\nCar: %s\nTime: %s\nBest: %s\nEarned: $%d\nScore: %d\nMax speed: %d km/h\nDrift score: %d" % [d["name"], car["name"], GameState.format_time(float(result["time"])), GameState.format_time(float(GameState.best_times[track_id])) if GameState.best_times.has(track_id) else "--:--.---", int(result["earned"]), int(result["score"]), int(result["max_speed_kmh"]), int(result["drift_score"])]
	l.position = Vector2(395, 155)
	l.size = Vector2(520, 300)
	l.add_theme_font_size_override("font_size", 25)
	c.add_child(l)
	_btn(c, "NEXT RACE", Vector2(280, 525), Vector2(200, 60), Callable(self, "next_race"))
	_btn(c, "GARAGE", Vector2(540, 525), Vector2(200, 60), Callable(self, "show_garage"))
	_btn(c, "MAIN MENU", Vector2(800, 525), Vector2(200, 60), Callable(self, "show_menu"))
	set_screen(c)
func next_race():
	var ids := GameState.track_ids()
	var i := ids.find(current_track)
	current_track = ids[(i + 1) % ids.size()]
	show_race(current_track)
