extends CharacterBody2D

# Burst effect scripts
const SnowWhiteBurstBeamScript = preload("res://scripts/SnowWhiteBurstBeam.gd")
const ScarletBurstEffectScript = preload("res://scripts/ScarletBurstEffect.gd")
const RapunzelBurstEffectScript = preload("res://scripts/RapunzelBurstEffect.gd")
const PlayerOverheadHudScript = preload("res://scripts/PlayerOverheadHud.gd")
const CharacterSwapEffectScript = preload("res://scripts/CharacterSwapEffect.gd")

@export var speed = 400
@export var dash_speed = 800
@export var dash_duration = 0.3
@export var acceleration = 6000
@export var friction = 5000
@export var momentum_duration = 0.1
@export var stamina = 100.0
@export var max_stamina = 100.0
@export var stamina_regen = 30.0
@export var dash_stamina_cost = 20.0
@export var boost_duration = 0.1
@export var attack_stamina_cost = 10.0
@export var boost_multiplier = 1.2
@export var running_speed_multiplier = 1.5
@export var running_stamina_drain = 20.0  # stamina per second while running
@export var attack_cooldown = 0.3
@export var burst_max = 100.0
@export var burst_per_hit = 5.0
@export var crit_rate: float = 0.2  # 20% default crit rate

@export var debug_upgrade_shop: bool = false
@export var debug_movement: bool = false
@export var dash_press_grace: float = 0.12

@onready var xp_ui = get_node_or_null("../CanvasLayer/XPUI")
@onready var player_hud = get_node_or_null("../CanvasLayer/PlayerHudCluster")
@onready var screen_flash = get_node_or_null("../ScreenFlashLayer/ScreenFlash")
@onready var _animator = $Sprite2D
@onready var overhead_hud = $PlayerOverheadHud

var audio_director = null

# Burst voice sounds
var _burst_sounds: Array = []

var attack_timer = 0.0
var dashing = false
var dash_direction = Vector2.ZERO
var dash_timer = 0.0
var invincible = false
var momentum_timer = 0.0
var boost_timer = 0.0
var previous_dash_direction = Vector2.ZERO
var wants_running = false
var _dash_press_timer = 0.0
var rapunzel_unlocked = false
var scarlet_unlocked = false
var turret_unlocked = false
var snow_burst_unlocked = false
var scarlet_special_unlocked = false
var scarlet_burst_unlocked = false
var rapunzel_special_unlocked = false
var rapunzel_burst_unlocked = false
var kilo_unlocked = false
var kilo_special_unlocked = false
var kilo_burst_unlocked = false
var unlocked_characters = [0]  # Start with Main character (slot 0)
var current_character = 0  # Start with Main character (slot 0)
var character_sprites = []
var hp = 10
var max_hp = 10
var xp = 0
var level = 1
var xp_to_next = 100
var burst_current = 0.0
var running = false
var shop_open = false
var scarlet_damage_accumulator = 0.0  # Tracks fractional self-damage for precise 3%

# Character swap visual effect
var _swap_effect: Node2D = null

# Ammo system - per character
var snow_white_ammo = 7
var snow_white_max_ammo = 7
var snow_white_reload_time = 1.5
var snow_white_reloading = false
var snow_white_reload_timer = 0.0

var rapunzel_ammo = 4
var rapunzel_max_ammo = 4
var rapunzel_reload_time = 3.0
var rapunzel_reloading = false
var rapunzel_reload_timer = 0.0

# Scarlet special attack (dash wave) has a cooldown
var scarlet_special_ammo = 1
var scarlet_special_max_ammo = 1
var scarlet_special_reload_time = 4.0
var scarlet_special_reloading = false
var scarlet_special_reload_timer = 0.0

# Snow White turret special ability - charge-based system
var snow_white_turret_cooldown = 8.0  # Seconds to refresh all charges
var snow_white_turret_timer = 0.0  # Current cooldown timer (0 = ready)
var snow_white_turret_charges = 1  # Current available charges
var snow_white_turret_max_charges = 1  # Max charges (updated by talents)
var snow_white_turret_recharging = false  # True when recharging after using turrets

# Rapunzel healing cross special ability cooldown
var rapunzel_cross_cooldown = 10.0  # Seconds between cross spawns
var rapunzel_cross_timer = 0.0  # Current cooldown timer (0 = ready)

# Kilo ammo and special attack system
var kilo_ammo = 6
var kilo_max_ammo = 6
var kilo_reload_time = 2.5
var kilo_reloading = false
var kilo_reload_timer = 0.0
var kilo_special_cooldown = 3.0  # Seconds between Penetrating Blast uses
var kilo_special_timer = 0.0  # Current cooldown timer (0 = ready)

# Kilo burst state
var kilo_burst_active = false
var kilo_burst_timer = 0.0
var kilo_burst_duration = 4.0  # Base duration 4s, upgraded to 8s
var kilo_burst_invincible = false

# Skill points notification UI reference
var _skill_points_notify: Control = null

# Selected characters from GameState (registry indices)
var _selected_char_indices: Array[int] = []
var _character_registry = null

# Default FPS values for character sprites (indexed by registry index)
const CHARACTER_FPS := {
	0: 12.5,  # scarlet
	1: 6.0,   # commander
	2: 5.0,   # rapunzel
	3: 6.0,   # kilo
	4: 6.0,   # marian
	5: 6.0,   # crown
	6: 4.5,   # snow_white
	7: 6.0,   # sin
	8: 6.0,   # cecil
	9: 6.0,   # nayuta
}

func _init_from_gamestate() -> void:
	# Load CharacterRegistry
	var CharacterRegistryClass = load("res://scripts/characters/CharacterRegistry.gd")
	if CharacterRegistryClass:
		_character_registry = CharacterRegistryClass.get_instance()
	
	# Load selected characters from GameState
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("get_shop_character_order"):
		# get_shop_character_order returns [Support1, Main, Support2] for display
		# But we want the original order [Main, Support1, Support2]
		# So we get selected_character_indices directly
		_selected_char_indices = game_state.selected_character_indices.duplicate()
		print("[Player] Loaded selected characters: ", _selected_char_indices)
	else:
		# Fallback defaults
		_selected_char_indices = [0, 1, 4]  # Scarlet, Commander, Marian
	
	# Build character_sprites from selected characters
	_build_character_sprites()
	
	# Start with Main character (slot 0)
	current_character = 0
	unlocked_characters = [0]

func _build_character_sprites() -> void:
	"""Build the character_sprites array from selected character indices."""
	character_sprites.clear()
	
	if _character_registry == null:
		push_warning("[Player] CharacterRegistry not loaded, using fallback sprites")
		# Fallback to old hardcoded sprites
		character_sprites = [
			{"texture": load("res://assets/characters/scarlet-sprite.png"), "fps": 12.5},
			{"texture": load("res://assets/characters/snow-white-sprite.png"), "fps": 4.5},
			{"texture": load("res://assets/characters/rapunzel-sprite.png"), "fps": 5.0},
			{"texture": load("res://assets/characters/kilo-sprite.png"), "fps": 6.0}
		]
		return
	
	var all_ids: Array[String] = _character_registry.get_all_character_ids()
	
	for char_idx in _selected_char_indices:
		if char_idx >= 0 and char_idx < all_ids.size():
			var char_id: String = all_ids[char_idx]
			var folder_name: String = char_id.replace("_", "-")
			# Sprites are inside character folders: characters/scarlet/scarlet-sprite.png
			var sprite_path: String = "res://assets/characters/%s/%s-sprite.png" % [folder_name, folder_name]
			var texture = load(sprite_path)
			var fps: float = CHARACTER_FPS.get(char_idx, 6.0)
			
			if texture:
				character_sprites.append({"texture": texture, "fps": fps})
				print("[Player] Loaded sprite for %s (index %d)" % [char_id, char_idx])
			else:
				push_warning("[Player] Could not load sprite: %s" % sprite_path)
				# Add placeholder
				character_sprites.append({"texture": null, "fps": 6.0})
		else:
			push_warning("[Player] Invalid character index: %d" % char_idx)
			character_sprites.append({"texture": null, "fps": 6.0})
	
	print("[Player] Built %d character sprites" % character_sprites.size())

func _build_burst_sounds() -> void:
	"""Build the _burst_sounds array from selected character indices."""
	_burst_sounds.clear()
	
	if _character_registry == null:
		push_warning("[Player] CharacterRegistry not loaded, using fallback burst sounds")
		# Fallback to old hardcoded sounds
		_burst_sounds = [
			load("res://assets/characters/scarlet/burst.mp3"),
			load("res://assets/characters/snow-white/burst.mp3"),
			load("res://assets/characters/rapunzel/burst.mp3"),
			load("res://assets/characters/kilo/burst.mp3")
		]
		return
	
	var all_ids: Array[String] = _character_registry.get_all_character_ids()
	
	for char_idx in _selected_char_indices:
		if char_idx >= 0 and char_idx < all_ids.size():
			var char_id: String = all_ids[char_idx]
			var folder_name: String = char_id.replace("_", "-")
			# Try mp3 first, then wav
			var sound_path: String = "res://assets/characters/%s/burst.mp3" % folder_name
			var sound = load(sound_path)
			if sound == null:
				sound_path = "res://assets/characters/%s/burst.wav" % folder_name
				sound = load(sound_path)
			
			_burst_sounds.append(sound)
			if sound:
				print("[Player] Loaded burst sound for %s" % char_id)
			else:
				push_warning("[Player] Could not load burst sound for %s" % char_id)
		else:
			_burst_sounds.append(null)
	
	print("[Player] Built %d burst sounds" % _burst_sounds.size())

func _ready():
	# Add to player group so enemies/XP orbs can find us
	add_to_group("player")
	
	# Initialize from GameState selected characters
	_init_from_gamestate()
	
	# Create shadow under player
	_create_shadow()
	
	# Initialize audio director
	var AudioDirectorScript = load("res://scripts/AudioDirector.gd")
	audio_director = AudioDirectorScript.new()
	audio_director.name = "AudioDirector"
	add_child(audio_director)
	
	# Initialize movement effects
	var MovementEffectsScript = load("res://scripts/PlayerMovementEffects.gd")
	var movement_effects = Node2D.new()
	movement_effects.set_script(MovementEffectsScript)
	movement_effects.name = "MovementEffects"
	add_child(movement_effects)
	
	# Stop menu music if MenuManager exists (autoload)
	if has_node("/root/MenuManager"):
		var menu_manager = get_node("/root/MenuManager")
		if menu_manager.has_method("stop_menu_music"):
			menu_manager.stop_menu_music()
	
	# Start battle music
	audio_director.play_random_battle_track()
	
	# Load burst voice sounds for selected characters (built dynamically)
	_build_burst_sounds()
	
	# Initialize overhead HUD with current values
	if overhead_hud:
		overhead_hud.update_health(hp, max_hp)
		overhead_hud.update_burst(burst_current, burst_max)
		overhead_hud.update_character(current_character)
		_update_overhead_ammo()
	
	update_xp_bar()
	# character_sprites is now built in _init_from_gamestate() via _build_character_sprites()
	
	update_sprite()
	# Defer HUD update to ensure it's ready
	call_deferred("_update_hud")

func _update_hud():
	if player_hud and player_hud.is_inside_tree():
		player_hud.set_character(current_character, _is_current_character_burst_unlocked())
		player_hud.configure(hp, max_hp, burst_current, burst_max, stamina, max_stamina)

func update_sprite():
	if not _animator:
		return
	if current_character < 0 or current_character >= character_sprites.size():
		push_warning("[Player] current_character %d out of bounds (sprites: %d)" % [current_character, character_sprites.size()])
		return
	var sprite_data = character_sprites[current_character]
	if sprite_data == null or sprite_data.get("texture") == null:
		push_warning("[Player] No texture for character slot %d" % current_character)
		return
	var texture = sprite_data["texture"]
	var fps = sprite_data["fps"]
	_animator.configure(texture, 3, 4, fps, 0.2)
	if player_hud and player_hud.is_inside_tree():
		player_hud.set_character(current_character, _is_current_character_burst_unlocked())

func _is_current_character_burst_unlocked() -> bool:
	match current_character:
		0:  # Scarlet
			return scarlet_burst_unlocked
		1:  # Snow White
			return snow_burst_unlocked
		2:  # Rapunzel
			return rapunzel_burst_unlocked
		3:  # Kilo
			return kilo_burst_unlocked
	return false

func _get_talent_tree() -> Control:
	"""Find the TalentTree node in the scene."""
	var canvas := get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = get_tree().root
	return canvas.get_node_or_null("TalentTree")

func get_talent_level(char_id: int, talent_id: String) -> int:
	"""Query the talent tree for a specific talent's level (0 = not unlocked)."""
	var tree := _get_talent_tree()
	if tree and tree.has_method("get_talent_level"):
		return tree.get_talent_level(char_id, talent_id)
	return 0

func _create_shadow() -> void:
	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = _create_ellipse_texture(48, 20)
	shadow.modulate = Color(0.1, 0.1, 0.15, 0.4)
	shadow.position = Vector2(0, 20)  # Below feet
	shadow.z_index = -1  # Behind player
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

func _trigger_swap_effect() -> void:
	# Create or reuse swap effect
	if not is_instance_valid(_swap_effect):
		_swap_effect = Node2D.new()
		_swap_effect.set_script(CharacterSwapEffectScript)
		_swap_effect.name = "SwapEffect"
		_swap_effect.z_index = 50
		get_parent().add_child(_swap_effect)
	
	# Trigger the effect at player position
	if _swap_effect.has_method("trigger"):
		_swap_effect.trigger(current_character, global_position)

func take_damage(dmg):
	if invincible:
		return
	var prev_hp = hp
	hp -= dmg
	
	# Screen flash on damage
	if screen_flash and screen_flash.has_method("flash_damage"):
		screen_flash.flash_damage()
	
	# Combat juice: hit spark and camera shake for player damage
	var HitSparkScript = preload("res://scripts/HitSpark.gd")
	if get_parent() and HitSparkScript:
		HitSparkScript.spawn_player_hit(get_parent(), global_position)
	var combat_juice_script = load("res://scripts/CombatJuice.gd")
	if combat_juice_script and combat_juice_script.instance:
		combat_juice_script.camera_shake(12.0)  # Stronger shake when player hit
	
	# Spawn floating damage number (much higher to avoid all UI elements)
	var FloatingNumber = preload("res://scripts/FloatingDamageNumber.gd")
	if get_parent():
		FloatingNumber.spawn_damage(get_parent(), global_position + Vector2(0, -100), dmg)
	
	if player_hud:
		player_hud.update_health(hp, max_hp, hp - prev_hp, true)
	if overhead_hud:
		overhead_hud.update_health(hp, max_hp)
	if hp <= 0:
		# game over or something
		pass

func heal(amount: int):
	var prev_hp = hp
	hp = min(hp + amount, max_hp)
	var actual_heal = hp - prev_hp
	
	# Spawn floating heal number (much higher to avoid all UI elements)
	if actual_heal > 0:
		var FloatingNumber = preload("res://scripts/FloatingDamageNumber.gd")
		if get_parent():
			FloatingNumber.spawn_heal(get_parent(), global_position + Vector2(0, -100), actual_heal)
	
	if player_hud:
		player_hud.update_health(hp, max_hp, hp - prev_hp, true)
	if overhead_hud:
		overhead_hud.update_health(hp, max_hp)

func register_burst_hit(_target = null, from_burst: bool = false):
	# Don't charge burst from burst attacks
	if from_burst:
		return
	
	# Don't charge burst if current character doesn't have burst unlocked
	if not _is_current_character_burst_unlocked():
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

func _attempt_burst_activation():
	# Ensure the current character's burst is unlocked before allowing activation
	if current_character == 0 and not scarlet_burst_unlocked:
		return
	if current_character == 1 and not snow_burst_unlocked:
		return
	if current_character == 2 and not rapunzel_burst_unlocked:
		return
	if current_character == 3 and not kilo_burst_unlocked:
		return

	if use_burst():
		_play_burst_voice()
		_trigger_character_burst()

func _update_burst_visibility():
	# Unlock burst bar if ANY character has burst unlocked
	var any_burst := snow_burst_unlocked or scarlet_burst_unlocked or rapunzel_burst_unlocked or kilo_burst_unlocked
	if player_hud and player_hud.has_method("set_burst_unlocked"):
		player_hud.set_burst_unlocked(any_burst)
	if overhead_hud and overhead_hud.has_method("update_burst_unlocked"):
		overhead_hud.update_burst_unlocked(any_burst)

func _update_burst_bar():
	# Update the burst bar UI after changes
	if player_hud and player_hud.has_method("update_burst"):
		player_hud.update_burst(burst_current, burst_max)
	if overhead_hud and overhead_hud.has_method("update_burst"):
		overhead_hud.update_burst(burst_current, burst_max)

func _refresh_turret_charges():
	# Refresh all turret charges and cancel any recharge cooldown
	var count_level := get_talent_level(1, "special_count")
	snow_white_turret_max_charges = 1 + count_level * 2
	snow_white_turret_charges = snow_white_turret_max_charges
	snow_white_turret_timer = 0
	snow_white_turret_recharging = false

func _play_burst_voice():
	if current_character < 0 or current_character >= _burst_sounds.size():
		return
	var sound = _burst_sounds[current_character]
	if sound == null:
		return
	
	# Create completely independent audio player at scene root
	# Use unique name with timestamp to avoid any conflicts
	var root = get_tree().root
	
	var audio_player = AudioStreamPlayer.new()
	audio_player.name = "BurstVoice_%d" % Time.get_ticks_msec()
	audio_player.stream = sound
	audio_player.volume_db = 10.0  # Very loud and clear
	audio_player.bus = "Master"
	audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(audio_player)
	audio_player.play()
	
	# Clean up when finished
	audio_player.finished.connect(audio_player.queue_free)

func _trigger_character_burst():
	var aim_direction = (get_global_mouse_position() - global_position).normalized()
	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2.RIGHT
	
	# Trigger burst combat juice effects (hitstop + chromatic + time dilation)
	var combat_juice_script = load("res://scripts/CombatJuice.gd")
	if combat_juice_script and combat_juice_script.instance:
		combat_juice_script.burst_effect()
	
	match current_character:
		0:  # Scarlet
			_activate_scarlet_burst()
		1:  # Snow White
			_activate_snow_white_burst(aim_direction)
		2:  # Rapunzel
			_activate_rapunzel_burst()
		3:  # Kilo
			_activate_kilo_burst()

func _activate_scarlet_burst():
	# Scarlet burst costs 50% of current HP
	var hp_cost = int(hp * 0.5)
	hp = max(hp - hp_cost, 1)  # Don't let burst kill Scarlet
	if player_hud:
		player_hud.update_health(hp, max_hp, -hp_cost, true)
	if overhead_hud:
		overhead_hud.update_health(hp, max_hp)
	
	var effect = ScarletBurstEffectScript.new()
	effect.owner_node = self
	# Pass talent levels for execution and vulnerability
	effect.execute_talent = get_talent_level(0, "burst_execute") > 0
	effect.vuln_talent = get_talent_level(0, "burst_vuln") > 0
	get_parent().add_child(effect)
	effect.global_position = global_position
	# Connect to handle teleport after burst completes
	effect.burst_complete.connect(_on_scarlet_burst_complete)
	if audio_director:
		audio_director.play_weapon_fire_sound("sword")

func _on_scarlet_burst_complete(teleport_position: Vector2):
	if teleport_position != Vector2.ZERO:
		global_position = teleport_position

func _activate_snow_white_burst(aim_direction: Vector2):
	var beam = SnowWhiteBurstBeamScript.new()
	beam.owner_node = self
	beam.damage = 50
	beam.beam_range = 1200.0
	beam.beam_angle_degrees = 90.0
	# Pass talent levels for burn and gauge effects
	beam.burn_level = get_talent_level(1, "burst_burn")
	beam.gauge_on_kill = get_talent_level(1, "burst_gauge") > 0
	beam.configure(aim_direction)
	get_parent().add_child(beam)
	beam.global_position = global_position
	if audio_director:
		audio_director.play_weapon_fire_sound("sniper")

func _activate_rapunzel_burst():
	var effect = RapunzelBurstEffectScript.new()
	effect.owner_node = self
	# Get talent levels for stun and invincibility
	var stun_level := get_talent_level(2, "burst_stun")
	var invuln_level := get_talent_level(2, "burst_invuln")
	# Stun: 4s base, 8s if talent unlocked
	effect.stun_duration = 8.0 if stun_level > 0 else 4.0
	# Invincibility: 8s if talent unlocked
	effect.grant_invuln = invuln_level > 0
	effect.invuln_duration = 8.0
	get_parent().add_child(effect)
	effect.global_position = global_position

func _activate_kilo_burst():
	# Kilo burst: Assign Priority - infinite ammo, rapid fire, invincibility
	kilo_burst_active = true
	
	# Check for duration upgrade (8s instead of 4s)
	var duration_level := get_talent_level(3, "burst_duration")
	kilo_burst_duration = 8.0 if duration_level > 0 else 4.0
	kilo_burst_timer = kilo_burst_duration
	
	# Always grant invincibility during burst
	invincible = true
	kilo_burst_invincible = true
	
	# Refill ammo during burst
	kilo_ammo = kilo_max_ammo
	_update_overhead_ammo()
	
	# Play shotgun sound to signal burst start
	if audio_director:
		audio_director.play_weapon_fire_sound("shotgun")

func _end_kilo_burst():
	kilo_burst_active = false
	kilo_burst_timer = 0.0
	# Always remove invincibility when burst ends
	invincible = false
	kilo_burst_invincible = false

func add_xp(amount):
	xp += amount
	var leveled_up := false
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = int(xp_to_next * 1.2)
		leveled_up = true
		show_upgrade_shop()
	update_xp_bar()
	if leveled_up:
		if xp_ui and xp_ui.has_method("flash_level_up"):
			xp_ui.flash_level_up()
		# Spawn WoW-style golden glow effect around player
		_spawn_level_up_glow()

func _spawn_level_up_glow() -> void:
	## Spawns the golden level-up glow effect around the player
	var LevelUpGlowScript = preload("res://scripts/LevelUpGlow.gd")
	var glow = LevelUpGlowScript.new()
	get_parent().add_child(glow)
	glow.attach_to_player(self)

func update_xp_bar():
	if xp_ui and xp_ui.has_method("set_xp"):
		xp_ui.set_xp(xp, xp_to_next)
		xp_ui.set_level(level)

func show_upgrade_shop():
	# Add skill point and update notification instead of immediately opening shop
	_add_skill_point_and_notify()

func _add_skill_point_and_notify():
	var canvas := get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = get_tree().root
	
	# Add skill point to existing talent tree or create one
	var existing := canvas.get_node_or_null("TalentTree")
	if existing:
		existing.add_skill_points(1)
	else:
		# Create talent tree to hold skill points (hidden)
		var TalentTreeScript = preload("res://scripts/TalentTree.gd")
		var tree = TalentTreeScript.new()
		tree.name = "TalentTree"
		tree.set_anchors_preset(Control.PRESET_FULL_RECT)
		canvas.add_child(tree)
		tree.add_skill_points(1)
		tree.talent_unlocked.connect(_on_talent_unlocked)
		tree.tree_closed.connect(_on_talent_tree_closed)
		existing = tree
	
	# Update or create skill points notification
	_update_skill_points_notification(existing.get_skill_points())

func _update_skill_points_notification(points: int):
	var canvas := get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = get_tree().root
	
	# Update overhead HUD arrow indicator
	if overhead_hud:
		overhead_hud.update_skill_points_available(points > 0)
	
	if points <= 0:
		# Hide/remove notification if no points
		if _skill_points_notify and is_instance_valid(_skill_points_notify):
			_skill_points_notify.visible = false
		return
	
	# Create notification if it doesn't exist
	if _skill_points_notify == null or not is_instance_valid(_skill_points_notify):
		_skill_points_notify = _create_skill_points_notification()
		canvas.add_child(_skill_points_notify)
	
	# Update text and make visible
	var main_label: Label = _skill_points_notify.get_node_or_null("MainLabel")
	if main_label:
		main_label.text = "SKILL POINTS AVAILABLE × %d" % points
	_skill_points_notify.visible = true
	
	# Animate entrance with pulse
	_animate_skill_points_notification()

func _create_skill_points_notification() -> Control:
	var container := Control.new()
	container.name = "SkillPointsNotify"
	# Position under player HUD with good padding (HUD is ~143px tall + margin)
	container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	container.position = Vector2(35, 200)  # Below the player HUD cluster, nudged right
	container.size = Vector2(240, 48)  # 60% of original 400x80
	container.pivot_offset = Vector2(120, 24)  # Center pivot for scaling (60% of 200, 40)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Background panel with golden border
	var bg := Panel.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.02, 0.02, 0.04, 0.95)
	bg_style.border_color = Color(1.0, 0.85, 0.2, 1.0)  # Golden border
	bg_style.set_border_width_all(3)  # Slightly thinner border
	bg_style.set_corner_radius_all(6)  # Smaller corner radius
	bg_style.shadow_color = Color(1.0, 0.75, 0.0, 0.5)  # Golden glow
	bg_style.shadow_size = 5  # Smaller glow
	bg.add_theme_stylebox_override("panel", bg_style)
	container.add_child(bg)
	
	# Main label - golden and very noticeable (60% font size)
	var main_label := Label.new()
	main_label.name = "MainLabel"
	main_label.text = "SKILL POINTS AVAILABLE × 1"
	main_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main_label.add_theme_font_size_override("font_size", 16)  # 60% of 26
	main_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))  # Golden
	main_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	main_label.add_theme_constant_override("shadow_offset_x", 1)
	main_label.add_theme_constant_override("shadow_offset_y", 1)
	main_label.position = Vector2(0, 4)
	main_label.size = Vector2(240, 24)  # 60% of 400x40
	container.add_child(main_label)
	
	# Sub label - smaller and less noticeable (60% font size)
	var sub_label := Label.new()
	sub_label.name = "SubLabel"
	sub_label.text = "PRESS TAB TO OPEN SKILL TREE"
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_label.add_theme_font_size_override("font_size", 9)  # 60% of 14
	sub_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.85))  # Muted
	sub_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	sub_label.add_theme_constant_override("shadow_offset_x", 1)
	sub_label.add_theme_constant_override("shadow_offset_y", 1)
	sub_label.position = Vector2(0, 28)  # 60% of 48
	sub_label.size = Vector2(240, 16)  # 60% of 400x24
	container.add_child(sub_label)
	
	return container

func _animate_skill_points_notification():
	if _skill_points_notify == null or not is_instance_valid(_skill_points_notify):
		return
	
	# Kill any existing pulse tween
	if _skill_points_notify.has_meta("pulse_tween"):
		var old_tween = _skill_points_notify.get_meta("pulse_tween")
		if old_tween and is_instance_valid(old_tween):
			old_tween.kill()
	
	# Pulse animation with scale - loops forever
	var tween := create_tween()
	tween.set_loops()  # Infinite loops (no argument = infinite)
	tween.tween_property(_skill_points_notify, "scale", Vector2(1.05, 1.05), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_skill_points_notify, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_skill_points_notify.set_meta("pulse_tween", tween)

func _show_talent_tree(add_point: bool = false):
	var canvas := get_parent().get_node_or_null("CanvasLayer")
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
	var existing := canvas.get_node_or_null("TalentTree")
	if existing:
		if add_point:
			existing.add_skill_points(1)  # Add point for leveling up
		existing.show_tree(self)
		shop_open = true
		if get_parent().has_method("set_game_paused"):
			get_parent().call_deferred("set_game_paused", true)
		return
	
	# Create new talent tree using preload for proper initialization
	var TalentTreeScript = preload("res://scripts/TalentTree.gd")
	var tree = TalentTreeScript.new()
	tree.name = "TalentTree"
	tree.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(tree)
	
	# Give initial skill point if leveling up
	if add_point:
		tree.add_skill_points(1)
	
	# Connect signals
	tree.talent_unlocked.connect(_on_talent_unlocked)
	tree.tree_closed.connect(_on_talent_tree_closed)
	
	# Show the tree
	tree.show_tree(self)
	shop_open = true
	if get_parent().has_method("set_game_paused"):
		get_parent().call_deferred("set_game_paused", true)

func _on_talent_tree_closed():
	shop_open = false
	if get_parent().has_method("set_game_paused"):
		get_parent().call_deferred("set_game_paused", false)
	
	# Update skill points notification based on remaining points
	var canvas := get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = get_tree().root
	var tree := canvas.get_node_or_null("TalentTree")
	if tree:
		_update_skill_points_notification(tree.get_skill_points())

func _on_talent_unlocked(char_id: int, talent_id: String):
	# Apply talent effects based on character and talent
	match char_id:
		0:  # Scarlet
			_apply_scarlet_talent(talent_id)
		1:  # Snow White
			_apply_snow_talent(talent_id)
		2:  # Rapunzel
			_apply_rapunzel_talent(talent_id)
		3:  # Kilo
			_apply_kilo_talent(talent_id)
	
	# Update HUD to reflect any changes
	if player_hud:
		player_hud.set_character(current_character, _is_current_character_burst_unlocked())

func _apply_scarlet_talent(talent_id: String):
	match talent_id:
		"unlock":
			scarlet_unlocked = true
			if not (0 in unlocked_characters):
				unlocked_characters.append(0)
				unlocked_characters.sort()
		"atk_speed":
			attack_cooldown *= 0.9  # 10% faster
		"damage":
			pass  # Would need damage multiplier system
		"special":
			scarlet_special_unlocked = true
			# Refresh special cooldown
			scarlet_special_ammo = scarlet_special_max_ammo
			scarlet_special_reloading = false
			scarlet_special_reload_timer = 0
		"special_cd":
			scarlet_special_reload_time = max(1.0, scarlet_special_reload_time - 1.0)
			# Refresh special cooldown
			scarlet_special_ammo = scarlet_special_max_ammo
			scarlet_special_reloading = false
			scarlet_special_reload_timer = 0
		"special_heal":
			# Vampiric Slash - heals instead of damages (logic in wave script)
			# Refresh special cooldown
			scarlet_special_ammo = scarlet_special_max_ammo
			scarlet_special_reloading = false
			scarlet_special_reload_timer = 0
		"burst":
			scarlet_burst_unlocked = true
			_update_burst_visibility()
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()
		"burst_execute":
			# Execution talent - kills non-elite/boss instantly (logic in burst effect)
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()
		"burst_vuln":
			# Expose Weakness - targets take 50% more damage (logic in burst effect)
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()

func _apply_snow_talent(talent_id: String):
	match talent_id:
		"unlock":
			pass  # Snow White starts unlocked
		"range":
			pass  # Range increase
		"crit":
			pass  # Crit chance
		"special":
			turret_unlocked = true
			# Refresh turret charges
			_refresh_turret_charges()
		"special_count":
			# Refresh turret charges (now with +2 more)
			_refresh_turret_charges()
		"special_capacity":
			# Refresh turret charges
			_refresh_turret_charges()
		"burst":
			snow_burst_unlocked = true
			_update_burst_visibility()
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()
		"burst_burn":
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()
		"burst_gauge":
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()

func _apply_rapunzel_talent(talent_id: String):
	match talent_id:
		"unlock":
			rapunzel_unlocked = true
			if not (2 in unlocked_characters):
				unlocked_characters.append(2)
				unlocked_characters.sort()
		"heal_rate":
			pass  # HP regen
		"max_hp":
			max_hp += 10
			hp = min(hp + 10, max_hp)
			if player_hud:
				player_hud.update_health(hp, max_hp, 10, true)
		"special":
			rapunzel_special_unlocked = true
			# Refresh healing cross cooldown
			rapunzel_cross_timer = 0
		"special_size":
			# Refresh healing cross cooldown
			rapunzel_cross_timer = 0
		"special_power":
			# Refresh healing cross cooldown
			rapunzel_cross_timer = 0
		"burst":
			rapunzel_burst_unlocked = true
			_update_burst_visibility()
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()
		"burst_stun":
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()
		"burst_invuln":
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()

func _apply_kilo_talent(talent_id: String):
	match talent_id:
		"unlock":
			kilo_unlocked = true
			if not (3 in unlocked_characters):
				unlocked_characters.append(3)
				unlocked_characters.sort()
		"special":
			kilo_special_unlocked = true
			# Refresh special cooldown
			kilo_special_timer = 0
		"special_burn":
			# Refresh special cooldown
			kilo_special_timer = 0
		"special_size":
			# Refresh special cooldown
			kilo_special_timer = 0
		"burst":
			kilo_burst_unlocked = true
			_update_burst_visibility()
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()
		"burst_duration":
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()
		"burst_invuln":
			# Refresh burst gauge
			burst_current = burst_max
			_update_burst_bar()

func _on_upgrade_selected(option_id):
	# Upgrade selected (logs suppressed)
	# Handle character-specific unlocks in sequence
	if option_id.find("SNOW WHITE") != -1:
		# Snow White slot
		if option_id.begins_with("UNLOCK SNOW WHITE:"):
			if not (1 in unlocked_characters):
				unlocked_characters.append(1)
				unlocked_characters.sort()
		elif option_id.find("TURRET") != -1:
			turret_unlocked = true
		elif option_id.find("BURST") != -1:
			snow_burst_unlocked = true
			_update_burst_visibility()
	elif option_id.find("SCARLET") != -1:
		# Scarlet slot
		if option_id.begins_with("UNLOCK SCARLET:"):
			if not scarlet_unlocked:
				scarlet_unlocked = true
				unlocked_characters.append(0)
				unlocked_characters.sort()
		elif option_id.find("SPECIAL") != -1:
			scarlet_special_unlocked = true
			# Propagate Scarlet special unlock to in-level Player instances so
			# running/testing scenes get the same unlocked state.
			_propagate_flag_to_scene_players("scarlet_special_unlocked", true)
		elif option_id.find("BURST") != -1:
			scarlet_burst_unlocked = true
			_update_burst_visibility()
	elif option_id.find("RAPUNZEL") != -1:
		# Rapunzel slot
		if option_id.begins_with("UNLOCK RAPUNZEL:"):
			if not rapunzel_unlocked:
				rapunzel_unlocked = true
				unlocked_characters.append(2)
				unlocked_characters.sort()
		elif option_id.find("SPECIAL") != -1:
			rapunzel_special_unlocked = true
		elif option_id.find("BURST") != -1:
			rapunzel_burst_unlocked = true
			_update_burst_visibility()
	else:
		# Handle generic upgrades
		if option_id == "Increase Max HP":
			max_hp += 2
			hp += 2
			if player_hud:
				player_hud.update_health(hp, max_hp)
			if overhead_hud:
				overhead_hud.update_health(hp, max_hp)
		elif option_id == "Boost Speed":
			speed += 50
		elif option_id == "More Stamina":
			max_stamina += 20
			stamina += 20
			if player_hud:
				player_hud.update_stamina(stamina, max_stamina)

	# Resume gameplay and re-enable player input after the shop closes
	if get_parent().has_method("set_game_paused"):
		get_parent().call_deferred("set_game_paused", false)

	shop_open = false

func find_free_turret_position():
	var distance = 100.0
	var min_distance_between = 80.0
	var angles = [0, PI/3, 2*PI/3, PI, 4*PI/3, 5*PI/3]  # 6 positions
	for angle in angles:
		var pos = global_position + Vector2(cos(angle), sin(angle)) * distance
		var free = true
		for child in get_parent().get_children():
			if child is Node2D and child.has_method("shoot"):
				if pos.distance_to(child.global_position) < min_distance_between:
					free = false
					break
		if free:
			return pos
	return Vector2.ZERO  # no free spot


func _calculate_safe_spawn_offset(instance: Node2D) -> float:
	# Determine player's collision extents (fallback to a sensible default)
	var player_extent = 32.0
	if has_node("CollisionShape2D") and $CollisionShape2D.shape:
		var shape = $CollisionShape2D.shape
		if typeof(shape) == TYPE_OBJECT:
			if shape is CircleShape2D:
				player_extent = shape.radius * max($CollisionShape2D.scale.x, $CollisionShape2D.scale.y)
			elif shape is RectangleShape2D:
				player_extent = max(shape.size.x, shape.size.y) * 0.5 * max($CollisionShape2D.scale.x, $CollisionShape2D.scale.y)

	# Determine instance (bullet) half-extent based on its collision shape
	var bullet_extent = 10.0
	if instance and instance.has_node("CollisionShape2D") and instance.get_node("CollisionShape2D").shape:
		var bshape = instance.get_node("CollisionShape2D").shape
		if bshape is RectangleShape2D:
			bullet_extent = max(bshape.size.x, bshape.size.y) * 0.5
		elif bshape is CircleShape2D:
			bullet_extent = bshape.radius

	# Add small margin to ensure no overlap
	var margin = 8.0
	# Add an extra safety buffer to account for sprite artwork that extends beyond collision shape
	# User requested an additional 100 pixels — apply that here
	var safety_buffer = 40.0
	var extra_user_buffer = 100.0
	var final_offset = player_extent + bullet_extent + margin + safety_buffer + extra_user_buffer
	# debug info removed, returning calculated final_offset
	return final_offset

func _process(delta):
	# Update reload timers (swapping characters doesn't interrupt reload)
	_update_reloads(delta)
	
	# When running, stamina should be consumed. Avoid applying the normal
	# regeneration while running to ensure net stamina loss; otherwise regen
	# can cancel out the drain and make running feel like it doesn't cost.
	if running and not dashing:
		var prev = stamina
		stamina = max(stamina - running_stamina_drain * delta, 0)
		if player_hud:
			player_hud.update_stamina(stamina, max_stamina, true)
		if debug_movement and prev != stamina:
			print("[Player.movement] running stamina drain: ", prev, " -> ", stamina)
	else:
		stamina = min(stamina + stamina_regen * delta, max_stamina)
		if player_hud:
			player_hud.update_stamina(stamina, max_stamina, false)

func _physics_process(_delta):
	if shop_open:
		return
	# Update dash press grace timer
	if _dash_press_timer > 0.0:
		_dash_press_timer -= _delta
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	input_vector = input_vector.normalized()

	var mouse_world_pos = get_global_mouse_position()
	var aim_direction = (mouse_world_pos - global_position).normalized()
	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2.RIGHT

	if attack_timer > 0:
		attack_timer -= _delta

	# Determine if we should fire
	# Kilo burst mode: continuous fire while holding attack button
	# Sin SMG / Crown Minigun / Commander AR: always continuous fire
	var wants_attack := false
	var is_kilo_burst := current_character == 3 and kilo_burst_active
	var is_auto_fire: bool = current_character == 1 or current_character == 4 or current_character == 5  # Commander AR, Sin SMG, or Crown Minigun
	if is_kilo_burst or is_auto_fire:
		# Automatic fire during Kilo burst or auto-fire weapons - fires while button is held
		wants_attack = Input.is_action_pressed("attack")
	else:
		# Normal semi-auto - only fires on press
		wants_attack = Input.is_action_just_pressed("attack")

	# During Kilo burst or auto-fire: no stamina requirement, free infinite attacks
	var can_fire: bool = wants_attack and attack_timer <= 0
	if not is_kilo_burst and not is_auto_fire:
		can_fire = can_fire and stamina >= attack_stamina_cost
	
	if can_fire:
		if not is_kilo_burst and not is_auto_fire:
			stamina -= attack_stamina_cost
		
		# Bullet rhythm pulse for combat juice
		var combat_juice_script = load("res://scripts/CombatJuice.gd")
		if combat_juice_script and combat_juice_script.instance:
			combat_juice_script.bullet_rhythm_pulse()
		
		if current_character == 0:  # Scarlet
			var slash_scene = preload("res://scenes/effects/Slash.tscn")
			var slash = slash_scene.instantiate()
			add_child(slash)
			slash.position = aim_direction * 50
			slash.rotation = aim_direction.angle()
			if audio_director:
				audio_director.play_weapon_fire_sound("sword")
			# Scarlet self-damage: 3% of max HP per attack
			_apply_scarlet_self_damage()
		elif current_character == 1:  # Snow White
			if snow_white_reloading or snow_white_ammo <= 0:
				if not snow_white_reloading and snow_white_ammo <= 0:
					_start_snow_white_reload()
			else:
				snow_white_ammo -= 1
				_update_overhead_ammo()
				var bullet_scene = preload("res://scenes/effects/Bullet.tscn")
				var bullet = bullet_scene.instantiate()
				# Calculate a safe spawn offset so the bullet doesn't overlap the player collider
				var offset = _calculate_safe_spawn_offset(bullet)
				get_parent().add_child(bullet)
				bullet.global_position = global_position + aim_direction * offset
				# instanced bullet spawn log suppressed for clarity
				bullet.rotation = aim_direction.angle()
				bullet.velocity = aim_direction * 3000
				bullet.owner_node = self
				# Snow White's bullets pierce through enemies
				bullet.pierce_all = true
				if audio_director:
					audio_director.play_weapon_fire_sound("sniper")
				# Auto-reload when empty
				if snow_white_ammo <= 0:
					_start_snow_white_reload()
		elif current_character == 2:  # Rapunzel
			if rapunzel_reloading or rapunzel_ammo <= 0:
				if not rapunzel_reloading and rapunzel_ammo <= 0:
					_start_rapunzel_reload()
			else:
				rapunzel_ammo -= 1
				_update_overhead_ammo()
				var missile_scene = preload("res://scenes/effects/Missile.tscn")
				var missile = missile_scene.instantiate()
				get_parent().add_child(missile)
				missile.global_position = global_position + aim_direction * 100
				missile.target_position = mouse_world_pos
				missile.direction = aim_direction
				missile.explode_at_target = true
				missile.speed = 400
				missile.acceleration = 1500
				missile.max_speed = 3000
				missile.owner_node = self
				missile.ground_fire_enabled = true  # Rapunzel missiles create burning area
				missile.ground_fire_duration = 3.0
				missile.ground_fire_damage = 5
				missile.ground_fire_radius = 100.0
				if audio_director:
					audio_director.play_weapon_fire_sound("rocket")
				# Auto-reload when empty
				if rapunzel_ammo <= 0:
					_start_rapunzel_reload()
		elif current_character == 3:  # Kilo
			# During burst: infinite ammo, no reload needed
			if kilo_burst_active:
				# Burst mode: rapid fire with infinite ammo
				_fire_kilo_shotgun(aim_direction, false)
				if audio_director:
					audio_director.play_weapon_fire_sound("shotgun")
			elif kilo_reloading or kilo_ammo <= 0:
				if not kilo_reloading and kilo_ammo <= 0:
					_start_kilo_reload()
			else:
				kilo_ammo -= 1
				_update_overhead_ammo()
				# Fire shotgun pellets in a spread pattern
				_fire_kilo_shotgun(aim_direction, false)
				if audio_director:
					audio_director.play_weapon_fire_sound("shotgun")
				# Auto-reload when empty
				if kilo_ammo <= 0:
					_start_kilo_reload()
		# Apply faster attack cooldown during Kilo's burst
		if current_character == 3 and kilo_burst_active:
			attack_timer = attack_cooldown * 0.3  # Much faster fire rate during burst
		else:
			attack_timer = attack_cooldown

	if Input.is_action_just_pressed("thrust") and attack_timer <= 0 and stamina >= attack_stamina_cost:
		stamina -= attack_stamina_cost
		if current_character == 0:  # Scarlet
			if scarlet_special_unlocked:
				# Check if special attack is available (ammo and not reloading)
				if scarlet_special_ammo > 0 and not scarlet_special_reloading:
					# Consume ammo and start cooldown
					scarlet_special_ammo -= 1
					_start_scarlet_special_reload()
					
					# Check for Vampiric Slash talent (heals instead of damages)
					var heal_level := get_talent_level(0, "special_heal")
					
					# Always spawn the wave projectile (visual effect)
					var wave_scene = load("res://scenes/effects/ScarletWave.tscn")
					if wave_scene:
						var w = wave_scene.instantiate()
						w.rotation = aim_direction.angle()
						w.owner_node = self
						w.pierce_all = true
						w.damage = 8  # Normal damage
						if heal_level > 0:
							# Vampiric Slash: wave heals per enemy hit IN ADDITION to damage
							w.heal_mode = true
							var heal_percents := [0.0, 0.05, 0.15, 0.25]  # 5/15/25% max HP per hit
							w.heal_percent = heal_percents[heal_level]
						get_parent().add_child(w)
						w.global_position = global_position + aim_direction * 36
						w.velocity = aim_direction.normalized() * 2400
					
					if audio_director:
						audio_director.play_weapon_fire_sound("sword")
					# Scarlet self-damage: 3% of max HP per attack
					_apply_scarlet_self_damage()
		elif current_character == 1:  # Snow White
			if turret_unlocked and snow_white_turret_charges > 0:
				# Get talent levels for turret bonuses
				var count_level := get_talent_level(1, "special_count")  # +2 max charges per level
				var capacity_level := get_talent_level(1, "special_capacity")  # +2 ammo per level
				
				# Update max charges based on talent (+2 per level)
				snow_white_turret_max_charges = 1 + count_level * 2
				
				# Spawn a turret and consume a charge
				var turret_scene = preload("res://scenes/effects/Turret.tscn")
				var turret = turret_scene.instantiate()
				# Apply capacity bonus before adding to scene
				turret.ammo = 4 + capacity_level * 2
				turret.max_ammo = turret.ammo
				# Find a free position
				var spawn_pos = find_free_turret_position()
				if spawn_pos != Vector2.ZERO:
					turret.global_position = spawn_pos
					get_parent().add_child(turret)
					# Consume a charge
					snow_white_turret_charges -= 1
					# Start recharging if not already
					if not snow_white_turret_recharging:
						snow_white_turret_recharging = true
						snow_white_turret_timer = snow_white_turret_cooldown
		elif current_character == 2:  # Rapunzel
			if rapunzel_special_unlocked and rapunzel_cross_timer <= 0:
				# Spawn a healing cross near the player
				var cross_scene = load("res://scenes/effects/HealingCross.tscn")
				if cross_scene:
					var cross = cross_scene.instantiate()
					# Get talent levels for healing cross bonuses
					var power_level := get_talent_level(2, "special_power")
					var size_level := get_talent_level(2, "special_size")
					# Apply power bonus: 3% base + 7/14.5/22% per level = 10/17.5/25% at max
					var power_bonuses := [0.0, 0.07, 0.145, 0.22]  # Levels 0,1,2,3
					cross.heal_percent = 0.03 + power_bonuses[mini(power_level, 3)]
					# Apply size bonus: 1x base + 0.5/1.5/3.0x per level for radius and lifespan
					var size_multipliers := [1.0, 1.5, 2.5, 4.0]  # Levels 0,1,2,3
					var size_mult: float = size_multipliers[mini(size_level, 3)]
					cross.heal_radius = 180.0 * size_mult
					cross.lifespan = 9.0 * size_mult
					get_parent().add_child(cross)
					cross.global_position = global_position + aim_direction * 60
					# Start cooldown
					rapunzel_cross_timer = rapunzel_cross_cooldown
		elif current_character == 3:  # Kilo
			if kilo_special_unlocked and kilo_special_timer <= 0:
				# Penetrating Blast: fire special shotgun with explosive beams
				if kilo_ammo > 0 or kilo_burst_active:
					if not kilo_burst_active:
						kilo_ammo -= 1
						_update_overhead_ammo()
					_fire_kilo_shotgun(aim_direction, true)  # true = special attack
					if audio_director:
						audio_director.play_weapon_fire_sound("shotgun")
					# Start cooldown
					kilo_special_timer = kilo_special_cooldown
					# Auto-reload if empty
					if kilo_ammo <= 0 and not kilo_burst_active:
						_start_kilo_reload()
		attack_timer = attack_cooldown

	if Input.is_action_just_pressed("dash") and input_vector != Vector2.ZERO and not dashing and not running and stamina >= dash_stamina_cost:
		stamina -= dash_stamina_cost
		dashing = true
		dash_direction = input_vector
		previous_dash_direction = dash_direction
		# Record that dash was pressed recently (grace window) and remember
		# whether the player is currently holding the dash button so we can
		# transition into running when the dash ends.
		_dash_press_timer = dash_press_grace
		wants_running = Input.is_action_pressed("dash")
		
		# Notify camera for juicy lag effect
		var camera = get_node_or_null("Camera2D")
		if camera and camera.has_method("notify_dash"):
			camera.notify_dash()
		
		# Scarlet special: if unlocked AND ammo available, dash lasts twice as long and spawns
		# two special helpers: a forward piercing wave and a short-lived
		# damage hitbox attached to the player to remove nearby enemies.
		if current_character == 0 and scarlet_special_unlocked and scarlet_special_ammo > 0 and not scarlet_special_reloading:
			# Consume ammo and start cooldown
			scarlet_special_ammo -= 1
			_start_scarlet_special_reload()
			
			dash_timer = dash_duration * 2.0

			# Check for Vampiric Slash talent (heals instead of damages)
			var heal_level := get_talent_level(0, "special_heal")
			
			# Always spawn the forward piercing wave (visual projectile)
			var wave_scene = load("res://scenes/effects/ScarletWave.tscn")
			if wave_scene:
				var w = wave_scene.instantiate()
				# Rotate the wave so its collision/visual faces dash direction
				w.rotation = dash_direction.angle()
				w.owner_node = self
				w.pierce_all = true
				w.damage = 8  # Normal damage
				if heal_level > 0:
					# Vampiric Slash: wave heals per enemy hit IN ADDITION to damage
					w.heal_mode = true
					var heal_percents := [0.0, 0.05, 0.15, 0.25]  # 5/15/25% max HP per hit
					w.heal_percent = heal_percents[heal_level]
				get_parent().add_child(w)
				w.global_position = global_position + dash_direction * 36
				w.velocity = dash_direction.normalized() * 2400

			# Spawn a short-lived hitbox attached to the player so enemies
			# that collide during the dash are immediately damaged/removed.
			var hit_scene = load("res://scenes/effects/ScarletDashHitbox.tscn")
			if hit_scene:
				var hb = hit_scene.instantiate()
				hb.owner_node = self
				hb.damage = 999
				hb.lifespan = dash_duration * 2.0
				add_child(hb)
				hb.position = Vector2.ZERO
		else:
			dash_timer = dash_duration
		invincible = true
		# Debug (developer) log prints are gated by debug_movement flag
		if debug_movement:
			print("[Player.movement] dash started. dir=", dash_direction, "stamina=", stamina)

	if dashing:
		# Continuously track whether the player still wants to run and allow
		# a recent-press grace window for brief timing mismatches.
		wants_running = Input.is_action_pressed("dash") or _dash_press_timer > 0.0
		if input_vector != Vector2.ZERO:
			if dash_direction != input_vector.normalized():
				boost_timer = boost_duration
			dash_direction = input_vector.normalized()
		var current_dash_speed = dash_speed
		if boost_timer > 0:
			current_dash_speed *= boost_multiplier
			boost_timer -= _delta
		velocity = dash_direction * current_dash_speed
		# Scarlet special: collisions/damage now handled by a short-lived
		# Area2D hitbox (ScarletDashHitbox) and the forward ScarletWave.
		# The per-tick scene-wide enemy scanning was removed for performance.
		# Per-tick debug printing is gated by debug_movement flag
		if debug_movement:
			print("[Player.movement] dashing tick: dash_timer=", dash_timer, "dir=", dash_direction, "input=", input_vector, "velocity=", velocity)
		dash_timer -= _delta
		if dash_timer <= 0:
			dashing = false
			invincible = false
			# If the player is still holding the dash button, allow them to transition
			# into running even if they don't have the full dash cost remaining —
			# running is a lower-cost/continuous state and should not require a
			# second dash-cost payment. Only require that some stamina remains.
			# Transition into running if the player intends to keep dashing
			# (either holds the dash key or pressed it recently within a
			# short grace window), and they have some stamina and are providing
			# movement input. This helps with quick taps/releases around the
			# dash end timing.
			# Allow running even when stamina == 0 so short dashes don't block
			# transitioning into running if the player is still holding dash.
			# If the player has signalled an intent to keep dashing (held or
			# recently pressed), transition to running as long as movement input
			# is still provided. We intentionally do NOT block this on stamina
			# because running is a lower-cost continuous state and should feel
			# responsive when the user keeps holding the dash key.
			if (wants_running or _dash_press_timer > 0.0) and input_vector != Vector2.ZERO:
				# Enter running state and apply immediate running velocity so the
				# player feels the speed change right away.
				running = true
				velocity = input_vector.normalized() * speed * running_speed_multiplier
				# While running we drain stamina over time (see below) so running
				# is a sustained, intentional state.
				if debug_movement:
					print("[Player.movement] TRANSITION -> running (stamina=", stamina, ", velocity=", velocity, ")")
				# Transition message is available when debug_movement is on
				if debug_movement:
					print("[Player.movement] transitioned to running at dash end (stamina=", stamina, ")")
			else:
				# Dash-end diagnostics are gated by debug_movement flag
				if debug_movement:
					print("[Player.movement] dash ended without running: wants_running=", wants_running, "_dash_press_timer=", _dash_press_timer, "stamina=", stamina, "input_vector=", input_vector)

				momentum_timer = momentum_duration
				velocity = dash_direction * (dash_speed * 0.3)
				if debug_movement:
					print("[Player.movement] dash ended. running=", running, "momentum=", momentum_timer, "velocity=", velocity)
	else:
		if running:
			if not Input.is_action_pressed("dash") or stamina < 0:
				running = false
				momentum_timer = momentum_duration

		# Non-dash movement handling ------------------------------------------------
		# If we are in a short momentum window (after a dash), preserve current velocity
		# until the momentum_timer expires. Otherwise accelerate towards the desired
		# target using acceleration and apply friction when no input is present.
		if momentum_timer > 0:
			momentum_timer -= _delta
			# keep current velocity while momentum lasts
			if debug_movement:
				print("[Player.movement] momentum active: ", momentum_timer, "velocity=", velocity)
		else:
			# Use a distinct running multiplier so running speed is noticeably
			# different from a short dash-boost (boost_multiplier). This ensures the
			# player sees an immediate, sustained speed increase while in running.
			var desired_speed = speed * (running_speed_multiplier if running else 1.0)
			if input_vector != Vector2.ZERO:
				var target_velocity = input_vector * desired_speed
				var max_delta_change = acceleration * _delta
				velocity = velocity.move_toward(target_velocity, max_delta_change)
			else:
				var decel_amount = friction * _delta
				velocity = velocity.move_toward(Vector2.ZERO, decel_amount)

		# Running stamina drain applied only when running is active and we're
		# not currently dashing. If stamina drops to zero, we stop running.
		if running and not dashing:
			stamina = max(stamina - running_stamina_drain * _delta, 0)
			if stamina <= 0:
				running = false
				momentum_timer = momentum_duration
				if debug_movement:
					print("[Player.movement] stopped running due to stamina=", stamina)

	# Update animator state so the correct facing/animation plays
	if _animator:
		_animator.update_state(velocity, aim_direction)

	# Always perform physics movement regardless of whether we were dashing
	# previously the move_and_slide call was only done in the non-dash branch
	# which meant dashing didn't actually move the player. Call it every tick.
	move_and_slide()

	if dashing or running:
		if is_on_wall():
			dash_direction = dash_direction.bounce(get_wall_normal())

func _input(event):
	if shop_open:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == 4:  # wheel up
			var current_index = unlocked_characters.find(current_character)
			var next_index = (current_index + 1) % unlocked_characters.size()
			current_character = unlocked_characters[next_index]
			update_sprite()
			_trigger_swap_effect()
			if overhead_hud:
				overhead_hud.update_character(current_character)
				_update_overhead_ammo()
		elif event.button_index == 5:  # wheel down
			var current_index = unlocked_characters.find(current_character)
			var prev_index = (current_index - 1 + unlocked_characters.size()) % unlocked_characters.size()
			current_character = unlocked_characters[prev_index]
			update_sprite()
			_trigger_swap_effect()
			if overhead_hud:
				overhead_hud.update_character(current_character)
				_update_overhead_ammo()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			if 0 in unlocked_characters:
				current_character = 0
				update_sprite()
				_trigger_swap_effect()
				if overhead_hud:
					overhead_hud.update_character(current_character)
					_update_overhead_ammo()
		elif event.keycode == KEY_2:
			if 1 in unlocked_characters:
				current_character = 1
				update_sprite()
				_trigger_swap_effect()
				if overhead_hud:
					overhead_hud.update_character(current_character)
					_update_overhead_ammo()
		elif event.keycode == KEY_3:
			if 2 in unlocked_characters:
				current_character = 2
				update_sprite()
				_trigger_swap_effect()
				if overhead_hud:
					overhead_hud.update_character(current_character)
					_update_overhead_ammo()
		elif event.keycode == KEY_E:  # Burst activation on E key
			_attempt_burst_activation()
		elif event.keycode == KEY_F5:  # Debug: fill burst gauge
			burst_current = burst_max
			if player_hud:
				player_hud.update_burst(burst_current, burst_max, true)
			if overhead_hud:
				overhead_hud.update_burst(burst_current, burst_max)
		elif event.keycode == KEY_F6:  # Debug: force level up
			add_xp(100)
		elif event.keycode == KEY_R:  # Manual reload
			_try_manual_reload()
		elif event.keycode == KEY_TAB:  # Open talent tree
			_show_talent_tree()


func _propagate_flag_to_scene_players(property_name: String, value) -> void:
	# Walk the scene tree and set the provided property on any Player instance
	# scripts found. We match based on the script resource path to avoid
	# accidentally setting unrelated nodes.
	var root = get_tree().root
	_propagate_flag_recursive(root, property_name, value)


func _propagate_flag_recursive(node: Node, property_name: String, value) -> void:
	for child in node.get_children():
		# Only consider nodes with a script; check resource_path for Player scripts
		if child.get_script() != null and child.get_script().resource_path:
			var path := str(child.get_script().resource_path)
			if path.find("scenes/characters/Player.gd") != -1 or path.find("scripts/Player.gd") != -1:
				if child != self:
					# set the property (Player scripts declare the expected vars)
					child.set(property_name, value)
		# Recurse into children
		_propagate_flag_recursive(child, property_name, value)


# --- Scarlet self-damage ---
func _apply_scarlet_self_damage() -> void:
	# Accumulate 3% of max HP as float to avoid rounding issues
	# With 10 max HP: 0.3 per attack, so after 4 attacks = 1.2 -> 1 HP lost
	# This ensures exactly 33-34 attacks to drain full HP
	scarlet_damage_accumulator += float(max_hp) * 0.03
	var actual_dmg = int(scarlet_damage_accumulator)
	if actual_dmg >= 1:
		scarlet_damage_accumulator -= float(actual_dmg)
		hp -= actual_dmg
		if player_hud:
			player_hud.update_health(hp, max_hp, -actual_dmg, true)
		if overhead_hud:
			overhead_hud.update_health(hp, max_hp)
		# Scarlet can kill herself with attacks
		if hp <= 0:
			# TODO: trigger death/game over
			pass


# --- Ammo and reload system ---
func _try_manual_reload() -> void:
	# Allow player to manually reload with R key
	if current_character == 1:  # Snow White
		if not snow_white_reloading and snow_white_ammo < snow_white_max_ammo:
			_start_snow_white_reload()
	elif current_character == 2:  # Rapunzel
		if not rapunzel_reloading and rapunzel_ammo < rapunzel_max_ammo:
			_start_rapunzel_reload()

func _start_snow_white_reload() -> void:
	if snow_white_reloading:
		return
	snow_white_reloading = true
	snow_white_reload_timer = snow_white_reload_time
	_update_overhead_ammo()
	if audio_director:
		audio_director.play_weapon_reload_sound("sniper")


func _start_rapunzel_reload() -> void:
	if rapunzel_reloading:
		return
	rapunzel_reloading = true
	rapunzel_reload_timer = rapunzel_reload_time
	_update_overhead_ammo()
	if audio_director:
		audio_director.play_weapon_reload_sound("rocket")


func _start_kilo_reload() -> void:
	if kilo_reloading:
		return
	kilo_reloading = true
	kilo_reload_timer = kilo_reload_time
	_update_overhead_ammo()
	if audio_director:
		audio_director.play_weapon_reload_sound("shotgun")


func _fire_kilo_shotgun(aim_direction: Vector2, is_special: bool) -> void:
	# Fire 5 pellets in a 15-degree spread pattern
	var pellet_count := 5
	var spread_angle := 15.0  # degrees
	var half_spread := deg_to_rad(spread_angle / 2.0)
	var base_angle := aim_direction.angle()
	
	# Get damage multiplier from burst
	var damage_mult := 1.0
	if kilo_burst_active:
		damage_mult = 2.2
	
	# Calculate spawn offset
	var spawn_offset := 60.0
	
	for i in range(pellet_count):
		# Calculate pellet angle - evenly distributed across spread
		var t := float(i) / float(pellet_count - 1) if pellet_count > 1 else 0.5
		var pellet_angle := base_angle - half_spread + (t * deg_to_rad(spread_angle))
		var pellet_dir := Vector2(cos(pellet_angle), sin(pellet_angle))
		
		# Create pellet (using bullet for now, will create proper pellet later)
		var bullet_scene = preload("res://scenes/effects/Bullet.tscn")
		var pellet = bullet_scene.instantiate()
		get_parent().add_child(pellet)
		pellet.global_position = global_position + pellet_dir * spawn_offset
		pellet.rotation = pellet_angle
		pellet.velocity = pellet_dir * 850  # Shotgun bullet speed
		pellet.owner_node = self
		pellet.pierce_all = false  # Pellets don't pierce by default
		pellet.base_damage = int(35 * damage_mult)  # Shotgun damage per pellet
		
		# If special attack, enable penetrating blast effect
		if is_special and kilo_special_unlocked:
			pellet.set_meta("kilo_special", true)
			pellet.set_meta("burn_level", get_talent_level(3, "special_burn"))
			pellet.set_meta("size_level", get_talent_level(3, "special_size"))


func _start_scarlet_special_reload() -> void:
	if scarlet_special_reloading:
		return
	scarlet_special_reloading = true
	scarlet_special_reload_timer = scarlet_special_reload_time
	_update_overhead_ammo()
	# Could add a sound here if desired
	# if audio_director:
	# 	audio_director.play_weapon_reload_sound("sword")


func _update_reloads(delta: float) -> void:
	if snow_white_reloading:
		snow_white_reload_timer -= delta
		if snow_white_reload_timer <= 0:
			snow_white_reloading = false
			snow_white_ammo = snow_white_max_ammo
			_update_overhead_ammo()
	
	if rapunzel_reloading:
		rapunzel_reload_timer -= delta
		if rapunzel_reload_timer <= 0:
			rapunzel_reloading = false
			rapunzel_ammo = rapunzel_max_ammo
			_update_overhead_ammo()
	
	if scarlet_special_reloading:
		scarlet_special_reload_timer -= delta
		if scarlet_special_reload_timer <= 0:
			scarlet_special_reloading = false
			scarlet_special_ammo = scarlet_special_max_ammo
			_update_overhead_ammo()
	
	if kilo_reloading:
		kilo_reload_timer -= delta
		if kilo_reload_timer <= 0:
			kilo_reloading = false
			kilo_ammo = kilo_max_ammo
			_update_overhead_ammo()
	
	if kilo_special_timer > 0:
		kilo_special_timer -= delta
	
	# Update Kilo burst timer
	if kilo_burst_active:
		kilo_burst_timer -= delta
		if kilo_burst_timer <= 0:
			_end_kilo_burst()
	
	# Special ability cooldown timers
	# Snow White turret recharge - when timer completes, refill ALL charges
	if snow_white_turret_recharging:
		snow_white_turret_timer -= delta
		if snow_white_turret_timer <= 0:
			snow_white_turret_timer = 0
			snow_white_turret_recharging = false
			# Refill all charges (respecting talent level, +2 per level)
			var count_level := get_talent_level(1, "special_count")
			snow_white_turret_max_charges = 1 + count_level * 2
			snow_white_turret_charges = snow_white_turret_max_charges
	
	if rapunzel_cross_timer > 0:
		rapunzel_cross_timer -= delta
		if rapunzel_cross_timer < 0:
			rapunzel_cross_timer = 0
	
	# Update special ability indicator
	_update_overhead_special()

func _update_overhead_special() -> void:
	if not overhead_hud:
		return
	match current_character:
		0:  # Scarlet - placeholder for future special ability
			# For now, show as not unlocked (sword icon will appear when we add the ability)
			overhead_hud.update_special_ability(false, 1.0)
		1:  # Snow White - Turret (charge-based)
			var progress := 1.0
			if snow_white_turret_recharging:
				progress = 1.0 - (snow_white_turret_timer / snow_white_turret_cooldown)
			# Show charges available (pass as extra info if overhead_hud supports it)
			if overhead_hud.has_method("update_special_ability_with_charges"):
				overhead_hud.update_special_ability_with_charges(turret_unlocked, progress, snow_white_turret_charges, snow_white_turret_max_charges)
			else:
				overhead_hud.update_special_ability(turret_unlocked, progress)
		2:  # Rapunzel - Healing Cross
			var progress := 1.0
			if rapunzel_cross_timer > 0:
				progress = 1.0 - (rapunzel_cross_timer / rapunzel_cross_cooldown)
			overhead_hud.update_special_ability(rapunzel_special_unlocked, progress)

func _update_overhead_ammo() -> void:
	if not overhead_hud:
		return
	match current_character:
		0:  # Scarlet - special attack has cooldown when unlocked
			overhead_hud.update_scarlet_special_unlocked(scarlet_special_unlocked)
			if scarlet_special_unlocked:
				overhead_hud.update_ammo(scarlet_special_ammo, scarlet_special_max_ammo, scarlet_special_reloading, scarlet_special_reload_time)
			else:
				overhead_hud.update_ammo(1, 1, false, 0.0)  # Normal attacks are unlimited
		1:  # Snow White
			overhead_hud.update_ammo(snow_white_ammo, snow_white_max_ammo, snow_white_reloading, snow_white_reload_time)
		2:  # Rapunzel
			overhead_hud.update_ammo(rapunzel_ammo, rapunzel_max_ammo, rapunzel_reloading, rapunzel_reload_time)
		3:  # Kilo
			if kilo_burst_active:
				overhead_hud.update_ammo(999, 999, false, 0.0)  # Infinite ammo during burst
			else:
				overhead_hud.update_ammo(kilo_ammo, kilo_max_ammo, kilo_reloading, kilo_reload_time)
