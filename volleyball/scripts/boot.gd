extends Node

const GAME := "res://scenes/Main.tscn"
const INTRO_SECONDS := 0.85
var screen: Control
var bar: ProgressBar
var caption: Label
var begun := 0
var failed := false

func _ready() -> void:
 if OS.get_name() in ["iOS", "Android"]:
  DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
 var layer := CanvasLayer.new()
 layer.layer = 100
 add_child(layer)
 screen = Control.new()
 screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 layer.add_child(screen)
 var art := VolleyMenuArt.new()
 art.show_ball = false
 screen.add_child(art)
 var center := CenterContainer.new()
 center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 screen.add_child(center)
 var column := VBoxContainer.new()
 column.custom_minimum_size.x = 330
 column.add_theme_constant_override("separation", 18)
 center.add_child(column)
 var brand := Label.new()
 brand.text = "VOLLEY / LAB"
 brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 brand.add_theme_font_override("font", VolleyMenuArt.typeface(800))
 brand.add_theme_font_size_override("font_size", 42)
 brand.add_theme_color_override("font_color", Color("d9f36b"))
 column.add_child(brand)
 bar = ProgressBar.new()
 bar.custom_minimum_size.y = 5
 bar.show_percentage = false
 for entry in [["background", Color("203d4c")], ["fill", Color("f18b58")]]:
  var style := VolleyMenuArt.panel(entry[1], 3)
  style.set_content_margin_all(0)
  bar.add_theme_stylebox_override(entry[0], style)
 column.add_child(bar)
 caption = Label.new()
 caption.text = "Запускаем игру"
 caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 caption.add_theme_font_size_override("font_size", 16)
 caption.add_theme_color_override("font_color", Color("a4bac2"))
 column.add_child(caption)
 var author := Label.new()
 author.text = "by Selivonchyk Alexey"
 author.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 author.add_theme_font_size_override("font_size", 15)
 author.add_theme_color_override("font_color", Color("a4bac2"))
 screen.add_child(author)
 author.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
 author.offset_left = 0
 author.offset_right = 0
 author.offset_top = -48
 author.offset_bottom = -20
 begun = Time.get_ticks_msec()
 if ResourceLoader.load_threaded_request(GAME) != OK:
  _fail()

func _process(_dt: float) -> void:
 if failed:
  return
 var progress: Array = []
 var status := ResourceLoader.load_threaded_get_status(GAME, progress)
 if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
  _fail()
  return
 var intro := clampf((Time.get_ticks_msec() - begun) / (INTRO_SECONDS * 1000.0), 0, 1)
 var loaded := 1.0 if status == ResourceLoader.THREAD_LOAD_LOADED else float(progress[0]) if not progress.is_empty() else 0.0
 bar.value = minf(intro, loaded) * 100.0
 if status == ResourceLoader.THREAD_LOAD_LOADED and intro >= 1:
  set_process(false)
  caption.text = "Открываем площадку"
  call_deferred("_open_game")

func _open_game() -> void:
 # Keep the drawn splash on screen while the scene creates its court/players.
 await get_tree().process_frame
 var scene := ResourceLoader.load_threaded_get(GAME) as PackedScene
 if scene == null:
  _fail()
  return
 var game := scene.instantiate()
 get_tree().root.add_child(game)
 get_tree().current_scene = game
 var fade := create_tween()
 fade.tween_property(screen, "modulate:a", 0.0, 0.18)
 fade.tween_callback(queue_free)
 print("VOLLEY_BOOT_READY")

func _fail() -> void:
 failed = true
 caption.text = "Не удалось открыть игру. Перезапустите приложение."
 push_error("Unable to load volleyball main scene")

