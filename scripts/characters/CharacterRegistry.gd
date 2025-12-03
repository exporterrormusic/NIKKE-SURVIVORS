class_name CharacterRegistry
extends RefCounted
## Registry that manages all playable characters.
## Loads character data and provides access to controllers.

# Preload class scripts
const CharacterDataScript = preload("res://scripts/characters/CharacterData.gd")
const CharacterControllerScript = preload("res://scripts/characters/CharacterController.gd")

# Singleton-style access
static var _instance: CharacterRegistry = null

# All registered characters (by ID)
var _characters: Dictionary = {}

# Character order (for UI)
var _character_order: Array[String] = []

# Controller scripts
const CONTROLLER_SCRIPTS = {
	"scarlet": preload("res://scripts/characters/ScarletController.gd"),
	"snow_white": preload("res://scripts/characters/SnowWhiteController.gd"),
	"rapunzel": preload("res://scripts/characters/RapunzelController.gd"),
	"kilo": preload("res://scripts/characters/KiloController.gd"),
	"sin": preload("res://scripts/characters/SinController.gd"),
	"crown": preload("res://scripts/characters/CrownController.gd"),
	"commander": preload("res://scripts/characters/CommanderController.gd"),
	"marian": preload("res://scripts/characters/MarianController.gd"),
	"cecil": preload("res://scripts/characters/CecilController.gd"),
	"nayuta": preload("res://scripts/characters/NayutaController.gd"),
}

## Get the singleton instance
static func get_instance() -> CharacterRegistry:
	if _instance == null:
		_instance = CharacterRegistry.new()
		_instance._load_all_characters()
	return _instance

## Load all character data from resources
func _load_all_characters() -> void:
	# Define characters in order (this determines UI order)
	_register_character("scarlet", {
		"display_name": "Scarlet",
		"description": "Melee fighter who sacrifices HP for power",
		"sprite_path": "scarlet-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.mp3",
		"primary_color": Color(0.9, 0.3, 0.3),
		"secondary_color": Color(0.6, 0.1, 0.1),
		"burst_color": Color(1.0, 0.2, 0.2),
		"base_speed": 180.0,
		"base_hp": 10,
		"base_damage": 10.0,
		"weapon_type": 0,  # Melee
		"ammo_capacity": -1,
		"attack_cooldown": 0.3,
	})
	
	_register_character("commander", {
		"display_name": "Legendary Commander",
		"description": "Leader with time control and ally summoning",
		"sprite_path": "commander-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.mp3",
		"primary_color": Color(0.72, 0.45, 0.22),
		"secondary_color": Color(0.5, 0.3, 0.15),
		"burst_color": Color(1.0, 0.84, 0.28),
		"base_speed": 150.0,
		"base_hp": 10,
		"base_damage": 8.0,
		"weapon_type": 6,  # Assault Rifle
		"ammo_capacity": 30,
		"reload_time": 2.0,
		"attack_cooldown": 0.2,  # Slower than SMG/Minigun but auto-fires
		"projectile_speed": 900.0,
	})
	
	_register_character("rapunzel", {
		"display_name": "Rapunzel",
		"description": "Rocket launcher with healing abilities",
		"sprite_path": "rapunzel-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.mp3",
		"primary_color": Color(1.0, 0.85, 0.3),
		"secondary_color": Color(0.8, 0.6, 0.1),
		"burst_color": Color(1.0, 0.95, 0.5),
		"base_speed": 140.0,
		"base_hp": 12,
		"base_damage": 25.0,
		"weapon_type": 2,  # Launcher
		"ammo_capacity": 4,
		"reload_time": 3.0,
		"attack_cooldown": 0.5,
		"projectile_speed": 400.0,
	})
	
	_register_character("kilo", {
		"display_name": "Kilo",
		"description": "Shotgun specialist with explosive blasts",
		"sprite_path": "kilo-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.mp3",
		"primary_color": Color(1.0, 0.5, 0.2),
		"secondary_color": Color(0.8, 0.3, 0.1),
		"burst_color": Color(1.0, 0.6, 0.3),
		"base_speed": 150.0,
		"base_hp": 10,
		"base_damage": 35.0,
		"weapon_type": 3,  # Shotgun
		"ammo_capacity": 8,
		"reload_time": 2.5,
		"attack_cooldown": 0.4,
		"projectile_speed": 850.0,
		"projectile_count": 5,
		"projectile_spread": 15.0,
	})
	
	_register_character("marian", {
		"display_name": "Marian",
		"description": "Minigun with charm and epic beam burst",
		"sprite_path": "marian-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.mp3",
		"primary_color": Color(0.5, 0.2, 0.8),
		"secondary_color": Color(0.3, 0.1, 0.5),
		"burst_color": Color(0.7, 0.3, 1.0),
		"base_speed": 140.0,
		"base_hp": 10,
		"base_damage": 2.0,
		"weapon_type": 5,  # Minigun
		"ammo_capacity": 100,
		"reload_time": 3.5,
		"attack_cooldown": 0.06,
		"projectile_speed": 1100.0,
	})
	
	_register_character("crown", {
		"display_name": "Crown",
		"description": "Minigun cavalry with golden nova burst",
		"sprite_path": "crown-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.wav",
		"primary_color": Color(1.0, 0.85, 0.3),
		"secondary_color": Color(0.8, 0.65, 0.1),
		"burst_color": Color(1.0, 0.95, 0.5),
		"base_speed": 145.0,
		"base_hp": 12,
		"base_damage": 2.0,
		"weapon_type": 5,  # Minigun
		"ammo_capacity": 100,
		"reload_time": 3.5,
		"attack_cooldown": 0.06,
		"projectile_speed": 1100.0,
	})
	
	_register_character("snow_white", {
		"display_name": "Snow White",
		"description": "Sniper with piercing shots and turrets",
		"sprite_path": "snow-white-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.mp3",
		"primary_color": Color(0.4, 0.7, 1.0),
		"secondary_color": Color(0.2, 0.4, 0.8),
		"burst_color": Color(0.6, 0.9, 1.0),
		"base_speed": 150.0,
		"base_hp": 10,
		"base_damage": 15.0,
		"weapon_type": 1,  # Rifle
		"ammo_capacity": 7,
		"reload_time": 1.5,
		"attack_cooldown": 0.35,
		"projectile_speed": 1650.0,
	})
	
	_register_character("sin", {
		"display_name": "Sin",
		"description": "SMG with charm and life drain abilities",
		"sprite_path": "sin-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.mp3",
		"primary_color": Color(0.7, 0.2, 0.9),
		"secondary_color": Color(0.5, 0.1, 0.7),
		"burst_color": Color(0.85, 0.4, 0.95),
		"base_speed": 160.0,
		"base_hp": 8,
		"base_damage": 2.0,
		"weapon_type": 4,  # Dual SMG
		"ammo_capacity": 45,
		"reload_time": 2.0,
		"attack_cooldown": 0.08,
		"projectile_speed": 900.0,
	})
	
	_register_character("cecil", {
		"display_name": "Cecil",
		"description": "SMG with drone robots and hacking burst",
		"sprite_path": "cecil-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.mp3",
		"primary_color": Color(0.2, 0.6, 1.0),
		"secondary_color": Color(0.1, 0.4, 0.8),
		"burst_color": Color(0.4, 0.8, 1.0),
		"base_speed": 155.0,
		"base_hp": 9,
		"base_damage": 2.0,
		"weapon_type": 4,  # Dual SMG
		"ammo_capacity": 45,
		"reload_time": 2.0,
		"attack_cooldown": 0.08,
		"projectile_speed": 900.0,
	})
	
	_register_character("nayuta", {
		"display_name": "Nayuta",
		"description": "SMG with clone summoning and galaxy burst",
		"sprite_path": "nayuta-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.mp3",
		"primary_color": Color(0.6, 0.3, 0.9),
		"secondary_color": Color(0.4, 0.15, 0.7),
		"burst_color": Color(0.7, 0.4, 1.0),
		"base_speed": 160.0,
		"base_hp": 10,
		"base_damage": 2.0,
		"weapon_type": 4,  # Dual SMG
		"ammo_capacity": 45,
		"reload_time": 2.0,
		"attack_cooldown": 0.08,
		"projectile_speed": 900.0,
	})

## Register a character with given data
func _register_character(id: String, config: Dictionary) -> void:
	var data = CharacterDataScript.new()
	data.id = id
	
	# Apply all config values
	for key in config:
		if key in data:
			data.set(key, config[key])
	
	# Set controller script path
	data.controller_script = "res://scripts/characters/%sController.gd" % id.capitalize().replace("_", "")
	
	_characters[id] = data
	_character_order.append(id)

## Get character data by ID
func get_character(id: String) -> Resource:  # CharacterData
	return _characters.get(id)

## Get character data by index
func get_character_by_index(index: int) -> Resource:  # CharacterData
	if index >= 0 and index < _character_order.size():
		return _characters.get(_character_order[index])
	return null

## Get character index by ID
func get_character_index(id: String) -> int:
	return _character_order.find(id)

## Get total number of characters
func get_character_count() -> int:
	return _character_order.size()

## Get all character IDs in order
func get_all_character_ids() -> Array[String]:
	return _character_order.duplicate()

## Create a new controller instance for a character
func create_controller(id: String, player: Node2D) -> RefCounted:  # CharacterController
	var data = get_character(id)
	if data == null:
		push_error("CharacterRegistry: Unknown character ID: %s" % id)
		return null
	
	var script = CONTROLLER_SCRIPTS.get(id)
	if script == null:
		push_error("CharacterRegistry: No controller script for: %s" % id)
		return null
	
	var controller = script.new()
	controller.initialize(player, data)
	return controller

## Create controller by index
func create_controller_by_index(index: int, player: Node2D) -> RefCounted:  # CharacterController
	if index >= 0 and index < _character_order.size():
		return create_controller(_character_order[index], player)
	return null

## Get character sprite texture
func get_sprite(id: String) -> Texture2D:
	var data = get_character(id)
	if data:
		return data.get_sprite()
	return null

## Get character portrait texture
func get_portrait(id: String) -> Texture2D:
	var data = get_character(id)
	if data:
		return data.get_portrait()
	return null

## Get character burst sound
func get_burst_sound(id: String) -> AudioStream:
	var data = get_character(id)
	if data:
		return data.get_burst_sound()
	return null
