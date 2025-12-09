extends Resource
class_name BossPhase
## Boss phase configuration resource.
##
## Defines a single phase in a boss fight with HP threshold and behavior changes.
##
## Usage:
##   var phase = BossPhase.new()
##   phase.phase_name = "Enraged"
##   phase.hp_threshold = 0.5  # Triggers at 50% HP
##   phase.speed_multiplier = 1.5

## Display name of this phase
@export var phase_name: String = "Phase 1"

## HP percentage to trigger this phase (0.0 - 1.0)
## Example: 0.75 = triggers at 75% HP
@export_range(0.0, 1.0) var hp_threshold: float = 1.0

## Speed multiplier for this phase
@export var speed_multiplier: float = 1.0

## Damage multiplier for this phase
@export var damage_multiplier: float = 1.0

## Fire rate multiplier for this phase
@export var fire_rate_multiplier: float = 1.0

## New attack patterns unlocked in this phase
@export var attack_patterns: Array[String] = []

## Visual tint for this phase
@export var phase_tint: Color = Color.WHITE

## Phase transition effect scene (optional)
@export var transition_effect_path: String = ""
