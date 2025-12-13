extends Node
## Centralized debug settings for development.
## Access via autoload: DebugSettings.force_night, etc.
## All flags default to false in release builds.

## Force night mode for testing night visuals
static var force_night: bool = false

## Enable verbose projectile compensation logging
static var projectile_debug_log: bool = false

## Enable verbose enemy AI logging
static var enemy_ai_debug: bool = false

## Enable visual debug overlays (collision shapes, etc.)
static var show_debug_overlays: bool = false

## Show FPS counter in HUD
static var show_fps: bool = false


## Called when loaded as autoload - only enable defaults in debug builds
func _ready() -> void:
	if OS.is_debug_build():
		# Can optionally enable some defaults for debug builds
		pass


## Reset all debug flags to defaults
static func reset_all() -> void:
	force_night = false
	projectile_debug_log = false
	enemy_ai_debug = false
	show_debug_overlays = false
