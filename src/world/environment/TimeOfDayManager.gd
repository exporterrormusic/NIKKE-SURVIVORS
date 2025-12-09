extends Node
class_name TimeOfDayManager
## Manages time of day transitions and lighting.
##
## Extracted from EnvironmentController for cleaner separation.
## Handles day/night cycle, CanvasModulate colors, and sun lighting.

signal time_of_day_changed(time_id: StringName)

const TIME_OF_DAY_DIR := "res://resources/time_of_day/"

var time_definitions: Array = []
var _time_lookup: Dictionary = {}
var _active_time: TimeOfDayDefinition = null
var _canvas_modulate: CanvasModulate = null
var _sun_light: DirectionalLight2D = null


## Load all time of day definitions from resources
func load_times() -> void:
	time_definitions.clear()
	_time_lookup.clear()
	
	var dir := DirAccess.open(TIME_OF_DAY_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var path := TIME_OF_DAY_DIR + file_name
				var time := load(path) as TimeOfDayDefinition
				if time:
					time_definitions.append(time)
			file_name = dir.get_next()
		dir.list_dir_end()
	
	_rebuild_lookup()
	print("[TimeOfDayManager] Loaded ", time_definitions.size(), " times of day")


## Rebuild time lookup dictionary
func _rebuild_lookup() -> void:
	_time_lookup.clear()
	for time in time_definitions:
		if time is TimeOfDayDefinition:
			_time_lookup[time.time_id] = time


## Get time by ID
func get_time(time_id: StringName) -> TimeOfDayDefinition:
	if _time_lookup.has(time_id):
		return _time_lookup[time_id]
	return null


## Set active time of day
func set_active_time(time_id: StringName) -> TimeOfDayDefinition:
	var time := get_time(time_id)
	if time:
		_active_time = time
		_apply_time_settings()
		time_of_day_changed.emit(time_id)
	return time


## Get active time
func get_active_time() -> TimeOfDayDefinition:
	return _active_time


## Set canvas modulate reference
func set_canvas_modulate(modulate: CanvasModulate) -> void:
	_canvas_modulate = modulate


## Set sun light reference
func set_sun_light(sun: DirectionalLight2D) -> void:
	_sun_light = sun


## Apply time of day settings to canvas modulate and sun
func _apply_time_settings() -> void:
	if not _active_time:
		return
	
	# Apply canvas modulate color
	if _canvas_modulate:
		_canvas_modulate.color = _active_time.modulate_color
	
	# Apply sun light settings
	if _sun_light:
		_sun_light.enabled = _active_time.sun_enabled
		if _active_time.sun_enabled:
			_sun_light.energy = _active_time.sun_energy
			_sun_light.color = _active_time.sun_color


## Get random time
func get_random_time(rng: RandomNumberGenerator) -> TimeOfDayDefinition:
	if time_definitions.is_empty():
		return null
	var idx := rng.randi_range(0, time_definitions.size() - 1)
	return time_definitions[idx]


## Get all time IDs
func get_time_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for time in time_definitions:
		if time is TimeOfDayDefinition:
			ids.append(time.time_id)
	return ids
