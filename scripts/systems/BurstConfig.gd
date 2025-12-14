extends Node
class_name BurstConfig
## Central configuration for per-weapon-type burst/XP generation rates.
## Used by PlayerCore and Goddess Fall (RaptureQueenN01).

# ===========================================
# WEAPON TYPE BURST RATES (% per hit)
# ===========================================
# These represent the percentage of burst gauge (100 max) gained per hit.
# Same rates used for Goddess Fall XP generation (% of level).

const RATE_SNIPER := 7.0       # Snow White primary
const RATE_SNIPER_TURRET := 3.0  # Snow White turret missiles
const RATE_SWORD := 5.0        # Scarlet primary
const RATE_SWORD_ROSE := 3.0   # Scarlet shop upgrade roses
const RATE_ROCKET := 10.0      # Rapunzel primary
const RATE_BURN_PER_TICK := 1.0  # Rapunzel burn per enemy per tick
const RATE_ASSAULT := 3.0      # Commander assault rifle
const RATE_SMG := 1.2          # Nayuta, Cecil, Sin (reduced 40%)
const RATE_MINIGUN := 1.0      # Marian, Crown (doubled)
const RATE_MINIGUN_BEAM := 2.0  # Marian beam per tick (doubled to 2%)
const RATE_SHOTGUN := 4.0      # Kilo per pellet (doubled, chains don't generate)
const RATE_TROMBE := 15.0      # Crown Trombe activation

# ===========================================
# SPECIAL MODIFIERS
# ===========================================
const RATE_CHARMED_ENEMY := 0.5  # Charmed enemies (Marian/Sin) hits
const SUMMON_MULTIPLIER := 0.333  # Summons generate 1/3 normal rate

# ===========================================
# HELPER FUNCTIONS
# ===========================================

## Get burst rate for a weapon type string
static func get_rate(weapon_type: String) -> float:
	match weapon_type.to_lower():
		"sniper", "snow_white", "snow":
			return RATE_SNIPER
		"turret", "turret_missile", "missile":
			return RATE_SNIPER_TURRET
		"sword", "scarlet", "slash", "melee":
			return RATE_SWORD
		"rose", "scarlet_rose":
			return RATE_SWORD_ROSE
		"rocket", "rapunzel", "launcher", "explosive":
			return RATE_ROCKET
		"burn", "fire", "ground_fire":
			return RATE_BURN_PER_TICK
		"burn_dot":  # Burning ground DOT - does NOT generate burst/XP
			return 0.0
		"assault", "commander", "assault_rifle":
			return RATE_ASSAULT
		"smg", "nayuta", "cecil", "sin":
			return RATE_SMG
		"minigun", "marian", "crown":
			return RATE_MINIGUN
		"beam", "marian_beam":
			return RATE_MINIGUN_BEAM
		"shotgun", "kilo", "pellet":
			return RATE_SHOTGUN
		"trombe", "cavalry", "charge":
			return RATE_TROMBE
		"charmed", "mind_control":
			return RATE_CHARMED_ENEMY
		_:
			# Default fallback - 1% per hit
			return 1.0

## Get burst rate adjusted for summons
static func get_summon_rate(weapon_type: String) -> float:
	return get_rate(weapon_type) * SUMMON_MULTIPLIER

## Check if source is from a burst attack (should not generate burst)
static func is_burst_source(source: String) -> bool:
	return "burst" in source.to_lower()
