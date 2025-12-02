extends "res://scripts/characters/CharacterController.gd"
class_name MarianController
## Marian - Minigun with Charm special and Epic Beam burst
## Special: AoE charm that converts enemies (like Sin) with blue visual
## Burst: 5-second aimable purple laser beam with upgrades

# Preload scripts
const MarianCharmEffectScript = preload("res://scripts/MarianCharmEffect.gd")
const MarianBulletScript = preload("res://scripts/MarianBullet.gd")
const MarianBeamScript = preload("res://scripts/MarianBeam.gd")

# Charm area indicator (similar to Sin)
var _charm_indicator: Node2D = null

# Minigun config
var bullet_speed: float = 1100.0
var spinup_time: float = 0.3
var _spinup_timer: float = 0.0
var _is_spinning: bool = false

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
	# Marian uses minigun - 100 rounds, very fast fire rate
	max_ammo = 100
	ammo = max_ammo
	
	# Set timings
	data.reload_time = 3.5
	data.attack_cooldown = 0.06  # Very fast minigun
	data.special_cooldown = charm_cooldown

func _on_cleanup() -> void:
	# Remove charm indicator when switching away from Marian
	if _charm_indicator and is_instance_valid(_charm_indicator):
		_charm_indicator.queue_free()
		_charm_indicator = null

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
	return not is_reloading and ammo > 0 and not burst_active

func _perform_attack(direction: Vector2) -> void:
	_is_spinning = true
	
	# Fire purple mystical bullet
	var bullet = MarianBulletScript.new()
	player.get_parent().add_child(bullet)
	bullet.global_position = player.global_position + direction * 35
	bullet.velocity = direction * bullet_speed
	bullet.rotation = direction.angle()
	bullet.owner_node = player
	bullet.base_damage = 2
	
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
			
			# Skip elites and bosses
			if _is_elite_or_boss(enemy):
				continue
			
			# Check range
			var dist := (enemy as Node2D).global_position.distance_to(mouse_pos)
			if dist > actual_radius:
				continue
			
			# Charm the enemy
			_charm_enemy(enemy)
	
	# Apply cooldown
	var cooldown_reduction := special_cooldown_level * 2.0
	special_timer = max(charm_cooldown - cooldown_reduction, 2.0)
	data.special_cooldown = special_timer

func _is_elite_or_boss(enemy: Node) -> bool:
	if enemy.has_meta("enemy_tier"):
		var tier = enemy.get_meta("enemy_tier")
		if tier in ["elite", "boss", "tank"]:
			return true
	if enemy.is_in_group("elite") or enemy.is_in_group("boss"):
		return true
	return false

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
	_active_beam.missile_upgrade = burst_missile_upgrade
	_active_beam.trail_upgrade = burst_trail_upgrade
	
	# Calculate initial direction toward mouse
	var aim_dir := (player.get_global_mouse_position() - player.global_position).normalized()
	
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
			special_timer = 0.0
		"special_size":
			special_size_level = mini(special_size_level + 1, 3)
		"special_cooldown":
			special_cooldown_level = mini(special_cooldown_level + 1, 3)
			var reduction := special_cooldown_level * 2.0
			data.special_cooldown = max(charm_cooldown - reduction, 2.0)
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

func _get_weapon_type_name() -> String:
	return "Minigun"
