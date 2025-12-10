extends Node2D
class_name BossBeam

## Boss beam attack with charge preview, sustained fire, and fade

signal beam_finished

# Beam settings
const BEAM_LENGTH := 5000.0 # Increased to ensure it hits map borders/rocks
const BEAM_WIDTH := 80.0
const PREVIEW_WIDTH := 4.0
const BASE_DAMAGE_PER_TICK := 1
const DAMAGE_INTERVAL := 0.2

# Damage (can be scaled by Goddess Fall)
var damage_per_tick: int = BASE_DAMAGE_PER_TICK

# State
enum BeamState { CHARGING, FIRING, FADING, DONE }
var _state := BeamState.CHARGING
var _boss: Node2D = null
var _player: Node2D = null
var _charge_time := 2.0
var _fire_time := 2.0
var _fade_time := 0.5
var _timer := 0.0
var _damage_timer := 0.0

# Tracking behavior
var track_during_charge: bool = true  # Lock direction at end of charge (elite) vs track during charge (boss)
var track_during_fire: bool = false   # Slow tracking during firing (boss only)
var tracking_speed: float = 0.08      # Very slow rotation during firing (radians per second) - must be dodgeable

# Direction locked when charging completes
var _locked_direction := Vector2.RIGHT
var _current_width := PREVIEW_WIDTH

# Visual
# Visual
var _beam_color := Color(1.0, 0.05, 0.05, 1.0) # Deep Red
var _preview_color := Color(1.0, 0.1, 0.1, 0.4)

func initialize(boss: Node2D, player: Node2D, charge_time: float, fire_time: float, fade_time: float, is_boss: bool = true, scaled_damage: int = BASE_DAMAGE_PER_TICK) -> void:
	_boss = boss
	_player = player
	_charge_time = charge_time
	_fire_time = fire_time
	_fade_time = fade_time
	damage_per_tick = scaled_damage
	
	# Boss beams track during charge and slowly during fire
	# Elite beams lock direction at start of charge, no tracking
	if is_boss:
		track_during_charge = true
		track_during_fire = true
		tracking_speed = 0.05  # Very slow rotation - player can outrun if moving
		# Initialize direction toward player (will slowly track from here)
		if _player and is_instance_valid(_player):
			_locked_direction = (_player.global_position - _boss.global_position).normalized()
			if _locked_direction == Vector2.ZERO:
				_locked_direction = Vector2.RIGHT
	else:
		# Elite: lock direction immediately when beam starts charging
		track_during_charge = false
		track_during_fire = false
		# Lock direction now
		if _player and is_instance_valid(_player):
			_locked_direction = (_player.global_position - _boss.global_position).normalized()
			if _locked_direction == Vector2.ZERO:
				_locked_direction = Vector2.RIGHT

func _ready() -> void:
	z_index = 100  # Draw on top
	# Make beam unshaded (glows in dark)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func _process(delta: float) -> void:
	if not _boss or not is_instance_valid(_boss):
		_finish()
		return
	
	_timer += delta
	
	match _state:
		BeamState.CHARGING:
			_process_charging(delta)
		BeamState.FIRING:
			_process_firing(delta)
		BeamState.FADING:
			_process_fading(delta)
		BeamState.DONE:
			pass
	
	queue_redraw()

func _process_charging(delta: float) -> void:
	# Track player during charge with same slow speed as firing (only if enabled)
	if track_during_charge and _player and is_instance_valid(_player):
		var target_dir := (_player.global_position - _boss.global_position).normalized()
		if target_dir != Vector2.ZERO:
			# Slowly rotate toward player (same speed as during firing)
			var current_angle := _locked_direction.angle()
			var target_angle := target_dir.angle()
			var angle_diff := wrapf(target_angle - current_angle, -PI, PI)
			var max_rotation := tracking_speed * delta
			var rotation_amount := clampf(angle_diff, -max_rotation, max_rotation)
			_locked_direction = _locked_direction.rotated(rotation_amount)
	
	# Pulse preview line
	var pulse := sin(_timer * 10.0) * 0.3 + 0.7
	_current_width = PREVIEW_WIDTH * pulse
	
	# Transition to firing
	if _timer >= _charge_time:
		_state = BeamState.FIRING
		_timer = 0.0
		_current_width = BEAM_WIDTH

func _process_firing(delta: float) -> void:
	# Slow tracking during fire (boss only)
	if track_during_fire and _player and is_instance_valid(_player):
		var target_dir := (_player.global_position - _boss.global_position).normalized()
		if target_dir != Vector2.ZERO:
			# Slowly rotate toward player
			var current_angle := _locked_direction.angle()
			var target_angle := target_dir.angle()
			var angle_diff := wrapf(target_angle - current_angle, -PI, PI)
			var max_rotation := tracking_speed * delta
			var rotation_amount := clampf(angle_diff, -max_rotation, max_rotation)
			_locked_direction = _locked_direction.rotated(rotation_amount)
	
	# Maintain full width beam
	_current_width = BEAM_WIDTH
	
	# Deal damage to player if in beam
	_damage_timer += delta
	if _damage_timer >= DAMAGE_INTERVAL:
		_damage_timer = 0.0
		_check_beam_hit()
	
	# Transition to fading
	if _timer >= _fire_time:
		_state = BeamState.FADING
		_timer = 0.0

func _process_fading(_delta: float) -> void:
	# Shrink beam width
	var t := _timer / _fade_time
	_current_width = BEAM_WIDTH * (1.0 - t)
	
	# Finish
	if _timer >= _fade_time:
		_finish()

func _check_beam_hit() -> void:
	if not _boss or not is_instance_valid(_boss):
		return
	
	# Get beam line segment
	var beam_start := _boss.global_position
	# Default end point
	var beam_end := beam_start + _locked_direction * BEAM_LENGTH
	
	# Check for boulder blocking
	var collision_point_info := _get_beam_collision_point(beam_start, _locked_direction, BEAM_LENGTH)
	if collision_point_info.has("point"):
		beam_end = collision_point_info.point
	
	# Check player
	if _player and is_instance_valid(_player):
		var player_pos := _player.global_position
		# Only check hit if player is essentially "behind" the beam end if it was shortened, 
		# but point_to_line_distance on a segment handles this if we use the shortened beam_end.
		var dist := _point_to_line_distance(player_pos, beam_start, beam_end)
		if dist < BEAM_WIDTH / 2.0:
			# Verify player is not past the beam end (the segment check might be slightly forgiving or player radius matters)
			# Projection check to ensure we don't hit beyond the blocker
			var to_player = player_pos - beam_start
			var projected_dist = to_player.dot(_locked_direction)
			var beam_len_sq = beam_start.distance_to(beam_end)
			
			if projected_dist >= 0 and projected_dist <= beam_len_sq + 20: # +20 grace
				if _player.has_method("take_damage"):
					_player.take_damage(damage_per_tick)
	
	# Check charmed allies (they're fighting for the player, so enemies should damage them)
	var tree := get_tree()
	if tree:
		var charmed_allies := tree.get_nodes_in_group("charmed_allies")
		for ally in charmed_allies:
			if not is_instance_valid(ally) or not ally is Node2D:
				continue
			var ally_pos := (ally as Node2D).global_position
			var dist := _point_to_line_distance(ally_pos, beam_start, beam_end)
			if dist < BEAM_WIDTH / 2.0:
				var to_ally = ally_pos - beam_start
				var projected_dist = to_ally.dot(_locked_direction)
				var beam_len_sq = beam_start.distance_to(beam_end)
				
				if projected_dist >= 0 and projected_dist <= beam_len_sq + 20:
					if ally.has_method("take_damage"):
						ally.take_damage(damage_per_tick)

func _get_beam_collision_point(start: Vector2, direction: Vector2, max_length: float) -> Dictionary:
	"""Check if beam hits a boulder and return the collision point."""
	var boulders := get_tree().get_nodes_in_group("boulders")
	var closest_dist := max_length
	var hit_point = null
	
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		
		# Assuming circular boulders for simple/fast checking
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = 150.0 # Default
		if boulder.get("boulder_size") != null:
			boulder_radius = boulder.boulder_size * 0.5
			
		# Vector from beam start to boulder center
		var to_boulder := boulder_pos - start
		
		# Project boulder center onto beam direction
		var projected_dist := to_boulder.dot(direction)
		
		# Boulder is behind the beam start
		if projected_dist < 0:
			continue
			
		# Boulder is too far
		if projected_dist > closest_dist + boulder_radius:
			continue
			
		# Perpendicular distance from beam line to boulder center
		var perp_dist_vec := to_boulder - (direction * projected_dist)
		var perp_dist := perp_dist_vec.length()
		
		# Check overlap (beam width + boulder radius)
		# Being generous with collision to ensure visually it looks blocked
		if perp_dist < (boulder_radius + BEAM_WIDTH * 0.4):
			# Approximate intersection: boulder center projection minus some offset to hit the surface
			# A true circle-line intersection is better but this is roughly ok
			var dist_to_surface = projected_dist - sqrt(max(0, boulder_radius * boulder_radius - perp_dist * perp_dist))
			
			if dist_to_surface < closest_dist and dist_to_surface > 0:
				closest_dist = dist_to_surface
				hit_point = start + direction * closest_dist
				
	if hit_point:
		return {"point": hit_point, "distance": closest_dist}
	return {}

func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line := line_end - line_start
	var line_length_sq := line.length_squared() # Optimization
	if line_length_sq == 0:
		return point.distance_to(line_start)
	
	# Project point onto line, clamped to segment
	var t := clampf((point - line_start).dot(line) / line_length_sq, 0.0, 1.0)
	var projection := line_start + line * t
	
	return point.distance_to(projection)

func _finish() -> void:
	_state = BeamState.DONE
	emit_signal("beam_finished")
	queue_free()

func _draw() -> void:
	if not _boss or not is_instance_valid(_boss):
		return
	
	var start := Vector2.ZERO  # Local origin (attached to boss)
	# Determine logical end point
	var beam_len_local = BEAM_LENGTH
	
	# We need to perform the collision check in local space logic or transform result to local
	# Since _get_beam_collision_point uses global coords, let's use that
	var start_global = global_position # This is where the beam starts
	# Note: global_position might change if parent moves, but _draw is called every frame
	
	var collision = _get_beam_collision_point(start_global, _locked_direction, BEAM_LENGTH)
	if collision.has("distance"):
		beam_len_local = collision.distance
	
	# Convert length to a vector in local space? 
	# Actually, the beam is drawn from (0,0) to some point.
	# _locked_direction is global direction.
	# If this node rotates with the boss, drawing along local X might be better, but
	# the script seems to use _locked_direction for logic. 
	# Let's see... _locked_direction is updated in process.
	# If the node's rotation is 0, we must draw using `to_local`.
	
	var end_global = start_global + _locked_direction * beam_len_local
	var end_local = to_local(end_global)
	
	match _state:
		BeamState.CHARGING:
			# Draw preview line (thin, pulsing, semi-transparent)
			draw_line(start, end_local, _preview_color, _current_width, true)
			# Draw glowing endpoint indicator
			# var indicator_pos := _locked_direction * 100.0 # This was hardcoded? keeping behavior or fixing?
			# Original code was indicator_pos := _locked_direction * 100.0. 
			# Let's make it appear at the end or fixed distance? 
			# User code had: var indicator_pos := _locked_direction * 100.0
			# We'll calculate it properly in local space
			var indicator_pos = end_local.normalized() * min(100.0, beam_len_local)
			draw_circle(indicator_pos, 10.0 + sin(_timer * 15.0) * 3.0, _preview_color)
		
		BeamState.FIRING:
			# Draw main beam (thick, bright)
			_draw_beam(start, end_local, _current_width, _beam_color)
			# Draw beam core (brighter, narrower)
			var core_color := Color(1.0, 0.6, 0.6, 1.0) # Pale red core (was orange/white)
			_draw_beam(start, end_local, _current_width * 0.4, core_color)
		
		BeamState.FADING:
			# Draw shrinking beam
			var fade_alpha := 1.0 - (_timer / _fade_time)
			var fade_color := Color(_beam_color.r, _beam_color.g, _beam_color.b, _beam_color.a * fade_alpha)
			_draw_beam(start, end_local, _current_width, fade_color)

func _draw_beam(start: Vector2, end: Vector2, width: float, color: Color) -> void:
	if width <= 0:
		return
	
	# Draw main beam body
	draw_line(start, end, color, width, true)
	
	# Draw caps at start and end
	draw_circle(start, width / 2.0, color)
	draw_circle(end, width / 2.0, color) # Draw cap at end too
	
	# Draw edge glow
	var glow_color := Color(color.r, color.g, color.b, color.a * 0.3)
	draw_line(start, end, glow_color, width * 1.5, true)

