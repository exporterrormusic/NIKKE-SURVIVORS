extends Node2D
class_name PhysicalGrassField

## Shader-based physical grass that sways and reacts to player movement
## Uses a single quad with procedural grass rendering for better compatibility

@export var field_size: Vector2 = Vector2(4096, 4096)
@export var world_bounds: Rect2 = Rect2(-2000, -2000, 4000, 4000)  # World boundary for clipping
@export var grass_density: float = 1.0  # Visual density
@export var blade_height: float = 54.0  # Increased from 40.0 (35% taller)
@export var sway_strength: float = 12.0
@export var wind_speed: float = 1.0
@export var interaction_radius: float = 80.0
@export var grass_color_base: Color = Color(0.3, 0.6, 0.2, 1.0)
@export var grass_color_tip: Color = Color(0.5, 0.8, 0.4, 1.0)

var _grass_quad: ColorRect = null
var _player_position: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _wind_direction: Vector2 = Vector2(1, 0)

func _ready():
	_create_grass_quad()
	set_process(true)

func _process(delta: float):
	_time += delta
	
	# Update shader parameters
	if _grass_quad and _grass_quad.material:
		var mat = _grass_quad.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("time", _time)
			mat.set_shader_parameter("player_pos", _player_position)
			# Use global position of the grass quad for world coordinates
			mat.set_shader_parameter("quad_position", _grass_quad.global_position)
			
			# Update mask texture if manager exists
			if GrassMaskManager.instance:
				mat.set_shader_parameter("mask_texture", GrassMaskManager.instance.get_mask_texture())

func _create_grass_quad():
	"""Create a single quad that covers the field and renders grass procedurally."""
	_grass_quad = ColorRect.new()
	
	# Use world_bounds to position and size the grass correctly
	_grass_quad.size = world_bounds.size
	_grass_quad.position = world_bounds.position
	_grass_quad.z_index = 0  # Same level as ground
	
	# Also update field_size to match world_bounds for shader calculations
	field_size = world_bounds.size
	
	_grass_quad.material = _create_grass_shader_material()
	
	add_child(_grass_quad)
	
	# print("Created procedural grass field: ", _grass_quad.size, " at position: ", _grass_quad.position)

func _create_grass_shader_material() -> ShaderMaterial:
	"""Create shader material that procedurally renders grass blades."""
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	
	shader.code = """
shader_type canvas_item;

uniform float grass_density = 1.0;
uniform float blade_height = 35.0;
uniform float sway_strength = 12.0;
uniform float wind_speed = 1.0;
uniform float time = 0.0;
uniform vec2 player_pos = vec2(0.0);
uniform float interaction_radius = 80.0;
uniform vec4 grass_color_base : source_color = vec4(0.3, 0.6, 0.2, 1.0);
uniform vec4 grass_color_tip : source_color = vec4(0.5, 0.8, 0.4, 1.0);
uniform vec2 field_size = vec2(4096.0, 4096.0);
uniform vec2 quad_position = vec2(0.0, 0.0);
uniform sampler2D mask_texture : hint_default_black;

// Hash function for pseudo-random values
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(443.897, 441.423, 437.195));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.x + p3.y) * p3.z);
}

// Check if we're in a "cut grass" region
float get_grass_height_multiplier(vec2 world_pos) {
	// Sample burn mask (Screen Space)
	// Since mask camera matches main camera, SCREEN_UV aligns perfect
	// We need to access SCREEN_UV but this is a fragment shader helper. 
	// We'll pass mask value into this function or sample global texture if possible?
	// In Godot CanvasItem shader, we can access texture(mask_texture, SCREEN_UV) anywhere in fragment()
	
	// BUT this function is called from fragment(). We'll just return height multiplier here based on NOISE.
	// Mask check happens in fragment() main loop.
	
	// Use multiple layers of noise at different scales for organic shapes
	// Layer 1: Large organic shapes (900px regions)
	vec2 large_pos = world_pos / 900.0;
	float large_noise = hash21(floor(large_pos));
	vec2 large_fract = fract(large_pos);
	
	// Sample multiple neighboring cells for smooth interpolation
	float n00 = hash21(floor(large_pos));
	float n10 = hash21(floor(large_pos) + vec2(1.0, 0.0));
	float n01 = hash21(floor(large_pos) + vec2(0.0, 1.0));
	float n11 = hash21(floor(large_pos) + vec2(1.0, 1.0));
	
	// Smooth interpolation for organic shapes (not linear)
	vec2 smooth_fract = large_fract * large_fract * (3.0 - 2.0 * large_fract);
	float n0 = mix(n00, n10, smooth_fract.x);
	float n1 = mix(n01, n11, smooth_fract.x);
	float base_noise = mix(n0, n1, smooth_fract.y);
	
	// Layer 2: Medium scale variation to break up large shapes (350px)
	vec2 med_pos = world_pos / 350.0;
	float m00 = hash21(floor(med_pos));
	float m10 = hash21(floor(med_pos) + vec2(1.0, 0.0));
	float m01 = hash21(floor(med_pos) + vec2(0.0, 1.0));
	float m11 = hash21(floor(med_pos) + vec2(1.0, 1.0));
	vec2 med_fract = fract(med_pos);
	vec2 med_smooth = med_fract * med_fract * (3.0 - 2.0 * med_fract);
	float m0 = mix(m00, m10, med_smooth.x);
	float m1 = mix(m01, m11, med_smooth.x);
	float med_noise = mix(m0, m1, med_smooth.y);
	
	// Combine noises for complex organic shapes
	float combined = base_noise * 0.7 + med_noise * 0.3;
	
	// Map to height values with tighter transitions
	// Make short grass much more rare (only 15% chance instead of 30%)
	float height;
	if (combined < 0.15) {
		// Very short cut grass - 15% height (RARE - only 15% of areas)
		height = 0.15 + (combined / 0.15) * 0.1; // 15-25% range
	} else if (combined < 0.3) {
		// Quick transition zone - blend from short to medium
		float t = (combined - 0.15) / 0.15;
		t = t * t * (3.0 - 2.0 * t); // Smooth curve
		height = mix(0.25, 0.6, t); // 25-60% range
	} else if (combined < 0.6) {
		// Medium height grass
		float t = (combined - 0.3) / 0.3;
		t = t * t * (3.0 - 2.0 * t);
		height = mix(0.6, 0.85, t); // 60-85% range
	} else {
		// Tall grass with smooth transition
		float t = (combined - 0.6) / 0.4;
		t = t * t * (3.0 - 2.0 * t);
		height = mix(0.85, 1.0, t); // 85-100% range
	}
	
	// Add fine detail variation for organic texture
	vec2 detail_pos = world_pos / 80.0;
	float d00 = hash21(floor(detail_pos));
	float d10 = hash21(floor(detail_pos) + vec2(1.0, 0.0));
	float d01 = hash21(floor(detail_pos) + vec2(0.0, 1.0));
	float d11 = hash21(floor(detail_pos) + vec2(1.0, 1.0));
	vec2 detail_fract = fract(detail_pos);
	vec2 detail_smooth = detail_fract * detail_fract * (3.0 - 2.0 * detail_fract);
	float d0 = mix(d00, d10, detail_smooth.x);
	float d1 = mix(d01, d11, detail_smooth.x);
	float detail = mix(d0, d1, detail_smooth.y);
	
	// Apply detail variation (±8%)
	height += (detail - 0.5) * 0.16;
	
	return clamp(height, 0.12, 1.05);
}

// Draw a grass clump (multiple blades together)
float draw_grass_clump(vec2 local_pos, vec2 clump_pos, float clump_seed, vec2 to_player_dir, float player_influence, float height_multiplier) {
	float total_coverage = 0.0;
	
	// Fewer blades in cut regions for sparse look
	int max_blades = height_multiplier < 0.4 ? 2 : int(2.0 + clump_seed * 1.0);  // Reduced from 3.0 for perf
	int num_blades = max_blades;
	
	for (int i = 0; i < 3; i++) { // Reduced from 5 for performance
		if (i >= num_blades) break;
		
		// More random positioning
		float blade_rand = hash21(vec2(clump_seed, float(i)));
		float blade_offset_x = (blade_rand - 0.5) * 25.0; // Random horizontal spread
		float blade_offset_y = hash21(vec2(clump_seed + 100.0, float(i))) * 8.0; // Random vertical offset
		float blade_seed = clump_seed + float(i) * 0.1547;
		
		// Blade properties - adjust width based on height
		float base_width = 10.5 + hash21(vec2(blade_seed, 0.0)) * 7.5;
		float blade_width = base_width * (0.7 + height_multiplier * 0.3); // Narrower when cut
		float base_height = blade_height * (0.85 + hash21(vec2(blade_seed, 1.0)) * 0.35);
		float blade_h = base_height * height_multiplier; // Apply height multiplier
		
		// Wind sway - less sway for shorter grass
		float phase = blade_seed * 6.28318;
		float wind_variation = 0.8 + hash21(vec2(blade_seed, 2.0)) * 0.4;
		float wind_sway = sin(time * wind_speed * wind_variation + phase * 0.5) * sway_strength * height_multiplier;
		
		// Player interaction - push away
		float push = to_player_dir.x * player_influence * 30.0 * height_multiplier;
		
		// Total horizontal displacement at blade top
		float sway_offset = wind_sway + push;
		
		// Position of this blade with random offset
		vec2 blade_pos = clump_pos + vec2(blade_offset_x, blade_offset_y);
		vec2 to_blade = local_pos - blade_pos;
		
		// Calculate if we're inside this blade
		float height_t = 1.0 - clamp(to_blade.y / blade_h, 0.0, 1.0);
		
		if (height_t > 0.0 && to_blade.y >= 0.0 && to_blade.y <= blade_h) {
			// Blade curves with sway - smoother curve for anime style
			float blade_center_x = sway_offset * pow(height_t, 1.8);
			float dist_from_center = abs(to_blade.x - blade_center_x);
			
			// Blade tapers to a point - cut grass has blunter tips
			float taper = height_multiplier < 0.4 ? 0.3 : 0.5;
			float current_width = blade_width * pow(1.0 - height_t, taper);
			
			if (dist_from_center < current_width * 0.5) {
				// Inside this blade - softer edges for anime aesthetic
				float edge_softness = smoothstep(current_width * 0.5, current_width * 0.15, dist_from_center);
				float alpha = edge_softness * (0.75 + 0.25 * height_t);
				
				total_coverage = max(total_coverage, alpha);
			}
		}
	}
	
	return total_coverage;
}

void fragment() {
	// Sample Mask first!
	vec4 mask = texture(mask_texture, SCREEN_UV);
	if (mask.r > 0.5) {
		discard; // Burned area - no grass
	}

	// Convert UV to world coordinates
	vec2 world_pos = UV * field_size + quad_position;
	
	// Determine grass height for this region
	float height_multiplier = get_grass_height_multiplier(world_pos);
	
	// Smaller spacing for double the grass density
	float cell_size = 38.0 / grass_density; // Reduced from 55.0 for 2x density
	vec2 cell = floor(world_pos / cell_size);
	vec2 cell_local = fract(world_pos / cell_size) * cell_size;
	
	vec4 final_color = vec4(0.0);
	
	// Check only 2x2 neighbor cells for performance (reduced from 3x3)
	for (int dx = 0; dx <= 1; dx++) {
		for (int dy = 0; dy <= 1; dy++) {
			vec2 neighbor_cell = cell + vec2(float(dx) - 0.5, float(dy) - 0.5);
			float clump_seed = hash21(neighbor_cell);
			
			// More random position within cell - not centered
			vec2 clump_offset = vec2(
				hash21(neighbor_cell + vec2(13.7, 0.0)) * 0.9 + 0.05, // 0.05-0.95 range
				hash21(neighbor_cell + vec2(0.0, 27.3)) * 0.4 // More Y variation now
			) * cell_size;
			
			vec2 clump_world_pos = neighbor_cell * cell_size + clump_offset;
			vec2 local_offset = world_pos - clump_world_pos;
			
			// Player interaction
			vec2 to_player = clump_world_pos - player_pos;
			float dist_to_player = length(to_player);
			float player_influence = 0.0;
			vec2 push_dir = vec2(0.0);
			
			if (dist_to_player < interaction_radius) {
				player_influence = pow(1.0 - (dist_to_player / interaction_radius), 1.5);
				push_dir = normalize(to_player);
			}
			
			// Draw grass clump with height multiplier
			float coverage = draw_grass_clump(local_offset, vec2(0.0), clump_seed, push_dir, player_influence, height_multiplier);
			
			if (coverage > 0.0) {
				// Height for color gradient
				float height_t = 1.0 - clamp(local_offset.y / (blade_height * height_multiplier), 0.0, 1.0);
				
				// Vibrant anime color gradient
				vec4 blade_color = mix(grass_color_base, grass_color_tip, pow(height_t, 0.6));
				
				// Cut grass is slightly darker/more saturated
				if (height_multiplier < 0.4) {
					blade_color.rgb *= 0.9; // Darker cut grass
				}
				
				// Uniform brightness - removed random variation
				// blade_color.rgb *= 1.0; // No brightness variation
				
				// Add glow effect during player interaction (anime style)
				blade_color.rgb += vec3(0.3, 0.35, 0.25) * player_influence * pow(height_t, 0.5);
				
				blade_color.a *= coverage;
				
				if (blade_color.a > 0.01) {
					final_color.rgb = mix(final_color.rgb, blade_color.rgb, blade_color.a);
					final_color.a = max(final_color.a, blade_color.a);
				}
			}
		}
	}
	
	COLOR = final_color;
}
"""
	
	mat.shader = shader
	mat.set_shader_parameter("grass_density", grass_density)
	mat.set_shader_parameter("blade_height", blade_height)
	mat.set_shader_parameter("sway_strength", sway_strength)
	mat.set_shader_parameter("wind_speed", wind_speed)
	mat.set_shader_parameter("interaction_radius", interaction_radius)
	mat.set_shader_parameter("grass_color_base", grass_color_base)
	mat.set_shader_parameter("grass_color_tip", grass_color_tip)
	mat.set_shader_parameter("player_pos", _player_position)
	mat.set_shader_parameter("time", 0.0)
	mat.set_shader_parameter("field_size", field_size)
	mat.set_shader_parameter("quad_position", Vector2.ZERO)  # Position relative to parent
	
	return mat

func update_player_position(pos: Vector2):
	"""Call this every frame with the player's position."""
	_player_position = pos

func set_wind_direction(direction: Vector2):
	"""Update wind direction."""
	_wind_direction = direction.normalized()

func set_grass_colors(base: Color, tip: Color):
	"""Update grass colors."""
	grass_color_base = base
	grass_color_tip = tip
	
	if _grass_quad and _grass_quad.material:
		var mat = _grass_quad.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("grass_color_base", base)
			mat.set_shader_parameter("grass_color_tip", tip)

func set_field_size(size: Vector2):
	"""Update field size and recreate grass."""
	field_size = size
	
	if _grass_quad:
		_grass_quad.queue_free()
		_create_grass_quad()

func set_world_bounds(bounds: Rect2):
	"""Update world bounds and recreate grass to match."""
	world_bounds = bounds
	field_size = bounds.size
	
	if _grass_quad:
		_grass_quad.queue_free()
		_create_grass_quad()
