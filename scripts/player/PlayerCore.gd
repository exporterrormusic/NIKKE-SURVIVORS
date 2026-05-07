extends CharacterBody2D
class_name PlayerCore
## Core player functionality: movement, health, XP, stamina, UI.
## Character-specific combat is delegated to CharacterController instances.

# Character system
const CharacterRegistryScript = preload("res://scripts/characters/CharacterRegistry.gd")
const PlayerOverheadHudScript = preload("res://scripts/player/PlayerOverheadHud.gd")
const CharacterSwapEffectScript = preload("res://scripts/effects/CharacterSwapEffect.gd")
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")
const MusicPlayerUIScript = preload("res://scripts/ui/MusicPlayerUI.gd")

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
var _controllers: Array = [] # CharacterController instances
var _current_controller: CharacterController = null
var _selected_char_indices: Array[int] = [] # Selected characters from GameManager
var current_character: int = 0 # Slot index (0=Main, 1=Support1, 2=Support2)
var swappable_slots: Array[int] = [0] # Slots activated in Talent Tree (0=Main ALWAYS active)
var owned_characters: Array[int] = [] # Registry IDs unlocked in shop/save

# Burst sounds
var _burst_sounds: Array = []

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
var xp_to_next: int = 100: get = get_xp_to_next

# Player subsystems (delegated)
var _health: PlayerHealth = null
var _movement: PlayerMovement = null
var _weapons: PlayerWeapons = null

# New modular components (Phase 2 refactor)
var _burst_system: BurstSystem = null

var _char_switcher: CharacterSwitcher = null
var _talent_ui: TalentUIManager = null

# Extracted modular components (Phase 3 refactor)
var _visual_effects: PlayerVisualEffects = null
var _night_glow: PlayerNightGlow = null
var _clone_manager: PlayerCloneManager = null
var _skill_points_notify: SkillPointsNotification = null

# Movement state (delegated to PlayerMovement)
var dashing: bool:
	get: return _movement.dashing if _movement else false

# Combat state
var attack_timer: float = 0.0
var shop_open: bool = false

# Controller/aim state
var _using_controller: bool = false
var aim_direction: Vector2 = Vector2.RIGHT

const AIM_ASSIST_ANGLE := 15.0 # degrees - subtle cone
const AIM_ASSIST_RANGE := 350.0 # pixels
const AIM_ASSIST_STRENGTH := 0.4 # how strongly to pull toward target

# Visual effects
var _swap_effect: Node2D = null

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
	
	# Register default squad switching actions if they don't exist
	if not InputMap.has_action("next_character"):
		InputMap.add_action("next_character")
		var ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP
		InputMap.action_add_event("next_character", ev)
		
	if not InputMap.has_action("prev_character"):
		InputMap.add_action("prev_character")
		var ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		InputMap.action_add_event("prev_character", ev)
	
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
	
	# Connect to switcher signals if using component
	if _char_switcher:
		_char_switcher.character_switched.connect(_on_controller_switched)


func _setup_components() -> void:
	"""Initialize all child components and systems."""
	# 1. Core Systems
	_progression = PlayerProgression.new()
	add_child(_progression)
	_progression.configure(1, 0, 100)
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

	_talent_ui = TalentUIManager.new()
	_talent_ui.name = "TalentUIManager"
	add_child(_talent_ui)
	_talent_ui.initialize(self)
	_talent_ui.talent_unlocked.connect(_on_component_talent_unlocked)
	_talent_ui.talent_tree_opened.connect(func(): shop_open = true)
	_talent_ui.talent_tree_closed.connect(func(): shop_open = false)
	
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


func _on_component_talent_unlocked(char_id: int, talent_id: String) -> void:
	"""Handle talent unlock from TalentUIManager component."""
	# Forward to existing handler
	_on_talent_unlocked(char_id, talent_id)

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
		_selected_char_indices = game_manager.selected_character_indices.duplicate()
		print("[PlayerCore] Loaded selected characters: ", _selected_char_indices)
	else:
		# Fallback defaults
		_selected_char_indices = [0, 1, 4] # Scarlet, Commander, Marian
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
	
	# Register squad for health tracking
	var squad_ids: Array = []
	for idx in _selected_char_indices:
		if idx >= 0 and idx < all_ids.size():
			squad_ids.append(all_ids[idx])
	
	if _health:
		_health.set_squad_ids(squad_ids)
	
	# Start with Main character (slot 0)
	current_character = 0
	# Load registry indices of characters unlocked in the shop/skill tree permanently
	if _upgrade_manager:
		owned_characters = _upgrade_manager.load_unlocked_characters_indices()
		# Fallback if load failed or empty (should always have Scarlet at index 0)
		if owned_characters.is_empty():
			owned_characters = [0]
	else:
		owned_characters = [0]

	# Slots unlocked in the current run via the Talent Tree
	# Always start with the first slot (Main character) swappable
	swappable_slots = [0]
	
	# RESTORE: Load previously unlocked slots from saved talents
	var saved_talents = _upgrade_manager.load_unlocked_talents_from_disk() if _upgrade_manager else {}
	for slot_idx in range(1, _selected_char_indices.size()):
		var reg_idx = _selected_char_indices[slot_idx]
		var char_data = saved_talents.get(reg_idx, saved_talents.get(str(reg_idx), {}))
		if char_data.get("unlock", 0) > 0:
			if slot_idx not in swappable_slots:
				swappable_slots.append(slot_idx)
	
	swappable_slots.sort()
	print("[PlayerCore] Initialized swappable_slots: ", swappable_slots)

	
	# Set initial controller
	if current_character < _controllers.size() and _controllers[current_character] != null:
		_current_controller = _controllers[current_character]
		# Sync ID to health system for character-specific defenses (Marian absorb)
		if _health and _registry:
			var char_idx = _selected_char_indices[current_character]
			var start_id = _registry.get_character_id(char_idx)
			_health.current_character_id = start_id
	
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
	   Delegated to PlayerUpgradeManager."""
	if _upgrade_manager:
		# PASS swappable_slots to ensure we only apply upgrades to characters active in the current run
		_upgrade_manager.apply_character_shop_upgrades(all_ids, _selected_char_indices, swappable_slots)
		
		# Explicitly notify controllers of changes that require immediate stat updates
		# (e.g. Snow White's ammo needs value update, not just a flag check)
		if _upgrade_manager.has_snow_white_ammo_upgrade:
			for controller in _controllers:
				# Fix: Resource path is likely 'snowwhitecontroller.gd', so 'snow_white' usually fails.
				# Check for 'snowwhite' (stripped) or rely on data.id if possible.
				if controller:
					var path = controller.get_script().resource_path.to_lower()
					if "snowwhite" in path or "snow_white" in path:
						# If controller has update_ammo_capacity method, use it
						# Or manually set if exposed
						if controller.has_method("apply_squad_upgrades"):
							controller.apply_squad_upgrades() # This function checks the upgrade flag!
							# Fix: Ensure ammo starts full if we just upgraded capacity
							if "ammo" in controller and "max_ammo" in controller:
								controller.ammo = controller.max_ammo
								if controller.has_signal("ammo_changed"):
									controller.ammo_changed.emit(controller.ammo, controller.max_ammo)
		
		# Handle local visual side effects (delegated to health + visual effects)
		if _upgrade_manager.has_cecil_eden_shield:
			_health.configure_shield(int(max_hp * 0.5))
			if _visual_effects:
				_visual_effects.create_eden_shield_visual()
				call_deferred("_visual_effects.update_shield_display", _health.shield_current, _health.shield_max)

func _apply_upgrade_for_character(char_idx: int) -> void:
	"""Apply shop upgrade for a specific character when unlocked during gameplay.
	   Delegated to PlayerUpgradeManager."""
	if not _registry:
		return
	if not _upgrade_manager:
		return
	
	if char_idx < 0:
		return
		
	var all_ids: Array = _registry.get_all_character_ids()
	if char_idx >= all_ids.size():
		return
	
	var char_id: String = all_ids[char_idx]
	_upgrade_manager.apply_upgrade_for_character(char_id)
	
	# Handle local visual side effects (delegated to health + visual effects)
	if char_id == "cecil" and _upgrade_manager.has_cecil_eden_shield:
		_health.configure_shield(int(max_hp * 0.5))
		if _visual_effects:
			_visual_effects.create_eden_shield_visual()
			call_deferred("_visual_effects.update_shield_display", _health.shield_current, _health.shield_max)


func _apply_all_talents_to_controllers() -> void:
	"""Apply all unlocked talents to controllers when the game starts."""
	# Load directly from disk to ensure we have data even if UI isn't open
	var unlocked_talents: Dictionary = {}
	
	if _upgrade_manager:
		unlocked_talents = _upgrade_manager.load_unlocked_talents_from_disk()
	
	# If disk load failed (empty), try tree as backup (if it happens to exist)
	if unlocked_talents.is_empty():
		var tree := _get_talent_tree()
		if tree and tree.has_method("get_unlocked_talents"):
			unlocked_talents = tree.get_unlocked_talents()
	
	if unlocked_talents.is_empty():
		return
	
	# Apply talents for each character slot
	for slot_idx in range(_controllers.size()):
		if slot_idx >= _selected_char_indices.size():
			continue
		
		var registry_idx: int = _selected_char_indices[slot_idx]
		
		# Fundamental Logic Fix: Do not apply talents if character slot is not active in the current run
		# This prevents upgrades from "leaking" to locked characters who happen to be in the default squad
		if not slot_idx in swappable_slots:
			continue

		var controller = _controllers[slot_idx]
		
		# Handle potential String/Int key mismatch from JSON/Config loading
		var char_talents: Dictionary = {}
		if registry_idx in unlocked_talents:
			char_talents = unlocked_talents[registry_idx]
		elif str(registry_idx) in unlocked_talents:
			char_talents = unlocked_talents[str(registry_idx)]
			
		if controller and not char_talents.is_empty():
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

func _init_ui() -> void:
	if overhead_hud:
		overhead_hud.update_health(hp, max_hp)
		overhead_hud.update_burst(burst_current, burst_max)
		# Pass registry index (not slot index) for proper ammo display
		var registry_idx: int = _selected_char_indices[current_character] if current_character < _selected_char_indices.size() else 0
		overhead_hud.update_character(registry_idx)
		_update_overhead_ammo()
	update_xp_bar()
	_hud_initialized = true

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
		
		# Apply universal shader for night glow
		_apply_universal_shader()
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

func _on_health_damage_taken_visuals(dmg: int, is_crit: bool, direction: Vector2) -> void:
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

func _on_controller_switched(slot_idx: int, registry_idx: int) -> void:
	"""Handle internal logic when controller changes."""
	# Update health system context
	if _health and _registry:
		var char_id = _registry.get_character_id(registry_idx)
		_health.current_character_id = char_id
		print("[PlayerCore] Switched character context to: ", char_id)

func _on_health_changed(current: int, maximum: int) -> void:
	# Call directly when HUD is ready, defer only during initialization
	if _hud_initialized:
		_update_health_display(0, false)
	else:
		call_deferred("_update_health_display", 0, false)

func add_skill_points(amount: int) -> void:
	if _progression:
		_progression.add_skill_points(amount)
		# Show/update skill points notification
		_update_skill_points_notification(_progression.get_skill_points())
	
	if overhead_hud:
		overhead_hud.update_skill_points_available(true)

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
	if current_character < 0 or current_character >= _selected_char_indices.size():
		return "smg"
	
	var char_idx = _selected_char_indices[current_character]
	if char_idx < 0 or char_idx >= all_ids.size():
		return "smg"
	
	var char_id = all_ids[char_idx]
	
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
	return _using_controller

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
	if _registry and current_character >= 0:
		var all_ids = _registry.get_all_character_ids()
		if current_character < _selected_char_indices.size():
			var char_idx = _selected_char_indices[current_character]
			if char_idx >= 0 and char_idx < all_ids.size():
				char_id = all_ids[char_idx]
	
	# Get sound at runtime (enables Commander random selection)
	var sound: AudioStream = null
	if char_id != "" and _registry:
		sound = _registry.get_burst_sound(char_id)
	else:
		# Fallback to cached sound
		if current_character >= 0 and current_character < _burst_sounds.size():
			sound = _burst_sounds[current_character]
	
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
		xp_ui.set_level(new_level)
		xp_ui.flash_level_up()
	
	# Play level up sound
	_play_level_up_sound()
	
	# Spawn WoW-style golden glow effect around player
	_spawn_level_up_glow()
	
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
	
	# Optimization: Do NOT instantiate TalentTree here. 
	# It causes a stutter on level up due to resource loading.
	# Rely on _update_skill_points_notification to inform the user.
	# The tree will be created when _show_talent_tree is called (TAB).
	var points_available = 1
	if existing and existing.has_method("get_skill_points"):
		points_available = existing.get_skill_points()
	elif _progression:
		points_available = _progression.get_skill_points()
	
	if overhead_hud:
		overhead_hud.update_skill_points_available(points_available > 0)
	
	# Show/update skill points notification
	_update_skill_points_notification(points_available)

func is_character_in_squad(char_id: String) -> bool:
	"""Check if a character is currently available in the squad (swappable/active in run)."""
	char_id = char_id.to_lower()
	
	# Check active squad slots
	for slot_idx in swappable_slots:
		if slot_idx >= 0 and slot_idx < _controllers.size():
			var controller = _controllers[slot_idx]
			if controller:
				# Robust check: Check controller data directly first
				# Using get() is safer than direct access if property might confuse parser
				var data = controller.get("data")
				if data and "id" in data:
					if data.id.to_lower() == char_id:
						return true
				
				# Fallback: Check script path for name match
				var path = controller.get_script().resource_path.to_lower()
				# Fix: Snow White controller file is "SnowWhiteController.gd", no underscore. 
				# Handle "snow_white" by checking for both "snow_white" and "snowwhite"
				var search_term = char_id.replace("_", "")
				if search_term in path.replace("_", ""):
					return true
	return false

func _refresh_squad_synergies() -> void:
	"""Notify all controllers to update stats based on current squad composition."""
	for controller in _controllers:
		if controller and controller.has_method("apply_squad_upgrades"):
			controller.apply_squad_upgrades()

func _on_talent_unlocked(char_id: int, talent_id: String) -> void:
	# char_id is a registry index, we need to convert to slot index
	var slot_idx: int = _selected_char_indices.find(char_id)
	
	# Unlock character slot if this is an unlock talent
	if talent_id == "unlock":
		# Find which slot this registry index corresponds to
		if slot_idx >= 0 and slot_idx not in swappable_slots:
			swappable_slots.append(slot_idx)
			swappable_slots.sort()
			print("[PlayerCore] Activated character slot %d (registry %d) in current run" % [slot_idx, char_id])
			
			# Apply shop upgrades for the newly unlocked character
			_apply_upgrade_for_character(char_id)
			print("[PlayerCore] Swappable slots now: ", swappable_slots)
			
			# Refresh squad synergies (e.g. Kilo's ammo buff needing Kilo in squad)
			_refresh_squad_synergies()
	
	# Forward talent to controller - use slot index
	# FIX: Only apply talent if the character slot is actually active in the current run
	if slot_idx >= 0 and slot_idx < _controllers.size() and slot_idx in swappable_slots:
		var controller = _controllers[slot_idx]
		if controller and controller.has_method("apply_talent"):
			controller.apply_talent(talent_id)
	
	# Save shop data when talents change
	var shop_menu = _get_shop_menu()
	if shop_menu and shop_menu.has_method("_save_shop_data"):
		shop_menu._save_shop_data()
	
	# Update burst visibility
	_update_burst_visibility()
	
	# Sync progression skill points
	var tree := _get_talent_tree()
	if tree and _progression and tree.has_method("get_skill_points"):
		_progression.set_skill_points(tree.get_skill_points())

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
	"""Show or update the skill points notification (delegated to SkillPointsNotification component)."""
	if _skill_points_notify == null or not is_instance_valid(_skill_points_notify):
		var canvas := get_parent().get_node_or_null("CanvasLayer")
		if canvas == null:
			canvas = get_tree().root
		_skill_points_notify = SkillPointsNotification.create(canvas)
	
	_skill_points_notify.show_notification(points)

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
	if swappable_slots.size() <= 1:
		return
	
	# Cleanup old controller before switching
	if _current_controller and _current_controller.has_method("cleanup"):
		_current_controller.cleanup()
	
	var old_char = current_character
	var idx = swappable_slots.find(current_character)
	idx = (idx + direction + swappable_slots.size()) % swappable_slots.size()
	current_character = swappable_slots[idx]
	_current_controller = _controllers[current_character]
	
	print("[PlayerCore] Swapping from slot %d to %d. SwappableSlots: %s. Controller: %s" % [old_char, current_character, swappable_slots, _current_controller])
	
	_trigger_swap_effect()
	update_sprite()
	_update_overhead_ammo()
	_update_burst_visibility() # Update burst bar for new character
	
	# Update GameManager so achievements track the correct character
	var registry_idx: int = _selected_char_indices[current_character] if current_character < _selected_char_indices.size() else 0
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.set_player_character(registry_idx)
	
	if overhead_hud:
		# Pass registry index (not slot index) for proper ammo display
		overhead_hud.update_character(registry_idx)
	
	# Sync character ID with health component for character-specific blocks/buffs
	if _health and _registry:
		var char_id = _registry.get_character_id(registry_idx)
		_health.current_character_id = char_id

func _trigger_swap_effect() -> void:
	if not is_instance_valid(_swap_effect):
		_swap_effect = Node2D.new()
		_swap_effect.set_script(CharacterSwapEffectScript)
		_swap_effect.name = "SwapEffect"
		_swap_effect.z_index = 50
		get_parent().add_child(_swap_effect)
	
	if _swap_effect.has_method("trigger"):
		# Pass registry index (not slot index) for correct character effect
		var registry_idx: int = _selected_char_indices[current_character] if current_character < _selected_char_indices.size() else 0
		_swap_effect.trigger(registry_idx, global_position)

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
		if char_idx == 1: # Scarlet's index in CharacterRegistry
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
	
	# Check for Wells locked state (Future Marian active)
	var is_locked: bool = false
	if "_special_blocked" in _current_controller:
		is_locked = _current_controller._special_blocked
	
	overhead_hud.update_special_ability(unlocked, progress, is_locked)

## Public accessor for current controller (used by PlayerCloneManager and external systems)
func get_current_controller() -> CharacterController:
	return _current_controller


# ============= MAIN GAME LOOP =============

	# Animator state is updated in _physics_process via update_state()

func _process(delta: float) -> void:
	if shop_open:
		return
		
	# Update aim every frame for smooth visual tracking
	_update_aim()
	
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
	
	_handle_input()
	
	# _update_aim() is now called in _process for smoother visual tracking
	
	# Delegate movement to component
	var input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _movement:
		_movement.handle_movement(delta, input_vector)
	
	# Update attack timer
	if attack_timer > 0:
		attack_timer -= delta
	
	# Handle attacks
	_handle_attacks(aim_direction, delta)
	
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

func _handle_input() -> void:
	if dashing:
		return
	
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# Dash input - only on press
	if Input.is_action_just_pressed("dash"):
		if _movement:
			_movement.try_dash(input_dir if input_dir.length() > 0 else aim_direction)
	
	# Running - holding dash key while not dashing (will also start after dash ends while held)
	if _movement:
		if Input.is_action_pressed("dash") and not dashing:
			_movement.set_running(true)
		elif not Input.is_action_pressed("dash"):
			_movement.set_running(false)
	
	# Character switching and Burst are now handled exclusively in _input(event) 
	# to prevent duplicate triggers (which caused swap-and-swap-back bugs).

func _update_aim() -> void:
	# Controller aim
	var stick_aim := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick_aim.length() > 0.3:
		_using_controller = true
		aim_direction = stick_aim.normalized()
		aim_direction = _apply_aim_assist(aim_direction)
	elif not _using_controller:
		# Mouse aim
		var mouse_pos := get_global_mouse_position()
		aim_direction = (mouse_pos - global_position).normalized()
	
	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2.RIGHT

	# Animator state is updated in _physics_process via update_state()


func _handle_attacks(aim_direction: Vector2, _delta: float) -> void:
	if not _current_controller:
		return
	
	# Check if Kilo burst mode is active for automatic fire
	var is_kilo_burst: bool = _current_controller is KiloController and _current_controller.burst_active
	
	
	# Use get_is_automatic() from controller base class instead of hardcoded checks
	var is_auto_fire: bool = false
	if _current_controller.has_method("get_is_automatic"):
		is_auto_fire = _current_controller.get_is_automatic()
	else:
		# Fallback for old controllers? Shouldn't happen if base class updated
		is_auto_fire = _current_controller is CommanderController or _current_controller is SinController or _current_controller is CecilController or _current_controller is CrownController or _current_controller is MarianController or _current_controller is NayutaController
	
	# Primary attack - during Kilo burst or auto-fire weapons: continuous while holding, no stamina cost
	var wants_attack := false
	
	# Block attacks if mouse is hovering over music player UI
	if MusicPlayerUIScript.is_mouse_over():
		wants_attack = false
	elif is_kilo_burst or is_auto_fire:
		wants_attack = Input.is_action_pressed("attack")
	else:
		wants_attack = Input.is_action_just_pressed("attack")
	
	var can_fire := wants_attack and attack_timer <= 0
	
	# Debug attack logic (temporary)
	# if wants_attack:
	# 	print("[PlayerCore] Attack requested. Timer: %.3f, Stamina: %.1f, CanFire: %s" % [attack_timer, stamina, can_fire])
	
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

func _on_dash_started() -> void:
	invincible = true
	# Notify camera for juicy lag effect
	var camera = get_node_or_null("Camera2D")
	if camera and camera.has_method("notify_dash"):
		camera.notify_dash()

func _on_dash_ended() -> void:
	invincible = false

func _input(event: InputEvent) -> void:
	# Delegate device detection to InputManager (which updates is_controller property)
	# But keep local listener for burst/switch if not handled by manager globally
	# If input manager handles buffering, we still need to buffer here? 
	# No, InputManager._input handles buffering global inputs.
	if shop_open:
		return

	# Detect mouse usage to switch aim mode - lower threshold to catch subtle movements
	if event is InputEventMouseMotion and event.relative.length_squared() > 0.01:
		_using_controller = false
	
	# Character switching (using remappable actions)
	if event.is_action_pressed("next_character") and not event.is_echo():
		switch_character(1)
	elif event.is_action_pressed("prev_character") and not event.is_echo():
		switch_character(-1)
	
	# Burst activation via controller button (Y/Triangle)
	if event.is_action_pressed("burst") and not event.is_echo():
		_attempt_burst_activation()
	
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
	
	# Skill tree via remappable action
	if event.is_action_pressed("show_talent_tree") and not event.is_echo():
		_show_talent_tree()


func _select_character_by_index(index: int) -> void:
	if index in swappable_slots and index >= 0 and index < _controllers.size():
		# Prevent switching to dead characters
		if _health and _registry:
			var registry_idx = _selected_char_indices[index] if index < _selected_char_indices.size() else 0
			var char_id = _registry.get_character_id(registry_idx)
			# Only blocking switch if explicitly dead
			if not _health.is_character_alive(char_id):
				print("[PlayerCore] Cannot switch to dead character: %s" % char_id)
				# TODO: Play error sound?
				return

		# Cleanup previous controller (removes active effects like Bullet Time audio/visuals)
		if _current_controller and _current_controller.has_method("cleanup"):
			_current_controller.cleanup()
			
		current_character = index
		_current_controller = _controllers[current_character]
		
		# Ensure current state is saved before switch (handled by setter of current_character_id)
		# But we need to update the ID on the health component to trigger load
		if _health and _registry:
			var char_idx = _selected_char_indices[current_character]
			var start_id = _registry.get_character_id(char_idx)
			_health.current_character_id = start_id
		
		_trigger_swap_effect()
		update_sprite()
		_update_overhead_ammo()
		_update_burst_visibility() # Update burst bar for new character
		
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
		_skill_points_notify.show_notification(-1) # -1 = hide
	
	# Check for existing talent tree
	var existing = canvas.get_node_or_null("TalentTree")
	if existing:
		if add_point:
			existing.add_skill_points(1) # Add point for leveling up
		# Sync points if needed (only if mismatch, but usually trust tree)
		# if _progression:
		# 	existing.set_skill_points(_progression.get_skill_points()) -> CAUSES INFINITE POINTS EXPLOIT
		existing.show_tree(self)
		shop_open = true
		if get_parent().has_method("set_game_paused"):
			get_parent().call_deferred("set_game_paused", true)
		return
	
	# Sync skill points from progression
	var current_points = _progression.get_skill_points() if _progression else 0

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
	
	# Initialize points
	tree.set_skill_points(current_points)
	
	if add_point:
		tree.add_skill_points(1)
	
	# Pass player reference via show_tree (not a property)
	tree.show_tree(self)
	shop_open = true
	if get_parent().has_method("set_game_paused"):
		get_parent().call_deferred("set_game_paused", true)

func get_low_hp_damage_multiplier() -> float:
	## Wrapper to get damage multiplier from current controller (for UI stats)
	if _current_controller and _current_controller.has_method("get_low_hp_damage_multiplier"):
		return _current_controller.get_low_hp_damage_multiplier()
	return 1.0

func _exit_tree() -> void:
	# Cleanup all controllers to ensure global effects (AudioServer, etc) are removed
	for controller in _controllers:
		if controller and controller.has_method("cleanup"):
			controller.cleanup()


## Apply subtle aim assist for controller users - pulls aim toward nearby enemies
func _apply_aim_assist(base_aim: Vector2) -> Vector2:
	if not _using_controller:
		return base_aim
	
	var best_target: Node2D = null
	var best_score: float = 0.0
	
	# Find best target in cone
	for enemy in TargetCache.get_enemies():
		if not is_instance_valid(enemy):
			continue
		var to_enemy: Vector2 = enemy.global_position - global_position
		var dist: float = to_enemy.length()
		if dist > AIM_ASSIST_RANGE or dist < 10:
			continue
		
		var angle_diff: float = rad_to_deg(absf(base_aim.angle_to(to_enemy.normalized())))
		if angle_diff > AIM_ASSIST_ANGLE:
			continue
		
		# Score: closer + more aligned = better
		var score: float = (1.0 - dist / AIM_ASSIST_RANGE) * (1.0 - angle_diff / AIM_ASSIST_ANGLE)
		if score > best_score:
			best_score = score
			best_target = enemy
	
	if best_target:
		var target_aim: Vector2 = (best_target.global_position - global_position).normalized()
		return base_aim.lerp(target_aim, AIM_ASSIST_STRENGTH * best_score)
	return base_aim
