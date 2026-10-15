extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
 call_deferred("run")
func check(ok: bool, text: String) -> void:
 checks += 1
 if ok:
  print("PASS: ", text)
 else:
  failures += 1
  push_error("FAIL: " + text)
func frames(n: int) -> void:
 for i in range(n):
  await physics_frame
func run() -> void:
 var game: Node3D = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 game.frontend.start_solo()
 await frames(20)
 var ui: VolleyHUD = game.hud
 var a: ContextAthlete = game.athlete
 ui.settings.layout.clear()
 ui.settings.button_scale = 1
 ui._layout()
 ui._process(0)
 ui._touch_down(1, ui.left_center + Vector2(25, 0))
 ui._touch_down(2, Vector2(700, 250))
 ui._touch_down(3, ui.buttons.jump.rect.get_center())
 ui._touch_down(4, ui.buttons.primary.rect.get_center())
 check(ui.move_id == 1 and ui.camera_id == 2 and ui.fingers.size() == 4, "Four simultaneous fingers independently captured")
 check(a.airborne() and a.action == VolleyAthlete.Action.PREPARE and a.technique == 2, "Jump and attack work while moving and turning")
 var yaw_before: float = game.rig.yaw
 ui._touch_move(2, Vector2(740, 250), Vector2(40, 0))
 check(game.rig.yaw != yaw_before and ui.move_id == 1, "Camera swipe preserves movement capture")
 var swings := a.strike_count
 ui._touch_up(4)
 check(a.strike_count == swings + 1 and ui.move_id == 1 and ui.camera_id == 2, "Attack release preserves other fingers")
 ui._touch_up(2)
 check(ui.camera_id == -1 and ui.move_id == 1, "Camera release independent of movement")
 ui._touch_up(1)
 ui._touch_up(3)
 check(ui.move_value == Vector2.ZERO and ui.fingers.is_empty(), "All fingers release without stuck state")
 a.action = VolleyAthlete.Action.IDLE
 ui._touch_down(5, ui.buttons.primary.rect.get_center())
 swings = a.strike_count
 ui._touch_up(5, true)
 check(a.action == VolleyAthlete.Action.IDLE and a.strike_count == swings, "OS canceled finger cannot trigger a hit")
 ui._touch_down(6, ui.buttons.primary.rect.get_center())
 ui._touch_up(99, true)
 check(a.action == VolleyAthlete.Action.PREPARE, "Unknown canceled touch does not cancel held action")
 ui._cancel()
 check(a.action == VolleyAthlete.Action.IDLE and ui.fingers.is_empty(), "Focus loss clears all holds")
 var mouse := InputEventMouseButton.new()
 mouse.device = InputEvent.DEVICE_ID_EMULATION
 mouse.button_index = MOUSE_BUTTON_LEFT
 mouse.pressed = true
 mouse.position = ui.buttons.primary.rect.get_center()
 ui._input(mouse)
 check(a.action == VolleyAthlete.Action.IDLE, "Emulated mouse does not duplicate a real finger")
 # Conflicting action fingers cannot release somebody else's charged action.
 game.begin_primary()
 game.begin_secondary()
 game.finish_action("secondary")
 check(a.action == VolleyAthlete.Action.PREPARE and game.action_owner == "primary", "Other action release cannot release primary charge")
 game.cancel_action("")
 ui.toggle_menu()
 check(paused and ui.menu.visible, "Menu pauses gameplay")
 await process_frame
 await process_frame
 var menu_content := ui.menu.get_child(0)
 var resume := menu_content.get_child(menu_content.get_child_count() - 1) as Button
 var native_click := InputEventMouseButton.new()
 native_click.device = InputEvent.DEVICE_ID_EMULATION
 native_click.button_index = MOUSE_BUTTON_LEFT
 native_click.position = resume.get_global_rect().get_center()
 native_click.global_position = native_click.position
 native_click.pressed = true
 root.push_input(native_click, true)
 await process_frame
 native_click.pressed = false
 root.push_input(native_click, true)
 await process_frame
 check(not paused and not ui.menu.visible, "Native Resume receives emulated touch mouse while paused")
 ui.toggle_menu()
 ui.stat_sliders.strength.value = 91
 ui.control_sliders.sensitivity.value = 1.4
 check(a.stats.values.strength == 91 and is_equal_approx(game.rig.sensitivity, 1.4), "Native settings controls work while paused")
 var cfg := VolleySettings.new()
 cfg.load_settings(a)
 check(is_equal_approx(cfg.sensitivity, 1.4), "Camera settings persist")
 check(not ui.settings.rebind("jump", KEY_W), "Conflicting key rejected")
 check(ui.settings.rebind("jump", KEY_J), "Key can be rebound")
 ui._save()
 cfg.load_settings(a)
 check(cfg.keys.jump == KEY_J, "Custom key survives reload")
 check(ui.settings.rebind("primary", KEY_C), "Primary action can move from mouse to keyboard")
 ui.settings.keys.jump = KEY_SPACE
 ui.settings.install_keys()
 ui.start_editor()
 check(ui.edit_mode and paused and not ui.menu.visible, "HUD editor pauses game and exposes controls")
 var target := Vector2(940, 550)
 ui._touch_down(7, ui.buttons.primary.rect.get_center())
 ui._touch_move(7, target)
 ui._touch_up(7)
 ui.editor_scale.value = 1.15
 ui.end_editor()
 cfg.load_settings(a)
 check(cfg.layout.has("primary") and absf(cfg.layout.primary.x - target.x / ui.size.x) < 0.001 and is_equal_approx(cfg.layout.primary.z, 1.15), "Dragged button location and size persist")
 ui.toggle_menu()
 check(not paused, "Resume works after HUD editor")
 # Default HUD has one movement stick and no old persistent controls.
 check(not ui.buttons.has("tech_0") and not ui.buttons.has("sprint"), "Old technique buttons and Sprint removed")
 a.action = VolleyAthlete.Action.IDLE
 a.velocity = Vector3.ZERO
 await frames(140)
 ui._process(0)
 check(not ui.buttons.jump_set.visible, "Jump Set button hidden on ground")
 a.jump()
 ui._process(0)
 check(ui.buttons.jump_set.visible and ui.buttons.secondary.text == "БЛОК", "Airborne context updates labels and Jump Set")
 ui._cancel()
 a.action = VolleyAthlete.Action.IDLE
 var rebound_key := InputEventKey.new()
 rebound_key.physical_keycode = KEY_C
 rebound_key.pressed = true
 ui._input(rebound_key)
 check(a.action == VolleyAthlete.Action.PREPARE, "Rebound primary keyboard starts actual gameplay action")
 rebound_key.pressed = false
 ui._input(rebound_key)
 check(a.action == VolleyAthlete.Action.STRIKE, "Rebound primary release executes actual swing")
 # Restore defaults so tests do not change a developer's next launch.
 ui.settings = VolleySettings.new()
 ui.settings.install_keys()
 ui.settings.save(a)
 print("V2 TESTS PASSED (%d context HUD checks)" % checks if failures == 0 else "FAILED %d / %d" % [failures, checks])
 game.queue_free()
 await process_frame
 quit(0 if failures == 0 else 1)
