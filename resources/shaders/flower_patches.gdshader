shader_type canvas_item;

// Simple flower patch overlay - draws colored dots as flowers
uniform float time_flow = 0.0;
uniform float density : hint_range(0.0, 1.0) = 0.4;
uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform vec2 world_offset = vec2(0.0, 0.0);
uniform float flower_scale : hint_range(0.25, 3.0) = 1.0;
uniform vec4 primary_color : source_color = vec4(1.0, 0.85, 0.2, 1.0);
uniform vec4 secondary_color : source_color = vec4(1.0, 0.4, 0.5, 1.0);
uniform vec4 tertiary_color : source_color = vec4(0.6, 0.4, 1.0, 1.0);
uniform float wind_sway : hint_range(0.0, 1.0) = 0.3;
uniform float cluster_size : hint_range(0.2, 1.0) = 0.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	// Convert UV to world space
	vec2 world_pos = world_offset + UV * view_size;
	
	// Create a grid of potential flower positions
	float cell_size = 80.0 * flower_scale;
	vec2 cell = floor(world_pos / cell_size);
	vec2 local = fract(world_pos / cell_size);
	
	// Random offset within cell
	float rand1 = hash(cell);
	float rand2 = hash(cell + vec2(17.0, 31.0));
	
	// Skip some cells based on density
	if (rand1 > density) {
		discard;
	}
	
	// Flower center position with random offset
	vec2 flower_center = vec2(0.3 + rand1 * 0.4, 0.3 + rand2 * 0.4);
	
	// Add wind sway
	float sway = sin(time_flow * 2.0 + rand1 * 6.28) * wind_sway * 0.05;
	flower_center.x += sway;
	
	// Distance from flower center
	float dist = length(local - flower_center);
	
	// Flower size
	float flower_radius = 0.08 + rand2 * 0.06;
	
	// Draw flower as soft circle
	if (dist > flower_radius) {
		discard;
	}
	
	// Pick color based on cell hash
	float color_pick = hash(cell + vec2(41.0, 73.0));
	vec3 flower_color;
	if (color_pick < 0.33) {
		flower_color = primary_color.rgb;
	} else if (color_pick < 0.66) {
		flower_color = secondary_color.rgb;
	} else {
		flower_color = tertiary_color.rgb;
	}
	
	// Soft edge
	float alpha = smoothstep(flower_radius, flower_radius * 0.5, dist);
	
	// Yellow center
	if (dist < flower_radius * 0.3) {
		flower_color = mix(flower_color, vec3(1.0, 0.95, 0.4), 0.7);
	}
	
	COLOR = vec4(flower_color, alpha * 0.9);
}
