extends Node2D
class_name BossBeam

## Boss beam attack with charge preview, sustained fire, and fade

signal beam_finished

# Beam settings
const BEAM_LENGTH := 2000.0
const BEAM_WIDTH := 80.0
const PREVIEW_WIDTH := 4.0
const DAMAGE_PER_TICK := 1
const DAMAGE_INTERVAL := 0.2

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
var tracking_speed: float = 0.3       # How fast beam rotates during firing (radians per second)

# Direction locked when charging completes
var _locked_direction := Vector2.RIGHT
var _current_width := PREVIEW_WIDTH

# Visual
var _beam_color := Color(1.0, 0.2, 0.1, 1.0)
var _preview_color := Color(1.0, 0.3, 0.1, 0.4)

func initialize(boss: Node2D, player: Node2D, charge_time: float, fire_time: float, fade_time: float, is_boss: bool = true) -> void:
	_boss = boss
	_player = player
	_charge_time = charge_time
	_fire_time = fire_time
	_fade_time = fade_time
	
	# Boss beams track during charge and slowly during fire
	# Elite beams lock direction at start of charge, no tracking
	if is_boss:
		track_during_charge = true
		track_during_fire = true
		tracking_speed = 0.15  # Very slow rotation during fire
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

func _process_charging(_delta: float) -> void:
	# Track player during charge (only if enabled)
	if track_during_charge and _player and is_instance_valid(_player):
		_locked_direction = (_player.global_position - _boss.global_position).normalized()
		if _locked_direction == Vector2.ZERO:
			_locked_direction = Vector2.RIGHT
	
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
	var beam_end := beam_start + _locked_direction * BEAM_LENGTH
	
	# Check player
	if _player and is_instance_valid(_player):
		var player_pos := _player.global_position
		var dist := _point_to_line_distance(player_pos, beam_start, beam_end)
		if dist < BEAM_WIDTH / 2.0:
			if _player.has_method("take_damage"):
				_player.take_damage(DAMAGE_PER_TICK)
	
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
				if ally.has_method("take_damage"):
					ally.take_damage(DAMAGE_PER_TICK)

func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line := line_end - line_start
	var line_length := line.length()
	if line_length == 0:
		return point.distance_to(line_start)
	
	# Project point onto line
	var t := clampf((point - line_start).dot(line) / (line_length * line_length), 0.0, 1.0)
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
	var end := _locked_direction * BEAM_LENGTH
	
	match _state:
		BeamState.CHARGING:
			# Draw preview line (thin, pulsing, semi-transparent)
			draw_line(start, end, _preview_color, _current_width, true)
			# Draw glowing endpoint indicator
			var indicator_pos := _locked_direction * 100.0
			draw_circle(indicator_pos, 10.0 + sin(_timer * 15.0) * 3.0, _preview_color)
		
		BeamState.FIRING:
			# Draw main beam (thick, bright)
			_draw_beam(start, end, _current_width, _beam_color)
			# Draw beam core (brighter, narrower)
			var core_color := Color(1.0, 0.8, 0.6, 1.0)
			_draw_beam(start, end, _current_width * 0.4, core_color)
		
		BeamState.FADING:
			# Draw shrinking beam
			var fade_alpha := 1.0 - (_timer / _fade_time)
			var fade_color := Color(_beam_color.r, _beam_color.g, _beam_color.b, _beam_color.a * fade_alpha)
			_draw_beam(start, end, _current_width, fade_color)

func _draw_beam(start: Vector2, end: Vector2, width: float, color: Color) -> void:
	if width <= 0:
		return
	
	# Draw main beam body
	draw_line(start, end, color, width, true)
	
	# Draw caps at start and end
	draw_circle(start, width / 2.0, color)
	
	# Draw edge glow
	var glow_color := Color(color.r, color.g, color.b, color.a * 0.3)
	draw_line(start, end, glow_color, width * 1.5, true)
