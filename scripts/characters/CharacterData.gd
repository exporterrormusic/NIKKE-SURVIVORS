class_name CharacterData
extends Resource
## Data container for character configuration.
## Each character has a .tres file in resources/characters/ that defines their stats.

# Basic Info
@export var id: String = ""  # Unique identifier (e.g., "scarlet", "snow_white")
@export var folder_name: String = ""  # Folder name in assets/characters/ (e.g., "snow-white")
@export var display_name: String = ""  # Display name (e.g., "Scarlet", "Snow White")
@export var description: String = ""

# Asset Paths (relative to res://assets/characters/{id}/)
@export var sprite_path: String = "sprite.png"
@export var portrait_path: String = "portrait-sq.png"
@export var burst_sound_path: String = "burst.mp3"

# Colors
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.GRAY
@export var burst_color: Color = Color.WHITE

# Base Stats
@export var base_speed: float = 150.0
@export var base_hp: int = 10
@export var base_damage: float = 10.0

# Weapon Config
@export_enum("Melee", "Rifle", "Launcher", "Shotgun") var weapon_type: int = 0
@export var ammo_capacity: int = -1  # -1 = unlimited
@export var reload_time: float = 1.5
@export var attack_cooldown: float = 0.3
@export var projectile_speed: float = 800.0
@export var projectile_count: int = 1  # For shotguns
@export var projectile_spread: float = 0.0  # Degrees

# Special Attack Config
@export var special_cooldown: float = 3.0
@export var special_name: String = ""
@export var special_description: String = ""

# Burst Config
@export var burst_name: String = ""
@export var burst_description: String = ""
@export var burst_duration: float = 5.0
@export var burst_damage_multiplier: float = 2.0

# Controller Script Path
@export var controller_script: String = ""

# Talent tree data - which talents this character has
@export var talents: Array[Dictionary] = []

## Get the full asset path for this character
func get_asset_path(filename: String) -> String:
	var folder = folder_name if not folder_name.is_empty() else id.replace("_", "-")
	return "res://assets/characters/%s/%s" % [folder, filename]

## Get the sprite texture
func get_sprite() -> Texture2D:
	var path = get_asset_path(sprite_path)
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Get the portrait texture
func get_portrait() -> Texture2D:
	var path = get_asset_path(portrait_path)
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Get the burst sound
func get_burst_sound() -> AudioStream:
	var path = get_asset_path(burst_sound_path)
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Get the controller script
func get_controller() -> Script:
	if controller_script.is_empty():
		return null
	if ResourceLoader.exists(controller_script):
		return load(controller_script)
	return null
