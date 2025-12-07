extends "res://scripts/characters/CharacterController.gd"
class_name CommanderController
## Legendary Commander - Assault Rifle with Time Freeze and Ally Summoning
## Special: Freeze all enemies with clock effect (like his burst in the main game)
## Burst: Summon AI-controlled allies (Scarlet, Snow White, or Rapunzel)

# Preload scripts
const CommanderStunEffectScript = preload("res://scripts/characters/effects/CommanderStunEffect.gd")
const SummonedAllyScript = preload("res://scripts/player/SummonedAlly.gd")

# Assault rifle config
var bullet_speed: float = 900.0

# Special config (Time Freeze)
var freeze_duration: float = 3.0  # How long enemies are frozen
var freeze_cooldown: float = 12.0  # Cooldown between freezes
var _freeze_active: bool = false
var _freeze_end_time: float = 0.0
var _frozen_enemies: Array = []

# Burst config (Summon Allies)
var summon_duration: float = 10.0  # How long summoned allies last
var _active_allies: Array = []

# Talent states
var summon_count: int = 1  # Base: 1, Left upgrade: 2, Both upgrades: 3
var left_upgrade_unlocked: bool = false
var right_upgrade_unlocked: bool = false

func _on_initialize() -> void:
	# Ammo already set from CharacterRegistry by base class
	data.special_cooldown = freeze_cooldown

func _on_process(_delta: float) -> void:
	# Update freeze effect
	if _freeze_active:
		var now := Time.get_ticks_msec() * 0.001
		if now >= _freeze_end_time:
			_end_freeze()
		else:
			# Keep enemies frozen
			_maintain_freeze()
	
	# Clean up dead allies
	_cleanup_allies()

func _can_attack() -> bool:
	return not is_reloading and ammo > 0

func _perform_attack(direction: Vector2) -> void:
	# Fire assault rifle bullet
	_fire_bullet(direction)
	
	# Note: ammo is handled by base CharacterController.attack()

func _fire_bullet(direction: Vector2) -> void:
	# Fire assault rifle bullet with golden-brown style
	var bullet = ProjectileCache.create_assault_bullet()
	
	player.get_parent().add_child(bullet)
	bullet.global_position = player.global_position + direction * 30
	bullet.velocity = direction * bullet_speed
	bullet.rotation = direction.angle()
	bullet.owner_node = player
	# Use character's base damage with level scaling
	bullet.base_damage = player.calc_damage()
	
	_play_sound("assault")

func _can_use_special() -> bool:
	return special_timer <= 0 and not _freeze_active

func _perform_special(_direction: Vector2) -> void:
	# Time freeze - freezes all enemies on screen
	_start_freeze()
	
	# Set cooldown
	special_timer = freeze_cooldown
	data.special_cooldown = freeze_cooldown

func _start_freeze() -> void:
	_freeze_active = true
	var now := Time.get_ticks_msec() * 0.001
	_freeze_end_time = now + freeze_duration
	_frozen_enemies.clear()
	
	# Find all enemies and freeze them
	var tree := player.get_tree()
	if not tree:
		return
	
	# Get view rect for on-screen check
	var viewport := player.get_viewport()
	var view_rect: Rect2
	if viewport:
		var camera := viewport.get_camera_2d()
		if camera:
			var viewport_size := viewport.get_visible_rect().size
			var cam_pos := camera.global_position
			var half_size := viewport_size / (2.0 * camera.zoom)
			view_rect = Rect2(cam_pos - half_size * 1.2, half_size * 2.4)  # Slightly larger to catch edge enemies
		else:
			view_rect = Rect2(player.global_position - Vector2(1000, 600), Vector2(2000, 1200))
	else:
		view_rect = Rect2(player.global_position - Vector2(1000, 600), Vector2(2000, 1200))
	
	var enemies := tree.get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		var enemy_node := enemy as Node2D
		
		# Check if on screen (or close)
		if not view_rect.has_point(enemy_node.global_position):
			continue
		
		# Freeze the enemy
		_freeze_enemy(enemy_node)
		_frozen_enemies.append(weakref(enemy_node))
	
	# Screen flash effect
	if player.screen_flash and player.screen_flash.has_method("flash_custom"):
		player.screen_flash.flash_custom(Color(0.9, 0.7, 0.3, 0.4), 0.3)
	
	# Play time stop sound
	_play_sound("assault")

func _freeze_enemy(enemy: Node2D) -> void:
	# Mark as frozen
	enemy.set_meta("commander_stunned", true)
	enemy.set_meta("commander_stun_end", _freeze_end_time)
	
	# Stop enemy movement if possible
	if "velocity" in enemy:
		enemy.set_meta("pre_freeze_velocity", enemy.velocity)
		enemy.velocity = Vector2.ZERO
	
	if enemy.has_method("set_stunned"):
		enemy.set_stunned(true)
	
	# Only disable physics process (movement), keep regular process for death checks
	if enemy.has_method("set_physics_process"):
		enemy.set_meta("was_physics_processing", enemy.is_physics_processing())
		enemy.set_physics_process(false)
	
	# Add clock visual effect
	var effect := CommanderStunEffectScript.new()
	effect.name = "CommanderStunEffect"
	enemy.add_child(effect)
	effect.position = Vector2.ZERO
	effect.z_index = 100

func _maintain_freeze() -> void:
	# Keep enemies frozen (in case they try to unfreeze themselves)
	for enemy_ref in _frozen_enemies:
		if not enemy_ref is WeakRef:
			continue
		var enemy: Node = enemy_ref.get_ref()
		if not enemy or not is_instance_valid(enemy):
			continue
		
		# Ensure velocity stays zero
		if "velocity" in enemy:
			enemy.velocity = Vector2.ZERO
		
		# Keep physics process disabled but allow regular process for death
		if enemy.has_method("set_physics_process"):
			enemy.set_physics_process(false)

func _end_freeze() -> void:
	_freeze_active = false
	
	# Unfreeze all enemies
	for enemy_ref in _frozen_enemies:
		if not enemy_ref is WeakRef:
			continue
		var enemy: Node = enemy_ref.get_ref()
		if not enemy or not is_instance_valid(enemy):
			continue
		
		_unfreeze_enemy(enemy as Node2D)
	
	_frozen_enemies.clear()

func _unfreeze_enemy(enemy: Node2D) -> void:
	# Remove frozen meta
	enemy.remove_meta("commander_stunned")
	enemy.remove_meta("commander_stun_end")
	
	# Restore velocity
	if enemy.has_meta("pre_freeze_velocity"):
		if "velocity" in enemy:
			enemy.velocity = enemy.get_meta("pre_freeze_velocity")
		enemy.remove_meta("pre_freeze_velocity")
	
	if enemy.has_method("set_stunned"):
		enemy.set_stunned(false)
	
	# Restore physics processing
	if enemy.has_meta("was_physics_processing"):
		enemy.set_physics_process(enemy.get_meta("was_physics_processing"))
		enemy.remove_meta("was_physics_processing")
	
	# Remove clock effect
	var effect := enemy.get_node_or_null("CommanderStunEffect")
	if effect:
		effect.queue_free()

func _on_burst_start() -> void:
	# Summon AI allies based on upgrade level
	_summon_allies()

func _summon_allies() -> void:
	# Determine how many allies to summon
	var count := summon_count
	
	# Available ally types (0=Scarlet, 1=Snow White, 2=Rapunzel)
	var available_types: Array[int] = [0, 1, 2]
	
	# Shuffle to randomize selection
	available_types.shuffle()
	
	# Play ONE random burst sound from the allies being summoned
	var sound_ally_type: int = available_types[randi() % mini(count, available_types.size())]
	_play_ally_burst_sound(sound_ally_type)
	
	# Summon allies with staggered timing to prevent lag
	for i in range(mini(count, available_types.size())):
		var ally_type: int = available_types[i]
		# Use call_deferred with a timer to stagger spawns
		if i == 0:
			_spawn_ally(ally_type, i)
		else:
			# Delay subsequent spawns by 0.15 seconds each
			var timer: SceneTreeTimer = player.get_tree().create_timer(0.15 * i)
			timer.timeout.connect(_spawn_ally.bind(ally_type, i))

func _spawn_ally(ally_type: int, index: int) -> void:
	var ally: Node2D = SummonedAllyScript.new()
	# Pass player level for damage scaling
	var level: int = player.level if "level" in player else 1
	ally.setup(player, ally_type, level)
	ally.lifetime = summon_duration
	
	# Position ally around player
	var angle := TAU * float(index) / float(summon_count) + PI / 4.0
	var offset := Vector2(cos(angle), sin(angle)) * 80.0
	
	player.get_parent().add_child(ally)
	ally.global_position = player.global_position + offset
	
	# Connect signals
	ally.ally_expired.connect(_on_ally_expired.bind(ally))
	ally.ally_died.connect(_on_ally_died.bind(ally))
	
	_active_allies.append(weakref(ally))

func _on_ally_expired(ally: Node2D) -> void:
	_remove_ally(ally)

func _on_ally_died(ally: Node2D) -> void:
	_remove_ally(ally)

func _remove_ally(ally: Node2D) -> void:
	for i in range(_active_allies.size() - 1, -1, -1):
		var ref: WeakRef = _active_allies[i]
		var stored_ally: Node = ref.get_ref() if ref else null
		if stored_ally == ally or stored_ally == null:
			_active_allies.remove_at(i)

func _cleanup_allies() -> void:
	# Remove invalid ally references
	for i in range(_active_allies.size() - 1, -1, -1):
		var ref: WeakRef = _active_allies[i]
		var ally: Node = ref.get_ref() if ref else null
		if ally == null or not is_instance_valid(ally):
			_active_allies.remove_at(i)

func _on_burst_end() -> void:
	# Burst ends, allies will expire on their own timer
	pass

func _on_cleanup() -> void:
	# Clean up freeze effect
	if _freeze_active:
		_end_freeze()
	
	# Clean up any remaining allies
	for ref in _active_allies:
		var ally: Node = ref.get_ref() if ref is WeakRef else null
		if ally and is_instance_valid(ally):
			ally.queue_free()
	_active_allies.clear()

func _play_sound(weapon_type: String) -> void:
	if player.audio_director:
		player.audio_director.play_weapon_fire_sound(weapon_type)

func _play_ally_burst_sound(ally_type: int) -> void:
	# Map ally type to character ID
	var char_id: String
	match ally_type:
		0:
			char_id = "scarlet"
		1:
			char_id = "snow_white"
		2:
			char_id = "rapunzel"
		_:
			return
	
	# Get registry to fetch burst sound
	var registry = player.get_meta("registry") if player.has_meta("registry") else null
	if registry == null:
		# Try to get from singleton
		registry = CharacterRegistry.get_instance()
	
	if registry == null:
		return
	
	var sound = registry.get_burst_sound(char_id)
	if sound == null:
		return
	
	# Use AudioDirector if available for proper audio management
	if player.audio_director and player.audio_director.has_method("play_burst_voice"):
		# Temporarily adjust volume for ally (quieter than main burst)
		player.audio_director.play_burst_voice(sound)
	else:
		# Fallback: Create independent audio player
		var root = player.get_tree().root
		var audio_player = AudioStreamPlayer.new()
		audio_player.name = "AllyBurstVoice_%d" % Time.get_ticks_msec()
		audio_player.stream = sound
		audio_player.volume_db = 8.0
		audio_player.bus = "SFX"  # Use SFX bus for voice lines
		audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
		root.add_child(audio_player)
		audio_player.play()
		audio_player.finished.connect(audio_player.queue_free)

## Get attack cooldown
func get_attack_cooldown() -> float:
	return data.attack_cooldown

## Apply talent upgrade
func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			special_timer = 0.0
		"special_duration":
			freeze_duration += 1.0  # +1 second per upgrade
		"special_cooldown":
			freeze_cooldown = maxf(6.0, freeze_cooldown - 2.0)  # -2s per upgrade, min 6s
			data.special_cooldown = freeze_cooldown
		"burst_left":
			# Summon +1 ally
			left_upgrade_unlocked = true
			summon_count = 2 if not right_upgrade_unlocked else 3
		"burst_right":
			# Summon +1 ally
			right_upgrade_unlocked = true
			summon_count = 2 if not left_upgrade_unlocked else 3
		"burst_duration":
			summon_duration += 3.0  # +3 seconds per upgrade

## Check if invincible
func is_invincible() -> bool:
	return false

## Get weapon type name for audio
func _get_weapon_type_name() -> String:
	return "Assault Rifle"
