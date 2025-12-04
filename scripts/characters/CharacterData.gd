class_name CharacterData
extends Resource
## Data container for character configuration.
## Each character has a .tres file in resources/characters/ that defines their stats.
## Used by both gameplay systems and the character select UI.

# =============================================================================
# IDENTITY
# =============================================================================
@export_group("Identity")
@export var id: String = ""  # Unique identifier (e.g., "scarlet", "snow_white")
@export var code_name: String = ""  # Alternative identifier for lookups
@export var folder_name: String = ""  # Folder name in assets/characters/ (e.g., "snow-white")
@export var display_name: String = ""  # Display name (e.g., "Scarlet", "Snow White")
@export_multiline var description: String = ""
@export var role: String = "Balanced"  # e.g., "DPS", "Tank", "Support"
@export var difficulty: String = "Standard"  # e.g., "Easy", "Standard", "Expert"
@export var is_unlocked: bool = true  # Whether available in character select

# =============================================================================
# ASSET PATHS (relative to res://assets/characters/{folder}/)
# =============================================================================
@export_group("Asset Paths")
@export var sprite_path: String = "sprite.png"
@export var portrait_path: String = "portrait-sq.png"
@export var burst_texture_path: String = "burst.png"
@export var burst_sound_path: String = "burst.wav"

# Pre-loaded textures (optional - used by UI if set, otherwise loaded from paths)
@export var portrait_texture: Texture2D
@export var burst_texture: Texture2D
@export var sprite_sheet: Texture2D

# Sprite sheet animation config
@export var sprite_sheet_columns: int = 1
@export var sprite_sheet_rows: int = 1
@export var sprite_animation_fps: float = 6.0
@export var sprite_scale: float = 0.2

# =============================================================================
# COLORS
# =============================================================================
@export_group("Colors")
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.GRAY
@export var burst_color: Color = Color.WHITE
@export var projectile_color: Color = Color(1.0, 0.9, 0.4, 1.0)

# =============================================================================
# STAT RATINGS (for UI display - 0-500 scale typically)
# =============================================================================
@export_group("Stat Ratings")
@export var hp: int = 250  # HP rating for UI
@export var attack: int = 75  # Attack rating for UI
@export var speed_rating: int = 250  # Speed rating for UI
@export var burst_rating: int = 5  # Burst power rating for UI

# =============================================================================
# BASE STATS (gameplay values)
# =============================================================================
@export_group("Base Stats")
@export var base_speed: float = 150.0
@export var move_speed: float = 400.0  # Actual movement speed
@export var base_hp: int = 10
@export var base_damage: float = 10.0
@export var crit_chance: float = 0.05  # Default 5% crit chance
@export var dash_speed: float = 900.0
@export var dash_duration: float = 0.2

# =============================================================================
# WEAPON CONFIG
# =============================================================================
@export_group("Weapon")
@export var weapon_name: String = "Standard-Issue"
@export var weapon_type_name: String = "Assault Rifle"  # Display name
@export_enum("Melee", "Rifle", "Launcher", "Shotgun", "SMG") var weapon_type: int = 1
@export_multiline var weapon_description: String = "Reliable weapon with balanced cadence."
@export var weapon_special_name: String = ""
@export_multiline var weapon_special_description: String = ""

@export var ammo_capacity: int = -1  # -1 = unlimited
@export var magazine_size: int = 30
@export var reload_time: float = 1.5
@export var attack_cooldown: float = 0.3
@export var fire_rate: float = 0.25
@export var fire_mode: String = "automatic"

@export var projectile_speed: float = 800.0
@export var projectile_count: int = 1  # For shotguns
@export var projectile_spread: float = 0.0  # Degrees
@export var projectile_damage: int = 1
@export var projectile_radius: float = 4.0
@export var projectile_range: float = 800.0
@export var projectile_lifetime: float = 0.75
@export var projectile_penetration: int = 1
@export var projectile_shape: String = "standard"

@export var pellet_count: int = 1
@export var spread_angle: float = 0.0
@export var grenade_rounds: int = 0
@export var grenade_reload_time: float = 0.0
@export var special_mechanics: Dictionary = {}
@export var special_attack_data: Dictionary = {}

# =============================================================================
# SPECIAL ATTACK CONFIG
# =============================================================================
@export_group("Special Attack")
@export var special_cooldown: float = 3.0
@export var special_name: String = ""
@export_multiline var special_description: String = ""
@export var special_upgrade1: String = ""
@export var special_upgrade2: String = ""

# =============================================================================
# BURST CONFIG
# =============================================================================
@export_group("Burst Ability")
@export var burst_name: String = ""
@export_multiline var burst_description: String = ""
@export var burst_upgrade1: String = ""
@export var burst_upgrade2: String = ""
@export var burst_duration: float = 5.0
@export var burst_damage_multiplier: float = 2.0
@export var burst_max_points: float = 100.0
@export var burst_points_per_enemy: float = 10.0
@export var burst_points_per_hit: float = 1.0

# =============================================================================
# CONTROLLER & TALENTS
# =============================================================================
@export_group("Controller")
@export var controller_script: String = ""
@export var talents: Array[Dictionary] = []

# =============================================================================
# HELPER METHODS
# =============================================================================

## Get the effective code name (prefers code_name, falls back to id)
func get_code_name() -> String:
	if not code_name.is_empty():
		return code_name
	return id

## Get the effective folder name
func get_folder_name() -> String:
	if not folder_name.is_empty():
		return folder_name
	var code = get_code_name()
	return code.replace("_", "-")

## Get the full asset path for this character
func get_asset_path(filename: String) -> String:
	return "res://assets/characters/%s/%s" % [get_folder_name(), filename]

## Get the sprite texture (uses cached texture or loads from path)
func get_sprite() -> Texture2D:
	if sprite_sheet:
		return sprite_sheet
	var path = get_asset_path(sprite_path)
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Get the portrait texture (uses cached texture or loads from path)
func get_portrait() -> Texture2D:
	if portrait_texture:
		return portrait_texture
	var path = get_asset_path(portrait_path)
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Get the burst texture (uses cached texture or loads from path)
func get_burst_texture() -> Texture2D:
	if burst_texture:
		return burst_texture
	var path = get_asset_path(burst_texture_path)
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

## Check if this character has sprite animation
func has_sprite_animation() -> bool:
	var tex = get_sprite()
	if tex == null:
		return false
	return sprite_sheet_columns > 0 and sprite_sheet_rows > 0 and sprite_sheet_columns * sprite_sheet_rows > 1

## Get a summary string for logging/debug
func summary() -> String:
	return "%s — %s" % [display_name, role]
