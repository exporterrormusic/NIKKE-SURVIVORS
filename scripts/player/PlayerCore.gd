extends CharacterBody2D
class_name PlayerCore
## Core player functionality: movement, health, XP, stamina, UI.
## Character-specific combat is delegated to CharacterController instances.

# Character system
const CharacterRegistryScript = preload("res://scripts/characters/CharacterRegistry.gd")
const PlayerOverheadHudScript = preload("res://scripts/player/PlayerOverheadHud.gd")
const CharacterSwapEffectScript = preload("res://scripts/effects/CharacterSwapEffect.gd")
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

# Movement settings
@export var speed: float = 400.0
@export var dash_speed: float = 800.0
@export var dash_duration: float = 0.3
@export var acceleration: float = 6000.0
@export var friction: float = 5000.0
@export var momentum_duration: float = 0.1

# Stamina settings
@export var stamina: float = 100.0
@export var max_stamina: float = 100.0
@export var stamina_regen: float = 30.0
@export var dash_stamina_cost: float = 20.0
@export var attack_stamina_cost: float = 10.0
@export var running_stamina_drain: float = 20.0
@export var running_speed_multiplier: float = 1.5

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
var _registry: RefCounted = null  # CharacterRegistry
var _controllers: Array = []  # CharacterController instances
var _current_controller: RefCounted = null  # Current CharacterController
var _selected_char_indices: Array[int] = []  # Selected characters from GameState
var current_character: int = 0  # Slot index (0=Main, 1=Support1, 2=Support2)
var unlocked_characters: Array[int] = [0]  # Start with Main character unlocked

# Burst sounds
var _burst_sounds: Array = []

# Level up sound
var _level_up_sfx: AudioStream = null

# Player state
var burst_current: float = 0.0

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

# Progression system (delegated)
var _progression: PlayerProgression = null
# Legacy accessors (for compatibility)
var xp: int = 0:get = get_xp, set = set_xp
var level: int = 1:get = get_level
var xp_to_next: int = 100:get = get_xp_to_next

# Player subsystems (delegated)
var _health: PlayerHealth = null
var _movement: PlayerMovement = null
var _weapons: PlayerWeapons = null

# Movement state
var dashing: bool = false
var dash_direction: Vector2 = Vector2.ZERO
var dash_timer: float = 0.0
var momentum_timer: float = 0.0
var previous_dash_direction: Vector2 = Vector2.ZERO
var running: bool = false
var wants_running: bool = false
var _dash_press_timer: float = 0.0

# Combat state
var attack_timer: float = 0.0
var shop_open: bool = false

# Visual effects
var _swap_effect: Node2D = null
var _skill_points_notify: Control = null

# Shop upgrade bonuses (cached at start)
var _shop_atk_bonus: float = 0.0  # Multiplier (e.g., 0.25 = +25%)
var _shop_crit_bonus: float = 0.0  # Flat chance (e.g., 0.10 = +10%)
var _shop_xp_bonus: float = 0.0  # Multiplier (e.g., 0.25 = +25%)

# Character-specific shop upgrades (for squad-wide effects)
var _has_rapunzel_healer_upgrade: bool = false  # "I'm a healer, but..." - heal 2% on kill
var _has_commander_burst_upgrade: bool = false  # "Obviously Anderson" - 2x burst generation
var _has_crown_xp_upgrade: bool = false  # "Royal Knowledge" - 2x XP
var _has_cecil_lives_upgrade: bool = false  # "Three Wishes..." - 3 extra lives
var _cecil_lives_remaining: int = 0  # Remaining extra lives
var _cecil_revive_invincible_timer: float = 0.0  # 5s invincibility after revive
var _has_kilo_shield_upgrade: bool = false  # "Protect Me Talos" - shield on kills
var _kilo_shield_current: int = 0  # Current shield amount
var _kilo_shield_max: int = 0  # Max shield (50% of max_hp)
var _kilo_shield_visual: Node2D = null  # Visual shield effect
var _has_nayuta_duplicity_upgrade: bool = false  # "Duplicity" - 10% clone spawn on kills

func _ready() -> void:
	add_to_group("player")
	
	# Set collision layer/mask to prevent squad trapping
	# Layer 2: Player/Allies
	# Mask: World (1), Enemies (3/4), Boulders (3/4), Items (5)
	# Explicitly exclude Layer 2 so squad members don't collide with each other
	collision_layer = 2
	set_collision_mask_value(2, false) # Don't collide with other players/allies
	
	_create_shadow()
	
	# Register sprite for night glow effect
	if _animator:
		NightGlowManager.register_sprite(_animator)
	
	# Initialize progression module
	_progression = PlayerProgression.new()
	add_child(_progression)
	_progression.configure(1, 0, 100)  # level, xp, xp_to_next
	_progression.level_up.connect(_on_progression_level_up)
	
	# Initialize health module
	_health = PlayerHealth.new()
	add_child(_health)
	_health.initialize(hp, max_hp)
	_health.damage_taken.connect(_on_health_damage_taken)
	_health.death.connect(_on_health_death)
	
	# Initialize movement module
	_movement = PlayerMovement.new()
	add_child(_movement)
	_movement.speed = speed
	_movement.dash_speed = dash_speed
	_movement.dash_duration = dash_duration
	_movement.dash_started.connect(_on_dash_started)
	_movement.dash_ended.connect(_on_dash_ended)
	
	# Initialize weapons module
	_weapons = PlayerWeapons.new()
	add_child(_weapons)
	_weapons.attack_cooldown = attack_cooldown
	
	_apply_shop_upgrades()
	_init_audio()
	_init_character_system()
	_init_ui()
	update_sprite()
	call_deferred("_update_hud")
	_level_up_sfx = load("res://assets/sounds/sfx/ui/level.wav")
	# Connect to environment for sprite darkening during night
	_setup_environment_modulate()

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

func _init_audio() -> void:
	var AudioDirectorScript = load("res://scripts/systems/AudioDirector.gd")
	audio_director = AudioDirectorScript.new()
	audio_director.name = "AudioDirector"
	add_child(audio_director)
	
	var MovementEffectsScript = load("res://scripts/player/PlayerMovementEffects.gd")
	var movement_effects = Node2D.new()
	movement_effects.set_script(MovementEffectsScript)
	movement_effects.name = "MovementEffects"
	add_child(movement_effects)
	
	audio_director.play_random_battle_track()

func _init_character_system() -> void:
	_registry = CharacterRegistryScript.get_instance()
	
	# Load selected characters from GameState
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		_selected_char_indices = game_state.selected_character_indices.duplicate()
		print("[PlayerCore] Loaded selected characters: ", _selected_char_indices)
	else:
		# Fallback defaults
		_selected_char_indices = [0, 1, 4]  # Scarlet, Commander, Marian
		print("[PlayerCore] Using fallback characters: ", _selected_char_indices)
	
	# Create controllers only for selected characters
	_controllers.clear()
	var all_ids = _registry.get_all_character_ids()
	for char_idx in _selected_char_indices:
		if char_idx >= 0 and char_idx < all_ids.size():
			var char_id = all_ids[char_idx]
			var controller = _registry.create_controller(char_id, self)
			_controllers.append(controller)
			print("[PlayerCore] Created controller for %s (index %d)" % [char_id, char_idx])
		else:
			_controllers.append(null)
			push_warning("[PlayerCore] Invalid character index: %d" % char_idx)
	
	# Start with Main character (slot 0)
	current_character = 0
	unlocked_characters = [0]
	
	# Set initial controller
	if current_character < _controllers.size() and _controllers[current_character] != null:
		_current_controller = _controllers[current_character]
	
	# Load burst sounds for selected characters
	_burst_sounds = []
	for char_idx in _selected_char_indices:
		if char_idx >= 0 and char_idx < all_ids.size():
			var char_id = all_ids[char_idx]
			var sound = _registry.get_burst_sound(char_id)
			_burst_sounds.append(sound)
		else:
			_burst_sounds.append(null)
	
	# Apply character-specific shop upgrades for selected squad
	_apply_character_shop_upgrades(all_ids)
	
	# Apply all unlocked talents to controllers
	_apply_all_talents_to_controllers()

func _apply_character_shop_upgrades(all_ids: Array) -> void:
	"""Apply character-specific shop upgrades based on selected squad.
	   Only applies if the character's slot is unlocked in the skill tree."""
	for slot_idx in range(_selected_char_indices.size()):
		var char_idx: int = _selected_char_indices[slot_idx]
		if char_idx < 0 or char_idx >= all_ids.size():
			continue
		
		# Check if this character slot is unlocked in the skill tree
		# Support characters (slots 1, 2) must be unlocked during gameplay
		if slot_idx not in unlocked_characters:
			continue
		
		var char_id: String = all_ids[char_idx]
		
		# Check each character's basic_attack upgrade
		match char_id:
			"rapunzel":
				if ShopMenuScript.has_character_upgrade("rapunzel", "basic_attack"):
					_has_rapunzel_healer_upgrade = true
					print("[PlayerCore] Rapunzel 'I'm a healer, but...' upgrade active")
			"commander":
				if ShopMenuScript.has_character_upgrade("commander", "basic_attack"):
					_has_commander_burst_upgrade = true
					print("[PlayerCore] Commander 'Obviously Anderson' upgrade active")
			"crown":
				if ShopMenuScript.has_character_upgrade("crown", "basic_attack"):
					_has_crown_xp_upgrade = true
					print("[PlayerCore] Crown 'Royal Knowledge' upgrade active")
			"cecil":
				if ShopMenuScript.has_character_upgrade("cecil", "basic_attack"):
					_has_cecil_lives_upgrade = true
					_cecil_lives_remaining = 3
					print("[PlayerCore] Cecil 'Three Wishes...' upgrade active (3 lives)")
			"kilo":
				if ShopMenuScript.has_character_upgrade("kilo", "basic_attack"):
					_has_kilo_shield_upgrade = true
					_kilo_shield_max = int(max_hp * 0.5)
					_kilo_shield_current = 0  # Shield starts empty
					_create_kilo_shield_visual()
					# Update the HUD to show empty shield bar
					call_deferred("_update_shield_display")
					print("[PlayerCore] Kilo 'Protect Me Talos' upgrade active (max shield: %d)" % _kilo_shield_max)
			"nayuta":
				if ShopMenuScript.has_character_upgrade("nayuta", "basic_attack"):
					_has_nayuta_duplicity_upgrade = true
					print("[PlayerCore] Nayuta 'Duplicity' upgrade active (10% clone spawn)")

func _apply_upgrade_for_character(char_idx: int) -> void:
	"""Apply shop upgrade for a specific character when unlocked during gameplay."""
	if not _registry:
		return
	var all_ids: Array = _registry.get_all_character_ids()
	if char_idx < 0 or char_idx >= all_ids.size():
		return
	
	var char_id: String = all_ids[char_idx]
	
	match char_id:
		"rapunzel":
			if ShopMenuScript.has_character_upgrade("rapunzel", "basic_attack"):
				_has_rapunzel_healer_upgrade = true
				print("[PlayerCore] Rapunzel 'I'm a healer, but...' upgrade now active (unlocked)")
		"commander":
			if ShopMenuScript.has_character_upgrade("commander", "basic_attack"):
				_has_commander_burst_upgrade = true
				print("[PlayerCore] Commander 'Obviously Anderson' upgrade now active (unlocked)")
		"crown":
			if ShopMenuScript.has_character_upgrade("crown", "basic_attack"):
				_has_crown_xp_upgrade = true
				print("[PlayerCore] Crown 'Royal Knowledge' upgrade now active (unlocked)")
		"cecil":
			if ShopMenuScript.has_character_upgrade("cecil", "basic_attack"):
				_has_cecil_lives_upgrade = true
				_cecil_lives_remaining = 3
				print("[PlayerCore] Cecil 'Three Wishes...' upgrade now active (unlocked)")
		"kilo":
			if ShopMenuScript.has_character_upgrade("kilo", "basic_attack"):
				_has_kilo_shield_upgrade = true
				_kilo_shield_max = int(max_hp * 0.5)
				_kilo_shield_current = 0  # Shield starts empty
				_create_kilo_shield_visual()
				call_deferred("_update_shield_display")
				print("[PlayerCore] Kilo 'Protect Me Talos' upgrade now active (unlocked)")
		"nayuta":
			if ShopMenuScript.has_character_upgrade("nayuta", "basic_attack"):
				_has_nayuta_duplicity_upgrade = true
				print("[PlayerCore] Nayuta 'Duplicity' upgrade now active (unlocked)")

func _apply_all_talents_to_controllers() -> void:
	"""Apply all unlocked talents to controllers when the game starts."""
	var tree := _get_talent_tree()
	if not tree or not tree.has_method("get_unlocked_talents"):
		return
	
	var unlocked_talents: Dictionary = tree.get_unlocked_talents()
	
	# Apply talents for each character slot
	for slot_idx in range(_controllers.size()):
		if slot_idx >= _selected_char_indices.size():
			continue
		
		var registry_idx: int = _selected_char_indices[slot_idx]
		var controller = _controllers[slot_idx]
		
		if controller and registry_idx in unlocked_talents:
			var char_talents: Dictionary = unlocked_talents[registry_idx]
			for talent_id in char_talents:
				var talent_level: int = char_talents[talent_id]
				for i in range(talent_level):
					if controller.has_method("apply_talent"):
						controller.apply_talent(talent_id)
						print("[PlayerCore] Applied talent %s (level %d) to controller slot %d (registry %d)" % [talent_id, i + 1, slot_idx, registry_idx])

func on_enemy_killed(_enemy: Node2D, killer_source: String = "player") -> void:
	"""Called by Level when an enemy dies. Handles kill-based character upgrades.
	   Only player kills (player, projectile, cecil_drone) grant benefits."""
	# Check if this is a valid kill source for upgrades
	# Valid: player, projectile, cecil_drone, summon (for other upgrades like Kilo shield)
	# Invalid: charmed_enemy
	var valid_kill: bool = killer_source in ["player", "projectile", "cecil_drone", "summon"]
	
	# Rapunzel: "I'm a healer, but..." - Heal 2% HP on each kill (exclude clone kills)
	var rapunzel_valid_kill: bool = killer_source in ["player", "projectile", "cecil_drone"]
	if _has_rapunzel_healer_upgrade and rapunzel_valid_kill:
		var heal_amount: int = int(max_hp * 0.02)
		if heal_amount < 1:
			heal_amount = 1
		heal(heal_amount)
	
	# Kilo: "Protect Me Talos" - Gain 1% of max HP as shield per kill (only valid kills)
	if _has_kilo_shield_upgrade and valid_kill:
		var shield_gain: int = int(max_hp * 0.01)
		if shield_gain < 1:
			shield_gain = 1
		_kilo_shield_current = min(_kilo_shield_current + shield_gain, _kilo_shield_max)
		_update_shield_display()
	
	# Nayuta: "Duplicity" - 10% chance to spawn a clone when an enemy dies (any kill)
	if _has_nayuta_duplicity_upgrade and randf() < 0.10:
		_spawn_duplicity_clone()

func _spawn_duplicity_clone() -> void:
	"""Spawn a clone at the player's position for Nayuta's Duplicity upgrade."""
	var NayutaCloneScript = preload("res://scripts/characters/effects/NayutaClone.gd")
	var clone: Node2D = NayutaCloneScript.new()
	get_parent().add_child(clone)
	clone.global_position = global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	
	# Clone stats: 25% player HP with level scaling, 20% damage multiplier, no heal on death
	# HP scales: base 25% of player HP, +25% per level
	var hp_level_mult := 1.0 + (level - 1) * 0.25
	var clone_hp: int = maxi(1, int((max_hp / 4.0) * hp_level_mult))
	var clone_attack: float = 0.2
	
	# Determine weapon type - use Nayuta's weapon pool if available
	var weapon_type: String = "smg"  # Default fallback
	if _current_controller is NayutaController:
		var nayuta_ctrl := _current_controller as NayutaController
		if nayuta_ctrl.has_method("get_weapon_pool"):
			var weapon_pool: Array = nayuta_ctrl.get_weapon_pool()
			if weapon_pool.size() > 0:
				weapon_type = weapon_pool[randi() % weapon_pool.size()]
	
	clone.call("initialize", self, weapon_type, clone_hp, clone_attack, false, level)

func _init_ui() -> void:
	if overhead_hud:
		overhead_hud.update_health(hp, max_hp)
		overhead_hud.update_burst(burst_current, burst_max)
		# Pass registry index (not slot index) for proper ammo display
		var registry_idx: int = _selected_char_indices[current_character] if current_character < _selected_char_indices.size() else 0
		overhead_hud.update_character(registry_idx)
		_update_overhead_ammo()
	update_xp_bar()

func _update_hud() -> void:
	if player_hud and player_hud.is_inside_tree():
		player_hud.set_character(current_character, is_burst_unlocked())
		player_hud.configure(hp, max_hp, burst_current, burst_max, stamina, max_stamina)

func update_sprite() -> void:
	if not _animator or not _registry:
		push_warning("[PlayerCore] update_sprite: animator or registry missing")
		return
	
	# current_character is slot index (0, 1, 2)
	# _selected_char_indices maps slot to registry index
	if current_character < 0 or current_character >= _selected_char_indices.size():
		push_warning("[PlayerCore] update_sprite: current_character %d out of bounds" % current_character)
		return
	
	var registry_idx: int = _selected_char_indices[current_character]
	var char_data = _registry.get_character_by_index(registry_idx)
	if char_data:
		var texture = char_data.get_sprite()
		if texture:
			# Default animation settings - could be in CharacterData
			_animator.configure(texture, 3, 4, 6.0, 0.2)
			print("[PlayerCore] Loaded sprite for slot %d (registry %d)" % [current_character, registry_idx])
		else:
			push_warning("[PlayerCore] update_sprite: No texture for character %d" % registry_idx)
		
		# Apply character stats
		_apply_character_stats(char_data)
	else:
		push_warning("[PlayerCore] update_sprite: No char_data for index %d" % registry_idx)
	
	if player_hud and player_hud.is_inside_tree():
		player_hud.set_character(current_character, is_burst_unlocked())

func _apply_character_stats(char_data: Resource) -> void:
	"""Apply character-specific stats like speed."""
	if char_data.base_speed > 0:
		# Apply base speed then shop bonus
		var base_speed: float = char_data.base_speed
		var speed_bonus: float = ShopMenuScript.get_upgrade_bonus("speed")
		speed = base_speed * (1.0 + speed_bonus)
		print("[PlayerCore] Applied speed: %.1f (base: %.1f, +%.0f%% shop)" % [speed, base_speed, speed_bonus * 100])

## Calculate damage with level scaling and shop ATK bonus
## Base formula: base_damage * level_mult * (1 + shop_atk_bonus)
## At level 1: 1.0x, level 2: 1.25x, level 3: 1.5x, level 5: 2.0x, level 10: 3.25x
func calculate_damage(base_damage: float, multiplier: float = 1.0) -> int:
	var level_multiplier: float = 1.0 + (level - 1) * 0.25
	var atk_multiplier: float = 1.0 + _shop_atk_bonus
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
	if current_character < 0 or current_character >= _selected_char_indices.size():
		return 1.0
	var registry_idx: int = _selected_char_indices[current_character]
	if _registry:
		var char_data = _registry.get_character_by_index(registry_idx)
		if char_data:
			return char_data.base_damage
	return 1.0

## Shorthand: calculate damage using current character's base damage
func calc_damage(multiplier: float = 1.0) -> int:
	return calculate_damage(get_base_damage(), multiplier)

func is_burst_unlocked() -> bool:
	if _current_controller:
		# Check if burst talent is unlocked for this character
		# Use registry index for talent lookup
		var registry_idx: int = _selected_char_indices[current_character] if current_character < _selected_char_indices.size() else 0
		return _get_talent_level(registry_idx, "burst") > 0
	return false

func _get_talent_tree() -> Control:
	var canvas := get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = get_tree().root
	return canvas.get_node_or_null("TalentTree")

func _get_shop_menu() -> Control:
	var canvas := get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = get_tree().root
	return canvas.get_node_or_null("ShopMenu")

func _get_talent_level(char_id: int, talent_id: String) -> int:
	var tree := _get_talent_tree()
	if tree and tree.has_method("get_talent_level"):
		return tree.get_talent_level(char_id, talent_id)
	return 0

func get_talent_level(char_id: int, talent_id: String) -> int:
	return _get_talent_level(char_id, talent_id)

func get_sin_captivating_level() -> int:
	"""Get Sin's Captivating talent level directly from the controller (if Sin is in party)."""
	for controller in _controllers:
		if controller is SinController:
			return controller.captivating_level
	return 0

func get_sin_damage() -> int:
	"""Get Sin's current damage for explosion calculations (if Sin is in party)."""
	for controller in _controllers:
		if controller is SinController:
			return calc_damage()  # Use player's damage (includes level scaling)
	return 0

func _create_shadow() -> void:
	# Uses the centralized ShadowHelper utility
	ShadowHelper.create_player_shadow(self)

func _apply_unshaded_shader() -> void:
	# Apply the same simple unshaded shader used by enemies so the player
	# doesn't get incorrectly darkened by CanvasModulate during storms.
	var shader = load("res://resources/shaders/enemy_red_glow.gdshader")
	if shader and _animator:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_animator.material = mat

func _setup_environment_modulate() -> void:
	# Connect to EnvironmentController to darken player sprite during night
	var env_controller = get_tree().get_first_node_in_group("environment_controller")
	if env_controller and env_controller is EnvironmentController:
		if env_controller.has_signal("modulate_changed"):
			env_controller.modulate_changed.connect(_on_environment_modulate_changed)
			# Set initial modulate
			_on_environment_modulate_changed(env_controller.current_modulate)

func _on_environment_modulate_changed(color: Color) -> void:
	# Manual darkening removed - handled by vignette overlay now
	pass

# ============= DAMAGE / HEALING =============

func take_damage(dmg: int) -> void:
	if invincible:
		return
	# Debug invincibility from debug menu
	if has_meta("debug_invincible") and get_meta("debug_invincible"):
		return
	if _current_controller and _current_controller.is_invincible():
		return
	
	# Check if Cecil's shield can absorb the hit
	if _current_controller is CecilController:
		var cecil_ctrl := _current_controller as CecilController
		if cecil_ctrl.try_absorb_damage():
			# Shield absorbed the hit
			return
	
	# Check if Kilo's "Protect Me Talos" shield can absorb damage
	if _has_kilo_shield_upgrade and _kilo_shield_current > 0:
		if _kilo_shield_current >= dmg:
			# Shield fully absorbs the hit
			_kilo_shield_current -= dmg
			_update_shield_display()
			_spawn_shield_hit_effect()
			return
		else:
			# Shield partially absorbs
			dmg -= _kilo_shield_current
			_kilo_shield_current = 0
			_update_shield_display()
			_spawn_shield_hit_effect()
			# Continue with reduced damage
	
	var prev_hp = hp
	hp -= dmg
	
	if screen_flash and screen_flash.has_method("flash_damage"):
		screen_flash.flash_damage()
	
	# Hit effects
	var HitSparkScript = preload("res://scripts/effects/HitSpark.gd")
	if get_parent() and HitSparkScript:
		HitSparkScript.spawn_player_hit(get_parent(), global_position)
	
	# Camera shake disabled for player damage
	# var combat_juice_script = load("res://scripts/CombatJuice.gd")
	# if combat_juice_script and combat_juice_script.instance:
	#	combat_juice_script.camera_shake(12.0)
	
	var FloatingNumber = preload("res://scripts/effects/FloatingDamageNumber.gd")
	if get_parent():
		FloatingNumber.spawn_damage(get_parent(), global_position + Vector2(0, -100), dmg)
	
	_update_health_display(hp - prev_hp, true)
	
	# Emit global event for decoupled systems
	EventBus.player_damaged.emit(dmg, null)
	
	if hp <= 0:
		_on_player_death()

func _on_player_death() -> void:
	# Cecil "Three Wishes..." upgrade: Use an extra life if available
	if _has_cecil_lives_upgrade and _cecil_lives_remaining > 0:
		_cecil_lives_remaining -= 1
		hp = max_hp
		_update_health_display(max_hp, false)
		_spawn_revive_effect()
		# Grant 5 seconds of invincibility
		_cecil_revive_invincible_timer = 5.0
		invincible = true
		print("[PlayerCore] Cecil's extra life used! %d lives remaining (5s invincibility)" % _cecil_lives_remaining)
		return
	
	# Record the run result to GameState for leaderboard
	if GameState:
		GameState.record_run_result("")
	
	# Find the Level node and trigger defeat menu
	var level_node = get_parent()
	if level_node and level_node.has_method("show_defeat_menu"):
		level_node.show_defeat_menu()
	else:
		# Fallback: try to find Level in tree
		var root = get_tree().current_scene
		if root and root.has_method("show_defeat_menu"):
			root.show_defeat_menu()

func heal(amount: int) -> void:
	var prev_hp = hp
	hp = min(hp + amount, max_hp)
	var actual_heal = hp - prev_hp
	
	# Always heal Nayuta clones for the full intended amount
	_heal_nayuta_clones(amount)
	
	if actual_heal > 0:
		var FloatingNumber = preload("res://scripts/effects/FloatingDamageNumber.gd")
		if get_parent():
			FloatingNumber.spawn_heal(get_parent(), global_position + Vector2(0, -100), actual_heal)
	
	_update_health_display(hp - prev_hp, true)

func _update_health_display(change: int = 0, animate: bool = false) -> void:
	if player_hud:
		player_hud.update_health(hp, max_hp, change, animate)
	if overhead_hud:
		overhead_hud.update_health(hp, max_hp)

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

func register_burst_hit(_target = null, from_burst: bool = false) -> void:
	if from_burst:
		return
	if not is_burst_unlocked():
		return
	
	# Commander "Obviously Anderson" upgrade: 2x burst generation
	var burst_gain: float = burst_per_hit
	if _has_commander_burst_upgrade:
		burst_gain *= 2.0
	
	burst_current = min(burst_current + burst_gain, burst_max)
	if player_hud:
		player_hud.update_burst(burst_current, burst_max, true)
	if overhead_hud:
		overhead_hud.update_burst(burst_current, burst_max)

func is_burst_ready() -> bool:
	return burst_current >= burst_max

func use_burst() -> bool:
	if not is_burst_ready():
		return false
	# Debug: don't consume burst if infinite burst enabled
	if not (has_meta("debug_infinite_burst") and get_meta("debug_infinite_burst")):
		burst_current = 0.0
	if player_hud:
		player_hud.update_burst(burst_current, burst_max, true)
	if overhead_hud:
		overhead_hud.update_burst(burst_current, burst_max)
	return true

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
	if current_character < 0 or current_character >= _burst_sounds.size():
		return
	var sound = _burst_sounds[current_character]
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
		audio_player.bus = "SFX"  # Use SFX bus for voice lines
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
	if _has_crown_xp_upgrade:
		xp_multiplier *= 2.0
	
	_progression.set_xp_multiplier(xp_multiplier)
	
	# Delegate to progression module (it handles EventBus emission)
	var leveled_up = _progression.add_xp(amount)
	
	# Update UI
	update_xp_bar()
	
	# Level up effects handled by callback (_on_progression_level_up)

func _on_progression_level_up(new_level: int, skill_points_gained: int) -> void:
	"""Called when PlayerProgression module triggers a level up"""
	# Add skill points (could be multiple if leveled up more than once)
	for i in range(skill_points_gained):
		_add_skill_point()
	
	# UI flash
	if xp_ui and xp_ui.has_method("flash_level_up"):
		xp_ui.flash_level_up()
	
	# Play level up sound
	_play_level_up_sound()
	
	# Spawn WoW-style golden glow effect around player
	_spawn_level_up_glow()
	
	# Note: EventBus.player_leveled_up already emitted by PlayerProgression

func _on_health_damage_taken(amount: int) -> void:
	"""Called when PlayerHealth module processes damage"""
	# Update HUD
	call_deferred("_update_hud")

func _on_health_death() -> void:
	"""Called when PlayerHealth module triggers death"""
	# Handle player death
	# Note: Death logic already in PlayerCore, will be refactored later
	pass

func _on_dash_started() -> void:
	"""Called when PlayerMovement starts a dash"""
	# Could add dash effects here
	pass

func _on_dash_ended() -> void:
	"""Called when PlayerMovement ends a dash"""
	pass

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

func _spawn_revive_effect() -> void:
	## Spawns a blue revive effect when Cecil's extra life is used
	var ReviveEffectScript = preload("res://scripts/effects/ReviveEffect.gd")
	var effect = ReviveEffectScript.new()
	get_parent().add_child(effect)
	effect.global_position = global_position

func _create_kilo_shield_visual() -> void:
	## Creates the visual shield effect for Kilo's upgrade
	if _kilo_shield_visual and is_instance_valid(_kilo_shield_visual):
		return
	
	var KiloShieldVisualScript = preload("res://scripts/effects/KiloShieldVisual.gd")
	_kilo_shield_visual = KiloShieldVisualScript.new()
	_kilo_shield_visual.name = "KiloShieldVisual"
	call_deferred("_add_kilo_shield_visual")

func _add_kilo_shield_visual() -> void:
	if _kilo_shield_visual and is_instance_valid(_kilo_shield_visual):
		get_parent().add_child(_kilo_shield_visual)
		_kilo_shield_visual.initialize(self)

func _update_shield_display() -> void:
	## Updates the overhead HUD and visual shield with current shield status
	if overhead_hud and overhead_hud.has_method("update_shield"):
		overhead_hud.update_shield(_kilo_shield_current, _kilo_shield_max)
	
	# Update visual shield
	if _kilo_shield_visual and is_instance_valid(_kilo_shield_visual):
		_kilo_shield_visual.update_shield(_kilo_shield_current, _kilo_shield_max)

func _spawn_shield_hit_effect() -> void:
	## Spawns a cyan shield hit effect when Kilo's shield absorbs damage
	var ShieldHitScript = preload("res://scripts/effects/ShieldHitEffect.gd")
	var effect = ShieldHitScript.new()
	get_parent().add_child(effect)
	effect.global_position = global_position
	
	# Also trigger flash on visual shield
	if _kilo_shield_visual and is_instance_valid(_kilo_shield_visual) and _kilo_shield_visual.has_method("on_shield_hit"):
		_kilo_shield_visual.on_shield_hit()

func update_xp_bar() -> void:
	if xp_ui and xp_ui.has_method("set_xp"):
		xp_ui.set_xp(xp, xp_to_next)
		xp_ui.set_level(level)

func _add_skill_point() -> void:
	var canvas := get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = get_tree().root
	
	var existing := canvas.get_node_or_null("TalentTree")
	if existing:
		existing.add_skill_points(1)
	else:
		var TalentTreeScript = preload("res://scripts/ui/TalentTree.gd")
		var tree = TalentTreeScript.new()
		tree.name = "TalentTree"
		tree.set_anchors_preset(Control.PRESET_FULL_RECT)
		canvas.add_child(tree)
		tree.add_skill_points(1)
		tree.talent_unlocked.connect(_on_talent_unlocked)
		tree.tree_closed.connect(_on_talent_tree_closed)
		existing = tree
	
	if overhead_hud:
		overhead_hud.update_skill_points_available(existing.get_skill_points() > 0)
	
	# Show/update skill points notification
	_update_skill_points_notification(existing.get_skill_points())

func _on_talent_unlocked(char_id: int, talent_id: String) -> void:
	# char_id is a registry index, we need to convert to slot index
	var slot_idx: int = _selected_char_indices.find(char_id)
	
	# Unlock character if this is an unlock talent
	if talent_id == "unlock":
		# Find which slot this registry index corresponds to
		if slot_idx >= 0 and slot_idx not in unlocked_characters:
			unlocked_characters.append(slot_idx)
			unlocked_characters.sort()
			print("[PlayerCore] Unlocked character slot %d (registry %d)" % [slot_idx, char_id])
			
			# Apply shop upgrades for the newly unlocked character
			_apply_upgrade_for_character(char_id)
	
	# Forward talent to controller - use slot index
	if slot_idx >= 0 and slot_idx < _controllers.size():
		var controller = _controllers[slot_idx]
		if controller and controller.has_method("apply_talent"):
			controller.apply_talent(talent_id)
	
	# Save shop data when talents change
	var shop_menu = _get_shop_menu()
	if shop_menu and shop_menu.has_method("_save_shop_data"):
		shop_menu._save_shop_data()
	
	# Update burst visibility
	_update_burst_visibility()

func _on_talent_tree_closed() -> void:
	shop_open = false
	if get_parent().has_method("set_game_paused"):
		get_parent().call_deferred("set_game_paused", false)
	
	var tree := _get_talent_tree()
	if tree and overhead_hud:
		overhead_hud.update_skill_points_available(tree.get_skill_points() > 0)
	
	# Update skill points notification
	if tree:
		_update_skill_points_notification(tree.get_skill_points())

func _update_skill_points_notification(points: int) -> void:
	var canvas := get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = get_tree().root
	
	# Hide if no points
	if points <= 0:
		if _skill_points_notify and is_instance_valid(_skill_points_notify):
			_skill_points_notify.visible = false
		return
	
	# Create notification if needed
	if _skill_points_notify == null or not is_instance_valid(_skill_points_notify):
		_skill_points_notify = _create_skill_points_notification()
		canvas.add_child(_skill_points_notify)
	
	# Update text and show
	var main_label: Label = _skill_points_notify.get_node_or_null("MainLabel")
	if main_label:
		main_label.text = "SKILL POINTS AVAILABLE × %d" % points
	_skill_points_notify.visible = true
	
	# Animate pulse
	_animate_skill_points_notification()

func _create_skill_points_notification() -> Control:
	var container := Control.new()
	container.name = "SkillPointsNotify"
	# Position under player HUD with good padding
	container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	container.position = Vector2(35, 200)
	container.size = Vector2(240, 48)
	container.pivot_offset = Vector2(120, 24)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Background panel with golden border
	var bg := Panel.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.02, 0.02, 0.04, 0.95)
	bg_style.border_color = Color(1.0, 0.85, 0.2, 1.0)
	bg_style.set_border_width_all(3)
	bg_style.set_corner_radius_all(6)
	bg_style.shadow_color = Color(1.0, 0.75, 0.0, 0.5)
	bg_style.shadow_size = 5
	bg.add_theme_stylebox_override("panel", bg_style)
	container.add_child(bg)
	
	# Main label
	var main_label := Label.new()
	main_label.name = "MainLabel"
	main_label.text = "SKILL POINTS AVAILABLE × 1"
	main_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main_label.add_theme_font_size_override("font_size", 16)
	main_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	main_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	main_label.add_theme_constant_override("shadow_offset_x", 1)
	main_label.add_theme_constant_override("shadow_offset_y", 1)
	main_label.position = Vector2(0, 4)
	main_label.size = Vector2(240, 24)
	container.add_child(main_label)
	
	# Sub label
	var sub_label := Label.new()
	sub_label.name = "SubLabel"
	sub_label.text = "PRESS TAB TO OPEN SKILL TREE"
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_label.add_theme_font_size_override("font_size", 9)
	sub_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.85))
	sub_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	sub_label.add_theme_constant_override("shadow_offset_x", 1)
	sub_label.add_theme_constant_override("shadow_offset_y", 1)
	sub_label.position = Vector2(0, 28)
	sub_label.size = Vector2(240, 16)
	container.add_child(sub_label)
	
	return container

func _animate_skill_points_notification() -> void:
	if _skill_points_notify == null or not is_instance_valid(_skill_points_notify):
		return
	
	# Kill existing tween
	if _skill_points_notify.has_meta("pulse_tween"):
		var old_tween = _skill_points_notify.get_meta("pulse_tween")
		if old_tween and is_instance_valid(old_tween):
			old_tween.kill()
	
	# Pulse animation
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(_skill_points_notify, "scale", Vector2(1.05, 1.05), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_skill_points_notify, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_skill_points_notify.set_meta("pulse_tween", tween)

func _update_burst_visibility() -> void:
	# Burst bar should only be visible for the CURRENT character if they have burst unlocked
	# Use registry index for talent lookup
	var registry_idx: int = _selected_char_indices[current_character] if current_character < _selected_char_indices.size() else 0
	var current_has_burst := _get_talent_level(registry_idx, "burst") > 0
	
	if player_hud and player_hud.has_method("set_burst_unlocked"):
		player_hud.set_burst_unlocked(current_has_burst)
		# Also refresh the burst gauge value to prevent visual reset
		if current_has_burst:
			player_hud.update_burst(burst_current, burst_max, false)
	if overhead_hud and overhead_hud.has_method("update_burst_unlocked"):
		overhead_hud.update_burst_unlocked(current_has_burst)
		# Also refresh the burst gauge value
		if current_has_burst:
			overhead_hud.update_burst(burst_current, burst_max)

# ============= CHARACTER SWITCHING =============

func switch_character(direction: int) -> void:
	if unlocked_characters.size() <= 1:
		return
	
	# Cleanup old controller before switching
	if _current_controller and _current_controller.has_method("cleanup"):
		_current_controller.cleanup()
	
	var idx = unlocked_characters.find(current_character)
	idx = (idx + direction + unlocked_characters.size()) % unlocked_characters.size()
	current_character = unlocked_characters[idx]
	_current_controller = _controllers[current_character]
	
	_trigger_swap_effect()
	update_sprite()
	_update_overhead_ammo()
	_update_burst_visibility()  # Update burst bar for new character
	
	if overhead_hud:
		# Pass registry index (not slot index) for proper ammo display
		var registry_idx: int = _selected_char_indices[current_character] if current_character < _selected_char_indices.size() else 0
		overhead_hud.update_character(registry_idx)

func _trigger_swap_effect() -> void:
	if not is_instance_valid(_swap_effect):
		_swap_effect = Node2D.new()
		_swap_effect.set_script(CharacterSwapEffectScript)
		_swap_effect.name = "SwapEffect"
		_swap_effect.z_index = 50
		get_parent().add_child(_swap_effect)
	
	if _swap_effect.has_method("trigger"):
		_swap_effect.trigger(current_character, global_position)

# ============= AMMO UI =============

func _update_overhead_ammo() -> void:
	if not overhead_hud or not _current_controller:
		return
	
	var cur_ammo = _current_controller.ammo
	var max_ammo = _current_controller.max_ammo
	var is_reloading = _current_controller.is_reloading
	var reload_time = 1.5
	if _current_controller.data:
		reload_time = _current_controller.data.reload_time
	
	if max_ammo <= 0:
		# Unlimited ammo
		overhead_hud.update_ammo(1, 1, false, reload_time)
	else:
		overhead_hud.update_ammo(cur_ammo, max_ammo, is_reloading, reload_time)

func _update_overhead_special() -> void:
	if not overhead_hud or not _current_controller:
		return
	
	var unlocked = _current_controller.special_unlocked
	var progress = 1.0
	
	# Update Scarlet's special unlocked status (index 1 in CharacterRegistry)
	# Check current character index in _selected_char_indices
	if _selected_char_indices.size() > current_character:
		var char_idx = _selected_char_indices[current_character]
		if char_idx == 1:  # Scarlet's index in CharacterRegistry
			overhead_hud.update_scarlet_special_unlocked(unlocked)
	
	# Get special cooldown progress from controller
	if _current_controller.has_method("get_special_cooldown_progress"):
		progress = _current_controller.get_special_cooldown_progress()
	elif _current_controller.has_method("get_special_progress"):
		progress = _current_controller.get_special_progress()
	
	# Check if controller supports charges (Snow White turrets)
	if _current_controller.has_method("get_special_charges"):
		var charges = _current_controller.get_special_charges()
		var max_charges = _current_controller.get_special_max_charges()
		if overhead_hud.has_method("update_special_ability_with_charges"):
			overhead_hud.update_special_ability_with_charges(unlocked, progress, charges, max_charges)
			return
	
	overhead_hud.update_special_ability(unlocked, progress)

# ============= MAIN GAME LOOP =============

func _process(delta: float) -> void:
	# Update controller
	if _current_controller:
		_current_controller.process(delta)
	
	# Stamina management
	var infinite_stamina: bool = has_meta("debug_infinite_stamina") and get_meta("debug_infinite_stamina")
	if running and not dashing and not infinite_stamina:
		stamina = max(stamina - running_stamina_drain * delta, 0)
		if player_hud:
			player_hud.update_stamina(stamina, max_stamina, true)
	else:
		if infinite_stamina:
			stamina = max_stamina
		else:
			stamina = min(stamina + stamina_regen * delta, max_stamina)
		if player_hud:
			player_hud.update_stamina(stamina, max_stamina, false)
	
	# Update ammo UI
	_update_overhead_ammo()
	
	# Update special ability indicator
	_update_overhead_special()

func _physics_process(delta: float) -> void:
	if shop_open:
		return
	
	# Cecil revive invincibility timer
	if _cecil_revive_invincible_timer > 0.0:
		_cecil_revive_invincible_timer -= delta
		if _cecil_revive_invincible_timer <= 0.0:
			_cecil_revive_invincible_timer = 0.0
			if not dashing:  # Don't remove invincibility if currently dashing
				invincible = false
	
	# Grace timer for dash
	if _dash_press_timer > 0.0:
		_dash_press_timer -= delta
	
	# Input
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	input_vector = input_vector.normalized()
	
	var aim_direction = _get_aim_direction()
	
	# Attack cooldown
	if attack_timer > 0:
		attack_timer -= delta
	
	# Handle attacks
	_handle_attacks(aim_direction, delta)
	
	# Handle dash
	_handle_dash(input_vector, delta)
	
	# Handle movement
	_handle_movement(input_vector, delta)
	
	# Character swap and burst are handled in _input()

func _get_aim_direction() -> Vector2:
	var mouse_world_pos = get_global_mouse_position()
	var aim = (mouse_world_pos - global_position).normalized()
	return aim if aim != Vector2.ZERO else Vector2.RIGHT

func _handle_attacks(aim_direction: Vector2, _delta: float) -> void:
	if not _current_controller:
		return
	
	# Check if Kilo burst mode is active for automatic fire
	var is_kilo_burst: bool = _current_controller is KiloController and _current_controller.burst_active
	
	# Check if Commander (AR), Sin (SMG), Cecil (SMG), Crown (Minigun), Marian (Minigun), or Nayuta (SMG) - always auto-fire
	var is_auto_fire: bool = _current_controller is CommanderController or _current_controller is SinController or _current_controller is CecilController or _current_controller is CrownController or _current_controller is MarianController or _current_controller is NayutaController
	
	# Primary attack - during Kilo burst or auto-fire weapons: continuous while holding, no stamina cost
	var wants_attack := false
	if is_kilo_burst or is_auto_fire:
		wants_attack = Input.is_action_pressed("attack")
	else:
		wants_attack = Input.is_action_just_pressed("attack")
	
	var can_fire := wants_attack and attack_timer <= 0
	if not is_kilo_burst and not is_auto_fire:
		can_fire = can_fire and stamina >= attack_stamina_cost
	
	if can_fire:
		if _current_controller.attack(aim_direction):
			if not is_kilo_burst and not is_auto_fire:
				stamina -= attack_stamina_cost
			
# Combat juice (no camera shake for regular attacks)
			
			# Set cooldown based on controller
			if _current_controller.has_method("get_attack_cooldown"):
				attack_timer = _current_controller.get_attack_cooldown()
			else:
				attack_timer = attack_cooldown
	
	# Special attack (thrust)
	if Input.is_action_just_pressed("thrust") and attack_timer <= 0 and stamina >= attack_stamina_cost:
		if _current_controller.use_special(aim_direction):
			stamina -= attack_stamina_cost
			attack_timer = attack_cooldown

func _handle_dash(input_vector: Vector2, delta: float) -> void:
	if dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			dashing = false
			invincible = false
			if wants_running and stamina > 0:
				running = true
		else:
			velocity = dash_direction * dash_speed
			invincible = true
	elif Input.is_action_just_pressed("dash") and input_vector != Vector2.ZERO and not running and stamina >= dash_stamina_cost:
		stamina -= dash_stamina_cost
		dashing = true
		dash_direction = input_vector
		dash_timer = dash_duration
		_dash_press_timer = dash_press_grace
		wants_running = Input.is_action_pressed("dash")
		
		# Notify camera for juicy lag effect
		var camera = get_node_or_null("Camera2D")
		if camera and camera.has_method("notify_dash"):
			camera.notify_dash()

func _handle_movement(input_vector: Vector2, delta: float) -> void:
	if dashing:
		move_and_slide()
		return
	
	# Running
	if running:
		if not Input.is_action_pressed("dash") or stamina <= 0 or input_vector == Vector2.ZERO:
			running = false
	
	var target_speed = speed
	if running:
		target_speed *= running_speed_multiplier
	
	if input_vector != Vector2.ZERO:
		velocity = velocity.move_toward(input_vector * target_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	
	move_and_slide()
	
	# Update sprite animation based on movement direction
	if _animator and _animator.has_method("update_state"):
		var aim_dir = _get_aim_direction()
		_animator.update_state(velocity, aim_dir)

func _input(event: InputEvent) -> void:
	if shop_open:
		return
	
	# Mouse wheel for character switching
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			switch_character(1)  # Next character
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			switch_character(-1)  # Previous character
	
	# Keyboard inputs
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_select_character_by_index(0)
			KEY_2:
				_select_character_by_index(1)
			KEY_3:
				_select_character_by_index(2)
			KEY_4:
				_select_character_by_index(3)
			KEY_E:
				_attempt_burst_activation()
			KEY_R:
				_try_manual_reload()
			KEY_TAB:
				_show_talent_tree()

func _select_character_by_index(index: int) -> void:
	if index in unlocked_characters and index in _controllers:
		current_character = index
		_current_controller = _controllers[current_character]
		
		_trigger_swap_effect()
		update_sprite()
		_update_overhead_ammo()
		_update_burst_visibility()  # Update burst bar for new character
		
		if overhead_hud:
			# Pass registry index (not slot index) for proper ammo display
			var registry_idx: int = _selected_char_indices[current_character] if current_character < _selected_char_indices.size() else 0
			overhead_hud.update_character(registry_idx)

func _try_manual_reload() -> void:
	# Allow player to manually reload with R key
	if not _current_controller:
		return
	
	# Delegate reload to controller if it supports it
	if _current_controller.has_method("manual_reload"):
		_current_controller.manual_reload()
		_update_overhead_ammo()

func _show_talent_tree(add_point: bool = false) -> void:
	var canvas = get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = get_tree().root
	
	# Hide skill points notification while tree is open
	if _skill_points_notify and is_instance_valid(_skill_points_notify):
		_skill_points_notify.visible = false
		# Kill pulse animation
		if _skill_points_notify.has_meta("pulse_tween"):
			var tween = _skill_points_notify.get_meta("pulse_tween")
			if tween and is_instance_valid(tween):
				tween.kill()
	
	# Check for existing talent tree
	var existing = canvas.get_node_or_null("TalentTree")
	if existing:
		if add_point:
			existing.add_skill_points(1)  # Add point for leveling up
		existing.show_tree(self)
		shop_open = true
		if get_parent().has_method("set_game_paused"):
			get_parent().call_deferred("set_game_paused", true)
		return
	
	# Create new talent tree using preload for proper initialization
	var TalentTreeScript = preload("res://scripts/ui/TalentTree.gd")
	var tree = TalentTreeScript.new()
	tree.name = "TalentTree"
	
	# For Controls in CanvasLayer, we need to set anchors properly
	tree.anchor_left = 0.0
	tree.anchor_top = 0.0
	tree.anchor_right = 1.0
	tree.anchor_bottom = 1.0
	tree.offset_left = 0.0
	tree.offset_top = 0.0
	tree.offset_right = 0.0
	tree.offset_bottom = 0.0
	
	canvas.add_child(tree)
	
	# Connect signals
	tree.talent_unlocked.connect(_on_talent_unlocked)
	tree.tree_closed.connect(_on_talent_tree_closed)
	
	if add_point:
		tree.add_skill_points(1)
	
	# Pass player reference via show_tree (not a property)
	tree.show_tree(self)
	shop_open = true
	if get_parent().has_method("set_game_paused"):
		get_parent().call_deferred("set_game_paused", true)
