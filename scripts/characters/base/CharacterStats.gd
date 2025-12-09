extends Resource
class_name CharacterStats
## Character statistics and configuration resource.
##
## Defines base stats for a character. Used with the composition-based
## character system where abilities are separate nodes.
##
## Usage:
##   var stats = CharacterStats.new()
##   stats.character_name = "Crown"
##   stats.base_hp = 150
##   stats.ability_paths = ["res://scripts/characters/crown/abilities/minigun.tscn"]

## Display name of the character
@export var character_name: String = ""

## Character's base HP
@export var base_hp: int = 100

## Base damage multiplier (affects all abilities)
@export var base_damage: float = 1.0

## Base movement speed
@export var base_speed: float = 300.0

## Paths to ability scene files (tscn or gd)
## These will be instantiated and added as child nodes
@export var ability_paths: Array[String] = []

## Character icon texture path
@export var icon_path: String = ""

## Character description for UI
@export_multiline var description: String = ""

## Unlock requirements (e.g., "Complete Stage 2")
@export var unlock_requirement: String = ""
