extends "res://scripts/characters/CharacterController.gd"
class_name MarianController
## Marian - Minigun with Charm special and Epic Beam burst
## Special: AoE charm that converts enemies (like Sin) with blue visual
## Burst: 5-second aimable purple laser beam with upgrades

# Preload scripts
const MarianCharmEffectScript = preload("res://scripts/characters/effects/MarianCharmEffect.gd")
const MarianBulletScript = preload("res://scripts/characters/effects/MarianBullet.gd")
const MarianBeamScript = preload("res://scripts/characters/effects/MarianBeam.gd")
const MarianBeamCannonScript = preload("res://scripts/characters/effects/MarianBeamCannon.gd")


# Charm area indicator (similar to Sin)
var _charm_indicator: Node2D = null

# Minigun config
var bullet_speed: float = 1100.0
var spinup_time: float = 0.3
var _spinup_timer: float = 0.0
var _is_spinning: bool = false

# "Main Heroine" upgrade - replaces minigun with beam cannon
var _has_beam_cannon_upgrade: bool = false
var _beam_cannon: Node2D = null  # Persistent beam cannon instance

# Special config (Charm - like Sin)
var charm_radius: float = 150.0
var charm_cooldown: float = 10.0

# Burst config
var beam_duration: float = 5.0
var _active_beam: Node2D = null

# Talent states
var special_size_level: int = 0  # AoE size upgrades
var special_cooldown_level: int = 0  # Cooldown reduction
var burst_missile_upgrade: bool = false  # Left: 4 homing missiles every 2.5s
var burst_trail_upgrade: bool = false    # Right: burning trail

func _on_initialize() -> void:
	# Ammo already set from CharacterRegistry by base class
	data.special_cooldown = charm_cooldown
	
	# Check for "Main Heroine" upgrade
	_has_beam_cannon_upgrade = has_upgrade("marian", "basic_attack")
	if _has_beam_cannon_upgrade:
		print("[MarianController] 'Main Heroine' upgrade active - beam cannon enabled")

func _on_cleanup() -> void:
	# Remove charm indicator when switching away from Marian
	if _charm_indicator and is_instance_valid(_charm_indicator):
		_charm_indicator.queue_free()
		_charm_indicator = null
	
	# Clean up beam cannon
	if _beam_cannon and is_instance_valid(_beam_cannon):
		_beam_cannon.queue_free()
		_beam_cannon = null

func _on_process(delta: float) -> void:
	# Update spinup
	if _is_spinning:
		_spinup_timer = minf(_spinup_timer + delta, spinup_time)
	else:
		_spinup_timer = maxf(_spinup_timer - delta * 2.0, 0.0)
	
	# Ensure charm indicator exists
	if not _charm_indicator or not is_instance_valid(_charm_indicator):
		_create_charm_indicator()
	
	# Update charm indicator visibility
	_update_charm_indicator()
	
	# Handle beam cannon firing state based on attack button
	if _has_beam_cannon_upgrade and _beam_cannon and is_instance_valid(_beam_cannon):
		if Input.is_action_pressed("attack") and _can_attack():
			_beam_cannon.start_firing()
			_is_spinning = true
		else:
			_beam_cannon.stop_firing()
			if not Input.is_action_pressed("attack"):
				_is_spinning = false

func _create_charm_indicator() -> void:
	if _charm_indicator and is_instance_valid(_charm_indicator):
		return
	
	if not player or not is_instance_valid(player):
		return
	var parent = player.get_parent()
	if not parent or not is_instance_valid(parent):
		return
	
	# Create indicator using dynamic script (similar to Sin)
	_charm_indicator = Node2D.new()
	_charm_indicator.set_script(_get_indicator_script())
	_charm_indicator.name = "MarianCharmIndicator"
	parent.add_child(_charm_indicator)
	_charm_indicator.set("player", player)
	_charm_indicator.set("radius", _get_current_charm_radius())
	_charm_indicator.set("indicator_color", Color(0.7, 0.5, 1.0, 0.65))  # Light purple, slightly more opaque

func _get_indicator_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var player: Node2D = null
var radius: float = 150.0
var indicator_color: Color = Color(0.3, 0.5, 1.0, 0.3)
var _visible: bool = false
var _activation_flash: float = 0.0

func show_indicator() -> void:
	_visible = true
	queue_redraw()

func hide_indicator() -> void:
	_visible = false
	queue_redraw()

func set_radius(r: float) -> void:
	radius = r
	queue_redraw()

func trigger_activation() -> void:
	_activation_flash = 1.0

func _process(delta: float) -> void:
	if player and is_instance_valid(player):
		global_position = player.get_global_mouse_position()
	
	if _activation_flash > 0:
		_activation_flash -= delta * 3.0
		queue_redraw()
	elif _visible:
		queue_redraw()

func _draw() -> void:
	if not _visible and _activation_flash <= 0:
		return
	
	var alpha := indicator_color.a
	if _activation_flash > 0:
		alpha = _activation_flash
	
	var color := Color(indicator_color.r, indicator_color.g, indicator_color.b, alpha)
	
	# Outer glow ring
	draw_arc(Vector2.ZERO, radius * 1.05, 0, TAU, 48, Color(color.r, color.g, color.b, alpha * 0.4), 8.0)
	
	# Main circle - thick and bright
	draw_arc(Vector2.ZERO, radius, 0, TAU, 48, color, 4.0)
	
	# Inner ring
	draw_arc(Vector2.ZERO, radius * 0.9, 0, TAU, 48, Color(color.r, color.g, color.b, alpha * 0.6), 2.0)
	
	# Filled center - more opaque
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, alpha * 0.35))
	
	# Crosshair lines
	var line_color := Color(color.r, color.g, color.b, alpha * 0.7)
	draw_line(Vector2(-radius * 0.3, 0), Vector2(radius * 0.3, 0), line_color, 2.0)
	draw_line(Vector2(0, -radius * 0.3), Vector2(0, radius * 0.3), line_color, 2.0)
"""
	script.reload()
	return script

func _get_current_charm_radius() -> float:
	var size_multipliers := [1.0, 1.5, 2.0, 3.0]
	return charm_radius * size_multipliers[mini(special_size_level, 3)]

func _update_charm_indicator() -> void:
	if not _charm_indicator or not is_instance_valid(_charm_indicator):
		return
	
	var should_show := special_unlocked and special_timer <= 0 and not burst_active
	
	if special_unlocked:
		_charm_indicator.call("set_radius", _get_current_charm_radius())
		if should_show:
			_charm_indicator.call("show_indicator")
		else:
			_charm_indicator.call("hide_indicator")
	else:
		_charm_indicator.call("hide_indicator")

func _can_attack() -> bool:
	# With beam cannon upgrade, always allow (beam handles its own state)
	if _has_beam_cannon_upgrade:
		return not burst_active
	return not is_reloading and ammo > 0 and not burst_active

func _perform_attack(direction: Vector2) -> void:
	_is_spinning = true
	
	# "Main Heroine" upgrade: continuous beam cannon (managed separately)
	if _has_beam_cannon_upgrade:
		# Create beam cannon if it doesn't exist
		if not _beam_cannon or not is_instance_valid(_beam_cannon):
			_beam_cannon = MarianBeamCannonScript.new()
			player.get_parent().add_child(_beam_cannon)
			# Pass self as controller_ref so beam can check ammo/reload state
			_beam_cannon.initialize(player.calc_damage(), player, player, self)
			print("[MarianController] Created beam cannon")
		# The beam cannon fires continuously while mouse is held
		# (controlled in _on_process)
		return
	
	# Normal: Fire purple mystical bullet
	var bullet = MarianBulletScript.new()
	player.get_parent().add_child(bullet)
	bullet.global_position = player.global_position + direction * 35
	bullet.velocity = direction * bullet_speed
	bullet.rotation = direction.angle()
	bullet.owner_node = player
	# Use character's base damage with level scaling
	bullet.base_damage = player.calc_damage()
	
	_play_sound("minigun")

func _can_use_special() -> bool:
	return special_timer <= 0 and not burst_active

func _perform_special(_direction: Vector2) -> void:
	var actual_radius: float = _get_current_charm_radius()
	var mouse_pos := player.get_global_mouse_position()
	
	# Trigger activation animation
	if is_instance_valid(_charm_indicator):
		_charm_indicator.call("trigger_activation")
	
	# Spawn visual indicator
	_spawn_charm_aoe_visual(mouse_pos, actual_radius)
	
	# Find and charm enemies
	var tree := player.get_tree()
	if tree:
		var enemies := tree.get_nodes_in_group("enemies")
		for enemy in enemies:
			if not is_instance_valid(enemy) or not enemy is Node2D:
				continue
			
			# Check enemy tier and whether we can affect them based on Queen Gene level
			var enemy_tier := _get_enemy_tier(enemy)
			var can_affect := _can_affect_enemy_tier(enemy_tier)
			
			if not can_affect:
				continue
			
			# Check range
			var dist := (enemy as Node2D).global_position.distance_to(mouse_pos)
			if dist > actual_radius:
				continue
			
			# Handle the enemy based on tier
			if enemy_tier == "boss" or enemy_tier == "super_boss":
				# Bosses get stunned for 5 seconds instead of charmed
				_stun_boss(enemy, 5.0)
			else:
				# Charm the enemy
				_charm_enemy(enemy)
	
	# Apply cooldown
	var cooldown_reduction := special_cooldown_level * 2.0
	special_timer = max(charm_cooldown - cooldown_reduction, 2.0)
	data.special_cooldown = special_timer

func _get_enemy_tier(enemy: Node) -> String:
	# Check for tier metadata first
	if enemy.has_meta("enemy_tier"):
		return enemy.get_meta("enemy_tier")
	# Check groups
	if enemy.is_in_group("boss") or enemy.is_in_group("super_boss"):
		return "boss"
	if enemy.is_in_group("elite"):
		return "elite"
	if enemy.is_in_group("tank"):
		return "tank"
	return "basic"

func _can_affect_enemy_tier(tier: String) -> bool:
	# Queen Gene levels unlock affecting different enemy types
	# Level 0: Only basic enemies
	# Level 1: + Tanks
	# Level 2: + Elites
	# Level 3: + Bosses (stun only)
	match tier:
		"basic":
			return true
		"tank":
			return special_size_level >= 1
		"elite":
			return special_size_level >= 2
		"boss", "super_boss":
			return special_size_level >= 3
	return true

func _stun_boss(boss: Node, duration: float) -> void:
	# Stun the boss instead of charming
	if boss.has_method("stun"):
		boss.stun(duration)
	elif boss.has_method("set_stunned"):
		boss.set_stunned(true, duration)
	else:
		# Fallback: set properties directly if available
		if "is_stunned" in boss:
			boss.is_stunned = true
		if "stun_timer" in boss:
			boss.stun_timer = duration
	
	# Add visual stun effect
	_spawn_stun_effect(boss)

func _charm_enemy(enemy: Node) -> void:
	if enemy.has_meta("charmed") and enemy.get_meta("charmed"):
		return
	
	# Mark as charmed
	enemy.set_meta("charmed", true)
	enemy.set_meta("charm_owner", player)
	
	# Change groups
	enemy.remove_from_group("enemies")
	enemy.add_to_group("charmed_allies")
	
	# Apply charm behavior
	if enemy.has_method("set_charmed"):
		enemy.set_charmed(player, true)
	
	# Add blue visual effect (Marian's signature)
	var effect = MarianCharmEffectScript.new()
	effect.name = "MarianCharmEffect"
	enemy.add_child(effect)

func _spawn_stun_effect(boss: Node) -> void:
	# Create a visual stun indicator on the boss
	var stun_visual := Node2D.new()
	stun_visual.name = "MarianStunEffect"
	stun_visual.z_index = 100
	
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var _time: float = 0.0
var _duration: float = 5.0
var _star_count: int = 5

func _process(delta: float) -> void:
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	# Draw spinning stars around the boss's head
	var radius := 40.0
	for i in range(_star_count):
		var angle := _time * 3.0 + float(i) * TAU / float(_star_count)
		var pos := Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -50)
		_draw_star(pos, 8.0, Color(1.0, 1.0, 0.5, 1.0))

func _draw_star(center: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var angle := float(i) * TAU / 10.0 - PI / 2.0
		var r := size if i % 2 == 0 else size * 0.4
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)
"""
	script.reload()
	stun_visual.set_script(script)
	stun_visual.set("_duration", 5.0)
	boss.add_child(stun_visual)

func _spawn_charm_aoe_visual(center: Vector2, radius: float) -> void:
	var visual := Node2D.new()
	visual.set_script(_get_charm_aoe_script())
	visual.set("radius", radius)
	visual.set("color", Color(0.3, 0.5, 1.0, 0.6))  # Blue for Marian
	player.get_parent().add_child(visual)
	visual.global_position = center

func _get_charm_aoe_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var radius: float = 150.0
var color: Color = Color(0.3, 0.5, 1.0, 0.6)
var _time: float = 0.0
var _duration: float = 0.5

func _ready() -> void:
	z_index = 100

func _process(delta: float) -> void:
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := _time / _duration
	var current_radius := radius * progress
	var alpha := (1.0 - progress) * color.a
	
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 64, Color(color.r, color.g, color.b, alpha), 4.0)
	draw_circle(Vector2.ZERO, current_radius * 0.9, Color(color.r, color.g, color.b, alpha * 0.3))
"""
	script.reload()
	return script

func _on_burst_start() -> void:
	# Create the epic beam
	_active_beam = MarianBeamScript.new()
	_active_beam.duration = beam_duration
	_active_beam.owner_node = player
	_active_beam.player_ref = player  # Pass player reference for tracking
	_active_beam.player_level = player.level if "level" in player else 1
	_active_beam.missile_upgrade = burst_missile_upgrade
	_active_beam.trail_upgrade = burst_trail_upgrade
	
	# Calculate initial direction toward mouse and set it BEFORE adding to scene
	var aim_dir := (player.get_global_mouse_position() - player.global_position).normalized()
	_active_beam.initial_direction = aim_dir
	
	player.get_parent().add_child(_active_beam)
	# Start beam in front of player
	_active_beam.global_position = player.global_position + aim_dir * 35.0
	
	# Connect beam end signal
	_active_beam.beam_ended.connect(_on_beam_ended)

func _on_beam_ended() -> void:
	_active_beam = null
	# End burst mode
	if player.has_method("end_burst"):
		player.end_burst()

func _on_burst_end() -> void:
	# Clean up beam if still active
	if _active_beam and is_instance_valid(_active_beam):
		_active_beam.queue_free()
		_active_beam = null

func _on_burst_process(_delta: float) -> void:
	# Update beam position to follow player
	if _active_beam and is_instance_valid(_active_beam):
		_active_beam.global_position = player.global_position

func _play_sound(weapon_type: String) -> void:
	if player.audio_director:
		player.audio_director.play_weapon_fire_sound(weapon_type)

func get_attack_cooldown() -> float:
	# Minigun spins up - faster when spinning
	var spinup_mult := 1.0 - (_spinup_timer / spinup_time) * 0.5
	return data.attack_cooldown * spinup_mult

func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			reset_special_cooldown()
		"special_size":
			special_size_level = mini(special_size_level + 1, 3)
		"special_cooldown":
			special_cooldown_level = mini(special_cooldown_level + 1, 3)
			var reduction := special_cooldown_level * 2.0
			data.special_cooldown = max(charm_cooldown - reduction, 2.0)
			reset_special_cooldown()
		"burst_left":
			# Missile upgrade - fire 4 homing missiles every 2.5s
			burst_missile_upgrade = true
		"burst_right":
			# Trail upgrade - leave burning trail
			burst_trail_upgrade = true
		"burst_duration":
			beam_duration += 1.0  # +1 second per upgrade

func is_invincible() -> bool:
	return burst_active  # Invincible during beam

## Override start_reload to skip default reload sound when beam cannon is active
## The beam cannon handles its own reload sound (beam_reload.wav)
func start_reload() -> void:
	if is_reloading or max_ammo <= 0:
		return
	if ammo >= max_ammo:
		return
	
	is_reloading = true
	reload_timer = data.reload_time
	reload_started.emit(data.reload_time)
	
	# Only play reload sound if NOT using beam cannon
	# Beam cannon has its own reload sound handling
	if not _has_beam_cannon_upgrade:
		if player and player.audio_director:
			var weapon_type := _get_weapon_type_name()
			player.audio_director.play_weapon_reload_sound(weapon_type)

func _get_weapon_type_name() -> String:
	return "Minigun"
