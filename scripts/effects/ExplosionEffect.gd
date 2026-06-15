extends Node2D
class_name ExplosionEffect

@export var radius: float = 80.0
@export var base_color: Color = Color(1.0, 0.52, 0.24, 0.7)
@export var duration: float = 0.55
@export var ring_thickness: float = 6.0
@export var glow_color: Color = Color(1.0, 0.6, 0.26, 0.6)
@export var core_color: Color = Color(1.0, 0.92, 0.74, 0.8)
@export var shockwave_color: Color = Color(1.0, 0.78, 0.3, 0.7)
@export var shockwave_thickness: float = 14.0
@export var spark_color: Color = Color(1.0, 0.76, 0.42, 0.7)
@export var spark_count: int = 16
## Warm fire hue used by the lobes/embers; overridable for tinted blasts (e.g.
## Scarlet's purple "In One Strike"). Restored to the default on pool reuse.
@export var flame_color: Color = Color(1.0, 0.62, 0.24)

# Palette defaults, restored in reset() so pooled reuse never inherits a tint.
const DEFAULT_BASE := Color(1.0, 0.52, 0.24, 0.7)
const DEFAULT_GLOW := Color(1.0, 0.6, 0.26, 0.6)
const DEFAULT_CORE := Color(1.0, 0.92, 0.74, 0.8)
const DEFAULT_SHOCK := Color(1.0, 0.78, 0.3, 0.7)
const DEFAULT_SPARK := Color(1.0, 0.76, 0.42, 0.7)
const DEFAULT_FLAME := Color(1.0, 0.62, 0.24)

const FOREGROUND_Z_INDEX := 915
const FIRE_LOBE_COUNT := 8
const SMOKE_PUFF_COUNT := 6

var _elapsed := 0.0
## Cheap render path for high-volume explosions (turret/barrage missiles): a single
## cached radial-glow texture + core + shockwave (~3 draws) instead of ~90 primitives.
var simple := false
var _rng := RandomNumberGenerator.new()
var _rotation_offset := 0.0
var _fire_lobes: Array = []
var _smoke_puffs: Array = []
var _ember_sparks: Array = []
var _spark_lengths: Array = []
var _spark_angle_offset: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	# One-time material setup (persists across pool reuse).
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	_activate()

## Re-initialize for a fresh explosion. Also called by ProjectileCache on pool reuse.
func reset() -> void:
	simple = false
	# Restore the warm default palette (a previous user may have tinted this one).
	base_color = DEFAULT_BASE
	glow_color = DEFAULT_GLOW
	core_color = DEFAULT_CORE
	shockwave_color = DEFAULT_SHOCK
	spark_color = DEFAULT_SPARK
	flame_color = DEFAULT_FLAME
	_activate()

## Recolour this blast to Scarlet's purple palette (used by her skill effects).
## reset() restores the warm default on pool reuse, so other blasts stay orange.
func apply_scarlet_tint() -> void:
	base_color = Color(0.66, 0.24, 0.95, 0.75)
	glow_color = Color(0.6, 0.3, 1.0, 0.65)
	core_color = Color(0.93, 0.84, 1.0, 0.9)
	shockwave_color = Color(0.82, 0.5, 1.0, 0.75)
	spark_color = Color(0.88, 0.6, 1.0, 0.75)
	flame_color = Color(0.74, 0.4, 1.0)


func _activate() -> void:
	z_as_relative = false
	z_index = FOREGROUND_Z_INDEX
	_elapsed = 0.0
	_rng.randomize()
	_rotation_offset = _rng.randf_range(0.0, TAU)
	_initialize_fire_lobes()
	_initialize_smoke_puffs()
	_initialize_sparks()
	set_process(true)
	queue_redraw()
	# Assign to effects layer to avoid night darkening (and for Z sorting)
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	if get_parent() == null:
		return
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 915 # FOREGROUND_Z_INDEX

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		ProjectileCache.return_to_pool(self)
		return
	# Reduce redraw frequency for better performance (30 FPS is enough for explosions)
	if Engine.get_process_frames() % 2 == 0:
		queue_redraw()

func _draw() -> void:
	if duration <= 0.0:
		return
	var progress := clampf(_elapsed / duration, 0.0, 1.0)
	var fade := 1.0 - progress
	if simple:
		_draw_simple(progress, fade)
		return
	_draw_fire_layers(progress, fade)
	_draw_core_flare(progress, fade)
	_draw_fire_lobes(progress, fade)
	_draw_shockwave(progress, fade)
	_draw_smoke(progress, fade)
	_draw_sparks(progress, fade)
	_draw_embers(progress, fade)
	_draw_debris(progress, fade)

## Cheap explosion: one cached radial-glow texture (additive) + a core + a shockwave
## ring. ~3 draw calls vs ~90 for the full procedural version. Used for the many
## concurrent turret/barrage missile explosions so they don't tank the framerate.
func _draw_simple(progress: float, fade: float) -> void:
	# Outer glow (cached radial texture) sized to match the full explosion's spread.
	var tex: Texture2D = TextureCache.get_light_texture_64()
	var glow_r := radius * (1.0 + 0.7 * progress)
	var glow_a := clampf(glow_color.a * (1.0 - progress * progress), 0.0, 1.0)
	if tex and glow_a > 0.0:
		draw_texture_rect(tex, Rect2(-glow_r, -glow_r, glow_r * 2.0, glow_r * 2.0), false,
			Color(glow_color.r, glow_color.g, glow_color.b, glow_a))
	# Bright core.
	var core_strength := clampf(1.0 - pow(progress, 1.5), 0.0, 1.0)
	if core_strength > 0.0:
		draw_circle(Vector2.ZERO, radius * 0.5 * core_strength,
			Color(core_color.r, core_color.g, core_color.b, core_color.a * core_strength))
		draw_circle(Vector2.ZERO, radius * 0.28 * core_strength, Color(1.0, 0.98, 0.86, core_strength))
	# A few fireball lobes spreading outward (the "fire" read of the original).
	var lobe_a := clampf(0.7 * fade * (1.0 - progress * 0.5), 0.0, 0.8)
	if lobe_a > 0.0:
		var travel := radius * lerpf(0.3, 0.95, progress)
		var lobe_r := radius * 0.34 * (1.0 - progress * 0.45)
		for i in range(6):
			var ang := _rotation_offset + TAU * float(i) / 6.0
			draw_circle(Vector2(cos(ang), sin(ang)) * travel, lobe_r, Color(flame_color.r, flame_color.g, flame_color.b, lobe_a))
	# Shockwave ring.
	var shock_a := shockwave_color.a * fade
	if shock_a > 0.0:
		draw_arc(Vector2.ZERO, radius * (0.85 + 0.6 * progress), 0.0, TAU, 28,
			Color(shockwave_color.r, shockwave_color.g, shockwave_color.b, shock_a), max(2.0, shockwave_thickness * 0.7))

func _draw_fire_layers(progress: float, fade: float) -> void:
	var primary_alpha := glow_color.a * clampf(1.0 - pow(progress, 1.6), 0.0, 1.0)
	var primary_color := Color(glow_color.r, glow_color.g, glow_color.b, primary_alpha)
	var primary_radius := radius * (0.85 + 0.55 * progress)
	_draw_radial_glow(primary_radius, primary_color, 0.7, 6)
	var ember_color := Color(flame_color.r, flame_color.g, flame_color.b, 0.45 * fade)
	_draw_radial_glow(radius * (0.58 + 0.28 * progress), ember_color, 0.5, 4)

func _draw_core_flare(progress: float, _fade: float) -> void:
	var fire_strength := clampf(1.0 - pow(progress, 1.5), 0.0, 1.0)
	var core_radius := radius * (0.28 + 0.35 * fire_strength)
	var center_color := Color(core_color.r, core_color.g, core_color.b, core_color.a * fire_strength)
	draw_circle(Vector2.ZERO, core_radius, center_color)
	var hotspot := Color(1.0, 0.96, 0.84, core_color.a * fire_strength * 0.85)
	draw_circle(Vector2.ZERO, core_radius * 0.55, hotspot)

func _draw_fire_lobes(progress: float, fade: float) -> void:
	if _fire_lobes.is_empty():
		return
	for lobe in _fire_lobes:
		var angle: float = float(lobe.get("angle", 0.0))
		var intensity: float = float(lobe.get("intensity", 1.0))
		var lobe_width: float = float(lobe.get("width", 1.0))
		var delay: float = float(lobe.get("delay", 0.0))
		var lobe_progress := clampf((progress - delay) / max(0.001, 1.0 - delay), 0.0, 1.0)
		if lobe_progress <= 0.0:
			continue
		var dir := Vector2(cos(angle), sin(angle))
		var travel := lerpf(radius * 0.22, radius * 0.95, lobe_progress)
		var center := dir * travel
		var lobe_radius := radius * lerpf(0.22, 0.55, lobe_progress) * intensity
		var lobe_alpha := clampf(0.65 * fade * (1.0 - lobe_progress) * intensity, 0.0, 0.8)
		if lobe_alpha <= 0.0:
			continue
		var fire_color := Color(flame_color.r, flame_color.g, flame_color.b, lobe_alpha)
		draw_circle(center, lobe_radius * lobe_width, fire_color)

func _draw_shockwave(progress: float, fade: float) -> void:
	var ring_alpha := base_color.a * fade * 0.85
	var ring_radius := radius * (0.8 + 0.3 * progress)
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 72, Color(base_color.r, base_color.g, base_color.b, ring_alpha), max(2.0, ring_thickness))
	var shock_alpha := shockwave_color.a * fade
	var shock_radius := radius * (0.96 + 0.78 * progress)
	draw_arc(Vector2.ZERO, shock_radius, 0.0, TAU, 64, Color(shockwave_color.r, shockwave_color.g, shockwave_color.b, shock_alpha), max(2.0, shockwave_thickness))

func _draw_smoke(progress: float, fade: float) -> void:
	if _smoke_puffs.is_empty():
		return
	var smoke_start := 0.18
	var smoke_progress := clampf((progress - smoke_start) / max(0.001, 1.0 - smoke_start), 0.0, 1.0)
	if smoke_progress <= 0.0:
		return
	var smoke_fade := clampf(1.0 - pow(smoke_progress, 1.6), 0.0, 1.0) * fade
	for puff in _smoke_puffs:
		var angle: float = float(puff.get("angle", 0.0))
		var puff_scale: float = float(puff.get("scale", 1.0))
		var offset: float = float(puff.get("offset", 0.7))
		var drift: float = float(puff.get("drift", 0.0))
		var tint: float = float(puff.get("tint", 0.0))
		var dir := Vector2(cos(angle + drift * smoke_progress), sin(angle + drift * smoke_progress))
		var distance := radius * lerpf(0.32, 1.15, smoke_progress) * offset
		var center := dir * distance
		var puff_radius := radius * lerpf(0.26, 0.74, smoke_progress) * puff_scale
		var smoke_color := Color(0.32 + tint, 0.27 + tint * 0.5, 0.22 + tint * 0.4, 0.42 * smoke_fade * puff_scale)
		draw_circle(center, puff_radius, smoke_color)

func _draw_sparks(progress: float, fade: float) -> void:
	if spark_count <= 0:
		return
	var fire_strength := clampf(1.0 - pow(progress, 1.25), 0.0, 1.0)
	var spark_alpha := spark_color.a * fire_strength * fade
	if spark_alpha <= 0.0:
		return
	var base_radius := radius * (0.42 + 0.52 * progress)
	for i in range(spark_count):
		var angle := _rotation_offset + TAU * float(i) / float(max(spark_count, 1))
		if i < _spark_angle_offset.size():
			angle += _spark_angle_offset[i]
		var length_factor := 1.0
		if i < _spark_lengths.size():
			length_factor = float(_spark_lengths[i])
		var jitter := sin(_elapsed * 9.0 + float(i)) * 0.12
		var dir := Vector2(cos(angle + jitter), sin(angle + jitter))
		var length := base_radius * length_factor
		var start := dir * (length * 0.3)
		var end := dir * length
		var spark := Color(spark_color.r, spark_color.g, spark_color.b, clampf(spark_alpha * length_factor, 0.0, 1.0))
		draw_line(start, end, spark, max(2.0, radius * 0.045), true)
		draw_circle(end, max(2.3, radius * 0.05 * fire_strength), Color(spark.r, spark.g, spark.b, spark.a * 0.85))

func _draw_embers(progress: float, fade: float) -> void:
	if _ember_sparks.is_empty():
		return
	var ember_strength := clampf(1.0 - pow(progress, 1.4), 0.0, 1.0) * fade
	if ember_strength <= 0.0:
		return
	for ember in _ember_sparks:
		var angle: float = float(ember.get("angle", 0.0))
		var speed: float = float(ember.get("speed", 1.0))
		var offset: float = float(ember.get("offset", 0.5))
		var dir := Vector2(cos(angle), sin(angle))
		var distance := radius * lerpf(0.18, 1.25, progress) * offset
		var ember_pos := dir * distance
		var ember_radius: float = 1.4 if 1.4 > radius * 0.035 * speed else radius * 0.035 * speed
		var glow := Color(flame_color.r, flame_color.g, flame_color.b, 0.45 * ember_strength * speed)
		draw_circle(ember_pos, ember_radius, glow)

func _draw_debris(progress: float, fade: float) -> void:
	var debris_count := int(clampf(radius / 24.0, 6.0, 20.0))
	var debris_color := base_color.lerp(Color(0.24, 0.22, 0.2, 0.5), 0.65)
	debris_color.a *= fade * 0.6
	for i in range(debris_count):
		var angle := _rotation_offset + TAU * float(i) / float(debris_count)
		var wobble := sin(_elapsed * 6.0 + float(i)) * 0.12
		var distance := radius * (0.55 + progress * 0.9 + wobble)
		var point := Vector2(cos(angle), sin(angle)) * distance
		draw_circle(point, radius * 0.05, debris_color)

func _draw_radial_glow(target_radius: float, color: Color, softness: float, steps: int) -> void:
	var clamped_steps := maxi(1, steps)
	for i in range(clamped_steps):
		var t := float(i) / float(clamped_steps)
		var falloff := pow(1.0 - t, 1.35)
		var ring_alpha := color.a * falloff
		if ring_alpha <= 0.0:
			continue
		var ring_radius := target_radius * (1.0 + softness * t)
		var ring_color := Color(color.r, color.g, color.b, ring_alpha)
		draw_circle(Vector2.ZERO, ring_radius, ring_color)

func _initialize_fire_lobes() -> void:
	_fire_lobes.clear()
	for _i in range(FIRE_LOBE_COUNT):
		_fire_lobes.append({
			"angle": _rng.randf_range(0.0, TAU),
			"intensity": _rng.randf_range(0.7, 1.2),
			"width": _rng.randf_range(0.8, 1.35),
			"delay": _rng.randf_range(0.0, 0.2)
		})

func _initialize_smoke_puffs() -> void:
	_smoke_puffs.clear()
	for _i in range(SMOKE_PUFF_COUNT):
		_smoke_puffs.append({
			"angle": _rng.randf_range(0.0, TAU),
			"scale": _rng.randf_range(0.7, 1.25),
			"offset": _rng.randf_range(0.55, 1.0),
			"drift": _rng.randf_range(-0.35, 0.35),
			"tint": _rng.randf_range(-0.08, 0.12)
		})

func _initialize_sparks() -> void:
	_spark_lengths.clear()
	_spark_angle_offset = PackedFloat32Array()
	var count: int = spark_count if spark_count > 0 else 0
	for _i in range(count):
		_spark_lengths.append(_rng.randf_range(0.75, 1.3))
		_spark_angle_offset.append(_rng.randf_range(-0.45, 0.45))
	_ember_sparks.clear()
	var ember_count: int = count * 2 if count * 2 > 12 else 12
	for _i in range(ember_count):
		_ember_sparks.append({
			"angle": _rng.randf_range(0.0, TAU),
			"speed": _rng.randf_range(0.4, 1.1),
			"offset": _rng.randf_range(0.25, 0.95)
		})
