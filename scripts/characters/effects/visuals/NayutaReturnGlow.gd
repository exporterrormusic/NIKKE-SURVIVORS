# Golden aura shown on Nayuta while RETURN UNTO ME's damage buff is active.
#
# Rendered additively on the environment EffectsLayer so it pierces night
# darkness (the layer's inverse-of-night modulate makes it glow brighter the
# darker it gets). Drawn as an OUTER ring halo with a hollow centre - it bleeds
# golden light around the silhouette's edges and breathes in/out, rather than a
# filled disc that covers the sprite. Additive blend means it only ever adds
# light, so the sprite is never obscured, just rim-lit.
extends Node2D

var _time: float = 0.0
var _active: bool = true
var _fade: float = 0.0  # ramps 0->1 on activate, 1->0 on deactivate
const FADE_SPEED := 2.4  # ~0.4s fade in/out

# Aura geometry
const SILHOUETTE_R := 42.0  # roughly the player sprite's radius
const HALO_REACH := 34.0    # how far the aura bleeds outward
const RINGS := 16

# Edge sparkle system
var _sparkles: Array = []
const MAX_SPARKLES := 40
const SPARKLE_SPAWN_RATE := 0.025
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
	z_index = 50
	# Additive + unshaded so the aura adds golden light without obscuring the
	# sprite, and brightens at night via the EffectsLayer's inverse modulate.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	light_mask = 0
	set_meta("owner_player", get_parent())
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_parent = get_parent()
			if saved_parent:
				saved_parent.remove_child(self)
			effects.add_child(self)
			z_as_relative = false
			z_index = 500

## Toggled by NayutaController when the buff starts/ends.
func set_active(active: bool) -> void:
	_active = active

func _process(delta: float) -> void:
	# Track the player (we've been reparented to the EffectsLayer)
	if has_meta("owner_player"):
		var p = get_meta("owner_player")
		if is_instance_valid(p):
			global_position = p.global_position
		else:
			# Player is gone - tear down even without a controller cleanup
			_active = false

	_time += delta

	# Fade in while active, out when deactivated
	if _active:
		_fade = minf(1.0, _fade + delta * FADE_SPEED)
	else:
		_fade = maxf(0.0, _fade - delta * FADE_SPEED)

	# Spawn edge sparkles only while active
	_sparkle_timer += delta
	if _active and _sparkle_timer >= SPARKLE_SPAWN_RATE and _sparkles.size() < MAX_SPARKLES:
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
			s.rotation += s.rot_speed * delta
	for i in range(to_remove.size() - 1, -1, -1):
		_sparkles.remove_at(to_remove[i])

	# Self-free once fully faded out and no sparkles remain
	if not _active and _fade <= 0.0 and _sparkles.is_empty():
		queue_free()
		return

	queue_redraw()

func _spawn_sparkle() -> void:
	var s = Sparkle.new()
	# Spawn around the silhouette edge so the sparkles read as an edge aura
	var ang := randf() * TAU
	var r := randf_range(SILHOUETTE_R - 6.0, SILHOUETTE_R + HALO_REACH * 0.6)
	s.pos = Vector2(cos(ang), sin(ang)) * r
	# Drift gently outward and up
	s.vel = Vector2(cos(ang), sin(ang)) * randf_range(6.0, 22.0) + Vector2(0, randf_range(-22.0, -6.0))
	s.life = randf_range(0.4, 0.8)
	s.max_life = s.life
	s.size = randf_range(2.0, 4.5)
	s.rotation = randf() * TAU
	s.rot_speed = randf_range(-5.0, 5.0)
	_sparkles.append(s)

func _draw() -> void:
	# Breathing aura that bleeds in and out
	var breathe := 0.5 + 0.5 * sin(_time * 2.2)
	var base_alpha := (0.16 + 0.12 * breathe) * _fade
	if base_alpha > 0.001:
		var reach := HALO_REACH + 8.0 * breathe
		# Soft outer halo: thin rings from just inside the silhouette outward,
		# brightest at the edge and fading both ways. Hollow centre = sprite shows.
		for i in range(RINGS):
			var t := float(i) / float(RINGS - 1)  # 0 (inner) -> 1 (outer)
			var radius := SILHOUETTE_R - 8.0 + t * (reach + 8.0)
			var fall := pow(1.0 - t, 1.6)  # bright at the rim, fading outward
			var a := base_alpha * fall
			var col := Color(1.0, 0.8 + 0.12 * (1.0 - t), 0.32 + 0.22 * (1.0 - t), a)
			draw_arc(Vector2.ZERO, radius, 0, TAU, 44, col, 3.5)

	# Edge sparkles (4-pointed stars)
	for s in _sparkles:
		var life_ratio: float = s.life / s.max_life
		var a: float = life_ratio * _fade
		var sz: float = s.size * (0.6 + life_ratio * 0.4)
		_draw_sparkle(s.pos, sz, s.rotation, a)

func _draw_sparkle(pos: Vector2, size: float, rot: float, alpha: float) -> void:
	draw_circle(pos, size * 0.6, Color(1.0, 0.9, 0.5, alpha * 0.4))
	draw_circle(pos, size * 0.35, Color(1.0, 1.0, 0.9, alpha))
	var ray_length := size * 1.5
	var ray_width := size * 0.2
	for i in range(4):
		var angle := rot + i * PI * 0.5
		var dir := Vector2(cos(angle), sin(angle))
		var tip := pos + dir * ray_length
		draw_line(pos, tip, Color(1.0, 0.9, 0.5, alpha * 0.4), ray_width * 1.5)
		draw_line(pos, tip, Color(1.0, 0.98, 0.85, alpha), ray_width)
