extends Area2D
class_name KiloPellet

## Kilo's shotgun pellet - bright orange/amber colored with intense glow
## Special attack: red-tinted, pulsing, draws damaging connecting lines between pellets
## Burst mode: same pellets but with persistent line connections across shots

var velocity := Vector2.ZERO
var lifetime := 0.0
var owner_node: Node = null
var start_position := Vector2.ZERO
var _start_position_set := false  # Track if start position has been captured

# Max range for shotgun pellets (2/3 screen width)
const MAX_RANGE := 750.0

@export var pierce_all := false
@export var pierce_count := 0

# Damage
var base_damage := 2

# Critical hit settings
const CRIT_CHANCE := 0.15
const CRIT_MULTIPLIER := 2.0

# Special attack properties
var is_special := false
var is_burst := false  # Burst mode pellets
var burn_level := 0
var size_level := 0

# Line connection for special/burst attacks
static var all_special_pellets: Array[KiloPellet] = []
static var all_burst_pellets: Array[KiloPellet] = []  # Persists across burst shots

# For zigzag chain pattern during burst
var wave_index: int = 0  # Which wave/volley this pellet belongs to
var pellet_index: int = 0  # Position in the wave (0 = leftmost, pellet_count-1 = rightmost)
static var current_burst_wave: int = 0  # Tracks current wave number

var _hit_nodes: Array = []
var _time := 0.0

# Enhanced visual colors - much brighter than before
const PELLET_COLOR := Color(1.0, 0.74, 0.32, 1.0)  # Bright orange/amber
const SPECIAL_COLOR := Color(1.0, 0.28, 0.08, 1.0)  # Deep red-orange for special
const BURST_COLOR := Color(1.0, 0.45, 0.12, 1.0)  # Orange-red for burst
const LINE_COLOR := Color(1.0, 0.35, 0.08, 0.85)  # Orange-red connecting line

# Pellet size - larger and more visible
const BASE_RADIUS := 10.0  # Was 6.0, now much larger

func _ready() -> void:
	connect("body_entered", Callable(self, "_on_body_entered"))
	# Don't set start_position here - pellet isn't positioned yet
	
	# Apply size scaling to hitbox if upgraded
	if (is_special or is_burst) and size_level > 0:
		var size_bonuses: Array[float] = [1.0, 1.5, 2.0, 3.0]
		var mult: float = size_bonuses[mini(size_level, 3)]
		
		# Scale the collision shape
		var shape = get_node_or_null("CollisionShape2D")
		if shape:
			shape.scale = Vector2(mult, mult)
	
	# Assign to effects layer to prevent night darkening (deferred so node is in tree)
	call_deferred("_assign_to_effects_layer")
	
	# Force Correct Mask for Hitboxes (Layer 4) AND Enemies (Layer 2)
	collision_mask = 6 
	
	queue_redraw()

	# Connect to environment modulate change if available so we redraw when lighting changes
	if not Engine.is_editor_hint():
		var tree := get_tree()
		if tree:
			var env = tree.get_first_node_in_group("environment_controller")
			if env and env.has_signal("modulate_changed"):
				env.modulate_changed.connect(Callable(self, "_on_environment_modulate_changed"))

func _enter_tree() -> void:
	# Register for line drawing (must be in _enter_tree to survive reparenting)
	if is_special and not self in all_special_pellets:
		all_special_pellets.append(self)
	if is_burst and not self in all_burst_pellets:
		all_burst_pellets.append(self)

func _exit_tree() -> void:
	# Use erase safely
	if self in all_special_pellets:
		all_special_pellets.erase(self)
	if self in all_burst_pellets:
		all_burst_pellets.erase(self)

func _assign_to_effects_layer() -> void:
	"""Deferred call to assign to effects layer after node is in tree"""
	# Use helper which ensures correct CanvasLayer settings (follow_viewport)
	VisualLayerHelper.reparent_to_effects_layer(self, 900)


func _draw() -> void:
	_time = Time.get_ticks_msec() / 1000.0
	
	# Determine base color and radius
	var color: Color
	var radius := BASE_RADIUS
	
	if is_special:
		color = SPECIAL_COLOR
	elif is_burst:
		color = BURST_COLOR
	else:
		color = PELLET_COLOR
	
	# Apply size multiplier for special/burst
	if (is_special or is_burst) and size_level > 0:
		var size_bonuses := [1.0, 1.5, 2.0, 3.0]
		radius *= size_bonuses[mini(size_level, 3)]
	
	# Pulsing effect for special attack
	var pulse := 1.0
	if is_special or is_burst:
		pulse = 1.0 + sin(_time * 10.0) * 0.3
	
	# === OUTER GLOW LAYERS - Tighter and quicker falloff ===
	# Outermost soft glow (reduced from 4.0x to 2.0x)
	var outer_glow := Color(color.r, color.g * 0.7, color.b * 0.5, 0.15 * pulse)
	draw_circle(Vector2.ZERO, radius * 2.0, outer_glow)
	
	# Inner glow layer (reduced from 1.8x to 1.4x)
	var inner_glow := Color(color.r, color.g * 0.9, color.b * 0.7, 0.4 * pulse)
	draw_circle(Vector2.ZERO, radius * 1.4, inner_glow)
	
	# === WHITE STROKE OUTLINE (like SMG bullets) ===
	draw_arc(Vector2.ZERO, radius + 1.5, 0, TAU, 24, Color(1.0, 1.0, 1.0, 0.9), 2.0)
	
	# === CORE ===
	# Main core - bright
	# Apply ambient/vignette compensation so pellet stays bright at night
	var vp := get_viewport()
	var comp_color := BasicProjectileVisual._apply_compensation(color, global_position, vp) if BasicProjectileVisual else color
	draw_circle(Vector2.ZERO, radius, Color(comp_color.r, comp_color.g, comp_color.b, 1.0))
	
	# Hot center - almost white
	var center_color := Color(1.0, 0.95, 0.8, 1.0)
	draw_circle(Vector2.ZERO, radius * 0.55, center_color)
	
	# White-hot core
	draw_circle(Vector2.ZERO, radius * 0.25, Color(1.0, 1.0, 0.95, 1.0))
	
	# === CONNECTING LINES ===
	_draw_connecting_lines()

func _draw_connecting_lines() -> void:
	if not is_special and not is_burst:
		return
	
	# Get the appropriate pellet array
	var pellet_array: Array[KiloPellet] = all_burst_pellets if is_burst else all_special_pellets
	
	# For burst mode: zigzag chain pattern
	# Connect edge pellets between consecutive waves
	if is_burst:
		_draw_burst_zigzag_lines(pellet_array)
	else:
		# Special attack: connect all pellets in the same wave
		_draw_special_web_lines(pellet_array)

func _draw_burst_zigzag_lines(pellet_array: Array[KiloPellet]) -> void:
	# Find our connection partner(s) for zigzag pattern
	# Each wave alternates: wave 0 connects right-to-left, wave 1 connects left-to-right
	
	for pellet in pellet_array:
		if pellet == self or not is_instance_valid(pellet):
			continue
		
		var should_connect := false
		
		# Same wave: connect adjacent pellets in sequence (forms the wave line)
		if pellet.wave_index == wave_index:
			# Connect to the next pellet in sequence
			if pellet.pellet_index == pellet_index + 1:
				should_connect = true
		
		# Adjacent waves: connect edge pellets for zigzag
		elif pellet.wave_index == wave_index + 1:
			# From wave N to wave N+1
			# Even waves: rightmost (high index) connects to rightmost of next wave
			# Odd waves: leftmost (index 0) connects to leftmost of next wave
			if wave_index % 2 == 0:
				# Even wave: connect our rightmost to their rightmost
				# We are the rightmost if we have highest pellet_index in our wave
				var our_wave_pellets := pellet_array.filter(func(p): return is_instance_valid(p) and p.wave_index == wave_index)
				var their_wave_pellets := pellet_array.filter(func(p): return is_instance_valid(p) and p.wave_index == wave_index + 1)
				
				if our_wave_pellets.size() > 0 and their_wave_pellets.size() > 0:
					var our_max_idx := 0
					var their_max_idx := 0
					for p in our_wave_pellets:
						if p.pellet_index > our_max_idx:
							our_max_idx = p.pellet_index
					for p in their_wave_pellets:
						if p.pellet_index > their_max_idx:
							their_max_idx = p.pellet_index
					
					# We connect if we're the rightmost and they're the rightmost
					if pellet_index == our_max_idx and pellet.pellet_index == their_max_idx:
						should_connect = true
			else:
				# Odd wave: connect our leftmost to their leftmost
				var our_wave_pellets := pellet_array.filter(func(p): return is_instance_valid(p) and p.wave_index == wave_index)
				var their_wave_pellets := pellet_array.filter(func(p): return is_instance_valid(p) and p.wave_index == wave_index + 1)
				
				if our_wave_pellets.size() > 0 and their_wave_pellets.size() > 0:
					var our_min_idx := 999
					var their_min_idx := 999
					for p in our_wave_pellets:
						if p.pellet_index < our_min_idx:
							our_min_idx = p.pellet_index
					for p in their_wave_pellets:
						if p.pellet_index < their_min_idx:
							their_min_idx = p.pellet_index
					
					# We connect if we're the leftmost and they're the leftmost
					if pellet_index == our_min_idx and pellet.pellet_index == their_min_idx:
						should_connect = true
		
		if not should_connect:
			continue
		
		_draw_line_to_pellet(pellet)

func _draw_special_web_lines(pellet_array: Array[KiloPellet]) -> void:
	# For special attack, connect all pellets in the same volley
	for pellet in pellet_array:
		if pellet == self or not is_instance_valid(pellet):
			continue
		
		_draw_line_to_pellet(pellet)

func _draw_line_to_pellet(pellet: KiloPellet) -> void:
	var local_pos := to_local(pellet.global_position)
	var dist := local_pos.length()
	
	# Connect within extended range
	if dist > 800:  # Extended for zigzag connections between waves
		return
	
	# More aggressive visuals - stronger alpha, faster pulse
	var alpha := clampf(1.0 - (dist / 800.0), 0.0, 1.0)
	alpha = pow(alpha, 0.6)  # Even less steep falloff for chain effect
	var pulse := 1.0 + sin(_time * 12.0) * 0.3
	
	# Outer glow line - thicker and more visible
	# More aggressive visuals - stronger alpha, faster pulse. Apply compensation.
	var comp_line := BasicProjectileVisual._apply_compensation(LINE_COLOR, global_position, get_viewport()) if BasicProjectileVisual else LINE_COLOR
	var outer_color := Color(comp_line.r, comp_line.g * 0.6, comp_line.b * 0.4, 0.5 * alpha * pulse)
	draw_line(Vector2.ZERO, local_pos, outer_color, 18.0)
	
	# Middle fire layer
	var mid_color := Color(comp_line.r, comp_line.g * 0.75, comp_line.b * 0.4, 0.7 * alpha * pulse)
	draw_line(Vector2.ZERO, local_pos, mid_color, 12.0)
	
	# Inner line - brighter orange
	var inner_color := Color(1.0, LINE_COLOR.g * 1.1, LINE_COLOR.b * 0.6, 0.85 * alpha * pulse)
	draw_line(Vector2.ZERO, local_pos, inner_color, 7.0)
	
	# Core line - white-hot center
	var core_color := Color(1.0, 0.95, 0.8, 0.95 * alpha * pulse)
	draw_line(Vector2.ZERO, local_pos, core_color, 3.0)

func _physics_process(delta: float) -> void:
	# Capture start position on first frame (after pellet has been positioned)
	if not _start_position_set:
		start_position = global_position
		_start_position_set = true
	
	position += velocity * delta
	
	lifetime += delta
	if lifetime > 3.0:  # Shorter lifetime for shotgun pellets
		queue_free()
		return
	
	# Check max range (750px for shotgun)
	if global_position.distance_to(start_position) >= MAX_RANGE:
		queue_free()
		return
	
	# Check boulder collision (reparenting to EffectsLayer breaks Area2D overlap)
	if _check_boulder_collision():
		queue_free()
		return
	
	# Always redraw for pulsing effect and line connections
	if is_special or is_burst:
		queue_redraw()
		# Check for line damage
		_check_line_damage(delta)

func _check_boulder_collision() -> bool:
	"""Manual boulder collision check since pellets are in EffectsLayer (different scene tree branch)."""
	var boulders := TargetCache.get_boulders()
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		if global_position.distance_to(boulder_pos) < boulder_radius:
			return true
	return false


# Track enemies hit by the connecting line to prevent double-damage
var _line_hit_enemies: Dictionary = {}
const LINE_DAMAGE_INTERVAL := 0.15  # Damage tick rate for line

func _check_line_damage(_delta: float) -> void:
	if not is_special and not is_burst:
		return
	
	var tree := get_tree()
	if tree == null:
		return
	
	var enemies := TargetCache.get_enemies()
	var pellet_array: Array[KiloPellet] = all_burst_pellets if is_burst else all_special_pellets
	var now := Time.get_ticks_msec() / 1000.0
	
	# Get list of pellets we're actually connected to
	var connected_pellets: Array[KiloPellet] = []
	
	if is_burst:
		# Zigzag connections only
		for pellet in pellet_array:
			if pellet == self or not is_instance_valid(pellet):
				continue
			
			var should_connect := false
			
			# Same wave: adjacent pellets
			if pellet.wave_index == wave_index and pellet.pellet_index == pellet_index + 1:
				should_connect = true
			
			# Adjacent waves: edge pellets for zigzag
			elif pellet.wave_index == wave_index + 1:
				if wave_index % 2 == 0:
					# Even wave: rightmost connects to rightmost
					var our_wave := pellet_array.filter(func(p): return is_instance_valid(p) and p.wave_index == wave_index)
					var their_wave := pellet_array.filter(func(p): return is_instance_valid(p) and p.wave_index == wave_index + 1)
					if our_wave.size() > 0 and their_wave.size() > 0:
						var our_max := 0
						var their_max := 0
						for p in our_wave:
							if p.pellet_index > our_max: our_max = p.pellet_index
						for p in their_wave:
							if p.pellet_index > their_max: their_max = p.pellet_index
						if pellet_index == our_max and pellet.pellet_index == their_max:
							should_connect = true
				else:
					# Odd wave: leftmost connects to leftmost
					var our_wave := pellet_array.filter(func(p): return is_instance_valid(p) and p.wave_index == wave_index)
					var their_wave := pellet_array.filter(func(p): return is_instance_valid(p) and p.wave_index == wave_index + 1)
					if our_wave.size() > 0 and their_wave.size() > 0:
						var our_min := 999
						var their_min := 999
						for p in our_wave:
							if p.pellet_index < our_min: our_min = p.pellet_index
						for p in their_wave:
							if p.pellet_index < their_min: their_min = p.pellet_index
						if pellet_index == our_min and pellet.pellet_index == their_min:
							should_connect = true
			
			if should_connect:
				connected_pellets.append(pellet)
	else:
		# Special attack: connect to all pellets in same volley
		for pellet in pellet_array:
			if pellet != self and is_instance_valid(pellet):
				connected_pellets.append(pellet)
	
	# Check damage along connected lines only
	for pellet in connected_pellets:
		var start_pos := global_position
		var end_pos := pellet.global_position
		var dist := start_pos.distance_to(end_pos)
		
		if dist > 800:  # Match extended line range
			continue
		
		# Check enemies against the line segment
		for enemy in enemies:
			if not is_instance_valid(enemy) or not enemy is Node2D:
				continue
			if not enemy.has_method("take_damage"):
				continue
			
			var enemy_pos: Vector2 = enemy.global_position
			var point_on_line := _closest_point_on_segment(start_pos, end_pos, enemy_pos)
			var dist_to_line := enemy_pos.distance_to(point_on_line)
			
			# Hit if within 30 pixels of line
			if dist_to_line > 30:
				continue
			
			# Check cooldown for this enemy
			var enemy_id: int = enemy.get_instance_id()
			var last_hit: float = _line_hit_enemies.get(enemy_id, 0.0)
			if now - last_hit < LINE_DAMAGE_INTERVAL:
				continue
			
			# Deal line damage (Scale with pellet damage)
			var line_damage: int = maxi(1, int(base_damage * 0.5))
			var hit_dir: Vector2 = (enemy_pos - point_on_line).normalized()
			# Pass is_burst as from_burst to prevent burst charge during burst attacks
			enemy.take_damage(line_damage, false, hit_dir, is_burst)
			_line_hit_enemies[enemy_id] = now

func _closest_point_on_segment(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var ab := b - a
	var ap := p - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.0001:
		return a
	var t := clampf(ap.dot(ab) / ab_len_sq, 0.0, 1.0)
	return a + ab * t

func _on_body_entered(body: Node2D) -> void:
	if body == owner_node:
		return
	if owner_node and body.name == "Player":
		return
	
	# Skip charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return
	
	if not body.has_method("take_damage"):
		return
	
	if _hit_nodes.has(body):
		return
	
	# Roll for critical
	var is_crit := randf() < CRIT_CHANCE
	var damage := base_damage
	if is_crit:
		damage = int(base_damage * CRIT_MULTIPLIER)
	
	var hit_direction := velocity.normalized()
	# Pass is_burst as from_burst to prevent burst charge during burst attacks
	body.take_damage(damage, is_crit, hit_direction, is_burst)
	
	# Register burst hit (only if not from burst)
	if owner_node and owner_node.has_method("register_burst_hit"):
		owner_node.register_burst_hit(body, is_burst)
		
	_hit_nodes.append(body)
	
	# Apply burn if special with burn talent
	if is_special and burn_level > 0:
		_apply_burn(body)
	
	# Spawn V-blast explosion effect for special attack
	if is_special:
		_spawn_v_blast_effect(body.global_position, hit_direction)
	
	if not pierce_all:
		queue_free()
		return
	
	if pierce_count > 0:
		pierce_count -= 1
		if pierce_count <= 0:
			queue_free()

## Spawn the V-shaped blast effect behind the enemy on special hit
func _spawn_v_blast_effect(hit_position: Vector2, forward: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	
	var effect := KiloVBlastEffect.new()
	effect.global_position = hit_position
	
	# Calculate scale based on size level
	var blast_scale: float = 1.0
	if size_level > 0:
		var size_bonuses: Array[float] = [1.0, 1.5, 2.0, 3.0]
		blast_scale = size_bonuses[mini(size_level, 3)]
		
	effect.configure(forward, 180.0, 45.0, SPECIAL_COLOR, owner_node, is_burst, blast_scale)
	parent.add_child(effect)

func _apply_burn(enemy: Node2D) -> void:
	if not is_instance_valid(enemy) or not "max_hp" in enemy:
		return
	
	# Burn rates: 15/25/35% HP/s for normal (and elite/tank), 3% for boss
	var burn_rates := [0.0, 0.15, 0.25, 0.35]
	var boss_rates := [0.0, 0.03, 0.03, 0.03] # Flat 3% for bosses
	
	# Logic: "reduced burn effect is only for bosses, not elites and tanks"
	var is_boss: bool = enemy.has_meta("enemy_tier") and enemy.get_meta("enemy_tier") == "boss"
	var burn_rate: float = boss_rates[burn_level] if is_boss else burn_rates[burn_level]
	var burn_duration := 3.0
	var damage_per_second := int(enemy.max_hp * burn_rate)
	
	# Check if already has burn
	if enemy.has_node("KiloBurn"):
		var existing := enemy.get_node("KiloBurn")
		existing.set("duration", burn_duration)  # Refresh duration
		return
	
	# Create burn effect
	var burn := Node.new()
	burn.name = "KiloBurn"
	burn.set_script(_get_burn_script())
	burn.set("damage_per_second", damage_per_second)
	burn.set("duration", burn_duration)
	burn.set("owner_node", owner_node)
	enemy.add_child(burn)

func _get_burn_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node

var damage_per_second: int = 0
var duration: float = 3.0
var owner_node: Node = null
var _timer: float = 0.0
var _tick_timer: float = 0.0
const TICK_INTERVAL := 0.5

func _process(delta: float) -> void:
	_timer += delta
	_tick_timer += delta
	
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer = 0.0
		_apply_tick()
	
	if _timer >= duration:
		queue_free()

func _apply_tick() -> void:
	var parent := get_parent()
	if not is_instance_valid(parent):
		queue_free()
		return
	
	var tick_damage := int(damage_per_second * TICK_INTERVAL)
	if tick_damage <= 0:
		return
	
	if parent.has_method(\"take_damage\"):
		parent.take_damage(tick_damage, false, Vector2.ZERO)
	elif \"hp\" in parent:
		parent.hp -= tick_damage
		if parent.hp <= 0 and parent.has_method(\"die\"):
			parent.die()
"""
	script.reload()
	return script
