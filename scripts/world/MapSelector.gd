extends PanelContainer
class_name MapSelector

signal map_selected(map_id: StringName)
signal time_selected(time_id: StringName)

@onready var ashen_sands_button: Button = $VBoxContainer/BiomeSection/GridContainer/AshenSandsButton
@onready var emerald_fields_button: Button = $VBoxContainer/BiomeSection/GridContainer/EmeraldFieldsButton
@onready var polar_front_button: Button = $VBoxContainer/BiomeSection/GridContainer/PolarFrontButton
@onready var sakura_grove_button: Button = $VBoxContainer/BiomeSection/GridContainer/SakuraGroveButton
@onready var day_button: Button = $VBoxContainer/TimeSection/TimeGrid/DayButton
@onready var night_button: Button = $VBoxContainer/TimeSection/TimeGrid/NightButton
@onready var close_button: Button = $VBoxContainer/CloseButton

var _map_definitions: Dictionary = {}

func _ready() -> void:
	_load_map_definitions()
	_connect_signals()
	# Start hidden
	visible = false

func _load_map_definitions() -> void:
	# Use ResourceManifest for export-safe file listing
	ResourceManifest.ensure_initialized()
	for map_path in ResourceManifest.map_files:
		if ResourceLoader.exists(map_path):
			var map_def: MapDefinition = load(map_path)
			if map_def:
				_map_definitions[map_def.map_id] = map_def
				print("[MapSelector] Loaded map: ", map_def.map_id)
	print("[MapSelector] Total maps loaded: ", _map_definitions.size())

func _connect_signals() -> void:
	# Biome buttons
	if ashen_sands_button:
		ashen_sands_button.pressed.connect(_on_map_button_pressed.bind(&"ashen_sands"))
	if emerald_fields_button:
		emerald_fields_button.pressed.connect(_on_map_button_pressed.bind(&"emerald_fields"))
	if polar_front_button:
		polar_front_button.pressed.connect(_on_map_button_pressed.bind(&"polar_front"))
	if sakura_grove_button:
		sakura_grove_button.pressed.connect(_on_map_button_pressed.bind(&"sakura_grove"))
	
	# Time of day buttons
	if day_button:
		day_button.pressed.connect(_on_time_button_pressed.bind(&"day"))
	if night_button:
		night_button.pressed.connect(_on_time_button_pressed.bind(&"night"))
	
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

func _on_map_button_pressed(map_id: StringName) -> void:
	print("[MapSelector] Map button pressed: ", map_id)
	if _map_definitions.has(map_id):
		emit_signal("map_selected", map_id)
		visible = false
	else:
		push_warning("MapSelector: No map definition found for %s" % map_id)

func _on_time_button_pressed(time_id: StringName) -> void:
	print("[MapSelector] Time button pressed: ", time_id)
	emit_signal("time_selected", time_id)
	visible = false

func _on_close_pressed() -> void:
	visible = false

func show_selector() -> void:
	print("[MapSelector] Showing selector")
	visible = true
