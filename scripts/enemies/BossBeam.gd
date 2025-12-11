extends Node2D
class_name BossBeam

## Boss beam attack with "Wide V" burst shape (Snow White style).
## Uses multi-raycast fan to conform to terrain (boulders).
## Spawns damaging OilBurnZones on the ground.

signal beam_finished

# Beam settings
const BEAM_MAX_LENGTH := 5000.0 
const BEAM_ANGLE_DEG := 70.0 
const RAY_COUNT := 20 
const BASE_DAMAGE_PER_TICK := 1
const DAMAGE_INTERVAL := 0.2
const OIL_SPAWN_INTERVAL := 0.1 # Slower spawn for polygons
const OIL_SPACING := 30.0 
const OIL_PER_TICK := 1

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
var _oil_timer := 0.0

# Tracking
var track_during_charge: bool = true
var track_during_fire: bool = false
var tracking_speed: float = 0.08
var _locked_direction := Vector2.RIGHT

# Data
var _poly_points: PackedVector2Array = [] # Local space polygon
var _hit_lengths: Array = [] # Length of each ray

# Visuals - DARK SOLID RED
var _beam_color := Color(0.6, 0.0, 0.0, 1.0) # Darker opaque red
var _preview_color := Color(0.8, 0.0, 0.0, 0.3)

# Oil Logic
var _enable_oil_burn: bool = false

# Preload Oil
const OilBurnZone = preload("res://scripts/enemies/bosses/effects/OilBurnZone.gd")

func initialize(boss: Node2D, player: Node2D, charge_time: float, fire_time: float, fade_time: float, is_boss: bool = true, scaled_damage: int = BASE_DAMAGE_PER_TICK, enable_oil_burn: bool = false) -> void:
	_boss = boss
	_player = player
	_charge_time = charge_time
	_fire_time = fire_time
	_fade_time = fade_time
	damage_per_tick = scaled_damage
	_enable_oil_burn = enable_oil_burn
	
	if is_boss:
		track_during_charge = true
		track_during_fire = true
		tracking_speed = 0.05
		if _player and is_instance_valid(_player):
			_locked_direction = (_player.global_position - _boss.global_position).normalized()
	else:
		track_during_charge = false
		track_during_fire = false
		if _player and is_instance_valid(_player):
			_locked_direction = (_player.global_position - _boss.global_position).normalized()

func _ready() -> void:
	z_index = 100 
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX # Solid mixing, not additive
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED # Still ignores lighting
	material = mat

func _process(delta: float) -> void:
	if not _boss or not is_instance_valid(_boss):
		_finish()
		return
	
	_timer += delta
	_update_fan_geometry() # Update Rays
	
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
	if track_during_charge and _player and is_instance_valid(_player):
		_update_tracking(delta)
	
	if _timer >= _charge_time:
		_state = BeamState.FIRING
		_timer = 0.0

func _process_firing(delta: float) -> void:
	if track_during_fire and _player and is_instance_valid(_player):
		_update_tracking(delta)
	
	# Continuous Camera Shake while firing
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("add_trauma"):
		# Maintain moderate shake (0.4 * delta ensures it stays active but not overwhelming)
		camera.add_trauma(0.8 * delta)
	
	_damage_timer += delta
	if _damage_timer >= DAMAGE_INTERVAL:
		_damage_timer = 0.0
		_check_fan_hit()
		
	_oil_timer += delta
	if _oil_timer >= OIL_SPAWN_INTERVAL:
		_oil_timer = 0.0
		for i in range(OIL_PER_TICK):
			_spawn_random_oil()
	
	if _timer >= _fire_time:
		_state = BeamState.FADING
		_timer = 0.0

func _process_fading(_delta: float) -> void:
	if _timer >= _fade_time:
		_finish()

func _update_tracking(delta: float) -> void:
	var target_dir := (_player.global_position - _boss.global_position).normalized()
	if target_dir != Vector2.ZERO:
		var current_angle := _locked_direction.angle()
		var target_angle := target_dir.angle()
		var angle_diff := wrapf(target_angle - current_angle, -PI, PI)
		var max_rotation := tracking_speed * delta
		var rotation_amount := clampf(angle_diff, -max_rotation, max_rotation)
		_locked_direction = _locked_direction.rotated(rotation_amount)

func _update_fan_geometry() -> void:
	if not _boss: return
	
	_poly_points.clear()
	_hit_lengths.clear()
	_poly_points.append(Vector2.ZERO) # Center
	
	var base_angle = _locked_direction.angle()
	var half_arc = deg_to_rad(BEAM_ANGLE_DEG / 2.0)
	var start_a = base_angle - half_arc
	var end_a = base_angle + half_arc
	
	var boulders = get_tree().get_nodes_in_group("boulders")
	
	# Raycast Fan
	for i in range(RAY_COUNT + 1):
		var t = float(i) / float(RAY_COUNT)
		var ang = lerp(start_a, end_a, t)
		var dir = Vector2(cos(ang), sin(ang))
		
		var dist = BEAM_MAX_LENGTH
		
		# Manual Ray against circular boulders
		var start_global = global_position
		for boulder in boulders:
			if not is_instance_valid(boulder): continue
			var b_pos = boulder.global_position
			var b_rad = 150.0
			if "boulder_size" in boulder: b_rad = boulder.boulder_size * 0.5
			
			var to_b = b_pos - start_global
			var proj = to_b.dot(dir)
			if proj > 0 and proj < dist + b_rad:
				var perp = (to_b - dir * proj).length()
				if perp < b_rad:
					var hit_d = proj - sqrt(max(0, b_rad*b_rad - perp*perp))
					if hit_d > 0 and hit_d < dist:
						dist = hit_d
		
		_hit_lengths.append(dist)
		_poly_points.append(to_local(global_position + dir * dist))

func _check_fan_hit() -> void:
	if not _player or not is_instance_valid(_player): return
	
	# Simple Fan Check: Distance and Angle + Line of Sight
	var p_pos = _player.global_position
	var to_p = p_pos - global_position
	var dist = to_p.length()
	var ang = to_p.angle()
	var base_ang = _locked_direction.angle()
	var diff = abs(wrapf(ang - base_ang, -PI, PI))
	var half = deg_to_rad(BEAM_ANGLE_DEG / 2.0)
	
	if diff <= half and dist < BEAM_MAX_LENGTH:
		# Check Blockers (Line of Sight)
		if _has_line_of_sight(global_position, p_pos):
			if _player.has_method("take_damage"):
				_player.take_damage(damage_per_tick)
	
	# Check Allies
	for ally in get_tree().get_nodes_in_group("charmed_allies"):
		if not is_instance_valid(ally): continue
		var a_pos = ally.global_position
		var a_diff = abs(wrapf((a_pos - global_position).angle() - base_ang, -PI, PI))
		if a_diff <= half and global_position.distance_to(a_pos) < BEAM_MAX_LENGTH:
			if _has_line_of_sight(global_position, a_pos):
				if ally.has_method("take_damage"):
					ally.take_damage(damage_per_tick)

	# Check Summons/Clones
	var summons = get_tree().get_nodes_in_group("summons") + get_tree().get_nodes_in_group("nayuta_clones")
	for summon in summons:
		if not is_instance_valid(summon): continue
		var s_pos = summon.global_position
		var s_diff = abs(wrapf((s_pos - global_position).angle() - base_ang, -PI, PI))
		if s_diff <= half and global_position.distance_to(s_pos) < BEAM_MAX_LENGTH:
			if _has_line_of_sight(global_position, s_pos):
				if summon.has_method("take_damage"):
					summon.take_damage(damage_per_tick)


func _spawn_random_oil() -> void:
	# "Stamp" the current fan polygon onto the ground
	if not _enable_oil_burn: return
	if _poly_points.size() < 3: return
	
	# Polygon is in local space. Convert to global.
	var global_poly = PackedVector2Array()
	for p in _poly_points:
		global_poly.append(to_global(p))
		
	# Find or Create Manager
	var manager = _get_oil_manager()
	if manager:
		manager.add_burn_poly(global_poly)

var _oil_manager_ref: Node2D = null
func _get_oil_manager() -> Node2D:
	if _oil_manager_ref and is_instance_valid(_oil_manager_ref):
		return _oil_manager_ref
		
	# Check if scene already has one
	# We can name it uniquely
	var parent = get_tree().current_scene
	var node = parent.get_node_or_null("BossOilManager")
	if node:
		_oil_manager_ref = node
		return node
		
	# Create new
	if OilBurnZone:
		var m = OilBurnZone.new() # It's now the manager script
		m.name = "BossOilManager"
		m.global_position = Vector2.ZERO
		parent.add_child(m)
		_oil_manager_ref = m
		return m
	return null

func _create_oil(pos: Vector2, rot: float) -> void:
	pass # Deprecated 

func _has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var space = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 4 
	var result = space.intersect_ray(query)
	return result.is_empty()

func _draw() -> void:
	if _poly_points.size() < 3: return
	
	match _state:
		BeamState.CHARGING:
			draw_polygon(_poly_points, PackedColorArray([_preview_color]))
			draw_polyline(_poly_points, Color(1, 0, 0, 0.8), 2.0)
			
		BeamState.FIRING:
			# Solid Beam Body
			draw_polygon(_poly_points, PackedColorArray([_beam_color]))
			
			# Red Edge Outline
			draw_polyline(_poly_points, Color(1.0, 0.3, 0.3, 1.0), 4.0)
			
		BeamState.FADING:
			var fade_alpha = 1.0 - (_timer / _fade_time)
			var col = _beam_color
			col.a *= fade_alpha
			draw_polygon(_poly_points, PackedColorArray([col]))

func _finish() -> void:
	_state = BeamState.DONE
	emit_signal("beam_finished")
	queue_free()
