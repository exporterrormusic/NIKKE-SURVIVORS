extends Node2D
class_name CharacterSwapEffect

## Unique themed swap effects for each character

const FLASH_DURATION := 0.5
const EFFECT_DURATION := 1.0

# Character colors and themes - indices match CharacterRegistry order
const CHARACTER_DATA := {
	0: {"name": "Snow White", "color": Color(0.95, 0.98, 1.0), "theme": "snowflake"},
	1: {"name": "Scarlet", "color": Color(1.0, 0.2, 0.15), "theme": "sword_slash"},
	2: {"name": "Rapunzel", "color": Color(1.0, 0.95, 0.6), "theme": "holy_glow"},
	3: {"name": "Nayuta", "color": Color(0.7, 0.75, 0.8), "theme": "wind"},
	4: {"name": "Commander", "color": Color(0.75, 0.55, 0.25), "theme": "clock"},
	5: {"name": "Marian", "color": Color(0.4, 0.1, 0.6), "theme": "dark_energy"},
	6: {"name": "Crown", "color": Color(1.0, 0.85, 0.3), "theme": "kingly"},
	7: {"name": "Kilo", "color": Color(0.3, 0.9, 0.4), "theme": "mech"},
	8: {"name": "Cecil", "color": Color(0.2, 0.8, 1.0), "theme": "code"},
	9: {"name": "Sin", "color": Color(0.7, 0.2, 0.8), "theme": "hearts"},
}

var _elapsed := 0.0
var _is_active := false
var _character_index := 0
var _character_color: Color = Color.WHITE
var _theme: String = ""

# Effect-specific particles/elements
var _particles: Array = []
var _slashes: Array = []
var _symbols: Array = []


func trigger(character_index: int, at_position: Vector2) -> void:
	global_position = at_position
	_character_index = character_index
	var data: Dictionary = CHARACTER_DATA.get(character_index, {"color": Color.WHITE, "theme": "default"})
	_character_color = data.get("color", Color.WHITE)
	_theme = data.get("theme", "default")
	_elapsed = 0.0
	_is_active = true
	
	# Scale effect 2x for better visibility
	scale = Vector2(2.0, 2.0)
	
	# Clear previous effects
	_particles.clear()
	_slashes.clear()
	_symbols.clear()
	
	# Spawn effect based on theme
	_spawn_themed_effect()
	_play_swap_sound()
	queue_redraw()


func _spawn_themed_effect() -> void:
	match _theme:
		"sword_slash":
			_spawn_sword_slashes()
		"snowflake":
			_spawn_snowflakes()
		"holy_glow":
			_spawn_holy_particles()
		"dark_energy":
			_spawn_dark_energy()
		"clock":
			_spawn_clock_effect()
		"code":
			_spawn_code_effect()
		"hearts":
			_spawn_hearts()
		"kingly":
			_spawn_kingly_effect()
		"mech":
			_spawn_mech_effect()
		"wind":
			_spawn_wind_effect()
		_:
			_spawn_default_particles()


func _spawn_sword_slashes() -> void:
	# Red sword slashes in X pattern
	for i in range(3):
		var angle := -PI/4 + (PI/4) * i
		_slashes.append({
			"angle": angle,
			"length": 0.0,
			"max_length": 80.0 + randf() * 20.0,
			"width": 8.0,
			"alpha": 1.0
		})


func _spawn_snowflakes() -> void:
	# Frosted snowflake particles floating outward
	for i in range(12):
		var angle := (TAU / 12) * i + randf() * 0.3
		_particles.append({
			"pos": Vector2.ZERO,
			"vel": Vector2.from_angle(angle) * randf_range(60, 120),
			"size": randf_range(8, 14),
			"rotation": randf() * TAU,
			"alpha": 1.0,
			"type": "snowflake"
		})


func _spawn_holy_particles() -> void:
	# Golden holy glow with rising light particles
	for i in range(16):
		var angle := (TAU / 16) * i
		var dist := randf_range(20, 50)
		_particles.append({
			"pos": Vector2.from_angle(angle) * dist,
			"vel": Vector2(0, -randf_range(40, 80)),
			"size": randf_range(4, 8),
			"alpha": 1.0,
			"type": "light"
		})


func _spawn_dark_energy() -> void:
	# Black and purple swirling energy
	for i in range(20):
		var angle := randf() * TAU
		var dist := randf_range(10, 40)
		_particles.append({
			"pos": Vector2.from_angle(angle) * dist,
			"vel": Vector2.from_angle(angle + PI/2) * randf_range(80, 150),
			"size": randf_range(5, 10),
			"alpha": 1.0,
			"type": "energy",
			"is_dark": randf() < 0.5
		})


func _spawn_clock_effect() -> void:
	# Clock hands and gear symbols
	_symbols.append({"type": "clock_face", "alpha": 1.0, "rotation": 0.0})
	for i in range(8):
		var angle := (TAU / 8) * i
		_particles.append({
			"pos": Vector2.from_angle(angle) * 45,
			"vel": Vector2.from_angle(angle) * 30,
			"size": 6,
			"alpha": 1.0,
			"type": "gear"
		})


func _spawn_code_effect() -> void:
	# Falling code characters like Cecil's burst
	for i in range(24):
		var x := randf_range(-60, 60)
		var y := randf_range(-80, 0)
		_particles.append({
			"pos": Vector2(x, y),
			"vel": Vector2(0, randf_range(100, 200)),
			"char": ["0", "1", "█", "▓", "░", "<", ">"][randi() % 7],
			"alpha": randf_range(0.5, 1.0),
			"type": "code"
		})


func _spawn_hearts() -> void:
	# Purple hearts floating upward
	for i in range(10):
		var angle := (TAU / 10) * i + randf() * 0.2
		var dist := randf_range(15, 35)
		_particles.append({
			"pos": Vector2.from_angle(angle) * dist,
			"vel": Vector2(randf_range(-20, 20), -randf_range(60, 100)),
			"size": randf_range(10, 18),
			"alpha": 1.0,
			"type": "heart"
		})


func _spawn_kingly_effect() -> void:
	# Golden crown symbol with radiating light
	_symbols.append({"type": "crown", "alpha": 1.0, "scale": 0.5})
	for i in range(12):
		var angle := (TAU / 12) * i
		_particles.append({
			"pos": Vector2.ZERO,
			"vel": Vector2.from_angle(angle) * randf_range(100, 160),
			"size": randf_range(4, 7),
			"alpha": 1.0,
			"type": "sparkle"
		})


func _spawn_mech_effect() -> void:
	# Green mechanical hexagons and circuit lines
	for i in range(6):
		var angle := (TAU / 6) * i
		_particles.append({
			"pos": Vector2.ZERO,
			"vel": Vector2.from_angle(angle) * 120,
			"size": 12,
			"alpha": 1.0,
			"type": "hexagon"
		})
	# Circuit lines
	for i in range(4):
		_slashes.append({
			"angle": randf() * TAU,
			"length": 0.0,
			"max_length": 60,
			"width": 2.0,
			"alpha": 1.0
		})


func _spawn_wind_effect() -> void:
	# Grey swirling wind trails
	for i in range(15):
		var angle := randf() * TAU
		var dist := randf_range(5, 30)
		_particles.append({
			"pos": Vector2.from_angle(angle) * dist,
			"vel": Vector2.from_angle(angle + PI/3) * randf_range(100, 180),
			"size": randf_range(3, 6),
			"alpha": 0.8,
			"trail_length": randf_range(15, 30),
			"type": "wind"
		})


func _spawn_default_particles() -> void:
	for i in range(16):
		var angle := (TAU / 16) * i + randf() * 0.3
		_particles.append({
			"pos": Vector2.ZERO,
			"vel": Vector2.from_angle(angle) * randf_range(100, 200),
			"size": randf_range(5, 10),
			"alpha": 1.0,
			"type": "default"
		})


func _play_swap_sound() -> void:
	var audio := AudioStreamPlayer.new()
	audio.name = "SwapSFX"
	audio.volume_db = -5.0
	audio.bus = "SFX"
	# Use existing select sound as swap sound
	var sound = load("res://assets/sounds/sfx/ui/select.wav")
	if sound:
		audio.stream = sound
		add_child(audio)
		audio.play()
		audio.finished.connect(audio.queue_free)


func _process(delta: float) -> void:
	if not _is_active:
		return
	
	_elapsed += delta
	var t := _elapsed / EFFECT_DURATION
	
	# Update particles
	for p in _particles:
		p["pos"] += p["vel"] * delta
		p["vel"] *= 0.92
		p["alpha"] = max(0.0, 1.0 - t * 1.2)
	
	# Update slashes
	for s in _slashes:
		s["length"] = min(s["length"] + delta * 400, s["max_length"])
		s["alpha"] = max(0.0, 1.0 - t * 1.5)
	
	# Update symbols
	for sym in _symbols:
		sym["alpha"] = max(0.0, 1.0 - t * 1.3)
		if "scale" in sym:
			sym["scale"] = min(sym["scale"] + delta * 3, 1.2)
		if "rotation" in sym:
			sym["rotation"] += delta * 3
	
	queue_redraw()
	
	if t >= 1.0:
		_is_active = false


func _draw() -> void:
	if not _is_active:
		return
	
	var t := _elapsed / EFFECT_DURATION
	
	# Central flash
	if t < 0.3:
		var flash_alpha := (1.0 - t / 0.3) * 0.8
		var flash_color := Color(_character_color.r * 1.5, _character_color.g * 1.5, _character_color.b * 1.5, flash_alpha)
		draw_circle(Vector2.ZERO, 40 + t * 60, flash_color)
	
	# Draw theme-specific elements
	match _theme:
		"sword_slash":
			_draw_sword_slashes()
		"snowflake":
			_draw_snowflakes()
		"holy_glow":
			_draw_holy_glow()
		"dark_energy":
			_draw_dark_energy()
		"clock":
			_draw_clock()
		"code":
			_draw_code()
		"hearts":
			_draw_hearts()
		"kingly":
			_draw_kingly()
		"mech":
			_draw_mech()
		"wind":
			_draw_wind()
		_:
			_draw_default()


func _draw_sword_slashes() -> void:
	for s in _slashes:
		if s["alpha"] <= 0:
			continue
		var col := Color(_character_color.r * 1.3, _character_color.g * 0.8, _character_color.b * 0.8, s["alpha"])
		var dir := Vector2.from_angle(s["angle"])
		var start: Vector2 = -dir * s["length"] * 0.5
		var end: Vector2 = dir * s["length"] * 0.5
		draw_line(start, end, col, s["width"], true)
		# Bright core
		var core_col := Color(1.0, 0.9, 0.9, s["alpha"] * 0.8)
		draw_line(start * 0.5, end * 0.5, core_col, s["width"] * 0.4, true)


func _draw_snowflakes() -> void:
	for p in _particles:
		if p["alpha"] <= 0:
			continue
		var col := Color(0.9, 0.95, 1.0, p["alpha"])
		_draw_snowflake_shape(p["pos"], p["size"], p["rotation"], col)


func _draw_snowflake_shape(pos: Vector2, size: float, rot: float, col: Color) -> void:
	# 6-pointed snowflake
	for i in range(6):
		var angle := rot + (TAU / 6) * i
		var dir := Vector2.from_angle(angle)
		draw_line(pos, pos + dir * size, col, 2.0, true)
		# Branch
		var branch_pos := pos + dir * size * 0.6
		for j in [-1, 1]:
			var branch_dir := Vector2.from_angle(angle + j * PI/4)
			draw_line(branch_pos, branch_pos + branch_dir * size * 0.3, col, 1.5, true)


func _draw_holy_glow() -> void:
	# Radial glow
	var glow_col := Color(_character_color.r, _character_color.g, _character_color.b, 0.4 * (1.0 - _elapsed / EFFECT_DURATION))
	for i in range(3):
		var r := 30 + i * 20 + _elapsed * 40
		draw_arc(Vector2.ZERO, r, 0, TAU, 32, glow_col, 3.0 - i * 0.5)
	
	# Light particles
	for p in _particles:
		if p["alpha"] <= 0:
			continue
		var col := Color(1.0, 0.95, 0.7, p["alpha"])
		draw_circle(p["pos"], p["size"], col)


func _draw_dark_energy() -> void:
	for p in _particles:
		if p["alpha"] <= 0:
			continue
		var col: Color
		if p.get("is_dark", false):
			col = Color(0.1, 0.0, 0.15, p["alpha"])
		else:
			col = Color(0.6, 0.2, 0.8, p["alpha"])
		draw_circle(p["pos"], p["size"], col)


func _draw_clock() -> void:
	# Clock face
	for sym in _symbols:
		if sym["type"] == "clock_face" and sym["alpha"] > 0:
			var col := Color(_character_color.r, _character_color.g, _character_color.b, sym["alpha"] * 0.6)
			draw_arc(Vector2.ZERO, 50, 0, TAU, 32, col, 3.0)
			# Hour marks
			for i in range(12):
				var angle := (TAU / 12) * i - PI/2
				var start := Vector2.from_angle(angle) * 42
				var end := Vector2.from_angle(angle) * 50
				draw_line(start, end, col, 2.0)
			# Hands
			var hand_col := Color(1.0, 0.9, 0.7, sym["alpha"])
			draw_line(Vector2.ZERO, Vector2.from_angle(sym["rotation"]) * 35, hand_col, 3.0)
			draw_line(Vector2.ZERO, Vector2.from_angle(sym["rotation"] * 0.5 - PI/2) * 25, hand_col, 4.0)
	
	# Gear particles
	for p in _particles:
		if p["alpha"] <= 0:
			continue
		var col := Color(0.8, 0.6, 0.3, p["alpha"])
		_draw_gear(p["pos"], p["size"], col)


func _draw_gear(pos: Vector2, size: float, col: Color) -> void:
	draw_circle(pos, size * 0.5, col)
	for i in range(6):
		var angle := (TAU / 6) * i
		var dir := Vector2.from_angle(angle)
		draw_line(pos + dir * size * 0.3, pos + dir * size, col, 2.0)


func _draw_code() -> void:
	var font := ThemeDB.fallback_font
	for p in _particles:
		if p["alpha"] <= 0:
			continue
		var col := Color(0.2, 0.9, 1.0, p["alpha"])
		draw_string(font, p["pos"], p["char"], HORIZONTAL_ALIGNMENT_CENTER, -1, 14, col)


func _draw_hearts() -> void:
	for p in _particles:
		if p["alpha"] <= 0:
			continue
		var col := Color(0.8, 0.3, 0.9, p["alpha"])
		_draw_heart(p["pos"], p["size"], col)


func _draw_heart(pos: Vector2, size: float, col: Color) -> void:
	var points: PackedVector2Array = []
	for i in range(32):
		var t := float(i) / 31.0 * TAU
		var x := 16 * pow(sin(t), 3)
		var y := -(13 * cos(t) - 5 * cos(2*t) - 2 * cos(3*t) - cos(4*t))
		points.append(pos + Vector2(x, y) * size / 16.0)
	draw_colored_polygon(points, col)


func _draw_kingly() -> void:
	# Crown symbol
	for sym in _symbols:
		if sym["alpha"] > 0:
			var s: float = sym.get("scale", 1.0) * 25
			var col := Color(1.0, 0.85, 0.3, sym["alpha"])
			# Crown shape
			var points: PackedVector2Array = [
				Vector2(-s, s * 0.5),
				Vector2(-s, -s * 0.3),
				Vector2(-s * 0.5, s * 0.1),
				Vector2(0, -s * 0.6),
				Vector2(s * 0.5, s * 0.1),
				Vector2(s, -s * 0.3),
				Vector2(s, s * 0.5)
			]
			draw_colored_polygon(points, col)
	
	# Sparkles
	for p in _particles:
		if p["alpha"] <= 0:
			continue
		var col := Color(1.0, 0.9, 0.5, p["alpha"])
		_draw_sparkle(p["pos"], p["size"], col)


func _draw_sparkle(pos: Vector2, size: float, col: Color) -> void:
	for i in range(4):
		var angle := (TAU / 4) * i + PI/4
		var dir := Vector2.from_angle(angle)
		draw_line(pos, pos + dir * size, col, 2.0)


func _draw_mech() -> void:
	# Hexagons
	for p in _particles:
		if p["alpha"] <= 0:
			continue
		var col := Color(0.3, 0.95, 0.4, p["alpha"])
		_draw_hexagon(p["pos"], p["size"], col)
	
	# Circuit lines
	for s in _slashes:
		if s["alpha"] <= 0:
			continue
		var col := Color(0.2, 0.8, 0.3, s["alpha"])
		var dir := Vector2.from_angle(s["angle"])
		draw_line(Vector2.ZERO, dir * s["length"], col, s["width"])


func _draw_hexagon(pos: Vector2, size: float, col: Color) -> void:
	var points: PackedVector2Array = []
	for i in range(6):
		var angle := (TAU / 6) * i - PI/6
		points.append(pos + Vector2.from_angle(angle) * size)
	draw_colored_polygon(points, col)


func _draw_wind() -> void:
	for p in _particles:
		if p["alpha"] <= 0:
			continue
		var col := Color(0.75, 0.8, 0.85, p["alpha"] * 0.7)
		# Wind trail
		var trail_dir: Vector2 = p["vel"].normalized()
		var trail_len: float = p.get("trail_length", 15.0)
		draw_line(p["pos"] - trail_dir * trail_len, p["pos"], col, p["size"], true)
		draw_circle(p["pos"], p["size"] * 0.6, Color(0.9, 0.92, 0.95, p["alpha"]))


func _draw_default() -> void:
	for p in _particles:
		if p["alpha"] <= 0:
			continue
		var col := Color(_character_color.r * 1.3, _character_color.g * 1.3, _character_color.b * 1.3, p["alpha"])
		draw_circle(p["pos"], p["size"], col)
