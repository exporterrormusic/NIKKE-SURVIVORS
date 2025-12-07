extends Node
class_name ProjectileCache
## Centralized scene cache to prevent concurrent preload race conditions.
## All combat effect scenes should be loaded through this singleton.

# =============================================================================
# BULLET SCENES
# =============================================================================
const BulletScene: PackedScene = preload("res://scenes/effects/Bullet.tscn")
const AssaultBulletScene: PackedScene = preload("res://scenes/effects/AssaultBullet.tscn")
const SMGBulletScene: PackedScene = preload("res://scenes/effects/SMGBullet.tscn")
const SnowWhiteBulletScene: PackedScene = preload("res://scenes/effects/SnowWhiteBullet.tscn")

# =============================================================================
# EXPLOSIVE/MISSILE SCENES
# =============================================================================
const MissileScene: PackedScene = preload("res://scenes/effects/Missile.tscn")
const RocketScene: PackedScene = preload("res://scenes/effects/Rocket.tscn")
const ExplosionScene: PackedScene = preload("res://scenes/effects/Explosion.tscn")
const ExplosionEffectScene: PackedScene = preload("res://scenes/effects/ExplosionEffect.tscn")
const GroundFireScene: PackedScene = preload("res://scenes/effects/GroundFire.tscn")

# =============================================================================
# MELEE/EFFECT SCENES
# =============================================================================
const SlashScene: PackedScene = preload("res://scenes/effects/Slash.tscn")
const ScarletWaveScene: PackedScene = preload("res://scenes/effects/ScarletWave.tscn")
const KiloPelletScene: PackedScene = preload("res://scenes/effects/KiloPellet.tscn")

# =============================================================================
# UTILITY SCENES
# =============================================================================
const TurretScene: PackedScene = preload("res://scenes/effects/Turret.tscn")
const HealingCrossScene: PackedScene = preload("res://scenes/effects/HealingCross.tscn")
const XPOrbScene: PackedScene = preload("res://scenes/effects/XPOrb.tscn")

# =============================================================================
# BULLET FACTORY METHODS
# =============================================================================
static func create_bullet() -> Node:
	return BulletScene.instantiate()

static func create_assault_bullet() -> Node:
	return AssaultBulletScene.instantiate()

static func create_smg_bullet() -> Node:
	return SMGBulletScene.instantiate()

static func create_snow_white_bullet() -> Node:
	return SnowWhiteBulletScene.instantiate()

# =============================================================================
# EXPLOSIVE FACTORY METHODS
# =============================================================================
static func create_missile() -> Node:
	return MissileScene.instantiate()

static func create_rocket() -> Node:
	return RocketScene.instantiate()

static func create_explosion() -> Node:
	return ExplosionScene.instantiate()

static func create_explosion_effect() -> Node:
	return ExplosionEffectScene.instantiate()

static func create_ground_fire() -> Node:
	return GroundFireScene.instantiate()

# =============================================================================
# MELEE/EFFECT FACTORY METHODS
# =============================================================================
static func create_slash() -> Node:
	return SlashScene.instantiate()

static func create_scarlet_wave() -> Node:
	return ScarletWaveScene.instantiate()

static func create_kilo_pellet() -> Node:
	return KiloPelletScene.instantiate()

# =============================================================================
# UTILITY FACTORY METHODS
# =============================================================================
static func create_turret() -> Node:
	return TurretScene.instantiate()

static func create_healing_cross() -> Node:
	return HealingCrossScene.instantiate()

static func create_xp_orb() -> Node:
	return XPOrbScene.instantiate()
