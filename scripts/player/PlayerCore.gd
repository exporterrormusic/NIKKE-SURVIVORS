extends CharacterBody2D
class_name PlayerCore
## Core player functionality: movement, health, XP, stamina, UI.
## Character-specific combat is delegated to CharacterController instances.

# Character system
const CharacterRegistryScript = preload("res://scripts/characters/CharacterRegistry.gd")
const PlayerOverheadHudScript = preload("res://scripts/player/PlayerOverheadHud.gd")
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

# Movement settings
@export var speed: float = 400.0
@export var dash_speed: float = 800.0
@export var dash_duration: float = 0.3
@export var acceleration: float = 6000.0
@export var friction: float = 5000.0
@export var momentum_duration: float = 0.1

# Stamina settings (Delegated to PlayerMovement)
var stamina: float:
	get: return _movement.stamina if _movement else 0.0
	set(value): if _movement: _movement.stamina = value

var max_stamina: float:
	get: return _movement.max_stamina if _movement else 100.0
	set(value): if _movement: _movement.max_stamina = value

# Combat settings
@export var attack_stamina_cost: float = 10.0


# Combat settings
@export var attack_cooldown: float = 0.3
@export var burst_max: float = 100.0
@export var burst_per_hit: float = 2.5

# Debug
@export var debug_movement: bool = false
@export var dash_press_grace: float = 0.12

# Node references
@onready var xp_ui = get_node_or_null("../CanvasLayer/XPUI")
@onready var player_hud = get_node_or_null("../CanvasLayer/PlayerHudCluster")
@onready var screen_flash = get_node_or_null("../ScreenFlashLayer/ScreenFlash")
@onready var _animator = $Sprite2D
@onready var overhead_hud = $PlayerOverheadHud

var audio_director = null

# Character management
var _registry: RefCounted = null # CharacterRegistry
var _current_controller: CharacterController = null
var _character_index: int = 0 # Registry index of the run's character

# Level up sound
var _level_up_sfx: AudioStream = null

# Player state
var burst_current: float = 0.0
# Modifier for burst generation from burst hits (default 0.0 = no gen)
var burst_gen_on_burst_hit_modifier: float = 0.0

# Health properties (delegate to _health module)
var hp: int = 10:
	get: return _health.hp if _health else 10
	set(value): if _health: _health.hp = value

var max_hp: int = 10:
	get: return _health.max_hp if _health else 10
	set(value): if _health: _health.max_hp = value

var invincible: bool = false:
	get: return _health.invincible if _health else false
	set(value): if _health: _health.invincible = value

func add_invincibility(duration: float) -> void:
	if _health:
		_health.add_invincibility(duration)

# Progression system (delegated)
var _progression: PlayerProgression = null
# Legacy accessors (for compatibility)
var xp: int = 0: get = get_xp, set = set_xp
var level: int = 1: get = get_level
var xp_to_next: int = 120: get = get_xp_to_next

# Player subsystems (delegated)
var _health: PlayerHealth = null
var _movement: PlayerMovement = null
var _weapons: PlayerWeapons = null

# New modular components (Phase 2 refactor)
var _burst_system: BurstSystem = null
var _hud_bridge: PlayerHudBridge = null
var _talent_bridge: PlayerTalentBridge = null
var _input_handler: PlayerInputHandler = null

# Extracted modular components (Phase 3 refactor)
var _visual_effects: PlayerVisualEffects = null
var _night_glow: PlayerNightGlow = null
var _clone_manager: PlayerCloneManager = null

# Movement state (delegated to PlayerMovement)
var dashing: bool:
	get: return _movement.dashing if _movement else false

# Combat state
var shop_open: bool = false

# Aim state (delegated to PlayerInputHandler; controllers read this)
var aim_direction: Vector2:
	get: return _input_handler.aim_direction if _input_handler else Vector2.RIGHT
	set(value): if _input_handler: _input_handler.aim_direction = value

# Character-specific shop upgrades manager
var _upgrade_manager: PlayerUpgradeManager = null

# Shop upgrade bonuses (cached at start)
var _shop_atk_bonus: float = 0.0
var _shop_crit_bonus: float = 0.0
var _shop_xp_bonus: float = 0.0

# Local state for visual/physics effects (Logic delegated, but state held here for now)
var _cecil_revive_invincible_timer: float:
	get: return _health._cecil_revive_invincible_timer if _health else 0.0
	set(v): if _health: _health._cecil_revive_invincible_timer = v

# Flag to prevent deferred HUD updates after initialization
var _hud_initialized: bool = false

func _ready() -> void:
	add_to_group("player")
	
	# Set collision layer/mask to prevent friendly fire
	# Layer 1: Player projectile avoidance
	# Layer 2: Player body (for item pickup detection like Pristine Cores)
	# Layer 16: World walls/boundaries
	collision_layer = 1 | 2 # Set both layer 1 and 2
	set_collision_mask_value(1, false) # Don't collide with other players/allies on layer 1
	set_collision_mask_value(16, true) # Collide with walls/boundaries
	
	_create_shadow()

	# Register sprite for night glow effect (Managed via universal shader now)
	# if _animator:
	#	NightGlowManager.register_sprite(_animator)
	
	# Apply universal shader for night glow and effects
	_apply_universal_shader()
	
	# Initialize components
	_setup_components()
	
	_apply_shop_upgrades()
	_init_character_system()
	_init_ui()
	update_sprite()
	call_deferred("_update_hud")
	_level_up_sfx = load("res://assets/sounds/sfx/ui/level.wav")
	# Deferred: connect to environment for night glow (delegated to PlayerNightGlow component)
	if _night_glow:
		_night_glow.call_deferred("setup_environment_modulate")

	# Pre-create the talent tree (hidden) so level-up can open it without a load stutter
	call_deferred("_ensure_talent_tree")


func _setup_components() -> void:
	"""Initialize all child components and systems."""
	# 1. Core Systems
	_progression = PlayerProgression.new()
	add_child(_progression)
	_progression.configure(1, 0, 120)
	_progression.level_up.connect(_on_progression_level_up)
	
	_health = PlayerHealth.new()
	_health.name = "PlayerHealth"
	add_child(_health)
	_health.health_changed.connect(_on_health_changed)
	_health.damage_taken.connect(_on_health_damage_taken_visuals)
	_health.damage_blocked_by_shield.connect(_on_health_shield_blocked_visuals)
	_health.sin_wish_triggered.connect(_on_health_sin_wish_triggered)
	_health.cecil_revive_triggered.connect(_on_health_cecil_revive_triggered)
	_health.marian_beam_absorbed.connect(_on_health_marian_beam_absorbed)
	_health.shield_changed.connect(_on_shield_changed)
	_health.death.connect(_on_health_death_final)
	_health.initialize(hp, max_hp)
	
	_movement = PlayerMovement.new()
	add_child(_movement)
	_movement.speed = speed
	_movement.dash_speed = dash_speed
	_movement.dash_duration = dash_duration
	_movement.dash_started.connect(_on_dash_started)
	_movement.dash_ended.connect(_on_dash_ended)
	if _movement.has_signal("stamina_changed"):
		_movement.stamina_changed.connect(_on_stamina_changed)
	
	_weapons = PlayerWeapons.new()
	add_child(_weapons)
	_weapons.attack_cooldown = attack_cooldown
	
	# 2. Modular Systems
	_burst_system = BurstSystem.new()
	_burst_system.name = "BurstSystem"
	_burst_system.burst_max = burst_max
	_burst_system.burst_per_hit = burst_per_hit
	add_child(_burst_system)
	_burst_system.initialize(self)
	_burst_system.burst_changed.connect(_on_burst_changed)
	
	_upgrade_manager = PlayerUpgradeManager.new(self)
	_upgrade_manager.name = "PlayerUpgradeManager"
	add_child(_upgrade_manager)
	print("[PlayerCore] PlayerUpgradeManager initialized")

	_hud_bridge = PlayerHudBridge.new()
	_hud_bridge.name = "PlayerHudBridge"
	add_child(_hud_bridge)
	_hud_bridge.initialize(self)

	_talent_bridge = PlayerTalentBridge.new()
	_talent_bridge.name = "PlayerTalentBridge"
	add_child(_talent_bridge)
	_talent_bridge.initialize(self)
	_talent_bridge.talent_unlocked.connect(_on_talent_unlocked)

	_input_handler = PlayerInputHandler.new()
	_input_handler.name = "PlayerInputHandler"
	add_child(_input_handler)
	_input_handler.initialize(self)

	# 3. Audio & Effects
	var AudioDirectorScript = load("res://scripts/systems/AudioDirector.gd")
	audio_director = AudioDirectorScript.new()
	audio_director.name = "AudioDirector"
	add_child(audio_director)
	
	var MovementEffectsScript = load("res://scripts/player/PlayerMovementEffects.gd")
	var movement_effects = Node2D.new()
	movement_effects.set_script(MovementEffectsScript)
	movement_effects.name = "MovementEffects"
	add_child(movement_effects)
	
	# 4. Visual Effects Module
	_visual_effects = PlayerVisualEffects.new()
	_visual_effects.name = "PlayerVisualEffects"
	_visual_effects.player = self
	add_child(_visual_effects)
	
	# 5. Night Glow Module
	_night_glow = PlayerNightGlow.new()
	_night_glow.name = "PlayerNightGlow"
	_night_glow.player = self
	add_child(_night_glow)
	
	# 6. Clone Manager (Nayuta Duplicity)
	_clone_manager = PlayerCloneManager.new()
	_clone_manager.name = "PlayerCloneManager"
	_clone_manager.player = self
	add_child(_clone_manager)
	
	print("[PlayerCore] Components setup complete")


func _on_burst_changed(current: float, maximum: float) -> void:
	"""Handle burst gauge updates from BurstSystem component."""
	burst_current = current
	if player_hud:
		player_hud.update_burst(current, maximum, true)
	if overhead_hud:
		overhead_hud.update_burst(current, maximum)


func _on_shield_changed(current: int, maximum: int) -> void:
	"""Handle shield updates from health component."""
	if overhead_hud:
		overhead_hud.update_shield(current, maximum)
	if _visual_effects:
		_visual_effects.update_shield_display(current, maximum)


func _on_revive_triggered() -> void:
	"""Handle revive from CharacterUpgrades component."""
	hp = max_hp
	_update_health_display(max_hp, false)
	if _visual_effects:
		_visual_effects.spawn_revive_effect()
	_cecil_revive_invincible_timer = 5.0
	invincible = true


func _apply_shop_upgrades() -> void:
	"""Apply permanent shop upgrades to player stats."""
	# HP bonus: +1 per level
	var hp_bonus: int = int(ShopMenuScript.get_upgrade_bonus("hp"))
	max_hp += hp_bonus
	hp = max_hp
	
	# Speed bonus: +3% per level
	var speed_bonus: float = ShopMenuScript.get_upgrade_bonus("speed")
	speed *= (1.0 + speed_bonus)
	
	# ATK bonus: +5% per level (stored for use in calculate_damage)
	_shop_atk_bonus = ShopMenuScript.get_upgrade_bonus("atk")
	
	# Crit bonus: +2% per level (stored for use in damage calculations)
	_shop_crit_bonus = ShopMenuScript.get_upgrade_bonus("crit")
	
	# XP bonus: +5% per level (stored for use in XP gain)
	_shop_xp_bonus = ShopMenuScript.get_upgrade_bonus("xp")
	
	if hp_bonus > 0 or speed_bonus > 0 or _shop_atk_bonus > 0 or _shop_crit_bonus > 0 or _shop_xp_bonus > 0:
		print("[PlayerCore] Applied shop upgrades: +%d HP, +%.0f%% SPD, +%.0f%% ATK, +%.0f%% CRIT, +%.0f%% XP" % [
			hp_bonus,
			speed_bonus * 100,
			_shop_atk_bonus * 100,
			_shop_crit_bonus * 100,
			_shop_xp_bonus * 100
		])


	# audio_director.play_random_battle_track() # Disabling to prevent conflict with Level BGM

func _init_character_system() -> void:
	_registry = CharacterRegistryScript.get_instance()
	
	# Load selected characters from GameManager
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		_character_index = game_manager.player_character_index
		print("[PlayerCore] Loaded selected character: ", _character_index)
	else:
		_character_index = 0 # Fallback: Snow White
		print("[PlayerCore] Using fallback character: ", _character_index)

	# Create the controller for the selected character
	var all_ids = _registry.get_all_character_ids()
	if _character_index < 0 or _character_index >= all_ids.size():
		push_warning("[PlayerCore] Invalid character index: %d" % _character_index)
		_character_index = 0

	var char_id: String = all_ids[_character_index]
	_current_controller = _registry.create_controller(char_id, self)
	print("[PlayerCore] Created controller for %s (index %d)" % [char_id, _character_index])

	# Sync ID to health system for character-specific defenses (Marian absorb)
	if _health:
		_health.current_character_id = char_id

	# Apply the character's shop upgrades
	# (Talents are run-only: the run starts with none; they apply via _on_talent_unlocked)
	_apply_character_shop_upgrades(char_id)

func _apply_character_shop_upgrades(char_id: String) -> void:
	"""Apply character-specific shop upgrades. Delegated to PlayerUpgradeManager."""
	if not _upgrade_manager:
		return

	_upgrade_manager.apply_upgrade_for_character(char_id)

	# Explicitly notify the controller of changes that require immediate stat updates
	# (e.g. Snow White's ammo needs value update, not just a flag check)
	if _upgrade_manager.has_snow_white_ammo_upgrade and _current_controller:
		if _current_controller.has_method("apply_shop_upgrades"):
			_current_controller.apply_shop_upgrades() # This function checks the upgrade flag!


func on_enemy_killed(_enemy: Node2D, killer_source: String = "player") -> void:
	"""Called by Level when an enemy dies. Handles kill-based character upgrades.
	   Only player kills (player, projectile, cecil_drone) grant benefits."""
	# Check if this is a valid kill source for upgrades
	# Valid: player, projectile, cecil_drone, summon (for other upgrades like Kilo shield)
	# Invalid: charmed_enemy
	var _valid_kill: bool = killer_source in ["player", "projectile", "cecil_drone", "summon"]
	
	# Rapunzel: "I'm a healer, but..." - Heal 2% HP on each kill (exclude clone kills)
	# Valid sources: player, projectile, and all weapon types (rocket, sniper, etc.) + Character Bursts
	# Note: "summon" (clones) are excluded from this healing
	var is_direct_kill: bool = (killer_source in ["player", "projectile", "cecil_drone", "rocket", "sniper", "smg", "shotgun", "minigun", "assault", "sword", "blade", "kilo", "MarianBurst", "SnowWhiteBurst", "SinBurst", "NayutaBurst", "ScarletBurst", "ScarletWave"]) and killer_source != "summon" and killer_source != "clone"
	if _upgrade_manager.has_rapunzel_healer and is_direct_kill:
		var heal_amount: int = int(max_hp * 0.02)
		if heal_amount < 1:
			heal_amount = 1
		heal(heal_amount)
	
	# Regen Eden Shield on kill (1% of max HP) - direct player kills only (delegated to health component)
	if _upgrade_manager.has_cecil_eden_shield and _health.shield_current < _health.shield_max and is_direct_kill:
		var regen_amount: int = maxi(1, int(max_hp * 0.01))
		_health.add_shield(regen_amount)
	
	# Nayuta: "Duplicity" - 10% chance to spawn a clone (delegated to PlayerCloneManager)
	if _clone_manager:
		_clone_manager.has_duplicity_upgrade = _upgrade_manager.has_nayuta_duplicity_upgrade
		_clone_manager.on_enemy_killed(is_direct_kill)

# (Duplicity clone spawning delegated to PlayerCloneManager)

# HUD plumbing is delegated to PlayerHudBridge; thin wrappers kept because
# many internal/external call sites use these names.
func _init_ui() -> void:
	_hud_bridge.init_ui()

func _update_hud() -> void:
	_hud_bridge.update_hud()

func update_sprite() -> void:
	if not _animator or not _registry:
		push_warning("[PlayerCore] update_sprite: animator or registry missing")
		return

	var char_data = _registry.get_character_by_index(_character_index)
	if char_data:
		var texture = char_data.get_sprite()
		if texture:
			# Default animation settings - could be in CharacterData
			_animator.configure(texture, 3, 4, 6.0, 0.2)
			print("[PlayerCore] Loaded sprite for character %d" % _character_index)
		else:
			push_warning("[PlayerCore] update_sprite: No texture for character %d" % _character_index)

		# Apply character stats
		_apply_character_stats(char_data)

		# Apply universal shader for night glow
		_apply_universal_shader()
	else:
		push_warning("[PlayerCore] update_sprite: No char_data for index %d" % _character_index)

	if player_hud and player_hud.is_inside_tree():
		player_hud.set_character(0, is_burst_unlocked())

func _apply_character_stats(char_data: Resource) -> void:
	"""Apply character-specific stats like speed."""
	if char_data.base_speed > 0:
		# Apply base speed then shop bonus
		var base_speed: float = char_data.base_speed
		var speed_bonus: float = ShopMenuScript.get_upgrade_bonus("speed")
		speed = base_speed * (1.0 + speed_bonus)
		print("[PlayerCore] Applied speed: %.1f (base: %.1f, +%.0f%% shop)" % [speed, base_speed, speed_bonus * 100])
	
	# Apply HP
	if "base_hp" in char_data and char_data.base_hp > 0:
		var base_hp_val: int = char_data.base_hp
		var hp_bonus: int = int(ShopMenuScript.get_upgrade_bonus("hp"))
		var new_max_hp: int = base_hp_val + hp_bonus
		
		# Only update if changed (prevents precision jitter if called repeatedly)
		if max_hp != new_max_hp:
			# Preserve HP percentage when switching/initializing
			var hp_percent: float = float(hp) / float(max_hp) if max_hp > 0 else 1.0
			max_hp = new_max_hp
			hp = maxi(1, int(max_hp * hp_percent))
			print("[PlayerCore] Applied HP: %d (base: %d, +%d shop)" % [max_hp, base_hp_val, hp_bonus])

## Calculate damage with level scaling and shop ATK bonus
## Base formula: base_damage * level_mult * (1 + shop_atk_bonus)
## At level 1: 1.0x, level 2: 1.25x, level 3: 1.5x, level 5: 2.0x, level 10: 3.25x
func calculate_damage(base_damage: float, multiplier: float = 1.0) -> int:
	var level_multiplier: float = 1.0 + (level - 1) * 0.25
	var atk_multiplier: float = 1.0 + _shop_atk_bonus
	
	# Apply character-specific multiplier (e.g. Marian beam absorb +100%)
	if _current_controller and _current_controller.has_method("get_damage_multiplier"):
		multiplier *= _current_controller.get_damage_multiplier()
		
	return maxi(1, int(base_damage * level_multiplier * atk_multiplier * multiplier))

## Calculate damage with potential critical hit (uses shop crit bonus)
## Returns [damage, is_crit] - damage is 2x on crit
func calculate_damage_with_crit(base_damage: float, multiplier: float = 1.0) -> Array:
	var damage: int = calculate_damage(base_damage, multiplier)
	var is_crit: bool = randf() < _shop_crit_bonus
	if is_crit:
		damage *= 2
	return [damage, is_crit]

## Get shop crit chance (for UI display or other systems)
func get_crit_chance() -> float:
	return _shop_crit_bonus

## Get current character's base damage from CharacterData
func get_base_damage() -> float:
	if _registry:
		var char_data = _registry.get_character_by_index(_character_index)
		if char_data:
			return char_data.base_damage
	return 1.0

## Shorthand: calculate damage using current character's base damage
func calc_damage(multiplier: float = 1.0) -> int:
	return calculate_damage(get_base_damage(), multiplier)

## Add burst charge directly (e.g. from Goddess Fall mechanics)
func add_burst_charge(amount: float) -> void:
	if _burst_system:
		_burst_system.gain_burst(amount)
		# Debug for infinite burst
		print("[PlayerCore] AddBurst: ", amount, " NewVal: ", _burst_system.burst_current, " Max: ", _burst_system.burst_max)

func gain_burst(amount: float) -> void:
	"""Alias for add_burst_charge."""
	add_burst_charge(amount)

func is_burst_unlocked() -> bool:
	if _current_controller:
		# Check if burst talent is unlocked for this character
		return _get_talent_level(_character_index, "burst") > 0
	return false

func _get_talent_tree() -> Control:
	return _talent_bridge.get_tree_node()

func _get_talent_level(char_id: int, talent_id: String) -> int:
	return _talent_bridge.get_talent_level(char_id, talent_id)

func get_talent_level(char_id: int, talent_id: String) -> int:
	return _get_talent_level(char_id, talent_id)

func get_sin_captivating_level() -> int:
	"""Get Sin's Captivating talent level directly from the controller (if playing Sin)."""
	if _current_controller is SinController:
		return _current_controller.captivating_level
	return 0

func get_sin_damage() -> int:
	"""Get Sin's current damage for explosion calculations (if playing Sin)."""
	if _current_controller is SinController:
		return calc_damage() # Use player's damage (includes level scaling)
	return 0

func _create_shadow() -> void:
	# Uses the centralized ShadowHelper utility
	ShadowHelper.create_player_shadow(self)

func _apply_universal_shader() -> void:
	# DISABLED: Don't apply any shader to the player sprite
	# Instead, we create a PointLight2D for night glow effect (see _setup_environment_modulate)
	pass

# (Night glow light management delegated to PlayerNightGlow)

# ============= DAMAGE / HEALING =============

func take_damage(dmg: int, is_crit: bool = false, direction: Vector2 = Vector2.ZERO, is_true_damage: bool = false, source: String = "enemy") -> void:
	if CheatManager.is_cheat_active("invincible"):
		return
	
	# Pass to health component
	_health.take_damage(dmg, is_crit, direction, is_true_damage, source)

func _on_health_damage_taken_visuals(dmg: int, _is_crit: bool, _direction: Vector2) -> void:
	"""Handle visuals when the health component actually takes damage."""
	if screen_flash and screen_flash.has_method("flash_damage"):
		screen_flash.flash_damage()
	
	# Hit effects
	var HitSparkScript = preload("res://scripts/effects/HitSpark.gd")
	if get_parent() and HitSparkScript:
		HitSparkScript.spawn_player_hit(get_parent(), global_position)
	
	var FloatingNumber = preload("res://scripts/effects/FloatingDamageNumber.gd")
	if get_parent():
		FloatingNumber.spawn_damage(get_parent(), global_position + Vector2(0, -100), dmg)
	
	# Update HP bar displays (both main HUD and overhead)
	_update_health_display(-dmg, true)
	
	# Emit global event for decoupled systems
	EventBus.player_damaged.emit(dmg, null)

func _on_health_shield_blocked_visuals(_amount: int) -> void:
	if _visual_effects:
		_visual_effects.spawn_shield_hit_effect()
		call_deferred("_visual_effects.update_shield_display", _health.shield_current, _health.shield_max)

func _on_health_sin_wish_triggered() -> void:
	if _visual_effects:
		_visual_effects.trigger_sin_wish_sequence()
	print("[PlayerCore] Sin's wish save triggered (via component)!")

func _on_health_cecil_revive_triggered() -> void:
	if _visual_effects:
		_visual_effects.spawn_revive_effect()
	_update_health_display(max_hp, false) # Full heal display
	print("[PlayerCore] Cecil revive triggered (via component)!")

func _on_health_marian_beam_absorbed() -> void:
	if _upgrade_manager:
		_upgrade_manager.trigger_marian_beam_absorb()
	if _visual_effects:
		_visual_effects.activate_marian_beam_buff()

func _on_health_death_final() -> void:
	# Record the run result to GameManager for leaderboard
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.record_run_result("")
	
	# Find the Level node and trigger defeat menu
	var level_node = get_parent()
	if level_node and level_node.has_method("show_defeat_menu"):
		level_node.show_defeat_menu()
	else:
		# Fallback: try to find Level in tree
		var root = get_tree().current_scene
		if root and root.has_method("show_defeat_menu"):
			root.show_defeat_menu()

func _on_health_changed(_current: int, _maximum: int) -> void:
	# Call directly when HUD is ready, defer only during initialization
	if _hud_initialized:
		_update_health_display(0, false)
	else:
		call_deferred("_update_health_display", 0, false)

func add_skill_points(amount: int) -> void:
	_talent_bridge.add_skill_points(amount)

func heal(amount: int) -> void:
	# Pass to health component
	_health.heal(amount)
	
	# Always heal Nayuta clones for the full intended amount
	_heal_nayuta_clones(amount)
	
	# Visuals handled in heal (but can be moved to signal if needed)
	var FloatingNumber = preload("res://scripts/effects/FloatingDamageNumber.gd")
	if get_parent():
		FloatingNumber.spawn_heal(get_parent(), global_position + Vector2(0, -100), amount)
	
	_update_health_display(amount, true)

func _update_health_display(change: int = 0, animate: bool = false) -> void:
	_hud_bridge.update_health_display(change, animate)

func _heal_nayuta_clones(player_heal_amount: int) -> void:
	"""Heal all active Nayuta clones for the full amount of player healing."""
	var clone_heal_amount = player_heal_amount
	if clone_heal_amount <= 0:
		return
	
	# Find all Nayuta clones in the scene
	var clones = get_tree().get_nodes_in_group("nayuta_clones")
	for clone in clones:
		if is_instance_valid(clone) and clone.has_method("heal"):
			clone.heal(clone_heal_amount)

# ============= BURST SYSTEM =============

func register_burst_hit(_target = null, from_burst: bool = false, weapon_type: String = "", is_summon: bool = false) -> void:
	## Register a hit for burst generation using per-weapon-type percentages.
	## weapon_type: String identifier for the weapon (e.g., "sniper", "smg", "minigun")
	## is_summon: If true, applies 1/3 rate multiplier
	if from_burst:
		return
	if not is_burst_unlocked():
		return
	
	# Get burst rate from BurstConfig based on weapon type
	var burst_rate: float
	if weapon_type == "":
		# Fallback: try to get from current character
		weapon_type = _get_current_weapon_type()
	
	if is_summon:
		burst_rate = BurstConfig.get_summon_rate(weapon_type)
	else:
		burst_rate = BurstConfig.get_rate(weapon_type)
	
	# Commander "Obviously Anderson" upgrade: 2x burst generation
	if _upgrade_manager.has_commander_burst:
		burst_rate *= 2.0
	
	# Delegate to BurstSystem if available (fixes desync)
	if _burst_system:
		_burst_system.gain_burst(burst_rate)
	else:
		# Fallback for safe compatibility
		burst_current = min(burst_current + burst_rate, burst_max)
		if player_hud:
			player_hud.update_burst(burst_current, burst_max, true)
		if overhead_hud:
			overhead_hud.update_burst(burst_current, burst_max)

func _get_current_weapon_type() -> String:
	## Get weapon type string for current character
	if not _registry:
		return "smg" # Fallback

	var all_ids = _registry.get_all_character_ids()
	if _character_index < 0 or _character_index >= all_ids.size():
		return "smg"

	var char_id = all_ids[_character_index]

	# Map character ID to weapon type
	match char_id:
		"snow_white":
			return "sniper"
		"scarlet":
			return "sword"
		"rapunzel":
			return "rocket"
		"commander":
			return "assault"
		"nayuta", "cecil", "sin":
			return "smg"
		"marian", "crown":
			return "minigun"
		"kilo":
			return "shotgun"
		_:
			return "smg"

func is_burst_ready() -> bool:
	if _burst_system:
		return _burst_system.is_ready()
	return burst_current >= burst_max

func use_burst() -> bool:
	if not is_burst_ready():
		return false
	# Delegate to BurstSystem to ensure proper reset and signal emission
	if _burst_system:
		return _burst_system.use_burst()
	# Legacy fallback if BurstSystem not available
	if not (has_meta("debug_infinite_burst") and get_meta("debug_infinite_burst")):
		burst_current = 0.0
	if player_hud:
		player_hud.update_burst(burst_current, burst_max, true)
	if overhead_hud:
		overhead_hud.update_burst(burst_current, burst_max)
	return true

func is_using_controller() -> bool:
	return _input_handler.is_using_controller() if _input_handler else false

func _attempt_burst_activation() -> void:
	if not is_burst_unlocked():
		return
	if use_burst():
		_play_burst_voice()
		if _current_controller:
			# Trigger combat juice
			var combat_juice_script = load("res://scripts/systems/CombatJuice.gd")
			if combat_juice_script and combat_juice_script.instance:
				combat_juice_script.burst_effect()
			
			_current_controller.activate_burst()

func _play_burst_voice() -> void:
	# Get current character ID for runtime sound lookup
	var char_id: String = ""
	if _registry:
		var all_ids = _registry.get_all_character_ids()
		if _character_index >= 0 and _character_index < all_ids.size():
			char_id = all_ids[_character_index]

	# Get sound at runtime (enables Commander random selection)
	var sound: AudioStream = null
	if char_id != "" and _registry:
		sound = _registry.get_burst_sound(char_id)

	if sound == null:
		return
	
	# Use AudioDirector's dedicated burst voice player if available
	# This ensures proper audio management and prevents cutoff
	if audio_director and audio_director.has_method("play_burst_voice"):
		audio_director.play_burst_voice(sound)
	else:
		# Fallback: Create independent audio player at scene root
		var root = get_tree().root
		var audio_player = AudioStreamPlayer.new()
		audio_player.name = "BurstVoice_%d" % Time.get_ticks_msec()
		audio_player.stream = sound
		audio_player.volume_db = 10.0
		audio_player.bus = "SFX" # Use SFX bus for voice lines
		audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
		root.add_child(audio_player)
		audio_player.play()
		audio_player.finished.connect(audio_player.queue_free)

# ============= XP / LEVELING =============

# Legacy property accessors (delegate to _progression)
func get_xp() -> int:
	return _progression.xp if _progression else 0

func set_xp(value: int) -> void:
	if _progression:
		_progression.xp = value


func get_level() -> int:
	return _progression.level if _progression else 1

func get_xp_to_next() -> int:
	return _progression.xp_to_next if _progression else 100

func add_xp(amount: int) -> void:
	if not _progression:
		return
	
	# Apply shop XP bonus
	var xp_multiplier: float = 1.0 + _shop_xp_bonus
	
	# Crown "Royal Knowledge" upgrade: 2x XP gain
	if _upgrade_manager.has_crown_xp:
		xp_multiplier *= 2.0
		
	# Cheat: Recipes (50x XP)
	if CheatManager.is_cheat_active("xp_boost"):
		xp_multiplier *= 50.0
	
	_progression.set_xp_multiplier(xp_multiplier)
	
	# Delegate to progression module (it handles EventBus emission)
	var _leveled_up = _progression.add_xp(amount)
	
	# Update UI
	update_xp_bar()
	
	# Level up effects handled by callback (_on_progression_level_up)

func _on_progression_level_up(new_level: int, skill_points_gained: int) -> void:
	"""Called when PlayerProgression module triggers a level up"""
	# Grant points to the talent tree (could be multiple if leveled up more than once)
	_talent_bridge.grant_points(skill_points_gained)

	# UI flash
	if xp_ui and xp_ui.has_method("flash_level_up"):
		xp_ui.set_level(new_level)
		xp_ui.flash_level_up()

	# Play level up sound
	_play_level_up_sound()

	# Spawn WoW-style golden glow effect around player
	_spawn_level_up_glow()

	# Open the talent tree to spend the point (level-up IS the upgrade choice)
	_show_talent_tree()

	# Note: EventBus.player_leveled_up already emitted by PlayerProgression


func _on_stamina_changed(current: float, max_val: float) -> void:
	"""Handle stamina changes from PlayerMovement component."""
	# Regenerating if current > previous? Hard to tell without prev state.
	# But PlayerHud usually handles the color/animation based on the 'regenerating' bool.
	# We can infer regenerating if current < max and not dashing/running?
	# Simpler: just pass 'true' for spending if we don't have perfect info, or assume regen.
	# Actually PlayerHud probably wants to know if we are draining.
	var draining = false
	if _movement:
		draining = _movement.running or _movement.dashing
	
	if player_hud:
		player_hud.update_stamina(current, max_val, draining)

func _play_level_up_sound() -> void:
	## Plays the level up sound effect
	if not _level_up_sfx:
		return
	var audio_player = AudioStreamPlayer.new()
	audio_player.bus = "SFX"
	audio_player.stream = _level_up_sfx
	audio_player.volume_db = -10.0
	add_child(audio_player)
	audio_player.play()
	audio_player.finished.connect(audio_player.queue_free)

func _spawn_level_up_glow() -> void:
	## Spawns the golden level-up glow effect around the player
	var LevelUpGlowScript = preload("res://scripts/effects/LevelUpGlow.gd")
	var glow = LevelUpGlowScript.new()
	get_parent().add_child(glow)
	glow.attach_to_player(self)

# (Revive effect spawning delegated to PlayerVisualEffects)

# (Eden shield visual management delegated to PlayerVisualEffects)

# ============= MARIAN BEAM BUFF =============

# (Marian beam buff visual delegated to PlayerVisualEffects)

# ============= SIN WISH SAVE =============

func reset_sin_wish_for_new_match() -> void:
	"""Reset Sin's wish usage for a new match."""
	_upgrade_manager.sin_wish_used_this_match = false


func update_xp_bar() -> void:
	_hud_bridge.update_xp_bar()

func is_playing_character(char_id: String) -> bool:
	"""Check if the given character is the one being played this run."""
	char_id = char_id.to_lower()

	if _current_controller:
		# Robust check: Check controller data directly first
		# Using get() is safer than direct access if property might confuse parser
		var data = _current_controller.get("data")
		if data and "id" in data:
			if data.id.to_lower() == char_id:
				return true

		# Fallback: Check script path for name match
		var path = _current_controller.get_script().resource_path.to_lower()
		# Fix: Snow White controller file is "SnowWhiteController.gd", no underscore.
		# Handle "snow_white" by checking for both "snow_white" and "snowwhite"
		var search_term = char_id.replace("_", "")
		if search_term in path.replace("_", ""):
			return true
	return false

func _on_talent_unlocked(char_id: int, talent_id: String) -> void:
	"""Gameplay application of a talent purchase (UI handled by PlayerTalentBridge)."""
	# Forward talent to controller (only the run's character has a controller)
	if char_id == _character_index and _current_controller:
		if _current_controller.has_method("apply_talent"):
			_current_controller.apply_talent(talent_id)

		# Re-check signature upgrades: migrated ex-shop talents activate their
		# upgrade flags (and side effects) through PlayerUpgradeManager
		if _registry:
			_apply_character_shop_upgrades(_registry.get_character_id(_character_index))

	# Update burst visibility
	_update_burst_visibility()

func _update_burst_visibility() -> void:
	_hud_bridge.update_burst_visibility()

# ============= AMMO UI =============

func _update_overhead_ammo() -> void:
	_hud_bridge.update_overhead_ammo()

func _update_overhead_special() -> void:
	_hud_bridge.update_overhead_special()

## Public accessor for current controller (used by PlayerCloneManager and external systems)
func get_current_controller() -> CharacterController:
	return _current_controller


# ============= MAIN GAME LOOP =============

	# Animator state is updated in _physics_process via update_state()

func _process(delta: float) -> void:
	if shop_open:
		return
		
	# Update aim every frame for smooth visual tracking
	_input_handler.update_aim()
	
	# Cheats
	if CheatManager.is_cheat_active("infinite_burst"):
		if burst_current < burst_max:
			burst_current = burst_max
			if player_hud:
				player_hud.update_burst(burst_current, burst_max, false)
			if overhead_hud:
				overhead_hud.update_burst(burst_current, burst_max)
				
	if CheatManager.is_cheat_active("give_skill_points"):
		# One-shot trigger: give 99 points then disable
		CheatManager.set_cheat_active("give_skill_points", false)
		add_skill_points(99)
		print("[PlayerCore] Cheat BLEED activated: +99 Skill Points")
		
		# Show notification via overhead hud if possible
		if overhead_hud and overhead_hud.has_method("show_message"):
			overhead_hud.show_message("+99 SKILL POINTS")

	# Update controller
	if _current_controller:
		_current_controller.process(delta)
	
	# Marian beam buff timer

	
	# Stamina management delegated to PlayerMovement
	# UI updates via signal connection
	
	# Update ammo UI
	_update_overhead_ammo()
	
	# Update special ability indicator
	_update_overhead_special()

func _physics_process(delta: float) -> void:
	if shop_open:
		return

	# Input, movement, and attacks (delegated to PlayerInputHandler;
	# aim is updated in _process for smoother visual tracking)
	_input_handler.physics_update(delta)

	# Cecil revive invincibility timer
	if _cecil_revive_invincible_timer > 0.0:
		_cecil_revive_invincible_timer -= delta
		if _cecil_revive_invincible_timer <= 0.0:
			_cecil_revive_invincible_timer = 0.0
			if not dashing:
				invincible = false
	
	# Grace timer for dash

	
	# Update current controller physics
	if _current_controller and _current_controller.has_method("physics_process"):
		_current_controller.physics_process(delta)
	
	# Update animator state
	if _animator and _animator.has_method("update_state"):
		_animator.update_state(velocity, aim_direction)

func _on_dash_started() -> void:
	invincible = true
	# Notify camera for juicy lag effect
	var camera = get_node_or_null("Camera2D")
	if camera and camera.has_method("notify_dash"):
		camera.notify_dash()

func _on_dash_ended() -> void:
	invincible = false


# Talent tree management is delegated to PlayerTalentBridge; thin wrappers
# kept because internal call sites use these names.
func _ensure_talent_tree() -> Control:
	return _talent_bridge.ensure_tree()

func _show_talent_tree() -> void:
	_talent_bridge.show_tree()

func get_low_hp_damage_multiplier() -> float:
	## Wrapper to get damage multiplier from current controller (for UI stats)
	if _current_controller and _current_controller.has_method("get_low_hp_damage_multiplier"):
		return _current_controller.get_low_hp_damage_multiplier()
	return 1.0

func _exit_tree() -> void:
	# Cleanup controller to ensure global effects (AudioServer, etc) are removed
	if _current_controller and _current_controller.has_method("cleanup"):
		_current_controller.cleanup()

