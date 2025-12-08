extends "res://scripts/characters/CharacterController.gd"
class_name KiloController
## Kilo - Shotgun with Penetrating Blast special
## Burst mode: automatic fire with persistent connecting lines across shots

const KiloPelletScript = preload("res://scripts/characters/effects/KiloPellet.gd")

# Shotgun config
var pellet_count: int = 5
var pellet_spread: float = 15.0  # degrees

# Burst state
var burst_invincible: bool = false
var _burst_fire_timer: float = 0.0
var _burst_wave_count: int = 0  # Tracks wave number during burst for zigzag pattern
const BURST_FIRE_INTERVAL := 0.2  # Auto-fire rate during burst (faster for more connected lines)

# Talent states
var special_burn_level: int = 0  # Searing Beams: burn damage
var special_size_level: int = 0  # Amplified Blast: size/damage bonus
var burst_duration_unlocked: bool = false  # Extended Assault: 10s duration
var burst_invuln_unlocked: bool = false  # T.A.L.O.S. Shield: invincibility

func _on_initialize() -> void:
	# Ammo already set from CharacterRegistry by base class
	data.special_cooldown = 3.0

func _on_process(delta: float) -> void:
	# Handle burst auto-fire
	if burst_active:
		_burst_fire_timer -= delta

func _can_attack() -> bool:
	# During burst, always can attack (infinite ammo)
	if burst_active:
		return true
	return not is_reloading and ammo > 0

func _perform_attack(direction: Vector2) -> void:
	# During burst, pellets are "burst" type with persistent line connections
	_fire_shotgun(direction, false, burst_active)
	_play_sound("shotgun")

func _can_use_special() -> bool:
	# Need ammo unless in burst mode
	if burst_active:
		return special_timer <= 0
	return special_timer <= 0 and ammo > 0

func _perform_special(direction: Vector2) -> void:
	# Consume ammo if not in burst
	if not burst_active:
		ammo -= 1
		ammo_changed.emit(ammo, max_ammo)
		if ammo <= 0:
			start_reload()
	
	# Special attack clears special array and adds pellets there
	_fire_shotgun(direction, true, false)
	_play_sound("shotgun")

func _fire_shotgun(direction: Vector2, is_special: bool, is_burst_shot: bool = false) -> void:
	# Calculate damage multiplier
	var damage_mult: float = 1.0
	if burst_active:
		damage_mult = 2.2  # Burst damage bonus
	
	# Special attack bonuses (size_level affects damage in pellet)
	if is_special and special_size_level > 0:
		var damage_bonuses := [1.0, 1.3, 1.6, 2.0]  # +30/60/100% damage
		damage_mult *= damage_bonuses[mini(special_size_level, 3)]
	
	# Fire pellets in spread pattern
	var base_angle = direction.angle()
	var spread_rad = deg_to_rad(pellet_spread)
	
	# Clear special pellet array for new special volley (not burst)
	if is_special:
		KiloPelletScript.all_special_pellets.clear()
	
	# For burst mode: increment wave count for zigzag tracking
	if is_burst_shot:
		_burst_wave_count += 1
	
	for i in range(pellet_count):
		var t: float = float(i) / float(pellet_count - 1) if pellet_count > 1 else 0.5
		var angle_offset = lerp(-spread_rad / 2.0, spread_rad / 2.0, t)
		var pellet_dir = Vector2.from_angle(base_angle + angle_offset)
		
		# Use KiloPellet for proper orange/amber visuals
		var pellet = ProjectileCache.create_kilo_pellet()
		pellet.global_position = player.global_position + pellet_dir * 30
		pellet.velocity = pellet_dir * 850
		pellet.owner_node = player
		# Use character's base damage with level scaling
		pellet.base_damage = player.calc_damage(damage_mult)
		pellet.pierce_all = false
		pellet.is_special = is_special
		pellet.is_burst = is_burst_shot  # Burst pellets get persistent lines
		pellet.burn_level = special_burn_level if is_special else 0
		pellet.size_level = special_size_level if (is_special or is_burst_shot) else 0

		# Set wave and pellet index for zigzag pattern
		if is_burst_shot:
			pellet.wave_index = _burst_wave_count
			pellet.pellet_index = i

		# Determine target parent: player's parent (world) for physics
		var target_parent = player.get_parent()
		
		# Add to target parent and set position
		target_parent.add_child(pellet)
func _on_burst_start() -> void:
	# Duration: 4s base, 8s with upgrade
	if burst_duration_unlocked:
		burst_timer = 8.0
	else:
		burst_timer = 4.0
	
	# Grant invincibility during burst if talent is unlocked
	if burst_invuln_unlocked:
		burst_invincible = true
		player.invincible = true
	
	# Apply golden glow effect to player
	_apply_burst_glow(true)
	
	# Refill ammo during burst
	ammo = max_ammo
	ammo_changed.emit(ammo, max_ammo)
	
	# Refill ammo during burst
	ammo = max_ammo
	ammo_changed.emit(ammo, max_ammo)
	
	# Clear burst pellet tracking for fresh start
	KiloPelletScript.all_burst_pellets.clear()
	
	# Reset burst fire timer and wave count for zigzag pattern
	_burst_fire_timer = 0.0
	_burst_wave_count = 0
	
	_play_sound("shotgun")

func _on_burst_end() -> void:
	# Remove invincibility when burst ends if talent was active
	if burst_invuln_unlocked:
		burst_invincible = false
		player.invincible = false
	
	# Remove golden glow effect
	_apply_burst_glow(false)
	
	# Clear burst pellet tracking
	KiloPelletScript.all_burst_pellets.clear()

var _burst_glow_node: Node2D = null

func _apply_burst_glow(enable: bool) -> void:
	if not is_instance_valid(player):
		return
	
	if enable:
		# Create golden glow with sparkles effect
		if _burst_glow_node == null or not is_instance_valid(_burst_glow_node):
			_burst_glow_node = Node2D.new()
			_burst_glow_node.name = "KiloBurstGlow"
			_burst_glow_node.set_script(_get_burst_glow_script())
			player.add_child(_burst_glow_node)
	else:
		# Remove glow effect
		if _burst_glow_node and is_instance_valid(_burst_glow_node):
			_burst_glow_node.queue_free()
			_burst_glow_node = null

func _get_burst_glow_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var _time: float = 0.0
const GLOW_COLOR := Color(1.0, 0.82, 0.2, 1.0)  # Golden color
const GLOW_RADIUS := 55.0

# Sparkle system - small and numerous
var _sparkles: Array = []
const MAX_SPARKLES := 35
const SPARKLE_SPAWN_RATE := 0.03
var _sparkle_timer: float = 0.0

class Sparkle:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var max_life: float
	var size: float
	var rotation: float
	var rot_speed: float

func _ready() -> void:
	z_index = 50  # Above player sprite for sparkles

func _process(delta: float) -> void:
	_time += delta
	_sparkle_timer += delta
	
	# Spawn new sparkles
	if _sparkle_timer >= SPARKLE_SPAWN_RATE and _sparkles.size() < MAX_SPARKLES:
		_sparkle_timer = 0.0
		_spawn_sparkle()
	
	# Update sparkles
	var to_remove := []
	for i in range(_sparkles.size()):
		var s = _sparkles[i]
		s.life -= delta
		if s.life <= 0:
			to_remove.append(i)
		else:
			s.pos += s.vel * delta
			s.vel.y -= 60.0 * delta  # Float upward gently
			s.rotation += s.rot_speed * delta
	
	for i in range(to_remove.size() - 1, -1, -1):
		_sparkles.remove_at(to_remove[i])
	
	queue_redraw()

func _spawn_sparkle() -> void:
	var s = Sparkle.new()
	# Spawn across wider area around character
	s.pos = Vector2(randf_range(-60.0, 60.0), randf_range(-70.0, 50.0))
	s.vel = Vector2(randf_range(-30, 30), randf_range(-50, -15))
	s.life = randf_range(0.4, 0.8)
	s.max_life = s.life
	s.size = randf_range(3.0, 6.0)  # Smaller, cuter sparkles
	s.rotation = randf() * TAU
	s.rot_speed = randf_range(-5.0, 5.0)
	_sparkles.append(s)

func _draw() -> void:
	# Smooth pulsing glow
	var pulse := 1.0 + sin(_time * 3.5) * 0.12
	var alpha_base := 0.7 + sin(_time * 2.0) * 0.15
	
	# Draw glow layers (behind at z_index, but we draw first)
	var layers := 8
	for i in range(layers):
		var t := float(i) / float(layers - 1)
		var radius := GLOW_RADIUS * pulse * (0.3 + t * 0.7)
		var layer_alpha := alpha_base * pow(1.0 - t, 2.0) * 0.5
		
		var r := lerpf(1.0, GLOW_COLOR.r, t * 0.4)
		var g := lerpf(0.95, GLOW_COLOR.g, t * 0.6)
		var b := lerpf(0.6, GLOW_COLOR.b, t * 0.8)
		
		draw_circle(Vector2.ZERO, radius, Color(r, g, b, layer_alpha))
	
	# Draw sparkles - brighter
	for s in _sparkles:
		var life_ratio: float = s.life / s.max_life
		var sparkle_alpha: float = life_ratio  # Full brightness
		var sparkle_size: float = s.size * (0.6 + life_ratio * 0.4)
		
		# Draw 4-pointed star
		_draw_sparkle(s.pos, sparkle_size, s.rotation, sparkle_alpha)

func _draw_sparkle(pos: Vector2, size: float, rot: float, alpha: float) -> void:
	# Soft outer glow
	draw_circle(pos, size * 0.6, Color(1.0, 0.9, 0.5, alpha * 0.4))
	
	# Core - bright white-gold
	draw_circle(pos, size * 0.35, Color(1.0, 1.0, 0.9, alpha))
	
	# 4-pointed star rays - delicate
	var ray_length := size * 1.5
	var ray_width := size * 0.2
	for i in range(4):
		var angle := rot + i * PI * 0.5
		var dir := Vector2(cos(angle), sin(angle))
		var tip := pos + dir * ray_length
		# Soft glow
		draw_line(pos, tip, Color(1.0, 0.9, 0.5, alpha * 0.4), ray_width * 1.5)
		# Bright core
		draw_line(pos, tip, Color(1.0, 0.98, 0.85, alpha), ray_width)
"""
	script.reload()
	return script

func is_invincible() -> bool:
	return burst_invincible

## Get weapon type name for audio
func _get_weapon_type_name() -> String:
	return "shotgun"

func _play_sound(weapon_type: String) -> void:
	if player.audio_director:
		player.audio_director.play_weapon_fire_sound(weapon_type)

## Apply talent upgrade
func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			special_timer = 0.0  # Refresh cooldown
		"special_burn":
			special_burn_level = mini(special_burn_level + 1, 3)
			special_timer = 0.0  # Refresh cooldown
		"special_size":
			special_size_level = mini(special_size_level + 1, 3)
			special_timer = 0.0  # Refresh cooldown
		"burst_duration":
			burst_duration_unlocked = true
		"burst_invuln":
			burst_invuln_unlocked = true

## Get attack cooldown (faster during burst - automatic fire)
func get_attack_cooldown() -> float:
	if burst_active:
		return BURST_FIRE_INTERVAL  # Automatic fire at 0.3s intervals
	return data.attack_cooldown
