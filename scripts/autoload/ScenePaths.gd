extends Node
## Centralized scene and asset paths to avoid hardcoded strings throughout codebase.
## Registered as autoload: ScenePaths

# =============================================================================
# SCENE PATHS
# =============================================================================

# Main scenes
const MAIN := "res://scenes/Main.tscn"
const MAIN_MENU := "res://scenes/ui/MainMenu.tscn"

# Menu scenes
const CHARACTER_SELECT := "res://scenes/ui/CharacterSelectMenu.tscn"
const SHOP := "res://scenes/ui/ShopMenu.tscn"
const SETTINGS := "res://scenes/ui/SettingsMenu.tscn"
const ACHIEVEMENTS := "res://scenes/ui/AchievementsMenu.tscn"
const LEADERBOARD := "res://scenes/ui/LeaderboardMenu.tscn"
const MAP_SELECTOR := "res://scenes/ui/MapSelector.tscn"

# =============================================================================
# AUDIO PATHS
# =============================================================================

# Music
const MUSIC_MAIN_MENU := "res://assets/sounds/music/menu/main-menu.mp3"
const MUSIC_GODDESS_TIMER := "res://assets/sounds/music/bgm/timer.mp3"

# =============================================================================
# ASSET PATHS
# =============================================================================

# UI
const LOGO := "res://assets/ui/logo.png"
const PATCH_NOTES := "res://patch.txt"

# Characters base path
const CHARACTERS_BASE := "res://assets/sprites/characters/"

# Characters sprites for loading animation
const CHAR_SPRITE_KILO := "res://assets/characters/kilo/kilo-sprite.png"
const CHAR_SPRITE_MARIAN := "res://assets/characters/marian/marian-sprite.png"
const CHAR_SPRITE_NAYUTA := "res://assets/characters/nayuta/nayuta-sprite.png"
const CHAR_SPRITE_SCARLET := "res://assets/characters/scarlet/scarlet-sprite.png"

# Shaders
const SHADER_HEX_GRID := "res://resources/shaders/hexagon_grid_overlay.gdshader"

# Backgrounds
const BG_BASE := "res://assets/backgrounds/"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

## Get character portrait path
static func get_character_portrait(char_id: String) -> String:
	var folder := char_id.replace("_", "-")
	return CHARACTERS_BASE + folder + "/portrait-sq.png"


## Get character sprite path
static func get_character_sprite(char_id: String) -> String:
	var folder := char_id.replace("_", "-")
	return CHARACTERS_BASE + folder + "/" + folder + "-sprite.png"
