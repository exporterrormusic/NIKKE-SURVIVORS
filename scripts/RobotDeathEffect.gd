extends Node2D
class_name RobotDeathEffect

# Robot destruction effect with:
# - Electric sparks
# - Smoke/fire
# - Metal debris pieces flying out
# - Core explosion
# - Dissolving remnants
# - Overkill enhancement (bigger explosion)

var _rng := RandomNumberGenerator.new()
var _age := 0.0
var _duration := 1.2
var _is_overkill := false  # Enhanced effect for overkill damage

# Sparks - vivid colors with brightness boost for bloom
var _sparks: Array = []
var _max_sparks := 25
const SPARK_COLORS := [
	Color(1.0, 0.9, 0.3, 1.0),   # Yellow electric
	Color(1.0, 0.5, 0.15, 1.0),  # Orange
	Color(0.4, 0.7, 1.0, 1.0),   # Blue electric
	Color(1.0, 1.0, 1.0, 1.0)    # White hot
]
const BLOOM_BOOST := 1.5  # Brightness multiplier for bloom

# Smoke/fire - vivid fire color
var _smoke_puffs: Array = []
var _max_smoke := 15
const SMOKE_COLOR := Color(0.3, 0.3, 0.35, 0.8)
const FIRE_COLOR := Color(1.0, 0.4, 0.15, 0.7)  # Orange-red fire

# Metal debris
var _debris: Array = []
var _max_debris := 12
const METAL_COLORS := [
	Color(0.5, 0.5, 0.55, 1.0),   # Dark metal
	Color(0.7, 0.7, 0.75, 1.0),   # Light metal
	Color(0.4, 0.4, 0.45, 1.0),   # Shadow metal
	Color(0.85, 0.4, 0.3, 1.0)    # Hot/damaged metal
]

# Core explosion - vivid color with brightness boost for bloom
var _explosion_radius := 0.0
var _explosion_alpha := 1.0
var _explosion_max_radius := 60.0
const EXPLOSION_COLOR := Color(1.0, 0.5, 0.2, 0.9)  # Orange explosion

# Screen shake callback (optional)
var on_screen_shake: Callable = Callable()

func set_overkill(is_overkill: bool) -> void:
	_is_overkill = is_overkill
	if _is_overkill:
		# Enhanced effect for overkill
		_max_sparks = 40
		_max_smoke = 25
		_max_debris = 20
		_explosion_max_radius = 100.0
		_duration = 1.5

func _ready() -> void:
	_rng.randomize()
	z_index = 100
	
	# Initial burst of effects
	_spawn_initial_explosion()
	_spawn_debris_burst()
	_spawn_spark_burst()
	_spawn_smoke_burst()
	
	# Trigger screen shake - stronger for overkill
	var shake_strength := 12.0 if _is_overkill else 8.0
	if on_screen_shake.is_valid():
		on_screen_shake.call(0.15, shake_strength)
	
	# Also use CombatJuice for camera shake
	var combat_juice_script = load("res://scripts/CombatJuice.gd")
	if combat_juice_script and combat_juice_script.instance:
		combat_juice_script.camera_shake(shake_strength)
	
	set_process(true)

func _spawn_initial_explosion() -> void:
	_explosion_radius = 10.0 if not _is_overkill else 20.0
	_explosion_alpha = 1.0

func _spawn_debris_burst() -> void:
	for i in range(_max_debris):
		var angle := _rng.randf() * TAU
		var speed := _rng.randf_range(80, 200)
		var size := _rng.randf_range(4, 12)
		var shape := _rng.randi() % 3  # 0=square, 1=triangle, 2=irregular
		
		_debris.append({
			"position": Vector2.ZERO,
			"velocity": Vector2(cos(angle), sin(angle)) * speed,
			"rotation": _rng.randf() * TAU,
			"angular_velocity": _rng.randf_range(-15, 15),
			"size": size,
			"shape": shape,
			"color": METAL_COLORS[_rng.randi() % METAL_COLORS.size()],
			"alpha": 1.0,
			"lifetime": _rng.randf_range(0.6, 1.0),
			"age": 0.0,
			"gravity": _rng.randf_range(150, 300)
		})

func _spawn_spark_burst() -> void:
	for i in range(_max_sparks):
		var angle := _rng.randf() * TAU
		var speed := _rng.randf_range(100, 350)
		
		_sparks.append({
			"position": Vector2.ZERO,
			"velocity": Vector2(cos(angle), sin(angle)) * speed,
			"size": _rng.randf_range(1.5, 4.0),
			"color": SPARK_COLORS[_rng.randi() % SPARK_COLORS.size()],
			"alpha": 1.0,
			"lifetime": _rng.randf_range(0.15, 0.4),
			"age": 0.0,
			"trail_length": _rng.randf_range(8, 20)
		})

func _spawn_smoke_burst() -> void:
	for i in range(_max_smoke):
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(0, 15)
		var is_fire := _rng.randf() < 0.4  # 40% chance of fire
		
		_smoke_puffs.append({
			"position": Vector2(cos(angle), sin(angle)) * distance,
			"velocity": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-80, -30)),
			"radius": _rng.randf_range(8, 15),
			"color": FIRE_COLOR if is_fire else SMOKE_COLOR,
			"alpha": 0.8 if is_fire else 0.6,
			"lifetime": _rng.randf_range(0.5, 1.0),
			"age": _rng.randf_range(0, 0.2),  # Stagger spawn
			"is_fire": is_fire,
			"growth_rate": _rng.randf_range(40, 80)
		})

func _process(delta: float) -> void:
	_age += delta
	
	# Update explosion
	if _explosion_alpha > 0:
		_explosion_radius += 200.0 * delta
		_explosion_alpha -= 3.0 * delta
		if _explosion_radius > _explosion_max_radius:
			_explosion_radius = _explosion_max_radius
	
	# Update sparks
	_update_sparks(delta)
	
	# Update smoke
	_update_smoke(delta)
	
	# Update debris
	_update_debris(delta)
	
	# Spawn trailing sparks during effect
	if _age < 0.5 and _rng.randf() < 0.3:
		_spawn_trailing_spark()
	
	# End effect
	if _age >= _duration:
		queue_free()
		return
	
	queue_redraw()

func _update_sparks(delta: float) -> void:
	var i := 0
	while i < _sparks.size():
		var s: Dictionary = _sparks[i]
		s["age"] += delta
		
		if s["age"] >= s["lifetime"]:
			_sparks.remove_at(i)
			continue
		
		s["position"] += s["velocity"] * delta
		s["velocity"] *= 0.92  # Drag
		s["alpha"] = 1.0 - (s["age"] / s["lifetime"])
		
		_sparks[i] = s
		i += 1

func _update_smoke(delta: float) -> void:
	var i := 0
	while i < _smoke_puffs.size():
		var p: Dictionary = _smoke_puffs[i]
		p["age"] += delta
		
		if p["age"] >= p["lifetime"]:
			_smoke_puffs.remove_at(i)
			continue
		
		p["position"] += p["velocity"] * delta
		p["velocity"] *= 0.95
		p["radius"] += p["growth_rate"] * delta
		
		var life_ratio: float = p["age"] / p["lifetime"]
		p["alpha"] = (1.0 - life_ratio) * (0.8 if p["is_fire"] else 0.6)
		
		# Fire turns to smoke over time
		if p["is_fire"] and life_ratio > 0.4:
			var smoke_blend := (life_ratio - 0.4) / 0.6
			p["color"] = FIRE_COLOR.lerp(SMOKE_COLOR, smoke_blend)
		
		_smoke_puffs[i] = p
		i += 1

func _update_debris(delta: float) -> void:
	var i := 0
	while i < _debris.size():
		var d: Dictionary = _debris[i]
		d["age"] += delta
		
		if d["age"] >= d["lifetime"]:
			_debris.remove_at(i)
			continue
		
		# Physics
		d["position"] += d["velocity"] * delta
		d["velocity"].y += d["gravity"] * delta  # Gravity
		d["velocity"] *= 0.98  # Air resistance
		d["rotation"] += d["angular_velocity"] * delta
		
		# Fade out
		var life_ratio: float = d["age"] / d["lifetime"]
		if life_ratio > 0.6:
			d["alpha"] = 1.0 - ((life_ratio - 0.6) / 0.4)
		
		_debris[i] = d
		i += 1

func _spawn_trailing_spark() -> void:
	if _sparks.size() >= _max_sparks * 2:
		return
	
	var offset := Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20))
	var angle := _rng.randf() * TAU
	var speed := _rng.randf_range(50, 150)
	
	_sparks.append({
		"position": offset,
		"velocity": Vector2(cos(angle), sin(angle)) * speed,
		"size": _rng.randf_range(1.0, 2.5),
		"color": SPARK_COLORS[_rng.randi() % SPARK_COLORS.size()],
		"alpha": 1.0,
		"lifetime": _rng.randf_range(0.1, 0.25),
		"age": 0.0,
		"trail_length": _rng.randf_range(5, 12)
	})

func _draw() -> void:
	# Draw explosion ring first (behind everything)
	if _explosion_alpha > 0:
		_draw_explosion()
	
	# Draw smoke (behind debris)
	for p in _smoke_puffs:
		var base_color: Color = p["color"]
		# Fire gets bloom boost, smoke stays normal
		var boost := BLOOM_BOOST if p["is_fire"] else 1.0
		var color := Color(base_color.r * boost, base_color.g * boost, base_color.b * boost, p["alpha"])
		
		# Outer soft smoke
		var outer_color := Color(color.r, color.g, color.b, color.a * 0.4)
		draw_circle(p["position"], p["radius"] * 1.4, outer_color)
		
		# Inner smoke
		draw_circle(p["position"], p["radius"], color)
	
	# Draw debris
	for d in _debris:
		_draw_debris_piece(d)
	
	# Draw sparks (on top)
	for s in _sparks:
		_draw_spark(s)

func _draw_explosion() -> void:
	# Outer ring - apply bloom boost for HDR
	var ring_color := Color(EXPLOSION_COLOR.r * BLOOM_BOOST, EXPLOSION_COLOR.g * BLOOM_BOOST, EXPLOSION_COLOR.b * BLOOM_BOOST, _explosion_alpha * 0.5)
	draw_arc(Vector2.ZERO, _explosion_radius, 0, TAU, 32, ring_color, 4.0)
	
	# Inner glow - boosted yellow/orange
	var inner_color := Color(1.0 * BLOOM_BOOST, 0.9 * BLOOM_BOOST, 0.7 * BLOOM_BOOST, _explosion_alpha * 0.7)
	draw_circle(Vector2.ZERO, _explosion_radius * 0.4, inner_color)
	
	# Core flash (very brief) - bright white with bloom
	if _age < 0.1:
		var core_alpha := (1.0 - _age / 0.1) * 0.9
		draw_circle(Vector2.ZERO, 25.0 * (1.0 - _age / 0.1), Color(BLOOM_BOOST, BLOOM_BOOST, BLOOM_BOOST, core_alpha))

func _draw_debris_piece(d: Dictionary) -> void:
	var color: Color = d["color"]
	color.a = d["alpha"]
	
	var pos: Vector2 = d["position"]
	var size: float = d["size"]
	var rot: float = d["rotation"]
	
	match d["shape"]:
		0:  # Square/rectangle
			var points := PackedVector2Array()
			var w := size * _rng.randf_range(0.6, 1.0)
			var h := size * _rng.randf_range(0.8, 1.2)
			for corner in [Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)]:
				points.append(pos + corner.rotated(rot))
			draw_polygon(points, [color, color, color, color])
			# Highlight edge
			var highlight := Color(1.0, 1.0, 1.0, color.a * 0.4)
			draw_line(points[0], points[1], highlight, 1.0)
		
		1:  # Triangle
			var points := PackedVector2Array()
			for j in range(3):
				var angle := rot + TAU * j / 3.0
				points.append(pos + Vector2(cos(angle), sin(angle)) * size)
			draw_polygon(points, [color, color, color])
		
		2:  # Irregular polygon
			var points := PackedVector2Array()
			var num_sides := 5
			for j in range(num_sides):
				var angle := rot + TAU * j / float(num_sides)
				var dist := size * _rng.randf_range(0.6, 1.0)
				points.append(pos + Vector2(cos(angle), sin(angle)) * dist)
			var colors := PackedColorArray()
			for j in range(num_sides):
				colors.append(color)
			draw_polygon(points, colors)

func _draw_spark(s: Dictionary) -> void:
	var base_color: Color = s["color"]
	# Apply bloom boost to preserve color while enabling HDR bloom
	var color := Color(base_color.r * BLOOM_BOOST, base_color.g * BLOOM_BOOST, base_color.b * BLOOM_BOOST, s["alpha"])
	
	var pos: Vector2 = s["position"]
	var vel: Vector2 = s["velocity"]
	
	# Draw spark trail
	if vel.length() > 10:
		var trail_length_val: float = float(s["trail_length"])
		var trail_end: Vector2 = pos - vel.normalized() * trail_length_val
		var trail_color := Color(color.r, color.g, color.b, color.a * 0.5)
		draw_line(pos, trail_end, trail_color, s["size"] * 0.6)
	
	# Draw spark head (bright with bloom)
	draw_circle(pos, s["size"], color)
	
	# Inner bright core - extra bright for bloom
	var core_color := Color(BLOOM_BOOST, BLOOM_BOOST, BLOOM_BOOST, color.a)
	draw_circle(pos, s["size"] * 0.4, core_color)
