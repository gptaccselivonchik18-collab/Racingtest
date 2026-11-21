class_name VolleyFrameRate
extends Node

# A local display preference; room snapshots never change it.
var limit := 0

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 var saved := ConfigFile.new()
 if saved.load("user://display.cfg") == OK:
  limit = int(saved.get_value("display", "limit", 0))
 if limit not in [0, 60, 90, 120]:
  limit = 0
 apply()

func choose(value: int) -> void:
 if value not in [0, 60, 90, 120]:
  return
 limit = value
 var saved := ConfigFile.new()
 saved.set_value("display", "limit", limit)
 saved.save("user://display.cfg")
 apply()

func apply() -> void:
 if DisplayServer.get_name() == "headless":
  return
 # Never infer a 60 FPS cap from the host or from a temporarily reported
 # 60 Hz adaptive screen. Automatic means the device's native pacing.
 Engine.max_fps = limit
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
 if OS.get_name() == "Android" and Engine.has_singleton("AndroidRuntime"):
  var runtime = Engine.get_singleton("AndroidRuntime")
  var activity = runtime.getActivity()
  var requested := limit
  var update = func():
   var display = activity.getWindowManager().getDefaultDisplay()
   var current = display.getMode()
   var selected = current
   var highest := 0.0
   # Keep resolution unchanged; only select a supported physical refresh.
   for mode in display.getSupportedModes():
    if mode.getPhysicalWidth() == current.getPhysicalWidth() and mode.getPhysicalHeight() == current.getPhysicalHeight():
     var hz: float = mode.getRefreshRate()
     if hz > highest:
      highest = hz
      selected = mode
   if requested > 0:
    var nearest := INF
    for mode in display.getSupportedModes():
     if mode.getPhysicalWidth() == current.getPhysicalWidth() and mode.getPhysicalHeight() == current.getPhysicalHeight():
      var hz: float = mode.getRefreshRate()
      if hz >= requested - 0.5 and hz < nearest:
       selected = mode
       nearest = hz
   var window = activity.getWindow()
   var attributes = window.getAttributes()
   # Java reflection sets public LayoutParams fields on the UI thread.
   var fields = attributes.getClass()
   fields.getField("preferredDisplayModeId").setInt(attributes, selected.getModeId())
   fields.getField("preferredRefreshRate").setFloat(attributes, selected.getRefreshRate())
   window.setAttributes(attributes)
  activity.runOnUiThread(runtime.createRunnableFromGodotCallable(update))

func _notification(what: int) -> void:
 if what == NOTIFICATION_APPLICATION_RESUMED:
  apply()
