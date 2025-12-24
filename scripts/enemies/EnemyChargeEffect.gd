extends Node2D

# Visual charging effect that appears on enemy before firing laser
# Shows a growing red glow that intensifies as charge completes

const CHARGE_COLOR := Color(3.0, 0.1, 0.1, 1.0) # Deep red (HDR match laser)
const CHARGE_GLOW_COLOR := Color(2.0, 0.2, 0.1, 0.7) # Red glow (HDR)
const CHARGE_CORE_COLOR := Color(5.0, 0.5, 0.5, 1.0) # Hot core (HDR match core)
const CHARGE_FLASH_COLOR := Color(8.0, 2.0, 2.0, 1.0) # Intense Flash (HDR)

var _charge_duration := 1.0
var _progress := 0.0
var _age := 0.0
var _is_active := false

# Visual components
var _outer_glow: Sprite2D = null
var _mid_glow: Sprite2D = null
var _core_glow: Sprite2D = null
var _core_sprite: Sprite2D = null
var _particles: Array = []
var _glow_texture: Texture2D = null
var _rng := RandomNumberGenerator.new()

# Animation
const PARTICLE_COUNT := 6
const PULSE_SPEED := 12.0

func _ready() -> void:
	_rng.randomize()
	_glow_texture = _create_radial_glow_texture(64)
	_create_visuals()

func start_charge(duration: float) -> void:
	_charge_duration = max(duration, 0.1)
	_progress = 0.0
	_age = 0.0
	_is_active = true

func set_progress(p: float) -> void:
	_progress = clampf(p, 0.0, 1.0)

func _process(delta: float) -> void:
	if not _is_active:
		return
	
	_age += delta
	_update_visuals()
	_update_particles(delta)
	queue_redraw()

func _create_visuals() -> void:
	# Large outer glow (ambient)
	_outer_glow = Sprite2D.new()
	_outer_glow.texture = _glow_texture
	_outer_glow.centered = true
	_outer_glow.modulate = Color(CHARGE_GLOW_COLOR.r, CHARGE_GLOW_COLOR.g, CHARGE_GLOW_COLOR.b, 0.0)
	_outer_glow.scale = Vector2(0.3, 0.3)
	var outer_mat := CanvasItemMaterial.new()
	outer_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_outer_glow.material = outer_mat
	add_child(_outer_glow)
	
	# Mid glow layer
	_mid_glow = Sprite2D.new()
	_mid_glow.texture = _glow_texture
	_mid_glow.centered = true
	_mid_glow.modulate = Color(CHARGE_COLOR.r, CHARGE_COLOR.g, CHARGE_COLOR.b, 0.0)
	_mid_glow.scale = Vector2(0.2, 0.2)
	var mid_mat := CanvasItemMaterial.new()
	mid_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_mid_glow.material = mid_mat
	add_child(_mid_glow)
	
	# Core glow (bright center)
	_core_glow = Sprite2D.new()
	_core_glow.texture = _glow_texture
	_core_glow.centered = true
	_core_glow.modulate = Color(CHARGE_CORE_COLOR.r, CHARGE_CORE_COLOR.g, CHARGE_CORE_COLOR.b, 0.0)
	_core_glow.scale = Vector2(0.1, 0.1)
	var core_mat := CanvasItemMaterial.new()
	core_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_core_glow.material = core_mat
	add_child(_core_glow)
	
	# Solid core center
	_core_sprite = Sprite2D.new()
	_core_sprite.texture = _glow_texture
	_core_sprite.centered = true
	_core_sprite.modulate = Color(1.0, 0.9, 0.8, 0.0)
	_core_sprite.scale = Vector2(0.05, 0.05)
	add_child(_core_sprite)
	
	# Create converging particles
	for i in range(PARTICLE_COUNT):
		var particle := Sprite2D.new()
		particle.texture = _glow_texture
		particle.centered = true
		particle.modulate = Color(CHARGE_COLOR.r, CHARGE_COLOR.g, CHARGE_COLOR.b, 0.0)
		particle.scale = Vector2(0.08, 0.08)
		var p_mat := CanvasItemMaterial.new()
		p_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		particle.material = p_mat
		add_child(particle)
		_particles.append({
			"node": particle,
			"angle": (TAU / PARTICLE_COUNT) * i,
			"distance": 40.0,
			"speed": _rng.randf_range(0.8, 1.2)
		})

func _update_visuals() -> void:
	# Eased progress for smooth growth
	var eased := _ease_out_quad(_progress)
	var pulse := sin(_age * PULSE_SPEED) * 0.15 + 0.85
	
	# Outer glow grows and intensifies
	if _outer_glow:
		var outer_scale := (0.3 + eased * 1.2) * 2.0
		_outer_glow.scale = Vector2.ONE * outer_scale * pulse
		_outer_glow.modulate.a = eased * 0.6 * pulse
	
	# Mid glow
	if _mid_glow:
		var mid_scale := (0.2 + eased * 0.8) * 2.0
		_mid_glow.scale = Vector2.ONE * mid_scale * pulse
		_mid_glow.modulate.a = eased * 0.8 * pulse
	
	# Core glow intensifies
	if _core_glow:
		var core_scale := (0.1 + eased * 0.5) * 2.0
		_core_glow.scale = Vector2.ONE * core_scale * pulse
		_core_glow.modulate.a = eased * 0.9
		# Color shifts toward white as charge completes
		var core_color := CHARGE_CORE_COLOR.lerp(CHARGE_FLASH_COLOR, eased * 0.5)
		_core_glow.modulate = Color(core_color.r, core_color.g, core_color.b, eased * 0.9)
	
	# Solid core
	if _core_sprite:
		var solid_scale := (0.05 + eased * 0.25) * 2.0
		_core_sprite.scale = Vector2.ONE * solid_scale
		_core_sprite.modulate.a = eased

func _update_particles(delta: float) -> void:
	for i in range(_particles.size()):
		var p: Dictionary = _particles[i]
		var node: Sprite2D = p["node"]
		if not node:
			continue
		
		# Particles spiral inward as charge progresses
		var base_distance := 40.0 * (1.0 - _progress * 0.9)
		var wobble := sin(_age * 8.0 + p["angle"] * 2.0) * 5.0
		p["distance"] = base_distance + wobble
		
		# Rotate around center
		p["angle"] += delta * (2.0 + _progress * 4.0) * p["speed"]
		
		var pos := Vector2(
			cos(p["angle"]) * p["distance"],
			sin(p["angle"]) * p["distance"]
		)
		node.position = pos
		
		# Fade in and intensify
		node.modulate.a = _progress * 0.8
		node.scale = Vector2.ONE * (0.06 + _progress * 0.1)
		
		# Color intensifies
		var p_color := CHARGE_COLOR.lerp(CHARGE_CORE_COLOR, _progress * 0.6)
		node.modulate = Color(p_color.r, p_color.g, p_color.b, _progress * 0.8)
		
		_particles[i] = p

func _ease_out_quad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)

func _draw() -> void:
	if not _is_active or _progress < 0.1:
		return
	
	# Draw electric arcs/crackles as charge builds
	var arc_count := int(3 + _progress * 4)
	var arc_alpha := _progress * 0.7
	
	for i in range(arc_count):
		var angle := _rng.randf() * TAU
		var length := 15.0 + _progress * 25.0
		var start := Vector2.ZERO
		var end := Vector2(cos(angle), sin(angle)) * length
		
		# Jagged arc
		var points: PackedVector2Array = [start]
		var segments := 3
		for j in range(1, segments):
			var t := float(j) / float(segments)
			var pos := start.lerp(end, t)
			var offset := Vector2(
				_rng.randf_range(-6, 6),
				_rng.randf_range(-6, 6)
			) * _progress
			points.append(pos + offset)
		points.append(end)
		
		# Draw the arc
		var arc_color := Color(1.0, 0.3, 0.2, arc_alpha)
		for k in range(points.size() - 1):
			draw_line(points[k], points[k + 1], arc_color, 1.5 + _progress, true)

func _create_radial_glow_texture(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var max_radius: float = minf(center.x, center.y)
	
	for y in size:
		for x in size:
			var pos := Vector2(x + 0.5, y + 0.5)
			var distance: float = pos.distance_to(center)
			var normalized: float = distance / max_radius
			var alpha := 0.0
			if normalized < 1.0:
				var falloff := pow(1.0 - normalized, 2.4)
				alpha = clampf(falloff, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	
	return ImageTexture.create_from_image(img)
