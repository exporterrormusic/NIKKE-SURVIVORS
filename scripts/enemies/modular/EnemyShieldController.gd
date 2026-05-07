extends Node
class_name EnemyShieldController
## Manages shield protection logic for ModularEnemy.
##
## Extracted from ModularEnemy.gd. Handles:
## - Shielder shield detection / caching (finds nearby active shields)
## - Generic boss shield creation and per-frame deployment
## - Shield damage absorption checks
## - Active shield stat queries

const ShielderShieldScript = preload("res://scripts/enemies/effects/ShielderShield.gd")

var _enemy: Node2D

# Boss shield
var _generic_boss_shield: Node2D = null
var _generic_shield_ready: bool = false

# Cached external shield (from Shielder enemies)
var _cached_shield: Node = null

# Shield check throttling
var _shield_check_timer: float = 0.0
const SHIELD_CHECK_INTERVAL: float = 0.2

# ── Setup ────────────────────────────────────────────────────────────────
func setup(enemy: Node2D) -> void:
	_enemy = enemy

func process_shield_tick(delta: float, on_screen: bool) -> void:
	"""Called from _process to update cached shield status."""
	_shield_check_timer -= delta
	var effective_interval = SHIELD_CHECK_INTERVAL if on_screen else SHIELD_CHECK_INTERVAL * 4.0
	if _shield_check_timer <= 0:
		_update_shield_status()
		_shield_check_timer = effective_interval

func process_boss_shield_deployment() -> void:
	"""Random chance to redeploy boss shield when ready."""
	if _generic_shield_ready and randf() < 0.005:
		if _generic_boss_shield and _generic_boss_shield.has_method("activate"):
			_generic_boss_shield.activate()
			_generic_shield_ready = false

# ── Shield cache / search ────────────────────────────────────────────────
func _update_shield_status() -> void:
	if is_instance_valid(_cached_shield) and _cached_shield.is_active():
		if _cached_shield.is_point_inside(_enemy.global_position):
			return
	_cached_shield = _find_active_shield()

func _find_active_shield() -> Node:
	if _enemy.is_in_group("shielder"):
		var my_shield = _enemy.get_node_or_null("ShielderShield")
		if my_shield and my_shield.protects_owner():
			return my_shield

	var shields = TargetCache.get_shielder_shields()
	for shield in shields:
		if not is_instance_valid(shield):
			continue
		if not shield.is_active():
			continue
		if shield.is_point_inside(_enemy.global_position):
			return shield
	return null

func _get_protecting_shield() -> Node:
	if is_instance_valid(_cached_shield) and _cached_shield.is_active():
		if _cached_shield.is_point_inside(_enemy.global_position):
			return _cached_shield
	return null

# ── Shield damage absorption ─────────────────────────────────────────────
func check_shielder_protection(damage_amount: int, source: String) -> bool:
	"""Returns true if damage was absorbed by a shield."""
	var shielding_unit = _get_protecting_shield()
	
	# Check for Chrono-Intangibility upgrade (Wells) — bypasses shield
	if _enemy.is_inside_tree():
		var player = _enemy.get_tree().get_first_node_in_group("player")
		if player and player.has_method("is_character_in_squad") and player.is_character_in_squad("wells"):
			const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")
			if ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility"):
				return false
	
	if shielding_unit:
		if shielding_unit.has_method("take_shield_damage"):
			shielding_unit.take_shield_damage(damage_amount, source)
		return true
	return false

func is_protected_by_shield() -> bool:
	return _get_protecting_shield() != null

# ── Active shield stats ──────────────────────────────────────────────────
func get_active_shield_stats() -> Vector2:
	"""Returns (current_hp, max_hp) of active shield, or Vector2.ZERO."""
	var shield = _get_protecting_shield()
	if shield and "shield_hp" in shield and "max_shield_hp" in shield:
		return Vector2(shield.shield_hp, shield.max_shield_hp)
	return Vector2.ZERO

# ── Generic boss shield ──────────────────────────────────────────────────
func setup_super_boss_shield() -> void:
	"""Called by EnemySpawner after groups are assigned."""
	if _enemy.is_in_group("ignore_generic_shield"):
		return
	_setup_generic_boss_shield()

func _setup_generic_boss_shield() -> void:
	var shield_script = load("res://scripts/enemies/effects/ShielderShield.gd")
	if not shield_script:
		return

	_generic_boss_shield = shield_script.new()
	_enemy.add_child(_generic_boss_shield)

	var enemy_max_hp := 1000
	var hc = _enemy.get_node_or_null("HealthComponent")
	if hc and hc.max_hp > 0:
		enemy_max_hp = hc.max_hp

	_generic_boss_shield.initialize(_enemy, enemy_max_hp, 0.1, 70.0)
	_generic_boss_shield.color_theme = Color(0.6, 0.2, 1.0) # Purple
	_generic_boss_shield.auto_regen = false
	_generic_boss_shield.recharge_duration = 15.0
	_generic_boss_shield.bar_offset_y = -54.0
	_generic_boss_shield.bar_width = 50.0
	_generic_boss_shield.bar_height = 6.0

	# Regular bosses have their own HUD bar; super bosses don't, so they need local one
	if _enemy.is_in_group("boss") and not _enemy.is_in_group("super_boss"):
		_generic_boss_shield.draw_hp_bar = false

	_generic_boss_shield.recharge_complete.connect(func(): _generic_shield_ready = true)
	_generic_boss_shield.activate()
	_generic_shield_ready = false

# ── Reset for pooling ────────────────────────────────────────────────────
func reset() -> void:
	_cached_shield = null
	if _generic_boss_shield:
		if _generic_boss_shield.get_parent() == _enemy:
			_enemy.remove_child(_generic_boss_shield)
		_generic_boss_shield.queue_free()
		_generic_boss_shield = null
	_generic_shield_ready = false
