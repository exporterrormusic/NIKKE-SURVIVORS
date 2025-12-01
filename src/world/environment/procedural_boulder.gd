extends StaticBody2D
class_name ProceduralBoulder

## Procedurally generated boulder obstacle that blocks bullets and movement

@export var boulder_size: float = 240.0  # Tripled from 80.0
@export var variation_seed: int = 0

var _visual: Polygon2D = null
var _collision_shape: CollisionShape2D = null

func _ready():
	_create_boulder()

func _create_boulder():
	"""Create boulder visuals and collision using procedural generation."""
	var rng = RandomNumberGenerator.new()
	rng.seed = variation_seed if variation_seed != 0 else randi()
	
	# Create visual polygon
	_visual = Polygon2D.new()
	_visual.z_index = 0  # Same as player - Y-sorting will handle depth
	_visual.y_sort_enabled = true
	add_child(_visual)
	
	# Generate irregular boulder shape
	var points: PackedVector2Array = []
	var num_points = rng.randi_range(8, 12)  # Irregular shape
	var base_radius = boulder_size * 0.5
	
	for i in range(num_points):
		var angle = (float(i) / num_points) * TAU
		# Randomize radius for each point
		var radius_variation = rng.randf_range(0.7, 1.0)
		var radius = base_radius * radius_variation
		var point = Vector2(cos(angle), sin(angle)) * radius
		points.append(point)
	
	_visual.polygon = points
	
	# Create shader material for anime-style gray rock texture
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	
	shader.code = """
shader_type canvas_item;

uniform float seed_value = 0.0;
uniform vec3 rock_base_color : source_color = vec3(0.65, 0.67, 0.7);
uniform vec3 rock_highlight : source_color = vec3(0.9, 0.92, 0.95);
uniform vec3 rock_shadow : source_color = vec3(0.4, 0.42, 0.45);

// Simple hash for noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth noise
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	vec2 noisy_uv = uv * 3.0 + vec2(seed_value * 10.0);
	
	// Large scale texture variation
	float large_noise = noise(noisy_uv * 1.2);
	
	// Medium scale rock bumps
	float medium_noise = noise(noisy_uv * 3.5);
	
	// Small details
	float small_noise = noise(noisy_uv * 7.0);
	
	// Combine for surface variation
	float surface = large_noise * 0.5 + medium_noise * 0.3 + small_noise * 0.2;
	
	// Anime-style cel shading - 3 distinct color bands
	vec3 final_color;
	if (surface < 0.4) {
		final_color = rock_shadow;  // Dark shadow areas
	} else if (surface < 0.7) {
		final_color = rock_base_color;  // Mid-tone
	} else {
		final_color = rock_highlight;  // Bright highlights
	}
	
	// Add edge highlight (top-left light source for anime look)
	float rim_light = smoothstep(0.2, -0.6, uv.y) * smoothstep(0.2, -0.4, uv.x);
	if (rim_light > 0.3) {
		final_color = rock_highlight;  // Sharp highlight on top-left edge
	}
	
	// Vignette for depth
	float dist = length(uv);
	float vignette = smoothstep(1.1, 0.6, dist);
	final_color *= vignette * 0.5 + 0.5;
	
	COLOR = vec4(final_color, 1.0);
}
"""
	
	mat.shader = shader
	mat.set_shader_parameter("seed_value", rng.randf())
	mat.set_shader_parameter("rock_base_color", Vector3(0.65, 0.67, 0.7))
	mat.set_shader_parameter("rock_highlight", Vector3(0.9, 0.92, 0.95))
	mat.set_shader_parameter("rock_shadow", Vector3(0.4, 0.42, 0.45))
	
	_visual.material = mat
	
	# Use simple circle collision shape to avoid concave polygon issues
	_collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = base_radius * 0.95  # Slightly smaller than visual for smooth movement
	_collision_shape.shape = circle
	add_child(_collision_shape)
	
	# Set collision layers - this is critical for proper physics
	# Layer 3 (bit 2): Environment/obstacles  
	# Mask: Player (layer 1/bit 0), Enemies (layer 3/bit 2), Projectiles (layer 2/bit 1)
	collision_layer = 0b0000_0000_0000_0100  # Layer 3 (bit 2 = value 4)
	collision_mask = 0b0000_0000_0000_0111   # Layers 1, 2, 3 (bits 0,1,2 = value 7)

func set_boulder_seed(new_seed: int):
	"""Set the variation seed for this boulder."""
	variation_seed = new_seed
	if is_node_ready():
		# Recreate with new seed
		if _visual:
			_visual.queue_free()
		if _collision_shape:
			_collision_shape.queue_free()
		_create_boulder()
