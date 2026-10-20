class_name VolleyLowerServe
extends Control

var game: Node3D
var panel: PanelContainer
var content: VBoxContainer
var top_camera: Camera3D
var height := 3.0
var stage := 0
var source_side := 1.0
var busy_actor: ContextAthlete
var elapsed := 0.0
var released := false
var struck := false
var rng := RandomNumberGenerator.new()
var target := Vector3.ZERO
var slipped := false
var slip_angle := 0.0
var launch_scale := 1.0

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 top_camera = Camera3D.new()
 top_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 top_camera.size = 11.3
 top_camera.near = 0.1
 game.add_child(top_camera)
 panel = PanelContainer.new()
 panel.add_theme_stylebox_override("panel", game.hud._panel(Color("132b3c"), 20))
 add_child(panel)
 content = VBoxContainer.new()
 content.add_theme_constant_override("separation", 8)
 panel.add_child(content)
 resized.connect(_layout)
 _layout()
 rng.randomize()
 hide()

func _process(_dt: float) -> void:
 if visible:
  _layout()

func _layout() -> void:
 if stage == 0:
  panel.position = Vector2(size.x * 0.15, 12)
  panel.size = Vector2(size.x * 0.70, 0)
 else:
  panel.position = Vector2(12, 12)
  panel.size = Vector2(minf(260, size.x * 0.28), 0)

func _clear() -> void:
 for child in content.get_children():
  content.remove_child(child)
  child.queue_free()

func _label(text: String) -> Label:
 var label := Label.new()
 label.text = text
 label.add_theme_font_size_override("font_size", 18)
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 content.add_child(label)
 return label

func serve_title() -> String:
 return "НИЖНЯЯ ПОДАЧА"

func network_role() -> String:
 return "lower_serve"

func height_hint() -> String:
 return "Низкая дуга может попасть в сетку. Направление выберете следующим касанием."

func open() -> bool:
 if not game.holding_ball() or game.automatic_serve_busy() or game.athlete.airborne():
  return false
 game.hud._cancel()
 game.hud.hide()
 source_side = 1.0 if game.athlete.position.z >= 0 else -1.0
 stage = 0
 show()
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 _clear()
 _label(serve_title())
 var value := _label("Высота дуги: +%.1f м от точки удара" % height)
 var slider := HSlider.new()
 slider.min_value = 0.8
 slider.max_value = 5.0
 slider.step = 0.1
 slider.value = height
 slider.custom_minimum_size.y = 40
 slider.value_changed.connect(func(v: float): height = v; value.text = "Высота дуги: +%.1f м от точки удара" % v)
 content.add_child(slider)
 _label(height_hint())
 game.hud._native_button(content, "Выбрать место на стороне соперника →", choose_target)
 game.hud._native_button(content, "Отмена", close)
 _layout()
 return true

func choose_target() -> void:
 stage = 1
 _clear()
 _label("ЦЕЛЬ ПОДАЧИ\nКоснитесь поля соперника")
 game.hud._native_button(content, "← Высота / отмена", func(): close(); open())
 var center := Vector3(0, 0, -source_side * 4.5)
 # The enclosure has a ceiling at 12 m: an outside camera sees the roof.
 top_camera.position = center + Vector3.UP * 10
 top_camera.look_at(center, Vector3(0, 0, -source_side))
 # Reserve a sidebar; the controls must not cover selectable court areas.
 top_camera.h_offset = -top_camera.size * (size.x / maxf(1, size.y)) * 0.14
 top_camera.current = true
 _layout()


func opposite_target(point: Vector3, side: float) -> bool:
 return point.is_finite() and absf(point.x) <= 4.5 and point.z * side <= -0.15 and point.z * side >= -9.0

func target_from_screen(at: Vector2) -> Variant:
 var plane := Plane(Vector3.UP, VolleyBall.RADIUS)
 var point: Variant = plane.intersects_ray(top_camera.project_ray_origin(at), top_camera.project_ray_normal(at))
 return point if point is Vector3 and opposite_target(point, source_side) else null

func _input(event: InputEvent) -> void:
 if not visible:
  return
 if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
  close()
  get_viewport().set_input_as_handled()
  return
 var at := Vector2.ZERO
 var tapped := false
 if event is InputEventScreenTouch and event.pressed and not event.canceled:
  at = event.position
  tapped = true
 elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
  at = event.position
  tapped = true
 if stage == 1 and tapped and not panel.get_global_rect().has_point(at):
  var point: Variant = target_from_screen(at)
  if point is Vector3:
   close()
   if game.lan.active:
    game.lan.local_action(network_role(), "press", {"aim": point, "apex": height})
   else:
    launch(game.athlete, point, height)
  get_viewport().set_input_as_handled()

func close() -> void:
 hide()
 game.hud.show()
 top_camera.current = false
 game.camera.current = true
 game.hud._cancel()
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.get_name() in ["iOS", "Android"] else Input.MOUSE_MODE_CAPTURED

func sample_error(aim: Vector3, accuracy: float, gain := 1.0, execution_level := 2, bot := false) -> Dictionary:
 var policy := VolleyBotDifficulty.execution(execution_level,bot)
 var scatter := lerpf(1.15, 0.15, accuracy) * float(policy.scatter) / gain
 var aim_error := Vector3(rng.randfn(0, scatter), 0, rng.randfn(0, scatter * 1.2))
 var slip := rng.randf() < float(policy.fault) * lerpf(1.8, 0.25, accuracy) / gain
 return {"target": aim + aim_error, "slip": slip, "angle": rng.randf_range(-0.55, 0.55), "scale": rng.randf_range(0.65, 0.9) if slip else rng.randf_range(1.0 - lerpf(0.04, 0.004, accuracy) * float(policy.scatter), 1.0 + lerpf(0.04, 0.004, accuracy) * float(policy.scatter))}

func launch(actor: ContextAthlete, aim: Vector3, apex: float) -> bool:
 var side := 1.0 if actor.position.z >= 0 else -1.0
 if (not VolleyRoles.can_serve(actor) and VolleyRules.in_service_zone(actor.service_origin())) or game.automatic_serve_busy() or not game.ball.held or game.ball.athlete != actor or not opposite_target(aim, side) or not is_finite(apex):
  return false
 height = clampf(apex, 0.8, 5.0)
 var skill := "serve" if VolleyRules.in_service_zone(actor.service_origin()) else "bump"
 var error := sample_error(aim, actor.style_stats.n(skill), actor.style_stats.factor(skill), actor.execution_level,actor.bot_execution)
 target = error.target
 slipped = error.slip
 slip_angle = error.angle
 launch_scale = error.scale
 game.formation.authorize_server(actor)
 busy_actor = actor
 actor.cancel_input()
 actor.move_axis = Vector2.ZERO
 actor.velocity.x = 0
 actor.velocity.z = 0
 var delta := aim - actor.position
 actor.visual.rotation.y = atan2(-delta.x, -delta.z)
 actor.camera_yaw = actor.visual.rotation.y
 if actor == game.athlete:
  game.rig.yaw = actor.camera_yaw
 actor.action = VolleyAthlete.Action.PREPARE
 actor.technique = VolleyAthlete.Technique.UNDERHAND
 actor.action_time = 0
 actor.lower_serve_active = true
 actor.last_result = "Нижняя подача • подброс и замах"
 game.serving = VolleyRules.in_service_zone(actor.service_origin())
 if not game.rules.strict:
  game.rules.reset(game.serving)
 elapsed = 0
 released = false
 struck = false
 return true

func cancel_sequence() -> void:
 if is_instance_valid(busy_actor):
  busy_actor.lower_serve_active = false
  busy_actor.cancel_input()
  busy_actor.action = VolleyAthlete.Action.IDLE
 busy_actor = null
 elapsed = 0

func _physics_process(dt: float) -> void:
 if not is_instance_valid(busy_actor):
  return
 var actor := busy_actor
 elapsed += dt
 actor.move_axis = Vector2.ZERO
 actor.velocity.x = 0
 actor.velocity.z = 0
 if elapsed >= 0.12 and not released:
  released = true
  var release_at := actor.visual.to_global(Vector3(0, 1.02, -0.55))
  game.ball.feed(release_at, Vector3.UP * 1.35)
 if elapsed >= 0.22 and not struck:
  struck = true
  actor.technique = VolleyAthlete.Technique.UNDERHAND
  actor.action = VolleyAthlete.Action.STRIKE
  actor.strike_technique = VolleyAthlete.Technique.UNDERHAND
  actor.strike_duration = 0.42
  actor.action_time = 0
  actor.hit_used = false
  actor.strike_count += 1
 # Automatic swing still has to meet the freely tossed ball with the platform.
 if released and struck and not actor.hit_used and actor.contact_active() and actor.intersects_ball(game.ball.position):
  var speed: Vector3 = game.ball.solve_launch(game.ball.position, target, height)
  if slipped:
   speed = speed.rotated(Vector3.UP, slip_angle) * launch_scale
  else:
   speed *= launch_scale
  actor.hit_used = true
  actor.contact_count += 1
  actor.last_result = "Нижняя подача • соскальзывание" if slipped else "Нижняя подача • мяч в игре"
  game.ball.feed(game.ball.position, speed)
  var kind := VolleyAthlete.Technique.SERVE if VolleyRules.in_service_zone(actor.service_origin()) else VolleyAthlete.Technique.UNDERHAND
  game._on_player_touch(actor, game.lan.player_id(actor), kind, game.ball.position, speed)
 if elapsed >= 0.9:
  if not actor.hit_used:
   actor.last_result = "Нижняя подача • промах при подбросе"
  actor.lower_serve_active = false
  busy_actor = null
