class_name PlayerUpgradeManager
extends Node

## Manages character-specific and shop-based upgrades for the player.
## Extracted from PlayerCore.gd to reduce monolith size.

# Dependencies
var _player: PlayerCore
var _registry: CharacterRegistry

# State: Active upgrade flags
var has_rapunzel_healer: bool = false
var has_commander_burst: bool = false
var has_commander_wave_heal: bool = false # "Nikke Endurance"
var has_crown_xp: bool = false
var has_crown_trombe_stacking: bool = false
var has_cecil_wishes: bool = false # "Three Wishes..."
var has_cecil_eden_shield: bool = false # "Noah's Defiance"
var has_sin_mind_control: bool = false
var has_sin_wish_upgrade: bool = false
var sin_wish_used_this_match: bool = false
var has_kilo_ammo_upgrade: bool = false
var has_snow_white_ammo_upgrade: bool = false
var has_nayuta_duplicity_upgrade: bool = false
var has_marian_beam_mode: bool = false
var has_marian_beam_absorb: bool = false

# Commander wave heal state
var _wave_heal_timer: float = 0.0
const WAVE_HEAL_INTERVAL: float = 30.0 # Used in timerless modes

# Special upgrade state
var marian_beam_buff_active: bool = false
var marian_beam_buff_timer: float = 0.0
const MARIAN_BEAM_BUFF_DURATION: float = 5.0

# Helpers
const UI := preload("res://scripts/ui/UITheme.gd")
const ShopMenuScript := preload("res://scripts/ui/ShopMenu.gd")

func _init(player: PlayerCore) -> void:
	_player = player
	_registry = CharacterRegistry.get_instance()
	name = "PlayerUpgradeManager"

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if marian_beam_buff_active:
		marian_beam_buff_timer -= delta
		if marian_beam_buff_timer <= 0:
			marian_beam_buff_active = false
			# Notify player to remove visual effect
			if _player.has_method("_update_marian_beam_visual"):
				_player._update_marian_beam_visual(false)
	
	# Commander wave heal - 30s timer for timerless modes
	if has_commander_wave_heal:
		_wave_heal_timer += delta
		if _wave_heal_timer >= WAVE_HEAL_INTERVAL:
			_wave_heal_timer = 0.0
			# Check if we're in a timerless wave or Goddess Fall mode
			if _is_timerless_mode():
				_apply_commander_wave_heal()

func apply_character_shop_upgrades(all_ids: Array, selected_indices: Array, swappable_slots: Array) -> void:
	"""Apply character-specific upgrades for characters currently in the squad."""
	for slot_idx in range(selected_indices.size()):
		var char_idx = selected_indices[slot_idx]
		
		if char_idx < 0 or char_idx >= all_ids.size():
			continue
		
		# Only apply if the squad slot is currently active in the run (swappable)
		# This prevents upgrades from leaking to "locked" slots even if the character is owned
		if slot_idx not in swappable_slots:
			continue
			
		var char_id: String = all_ids[char_idx]
		_check_and_activate_upgrade(char_id)
	
## Apply upgrade for a newly unlocked character (during gameplay)
func apply_upgrade_for_character(char_id: String) -> void:
	_check_and_activate_upgrade(char_id)

func _check_and_activate_upgrade(char_id: String) -> void:
	match char_id:
		"rapunzel":
			if ShopMenuScript.has_character_upgrade("rapunzel", "basic_attack"):
				has_rapunzel_healer = true
				if _player._health: _player._health.enable_rapunzel_healing()
				print("[UpgradeManager] Rapunzel 'I'm a healer' active")
		"commander":
			if ShopMenuScript.has_character_upgrade("commander", "basic_attack"):
				has_commander_burst = true
				print("[UpgradeManager] Commander 'Obviously Anderson' active")
			if ShopMenuScript.has_character_upgrade("commander", "wave_heal"):
				has_commander_wave_heal = true
				# Connect to wave_completed signal for timed waves
				if not EventBus.wave_completed.is_connected(_on_wave_completed):
					EventBus.wave_completed.connect(_on_wave_completed)
				print("[UpgradeManager] Commander 'Nikke Endurance' active")
		"crown":
			if ShopMenuScript.has_character_upgrade("crown", "basic_attack"):
				has_crown_xp = true
				print("[UpgradeManager] Crown 'Royal Knowledge' active")
			if ShopMenuScript.has_character_upgrade("crown", "trombe_stacking"):
				has_crown_trombe_stacking = true
				print("[UpgradeManager] Crown 'Trombe Stacking' active")
		"cecil":
			if ShopMenuScript.has_character_upgrade("cecil", "basic_attack"):
				has_cecil_wishes = true
				if _player._health: _player._health.configure_cecil_lives(3) # Default 3 lives
				print("[UpgradeManager] Cecil 'Three Wishes' active")
			if ShopMenuScript.has_character_upgrade("cecil", "eden_shield"):
				has_cecil_eden_shield = true
				# CRITICAL: Configure shield for ALL squad members, not just current!
				if _player._health:
					_player._health.configure_shield_for_squad(0.5) # 50% of max HP
				if _player.has_method("_update_shield_display"):
					_player.call_deferred("_update_shield_display")
				print("[UpgradeManager] Cecil 'Noah's Defiance' active - Shield for ALL squad")
		"kilo":
			if ShopMenuScript.has_character_upgrade("kilo", "talos_ammo"):
				has_kilo_ammo_upgrade = true
				print("[UpgradeManager] Kilo 'Build-a-Bullet' active")
		"snow_white":
			if ShopMenuScript.has_character_upgrade("snow_white", "master_mechanic"):
				has_snow_white_ammo_upgrade = true
				print("[UpgradeManager] Snow White 'Master Mechanic' active")
		"nayuta":
			if ShopMenuScript.has_character_upgrade("nayuta", "basic_attack"):
				has_nayuta_duplicity_upgrade = true
				print("[UpgradeManager] Nayuta 'Duplicity' active")
		"marian":
			if ShopMenuScript.has_character_upgrade("marian", "basic_attack"):
				has_marian_beam_mode = true
				print("[UpgradeManager] Marian 'Main Heroine' active")
			if ShopMenuScript.has_character_upgrade("marian", "beam_absorb"):
				has_marian_beam_absorb = true
				if _player._health: _player._health.enable_marian_beam_absorb()
				print("[UpgradeManager] Marian 'She'll Eat Anything' active")
		"sin":
			if ShopMenuScript.has_character_upgrade("sin", "basic_attack"):
				has_sin_mind_control = true
				print("[UpgradeManager] Sin 'Magnetic Personality' active")
			if ShopMenuScript.has_character_upgrade("sin", "wish_save"):
				has_sin_wish_upgrade = true
				if _player._health: _player._health.enable_sin_wish()
				print("[UpgradeManager] Sin 'I WISH They Were Gone' active")

## Trigger Marian's beam absorb effect
func trigger_marian_beam_absorb() -> void:
	if not has_marian_beam_absorb: return
	
	marian_beam_buff_active = true
	marian_beam_buff_timer = MARIAN_BEAM_BUFF_DURATION
	if _player.has_method("_update_marian_beam_visual"):
		_player._update_marian_beam_visual(true)

# --- Cecil: Three Wishes (Revive) ---
var cecil_lives_remaining: int = 0

func try_revive() -> bool:
	if not has_cecil_wishes or cecil_lives_remaining <= 0:
		return false
	
	cecil_lives_remaining -= 1
	# _player.lives_changed.emit(cecil_lives_remaining) # If player has this signal
	print("[UpgradeManager] Cecil's extra life used! %d lives remaining" % cecil_lives_remaining)
	return true

# --- Kilo: Protect Me Talos (Shield) ---
var kilo_shield_current: int = 0
var kilo_shield_max: int = 0
var kilo_shield_visual: Node2D = null

func try_absorb_damage(damage: int) -> int:
	if not has_cecil_eden_shield or kilo_shield_current <= 0: # Correction: Kilo has Talos Shield, Cecil has Eden Shield. Old code confused them?
		# Wait, PlayerCore: Cecil "Noah's Defiance" -> Eden Shield visual.
		# CharacterUpgrades: Kilo "Protect Me Talos" -> Shield. 
		# Let's check ShopData. 
		# Kilo id: "talos_ammo" (Build-a-Bullet).
		# Cecil id: "eden_shield" (Noah's Defiance).
		# CharacterUpgrades line 68 says: ShopMenuScript.has_character_upgrade("kilo", "basic_attack").
		# But ShopData for Kilo basic_attack is MISSING? No, ShopData has "talos_ammo".
		# Ah, ShopData line 62: "talos_ammo".
		# It seems CharacterUpgrades.gd references "basic_attack" which might not exist for Kilo?
		# Let's trust PlayerCore's logic for now, but consolidate.
		pass
		
	# Re-reading PlayerCore logic (lines 430+): 
	# Cecil: "eden_shield" -> _has_cecil_eden_shield -> _create_eden_shield_visual().
	# Kilo: "talos_ammo" -> _has_kilo_ammo_upgrade.
	
	# CharacterUpgrades.gd seems to have legacy ideas (Kilo shield). 
	# I will stick to what PlayerCore actually uses: Cecil has the shield ("Noah's Defiance").
	# So I will implement accessors for Cecil's shield if needed, but PlayerCore seems to handle it visually.
	
	return damage

# Actually, I will defer adding complex logic I'm unsure about until I verified PlayerCore usage.
# PlayerCore uses `_has_cecil_eden_shield`. I expose `has_cecil_eden_shield` in this manager.
# I will stick to just the flags for now to avoid breaking working logic.

# --- Persistence Helper ---

## Loads unlocked talents directly from disk to ensure they differ from UI state
func load_unlocked_talents_from_disk() -> Dictionary:
	# Access SaveManager global class directly
	# We know the path is "user://shop_data.cfg" from SaveManager.SHOP_PATH class const
	# But since we can't easily access the const if SaveManager isn't a global class_name in this scope (it is an autoload),
	# we will string match or try to access the singleton.
	var save_path := "user://shop_data.cfg"
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		if "SHOP_PATH" in sm:
			save_path = sm.SHOP_PATH
	
	var config := ConfigFile.new()
	var err := config.load(save_path)
	if err != OK:
		print("[PlayerUpgradeManager] Failed to load shop data from path: %s (Error %d)" % [save_path, err])
		return {}
	
	# Structure in ShopMenu._save_shop_data: data["talents"] = { "unlocked": ... }
	# ConfigFile saves dictionary as a value under the key.
	# So we look for section "talents", key "unlocked".
	
	if config.has_section_key("talents", "unlocked"):
		var val = config.get_value("talents", "unlocked", {})
		if val is Dictionary:
			print("[PlayerUpgradeManager] Loaded %d unlocked talents from info on disk" % val.size())
			return val
	
	print("[PlayerUpgradeManager] 'talents/unlocked' key not found in shop data.")
	return {}

## Loads unlocked characters and converts to indices (for PlayerCore)
func load_unlocked_characters_indices() -> Array[int]:
	# STRICT MODE: Only trust save data or absolute mandatory starter (Scarlet)
	# Do NOT trust CharacterRegistry.DEFAULT_UNLOCKED as it likely contains the whole squad for testing.
	var unlocked_ids: Array = ["scarlet"] # Base starter only
	
	# Load from disk
	var save_path := "user://shop_data.cfg"
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		if "SHOP_PATH" in sm:
			save_path = sm.SHOP_PATH
			
	var config := ConfigFile.new()
	var err := config.load(save_path)
	
	if err == OK:
		# If save exists, respect it completely.
		# If it has "characters/unlocked", use those.
		var disk_unlocked = config.get_value("characters", "unlocked", [])
		if not disk_unlocked.is_empty():
			# Merge, but actually if save exists we should barely need Scarlet fallback if the save is valid?
			# Let's just append disk ones to the base starter
			for id in disk_unlocked:
				if id not in unlocked_ids:
					unlocked_ids.append(id)
	else:
		# Save file missing?
		print("[UpgradeManager] No save data found. Defaulting to ONLY Scarlet.")
	
	print("[UpgradeManager DEBUG] Final Unlocked IDs for Upgrades: ", unlocked_ids)
	
	# Convert to indices
	var valid_indices: Array[int] = []
	var all_ids: Array = []
	if _registry:
		all_ids = _registry.get_all_character_ids()
	
	for id in unlocked_ids:
		var idx = all_ids.find(id)
		if idx != -1:
			valid_indices.append(idx)
			
	return valid_indices

# ========== COMMANDER WAVE HEAL UPGRADE ==========

## Called when a timed wave ends
func _on_wave_completed(wave_number: int) -> void:
	if not has_commander_wave_heal:
		return
	
	# Only heal on timed waves (1-10), skip wave 11 and 12 (final/boss waves)
	if wave_number <= 10:
		_apply_commander_wave_heal()
		print("[UpgradeManager] Commander wave heal triggered on wave %d" % wave_number)

## Check if we're in a timerless mode (Goddess Fall, wave 11/12, etc)
func _is_timerless_mode() -> bool:
	# Check for Goddess Fall mode
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and "is_goddess_fall" in game_manager and game_manager.is_goddess_fall:
		return true
	
	# Check GameManager singleton
	if GameManager and "is_goddess_fall" in GameManager and GameManager.is_goddess_fall:
		return true
	
	# Check current wave number from WaveDirector
	var wave_director = get_tree().get_first_node_in_group("wave_director")
	if wave_director and "current_wave" in wave_director:
		var wave = wave_director.current_wave
		if wave >= 11: # Waves 11+ are timerless (final boss waves)
			return true
	
	return false

## Apply Commander wave heal based on burst bar percentage
func _apply_commander_wave_heal() -> void:
	if not _player or not is_instance_valid(_player):
		return
	
	# Get burst percentage (0.0 to 1.0)
	var burst_percent := 0.0
	if "burst" in _player and "burst_max" in _player and _player.burst_max > 0:
		burst_percent = float(_player.burst) / float(_player.burst_max)
	elif _player._health and "burst" in _player._health:
		burst_percent = _player._health.burst / 100.0 # Assuming 0-100 scale
	
	# Calculate heal amount based on burst percentage
	# Base heal: 2
	# 0-20% burst: +8 (total 10)
	# 21-40% burst: +6 (total 8) 
	# 41-60% burst: +4 (total 6)
	# 61-80% burst: +2 (total 4)
	# 81-100% burst: +0 (total 2)
	var base_heal := 2
	var bonus_heal := 0
	
	if burst_percent <= 0.2:
		bonus_heal = 8
	elif burst_percent <= 0.4:
		bonus_heal = 6
	elif burst_percent <= 0.6:
		bonus_heal = 4
	elif burst_percent <= 0.8:
		bonus_heal = 2
	# else: 0 bonus
	
	var total_heal := base_heal + bonus_heal
	
	# Heal Commander specifically (even if not active character)
	# Find Commander in squad and heal their HP bar
	if _player._health and _player._health.has_method("heal_character_by_id"):
		_player._health.heal_character_by_id("commander", total_heal)
	elif _player.has_method("heal"):
		# Fallback: heal current player if Commander
		if _player._health and "current_character_id" in _player._health:
			if _player._health.current_character_id == "commander":
				_player.heal(total_heal)
		else:
			_player.heal(total_heal)
	
	print("[UpgradeManager] Commander healed for %d (burst: %.0f%%)" % [total_heal, burst_percent * 100])
