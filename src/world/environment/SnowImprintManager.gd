extends Node
class_name SnowImprintManager
## Manages snow imprints (footprints, paths, accumulations) and snow particles.
##
## Extracted from EnvironmentController to reduce god class size.
## Handles: snow imprint texture generation/updating, snow stamping for
## footprints, snow pile containers, and snow kickup particles.

const SNOW_IMPRINT_TEXTURE_SIZE := 1024
const SNOW_IMPRINT_DEFAULT := 0.5
const SNOW_FOOTPRINT_FADE := 0.8
const SNOW_PATH_RADIUS := 120.0
const SNOW_PARTICLE_LIFETIME := 0.55
const SNOW_PARTICLE_GRAVITY := 480.0

var _snow_imprint_image: Image = null
var _snow_imprint_texture: ImageTexture = null
var _snow_imprint_enabled: bool = false
var _snow_particle_texture: Texture2D = null
var _snow_pile_container: Node2D = null
var _snow_particle_container: Node2D = null
var _parent: Node = null
var _ground_getter: Callable = Callable() # Returns the ground Polygon2D


func setup(parent: Node, ground_getter: Callable) -> void:
	_parent = parent
	_ground_getter = ground_getter
	_ensure_snow_pile_container()
	_ensure_snow_particle_container()


## Configure snow imprint state based on biome.
func configure(biome: BiomeDefinition) -> void:
	var ground: Polygon2D = _ground_getter.call()
	if ground == null:
		return
	var shader_material := ground.material as ShaderMaterial
	if shader_material == null:
		return
	
	if biome == null or biome.snow_cover <= 0.05:
		_snow_imprint_enabled = false
		shader_material.set_shader_parameter("snow_imprint_strength", 0.0)
		clear_imprint()
		clear_piles()
		return
	
	_ensure_resources()
	_snow_imprint_enabled = true
	shader_material.set_shader_parameter("snow_imprint_texture", _snow_imprint_texture)
	shader_material.set_shader_parameter("snow_imprint_texel_size", Vector2(1.0 / SNOW_IMPRINT_TEXTURE_SIZE, 1.0 / SNOW_IMPRINT_TEXTURE_SIZE))
	shader_material.set_shader_parameter("snow_imprint_strength", clampf(biome.snow_cover * 1.1, 0.2, 2.0))
	clear_imprint()
	clear_piles()


func is_enabled() -> bool:
	return _snow_imprint_enabled and _snow_imprint_image != null


func add_footprint(world_position: Vector2, parent_node: Node2D, radius: float = 80.0, depth: float = SNOW_FOOTPRINT_FADE) -> void:
	if not is_enabled():
		return
	var local := parent_node.to_local(world_position)
	_add_stamp(local, radius, -abs(depth))
	_add_stamp(local, radius * 1.35, abs(depth) * 0.18)
	_emit_particles(world_position, abs(depth))


func add_path_sample(world_position: Vector2, parent_node: Node2D, radius: float = SNOW_PATH_RADIUS, depth: float = SNOW_FOOTPRINT_FADE) -> void:
	if not is_enabled():
		return
	var local := parent_node.to_local(world_position)
	_add_stamp(local, radius, -abs(depth))
	_add_stamp(local, radius * 1.5, abs(depth) * 0.22)
	if depth > 0.3:
		_emit_particles(world_position, abs(depth) * 0.6)


func add_accumulation(world_position: Vector2, parent_node: Node2D, radius: float, height: float) -> void:
	if not is_enabled():
		return
	var local := parent_node.to_local(world_position)
	_add_stamp(local, radius, abs(height))


func emit_kickup(world_position: Vector2, _parent_node: Node2D, strength: float = 0.45) -> void:
	if not is_enabled():
		return
	_emit_particles(world_position, clampf(strength, 0.0, 1.0))


func clear_imprint(value: float = SNOW_IMPRINT_DEFAULT) -> void:
	if _snow_imprint_image == null:
		return
	_snow_imprint_image.fill(Color(value, value, value, 1.0))
	if _snow_imprint_texture:
		_snow_imprint_texture.update(_snow_imprint_image)


func clear_piles() -> void:
	if _snow_pile_container == null:
		return
	for child in _snow_pile_container.get_children():
		child.queue_free()


func seed_piles(_biome: BiomeDefinition) -> void:
	# Small obstacles (snow piles) are disabled — keep obstacles limited to procedural boulders only
	clear_piles()


func _ensure_resources() -> void:
	if _snow_imprint_image != null and _snow_imprint_texture != null:
		return
	_snow_imprint_image = Image.create(SNOW_IMPRINT_TEXTURE_SIZE, SNOW_IMPRINT_TEXTURE_SIZE, false, Image.FORMAT_RF)
	_snow_imprint_image.fill(Color(SNOW_IMPRINT_DEFAULT, SNOW_IMPRINT_DEFAULT, SNOW_IMPRINT_DEFAULT, 1.0))
	_snow_imprint_texture = ImageTexture.create_from_image(_snow_imprint_image)
	
	var ground: Polygon2D = _ground_getter.call()
	if ground:
		var shader_material := ground.material as ShaderMaterial
		if shader_material:
			shader_material.set_shader_parameter("snow_imprint_texture", _snow_imprint_texture)
			shader_material.set_shader_parameter("snow_imprint_texel_size", Vector2(1.0 / SNOW_IMPRINT_TEXTURE_SIZE, 1.0 / SNOW_IMPRINT_TEXTURE_SIZE))


func _ensure_snow_pile_container() -> void:
	if _snow_pile_container != null:
		return
	var node := _parent.get_node_or_null("SnowPiles")
	if node and node is Node2D:
		_snow_pile_container = node
		return
	var container := Node2D.new()
	container.name = "SnowPiles"
	container.z_index = -45
	_parent.add_child(container)
	if Engine.is_editor_hint():
		container.owner = _parent.get_tree().edited_scene_root
	_snow_pile_container = container


func _ensure_snow_particle_container() -> void:
	if _snow_particle_container != null:
		return
	var node := _parent.get_node_or_null("SnowParticles")
	if node and node is Node2D:
		_snow_particle_container = node
		return
	var container := Node2D.new()
	container.name = "SnowParticles"
	container.z_index = -40
	_parent.add_child(container)
	if Engine.is_editor_hint():
		container.owner = _parent.get_tree().edited_scene_root
	_snow_particle_container = container


func _add_stamp(local_position: Vector2, radius: float, delta: float) -> void:
	if not _snow_imprint_enabled or _snow_imprint_image == null:
		return
	if _parent == null:
		return
	
	var extent := _get_effective_ground_extent()
	var half_extent := extent * 0.5
	var uv := Vector2(
		(local_position.x + half_extent) / extent,
		(local_position.y + half_extent) / extent
	)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return
	
	var center_px := Vector2i(
		int(round(clampf(uv.x, 0.0, 1.0) * float(SNOW_IMPRINT_TEXTURE_SIZE - 1))),
		int(round(clampf(uv.y, 0.0, 1.0) * float(SNOW_IMPRINT_TEXTURE_SIZE - 1)))
	)
	var radius_px := int(max(1.0, round((radius / extent) * float(SNOW_IMPRINT_TEXTURE_SIZE))))
	
	for y_offset in range(-radius_px, radius_px + 1):
		var py := center_px.y + y_offset
		if py < 0 or py >= SNOW_IMPRINT_TEXTURE_SIZE:
			continue
		for x_offset in range(-radius_px, radius_px + 1):
			var px := center_px.x + x_offset
			if px < 0 or px >= SNOW_IMPRINT_TEXTURE_SIZE:
				continue
			var dist := sqrt(float(x_offset * x_offset + y_offset * y_offset)) / float(radius_px)
			if dist > 1.0:
				continue
			var falloff := pow(clampf(1.0 - dist, 0.0, 1.0), 2.2)
			var current := _snow_imprint_image.get_pixel(px, py).r
			var target := clampf(current + delta * falloff, 0.0, 1.0)
			_snow_imprint_image.set_pixel(px, py, Color(target, target, target, 1.0))
	
	if _snow_imprint_texture:
		_snow_imprint_texture.update(_snow_imprint_image)


func _emit_particles(world_position: Vector2, strength: float) -> void:
	if _snow_particle_container == null:
		return
	var texture := _get_particle_texture()
	var particles := GPUParticles2D.new()
	particles.one_shot = true
	particles.amount = int(round(clampf(lerpf(10.0, 22.0, clampf(strength, 0.0, 1.0)), 6.0, 28.0)))
	particles.lifetime = SNOW_PARTICLE_LIFETIME
	particles.explosiveness = 0.6
	particles.speed_scale = 1.0
	particles.texture = texture
	particles.process_material = _create_particle_material(strength)
	particles.global_position = world_position
	_snow_particle_container.add_child(particles)
	particles.finished.connect(Callable(particles, "queue_free"))
	particles.emitting = true


func _create_particle_material(strength: float) -> ParticleProcessMaterial:
	var particle_material := ParticleProcessMaterial.new()
	particle_material.gravity = Vector3(0.0, SNOW_PARTICLE_GRAVITY, 0.0)
	var intensity := clampf(strength, 0.0, 1.0)
	var velocity := lerpf(55.0, 120.0, intensity)
	particle_material.initial_velocity_min = velocity * 0.35
	particle_material.initial_velocity_max = velocity * 0.9
	particle_material.direction = Vector3(0.0, -0.75, 0.0)
	particle_material.spread = 78.0
	particle_material.angular_velocity_min = -8.0
	particle_material.angular_velocity_max = 8.0
	particle_material.scale_min = 0.32
	particle_material.scale_max = 0.62
	particle_material.damping_min = 1.6
	particle_material.damping_max = 3.9
	particle_material.color_ramp = _get_particle_ramp()
	return particle_material


func _get_particle_texture() -> Texture2D:
	if _snow_particle_texture != null:
		return _snow_particle_texture
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := float(x) / float(size - 1)
			var v := float(y) / float(size - 1)
			var dx := u - 0.5
			var dy := v - 0.5
			var dist := sqrt(dx * dx + dy * dy) * 2.2
			var alpha := clampf(1.0 - dist, 0.0, 1.0)
			var color := Color(0.96, 0.99, 1.0, pow(alpha, 1.5) * 0.9)
			image.set_pixel(x, y, color)
	_snow_particle_texture = ImageTexture.create_from_image(image)
	return _snow_particle_texture


func _get_particle_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.95, 0.98, 1.0, 0.75),
		Color(0.95, 0.98, 1.0, 0.35),
		Color(0.95, 0.98, 1.0, 0.0)
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _get_effective_ground_extent() -> float:
	if _parent and _parent.has_method("_get_effective_ground_extent"):
		return _parent._get_effective_ground_extent()
	return 4096.0
