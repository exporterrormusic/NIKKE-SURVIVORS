extends Node2D
class_name MarianBeamCannon

## Marian's "Main Heroine" upgrade beam cannon
## Continuous beam that fires while mouse is held
## Has wind-up time, wavy/shaking effect, pierces all enemies

const BEAM_RANGE := 1500.0
const BEAM_WIDTH := 96.0  # Twice as wide
const WINDUP_TIME := 0.4  # Wind-up before firing
const DAMAGE_INTERVAL := 0.05  # Faster damage tick rate

# Visual shake/wave parameters
const WAVE_AMPLITUDE := 8.0  # How much the beam waves
const WAVE_FREQUENCY := 15.0  # Wave speed
const SHAKE_AMOUNT := 3.0  # Random shake intensity

# Sparkle particle settings
const SPARKLE_SPAWN_RATE := 0.4  # Chance per frame to spawn sparkle
const SPARKLE_COUNT := 6  # Max sparkles per spawn
const SPARKLE_LIFETIME := 0.25  # How long sparkles last

# Sound settings
const SOUND_FADE_TIME := 0.2  # Fade in/out duration for beam sound
const BEAM_SOUND_PATH := "res://assets/sounds/sfx/weapons/minigun/beam.wav"
const BEAM_RELOAD_SOUND_PATH := "res://assets/sounds/sfx/weapons/minigun/beam_reload.wav"

# Colors - vibrant purple to match Marian's theme
var core_color := Color(1.0, 0.95, 1.0, 1.0)
var inner_color := Color(0.85, 0.5, 1.0, 0.95)
var outer_color := Color(0.6, 0.2, 0.9, 0.7)
var charge_color := Color(0.7, 0.4, 1.0, 0.8)

var owner_node: Node = null
var player: Node2D = null
var _damage: int = 5
var _is_firing: bool = false
var _windup_progress: float = 0.0  # 0 to 1
var _time: float = 0.0
var _damage_timer: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _hit_enemies_this_tick: Array = []

# Charge particles
var _charge_particles: Array = []

# Sparkle particles (for active beam)
var _sparkles: Array = []

# Controller reference for ammo state
var _controller: RefCounted = null

# Offset from player (beam starts outside player)
const BEAM_OFFSET := 35.0

# Sound players
var _beam_sound: AudioStreamPlayer2D = null
var _beam_target_volume: float = 0.0  # Target volume for fade
var _beam_current_volume: float = -80.0  # Current volume (starts silent)
var _was_firing_beam: bool = false  # Track if beam was active last frame
var _played_reload_sound: bool = false  # Track if we played reload sound this reload cycle

func _ready() -> void:
	z_index = 50
	top_level = true
	
	# Unshaded so beam is always visible
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	# Create beam sound player
	_beam_sound = AudioStreamPlayer2D.new()
	_beam_sound.bus = "SFX"
	_beam_sound.max_distance = 2000.0
	_beam_sound.volume_db = -80.0  # Start silent
	add_child(_beam_sound)
	
	# Load and configure looping beam sound
	var beam_audio = load(BEAM_SOUND_PATH)
	if beam_audio:
		_beam_sound.stream = beam_audio

func initialize(damage: int, owner_ref: Node, player_ref: Node2D, controller_ref: RefCounted = null) -> void:
	_damage = damage
	owner_node = owner_ref
	player = player_ref
	_controller = controller_ref
	# print("[MarianBeamCannon] Beam cannon initialized")

func start_firing() -> void:
	## Called when mouse button is pressed - starts wind-up
	_is_firing = true

func stop_firing() -> void:
	## Called when mouse button is released - stops beam
	_is_firing = false

func is_active() -> bool:
	return _is_firing or _windup_progress > 0.0

func is_reloading_or_empty() -> bool:
	"""Check if controller is reloading or out of ammo"""
	if not _controller:
		return false
	return _controller.is_reloading or _controller.ammo <= 0

func _process(delta: float) -> void:
	_time += delta
	
	if not player or not is_instance_valid(player):
		queue_free()
		return
	
	# Calculate aim direction from player to mouse
	var mouse_pos: Vector2 = player.get_global_mouse_position()
	var aim_dir: Vector2 = (mouse_pos - player.global_position).normalized()
	if aim_dir == Vector2.ZERO:
		aim_dir = Vector2.RIGHT
	rotation = aim_dir.angle()
	
	# Position beam offset from player (outside the player, not inside)
	global_position = player.global_position + aim_dir * BEAM_OFFSET
	
	# Check if reloading or out of ammo - beam sputters/stops
	var should_fire: bool = _is_firing and not is_reloading_or_empty()
	
	# Update wind-up progress
	if should_fire:
		_windup_progress = minf(_windup_progress + delta / WINDUP_TIME, 1.0)
	else:
		# Faster wind-down when reloading for sputtering effect
		var wind_down_speed: float = 0.5 if is_reloading_or_empty() else 0.5
		_windup_progress = maxf(_windup_progress - delta / (WINDUP_TIME * wind_down_speed), 0.0)
	
	# Only deal damage when fully wound up and not reloading
	if _windup_progress >= 1.0 and not is_reloading_or_empty():
		_damage_timer += delta
		if _damage_timer >= DAMAGE_INTERVAL:
			_damage_timer = 0.0
			_hit_enemies_this_tick.clear()
			# Log critical transform data
			# DebugLog.log("BeamPos: %s Rot: %.1f Mouse: %s" % [global_position, rotation_degrees, get_global_mouse_position()])
			_apply_damage()
	
	# Update beam sound (fade in/out with 0.2s transition)
	_update_beam_sound(delta)
	
	# Generate shake
	_shake_offset = Vector2(
		randf_range(-SHAKE_AMOUNT, SHAKE_AMOUNT) * _windup_progress,
		randf_range(-SHAKE_AMOUNT, SHAKE_AMOUNT) * _windup_progress
	)
	
	# Update charge particles during windup
	if _windup_progress > 0.0 and _windup_progress < 1.0:
		_update_charge_particles(delta)
	else:
		_charge_particles.clear()
	
	# Update sparkles when beam is fully active
	if _windup_progress >= 1.0 and not is_reloading_or_empty():
		_update_sparkles(delta)
	else:
		_sparkles.clear()
	
	queue_redraw()

func _update_charge_particles(delta: float) -> void:
	# Spawn new particles
	if randf() < 0.3:
		var angle := randf() * TAU
		var dist := randf_range(60, 120)
		_charge_particles.append({
			"pos": Vector2(cos(angle), sin(angle)) * dist,
			"vel": Vector2(-cos(angle), -sin(angle)) * 200,
			"life": 0.3,
			"max_life": 0.3
		})
	
	# Update existing particles
	var new_particles := []
	for p in _charge_particles:
		p["life"] -= delta
		p["pos"] += p["vel"] * delta
		if p["life"] > 0:
			new_particles.append(p)
	_charge_particles = new_particles

func _update_sparkles(delta: float) -> void:
	# Spawn new sparkles along the beam
	if randf() < SPARKLE_SPAWN_RATE:
		for i in range(randi_range(2, SPARKLE_COUNT)):
			var beam_t: float = randf()  # Position along beam (0-1)
			var x_pos: float = beam_t * BEAM_RANGE
			# Calculate wave offset at this position
			var wave_strength: float = beam_t * beam_t
			var wave_y: float = sin(_time * WAVE_FREQUENCY + beam_t * 8.0) * WAVE_AMPLITUDE * wave_strength
			# Random offset within beam width
			var y_offset: float = randf_range(-BEAM_WIDTH * 0.4, BEAM_WIDTH * 0.4)
			
			_sparkles.append({
				"pos": Vector2(x_pos, wave_y + y_offset),
				"vel": Vector2(randf_range(-30, 30), randf_range(-50, 50)),
				"life": SPARKLE_LIFETIME,
				"max_life": SPARKLE_LIFETIME,
				"size": randf_range(2.0, 5.0)
			})
	
	# Update existing sparkles
	var new_sparkles := []
	for s in _sparkles:
		s["life"] -= delta
		s["pos"] += s["vel"] * delta
		if s["life"] > 0:
			new_sparkles.append(s)
	_sparkles = new_sparkles

func _update_beam_sound(delta: float) -> void:
	# Beam should be audible when fully wound up and firing
	var beam_active: bool = _windup_progress >= 1.0 and not is_reloading_or_empty()
	
	# Set target volume based on beam state (6.0 dB when active for louder beam)
	_beam_target_volume = 6.0 if beam_active else -80.0
	
	# Fade volume toward target (0.2s fade time)
	var fade_speed: float = 80.0 / SOUND_FADE_TIME  # dB per second
	if _beam_current_volume < _beam_target_volume:
		_beam_current_volume = minf(_beam_current_volume + fade_speed * delta, _beam_target_volume)
	elif _beam_current_volume > _beam_target_volume:
		_beam_current_volume = maxf(_beam_current_volume - fade_speed * delta, _beam_target_volume)
	
	# Apply volume to sound player
	if _beam_sound:
		_beam_sound.volume_db = _beam_current_volume
		
		# Start/stop playback
		if beam_active and not _beam_sound.playing:
			_beam_sound.play()
			_was_firing_beam = true
			_played_reload_sound = false  # Reset reload sound flag when firing
		elif not beam_active and _beam_current_volume <= -79.0 and _beam_sound.playing:
			_beam_sound.stop()
	
	# Play reload sound when beam stops due to reload (and hasn't played yet this cycle)
	if _was_firing_beam and is_reloading_or_empty() and not _played_reload_sound:
		_play_reload_sound()
		_played_reload_sound = true
		_was_firing_beam = false

func _play_reload_sound() -> void:
	var reload_audio = load(BEAM_RELOAD_SOUND_PATH)
	if reload_audio:
		var reload_player := AudioStreamPlayer2D.new()
		reload_player.bus = "SFX"
		reload_player.stream = reload_audio
		reload_player.volume_db = 0.0
		reload_player.max_distance = 2000.0
		add_child(reload_player)
		reload_player.play()
		# Auto-cleanup when done
		reload_player.finished.connect(func(): reload_player.queue_free())

func _apply_damage() -> void:
	var tree := get_tree()
	if not tree:
		return
	
	var enemies := tree.get_nodes_in_group("enemies")
	# DebugLog.log("[MarianBeam] Scanning " + str(enemies.size()) + " enemies")
	
	# Collect beam hit candidates
	var candidates := []
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if not enemy.has_method("take_damage"):
			continue
		# Skip already hit enemies this tick
		if enemy in _hit_enemies_this_tick:
			continue
		# Don't damage charmed enemies
		if enemy.is_in_group("charmed_allies"):
			continue
		
		# Check if enemy is within beam (in local space)
		var to_enemy_world: Vector2 = enemy.global_position - global_position
		# Convert to local beam space (beam points along +X)
		var to_enemy_local: Vector2 = to_enemy_world.rotated(-rotation)
		
		# Check if along beam (positive X direction)
		if to_enemy_local.x < 0 or to_enemy_local.x > BEAM_RANGE:
			# DebugLog.log("[MarianBeam] FAIL: %s out of range X: %.1f" % [enemy.name, to_enemy_local.x])
			continue
		
		# Check perpendicular distance (Y in local space)
		var perp_dist: float = abs(to_enemy_local.y)
		if perp_dist > BEAM_WIDTH * 0.5:
			# DebugLog.log("[MarianBeam] FAIL: %s out of width Y: %.1f" % [enemy.name, to_enemy_local.y])
			continue
		
		# Check if a boulder blocks the beam before reaching this enemy
		if _is_boulder_blocking(to_enemy_local.x):
			# DebugLog.log("[MarianBeam] FAIL: %s blocked by boulder" % enemy.name)
			continue
		
		# Hit!
		# DebugLog.log("[MarianBeam] HIT enemy %s at dist %.1f" % [enemy.name, to_enemy_local.x])
		enemy.take_damage(_damage, false, Vector2.RIGHT.rotated(rotation))
		_hit_enemies_this_tick.append(enemy)
		# Note: Don't call register_burst_hit here - the beam cannon is a normal attack
		# Burst generation happens on kills via Enemy.take_damage()

func _is_boulder_blocking(distance_along_beam: float) -> bool:
	"""Check if any boulder blocks the beam before the given distance."""
	var boulders := get_tree().get_nodes_in_group("boulders")
	var beam_origin: Vector2 = global_position
	if player and is_instance_valid(player):
		beam_origin = player.global_position
	
	var beam_dir: Vector2 = Vector2.RIGHT.rotated(rotation)
	
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = 150.0  # Default
		if boulder.get("boulder_size") != null:
			boulder_radius = boulder.boulder_size * 0.5
		
		# Check if beam intersects this boulder
		var to_boulder := boulder_pos - beam_origin
		var along := to_boulder.dot(beam_dir)
		
		# Boulder must be in front and before our target point
		if along < 0 or along > distance_along_beam + BEAM_OFFSET:
			continue
		
		# Check perpendicular distance to beam center line
		var perp: float = abs(to_boulder.dot(beam_dir.orthogonal()))
		if perp < boulder_radius + BEAM_WIDTH * 0.5:
			return true  # Beam is blocked by this boulder
	
	return false


func _draw() -> void:
	if _windup_progress <= 0.0:
		return
	
	var beam_alpha: float = _windup_progress
	var current_width: float = BEAM_WIDTH * _windup_progress
	var current_range: float = BEAM_RANGE * (0.3 + 0.7 * _windup_progress)
	
	# Calculate visible range (stop at closest boulder OR closest enemy)
	var visible_range: float = _get_visible_beam_range(current_range)
	
	# Draw charge effect during windup
	if _windup_progress < 1.0:
		_draw_charge_effect()
		return
	
	# Draw full beam with wavy effect (stopped at target)
	_draw_beam(visible_range, current_width, beam_alpha)
	
	# Draw muzzle flash
	_draw_muzzle_flash()

func _get_visible_beam_range(max_range: float) -> float:
	"""Calculate how far the beam can visually extend (stops at closest boulder)."""
	var boulders := get_tree().get_nodes_in_group("boulders")
	var beam_origin: Vector2 = global_position
	if player and is_instance_valid(player):
		beam_origin = player.global_position
	
	var beam_dir: Vector2 = Vector2.RIGHT.rotated(rotation)
	var closest_hit: float = max_range
	
	# 1. Check Boulders
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = 150.0 
		if boulder.get("boulder_size") != null:
			boulder_radius = boulder.boulder_size * 0.5
		
		# Check if beam intersects this boulder
		var to_boulder := boulder_pos - beam_origin
		var along := to_boulder.dot(beam_dir)
		if along < 0: continue
		var perp_dist: float = abs(to_boulder.dot(beam_dir.orthogonal()))
		if perp_dist < boulder_radius + BEAM_WIDTH * 0.5:
			var hit_distance: float = along - boulder_radius
			if hit_distance > 0 and hit_distance < closest_hit:
				closest_hit = hit_distance

	# 2. Check Enemies (Stop visual at first hit)
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		# Only block beam if enemy is actually hittable
		if not enemy.has_method("take_damage") or enemy.is_queued_for_deletion():
			continue
		# Don't stop on allies
		if enemy.is_in_group("charmed_allies"):
			continue
			
		var to_enemy: Vector2 = (enemy as Node2D).global_position - beam_origin
		var along: float = to_enemy.dot(beam_dir)
		if along < 0 or along > max_range: continue # Ignore out of range
		
		var perp_dist: float = abs(to_enemy.dot(beam_dir.orthogonal()))
		if perp_dist < BEAM_WIDTH * 0.5 + 20.0: # Add margin for enemy radius
			if along < closest_hit:
				closest_hit = along

	return closest_hit


func _draw_charge_effect() -> void:
	# Pulsing charge circle at origin
	var pulse: float = sin(_time * 10.0) * 0.3 + 0.7
	var charge_size: float = 30.0 * _windup_progress * pulse
	
	# Outer glow
	var outer := charge_color
	outer.a = 0.3 * _windup_progress
	draw_circle(Vector2.ZERO, charge_size * 1.5, outer)
	
	# Inner core
	var inner := core_color
	inner.a = 0.8 * _windup_progress
	draw_circle(Vector2.ZERO, charge_size * 0.5, inner)
	
	# Electric arcs
	for i in range(4):
		var angle: float = _time * 5.0 + i * TAU / 4.0
		var arc_end := Vector2(cos(angle), sin(angle)) * charge_size * 1.2
		var arc_col := inner_color
		arc_col.a = 0.6 * _windup_progress
		draw_line(Vector2.ZERO, arc_end, arc_col, 2.0, true)
	
	# Charging particles
	for p in _charge_particles:
		var alpha: float = p["life"] / p["max_life"]
		var col := charge_color
		col.a = alpha * 0.8
		draw_circle(p["pos"], 3.0, col)
	
	# Forming beam (grows from origin)
	if _windup_progress > 0.5:
		var beam_progress: float = (_windup_progress - 0.5) * 2.0
		var beam_len: float = BEAM_RANGE * 0.3 * beam_progress
		var beam_w: float = BEAM_WIDTH * 0.3 * beam_progress
		var col := inner_color
		col.a = 0.4 * beam_progress
		draw_line(Vector2.ZERO, Vector2(beam_len, 0), col, beam_w, true)

func _draw_beam(beam_range: float, beam_width: float, alpha: float) -> void:
	# Draw wavy beam using line segments
	var segments := 32
	var prev_point := Vector2.ZERO
	
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var x: float = t * beam_range
		
		# Calculate wave offset (gets stronger toward the end)
		var wave_strength: float = t * t  # Quadratic falloff - more wave at end
		var wave_y: float = sin(_time * WAVE_FREQUENCY + t * 8.0) * WAVE_AMPLITUDE * wave_strength
		
		# Add shake
		var shake_y: float = _shake_offset.y * wave_strength
		
		var point := Vector2(x, wave_y + shake_y)
		
		if i > 0:
			# Draw outer glow
			var outer := outer_color
			outer.a *= alpha * (1.0 - t * 0.3)  # Fade toward end
			draw_line(prev_point, point, outer, beam_width, true)
			
			# Draw inner beam
			var inner := inner_color
			inner.a *= alpha * (1.0 - t * 0.2)
			draw_line(prev_point, point, inner, beam_width * 0.5, true)
			
			# Draw core
			var core := core_color
			core.a *= alpha * (1.0 - t * 0.1)
			draw_line(prev_point, point, core, beam_width * 0.15, true)
		
		prev_point = point
	
	# Draw sparkles
	_draw_sparkles(alpha)
	
	# Draw end flare
	var end_point := Vector2(beam_range, sin(_time * WAVE_FREQUENCY + 8.0) * WAVE_AMPLITUDE)
	var flare_size: float = beam_width * (0.8 + sin(_time * 8.0) * 0.2)
	var flare_col := inner_color
	flare_col.a = alpha * 0.6
	draw_circle(end_point, flare_size, flare_col)

func _draw_sparkles(alpha: float) -> void:
	for s in _sparkles:
		var life_ratio: float = s["life"] / s["max_life"]
		var sparkle_alpha: float = life_ratio * alpha
		var size: float = s["size"] * life_ratio
		
		# Draw sparkle with bright white core and colored glow
		var glow_col := inner_color
		glow_col.a = sparkle_alpha * 0.5
		draw_circle(s["pos"], size * 2.0, glow_col)
		
		# White sparkle core
		var core_col := Color(1.0, 1.0, 1.0, sparkle_alpha)
		draw_circle(s["pos"], size, core_col)
		
		# Cross/star shape for extra sparkle
		var line_len: float = size * 1.5
		var line_col := Color(1.0, 0.95, 1.0, sparkle_alpha * 0.8)
		draw_line(s["pos"] - Vector2(line_len, 0), s["pos"] + Vector2(line_len, 0), line_col, 1.5, true)
		draw_line(s["pos"] - Vector2(0, line_len), s["pos"] + Vector2(0, line_len), line_col, 1.5, true)

func _draw_muzzle_flash() -> void:
	# Bright flash at origin
	var flash_pulse: float = sin(_time * 20.0) * 0.3 + 0.7
	var flash_size: float = BEAM_WIDTH * 0.8 * flash_pulse
	
	# Outer glow
	var glow := outer_color
	glow.a = 0.5
	draw_circle(Vector2.ZERO, flash_size * 1.5, glow)
	
	# Inner flash
	draw_circle(Vector2.ZERO, flash_size, inner_color)
	
	# White core
	draw_circle(Vector2.ZERO, flash_size * 0.4, core_color)
