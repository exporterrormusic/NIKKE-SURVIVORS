class_name EnemyTierConfig
extends RefCounted
## Data-driven enemy tier configuration system.
## Centralizes all tier multipliers and visual settings for consistent enemy scaling.
##
## Usage:
##   var tier = EnemyTierConfig.get_tier("tank")
##   enemy.max_hp = int(enemy.max_hp * tier.hp_mult * health_multiplier * difficulty_mult)
##   enemy.scale = Vector2.ONE * tier.scale

# =============================================================================
# TIER DEFINITIONS
# =============================================================================

## Tier configuration data
## Each tier defines: scale, hp_mult, damage_mult, speed_mult, glow_color, groups
static var TIERS := {
	"basic": {
		"scale": 1.0,
		"hp_mult": 1.0,
		"damage_mult": 1.0,
		"speed_mult": 1.0,
		"glow_color": Color.TRANSPARENT,
		"glow_enhanced": false,
		"groups": [],
		"has_boss_ai": false,
		"can_shoot": true,
	},
	"tank": {
		"scale": 2.0,
		"hp_mult": 5.0,
		"damage_mult": 2.0,
		"speed_mult": 1.0,
		"glow_color": Color(0.85, 0.35, 0.15, 1.0),  # Dark reddish-orange
		"glow_enhanced": true,
		"groups": ["tank"],
		"has_boss_ai": false,  # Set true in Goddess Fall mode
		"can_shoot": true,
		"effects_script": "res://scripts/enemies/effects/TankEffects.gd",
	},
	"shielder": {
		"scale": 2.0,
		"hp_mult": 5.0,
		"damage_mult": 2.0,
		"speed_mult": 0.8,  # Slightly slower - defensive unit
		"glow_color": Color(0.3, 0.6, 1.0, 1.0),  # Blue glow
		"glow_enhanced": true,
		"groups": ["tank", "shielder"],
		"has_boss_ai": false,
		"can_shoot": false,  # Defender, doesn't shoot
		"effects_script": "res://scripts/enemies/effects/ShielderShield.gd",
		"hp_bar_color": Color(0.3, 0.6, 1.0),  # Blue HP bar
	},
	"exploder": {
		"scale": 1.5,  # 50% larger than normal enemies
		"hp_mult": 3.0,  # Less HP - suicide unit
		"damage_mult": 4.0,  # High explosion damage
		"speed_mult": 1.2,  # Faster - needs to reach player
		"glow_color": Color(1.0, 0.2, 0.2, 1.0),  # Red glow
		"glow_enhanced": true,
		"enable_outline": false, # Disable shader outline (ring effect)
		"groups": ["tank", "exploder"],
		"has_boss_ai": false,
		"can_shoot": false,  # Explodes instead
		"hp_bar_color": Color(1.0, 0.2, 0.2),  # Red HP bar
		"strobe_effect": true,  # Red strobe
	},
	"elite": {
		"scale": 3.25,
		"hp_mult": 10.0,
		"damage_mult": 3.0,
		"speed_mult": 0.8,
		"glow_color": Color(0.8, 0.1, 0.1, 1.0),  # Red glow
		"glow_enhanced": true,
		"groups": ["elite"],
		"has_boss_ai": true,
		"can_shoot": true,
		"effects_script": "res://scripts/enemies/effects/EliteEffects.gd",
	},
	"boss": {
		"scale": 4.5,
		"hp_mult": 50.0,
		"damage_mult": 5.0,
		"speed_mult": 0.5,
		"glow_color": Color(0.7, 0.2, 1.0, 1.0),  # Purple glow
		"glow_enhanced": true,
		"groups": ["boss"],
		"has_boss_ai": true,
		"can_shoot": true,
		"effects_script": "res://scripts/enemies/effects/BossEffects.gd",
		"core_drop_chance": 0.333,
		"health_bar_name": "RAPTURE TITAN",
	},
	"super_boss": {
		"scale": 5.5,
		"hp_mult": 100.0,
		"damage_mult": 8.0,
		"speed_mult": 0.4,
		"glow_color": Color(1.0, 0.2, 0.5, 1.0),  # Red-purple glow
		"glow_enhanced": true,
		"groups": ["boss", "super_boss"],
		"has_boss_ai": true,
		"can_shoot": true,
		"effects_script": "res://scripts/enemies/effects/BossEffects.gd",
		"core_drop_chance": 1.0,  # Guaranteed
		"health_bar_name": "RAPTURE OVERLORD",
		"has_aura": true,
	},
}

# =============================================================================
# TIER ACCESS
# =============================================================================

## Get tier configuration by name
static func get_tier(tier_name: String) -> Dictionary:
	if tier_name in TIERS:
		return TIERS[tier_name]
	push_warning("[EnemyTierConfig] Unknown tier: %s, defaulting to basic" % tier_name)
	return TIERS["basic"]


## Get all tier names
static func get_tier_names() -> Array:
	return TIERS.keys()


## Check if tier exists
static func has_tier(tier_name: String) -> bool:
	return tier_name in TIERS

# =============================================================================
# TIER UPGRADE MAPPING (for Stage 2 / Goddess Fall)
# =============================================================================

## Map enemy types to upgraded versions for hard modes
static var TIER_UPGRADES := {
	"basic": "tank",
	"tank": "elite",
	"elite": "boss",
	"boss": "super_boss",
}

## Get the upgraded tier for a given tier (Stage 2 mode)
static func get_upgraded_tier(tier_name: String) -> String:
	if tier_name in TIER_UPGRADES:
		return TIER_UPGRADES[tier_name]
	return tier_name  # No upgrade available

# =============================================================================
# GODDESS FALL MODIFIERS
# =============================================================================

## Speed multiplier applied in Goddess Fall mode
const GODDESS_FALL_SPEED_MULT := 1.3

## Whether tanks get boss AI in Goddess Fall mode
const GODDESS_FALL_TANK_BOSS_AI := true

## Elite core drop chance in Goddess Fall mode
const GODDESS_FALL_ELITE_CORE_CHANCE := 0.2
