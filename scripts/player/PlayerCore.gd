extends CharacterBody2D
class_name PlayerCore
## Core player functionality: movement, health, XP, stamina, UI.
## Character-specific combat is delegated to CharacterController instances.

# Character system
const CharacterRegistryScript = preload("res://scripts/characters/CharacterRegistry.gd")
const PlayerOverheadHudScript = preload("res://scripts/player/PlayerOverheadHud.gd")
const CharacterSwapEffectScript = preload("res://scripts/effects/CharacterSwapEffect.gd")

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

# Player state
var hp: int = 10
var max_hp: int = 10
var xp: int = 0
var level: int = 1
var xp_to_next: int = 100
var burst_current: float = 0.0
var invincible: bool = false

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

func _ready() -> void:
	add_to_group("player")
	_create_shadow()
	_init_audio()
	_init_character_system()
	_init_ui()
	update_sprite()
	call_deferred("_update_hud")

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
		speed = char_data.base_speed
		print("[PlayerCore] Applied speed: %.1f" % speed)

## Calculate damage with level scaling
## Base formula: base_damage * (1.0 + (level - 1) * 0.5)
## At level 1: 1.0x, level 2: 1.5x, level 3: 2.0x, level 5: 3.0x, level 10: 5.5x
func calculate_damage(base_damage: float, multiplier: float = 1.0) -> int:
	var level_multiplier: float = 1.0 + (level - 1) * 0.5
	return maxi(1, int(base_damage * level_multiplier * multiplier))

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

func _get_talent_level(char_id: int, talent_id: String) -> int:
	var tree := _get_talent_tree()
	if tree and tree.has_method("get_talent_level"):
		return tree.get_talent_level(char_id, talent_id)
	return 0

func get_talent_level(char_id: int, talent_id: String) -> int:
	return _get_talent_level(char_id, talent_id)

func _create_shadow() -> void:
	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = _create_ellipse_texture(48, 20)
	shadow.modulate = Color(0.1, 0.1, 0.15, 0.4)
	shadow.position = Vector2(0, 20)
	shadow.z_index = -1
	add_child(shadow)

func _create_ellipse_texture(width: int, height: int) -> Texture2D:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var center := Vector2(width / 2.0, height / 2.0)
	for y in height:
		for x in width:
			var dx := (x - center.x) / (width / 2.0)
			var dy := (y - center.y) / (height / 2.0)
			var dist := dx * dx + dy * dy
			if dist <= 1.0:
				var alpha := 1.0 - sqrt(dist)
				img.set_pixel(x, y, Color(1, 1, 1, alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

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
	
	if hp <= 0:
		_on_player_death()

func _on_player_death() -> void:
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

# ============= BURST SYSTEM =============

func register_burst_hit(_target = null, from_burst: bool = false) -> void:
	if from_burst:
		return
	if not is_burst_unlocked():
		return
	
	burst_current = min(burst_current + burst_per_hit, burst_max)
	if player_hud:
		player_hud.update_burst(burst_current, burst_max, true)
	if overhead_hud:
		overhead_hud.update_burst(burst_current, burst_max)

func is_burst_ready() -> bool:
	return burst_current >= burst_max

func use_burst() -> bool:
	if not is_burst_ready():
		return false
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
		audio_player.bus = "Master"
		audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
		root.add_child(audio_player)
		audio_player.play()
		audio_player.finished.connect(audio_player.queue_free)

# ============= XP / LEVELING =============

func add_xp(amount: int) -> void:
	xp += amount
	var leveled_up := false
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = int(xp_to_next * 1.2)
		leveled_up = true
		_add_skill_point()
	update_xp_bar()
	if leveled_up:
		if xp_ui and xp_ui.has_method("flash_level_up"):
			xp_ui.flash_level_up()
		# Spawn WoW-style golden glow effect around player
		_spawn_level_up_glow()

func _spawn_level_up_glow() -> void:
	## Spawns the golden level-up glow effect around the player
	var LevelUpGlowScript = preload("res://scripts/effects/LevelUpGlow.gd")
	var glow = LevelUpGlowScript.new()
	get_parent().add_child(glow)
	glow.attach_to_player(self)

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
	
	# Forward talent to controller - use slot index
	if slot_idx >= 0 and slot_idx < _controllers.size():
		var controller = _controllers[slot_idx]
		if controller and controller.has_method("apply_talent"):
			controller.apply_talent(talent_id)
	
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
	if running and not dashing:
		stamina = max(stamina - running_stamina_drain * delta, 0)
		if player_hud:
			player_hud.update_stamina(stamina, max_stamina, true)
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
