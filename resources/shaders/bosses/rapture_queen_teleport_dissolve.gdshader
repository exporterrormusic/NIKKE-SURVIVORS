shader_type canvas_item;

// Teleport dissolve shader for Rapture Queen N01
// Creates a flowing black liquid dissolve effect during teleport

uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float flow_speed : hint_range(0.0, 5.0) = 1.0;
uniform vec4 edge_glow_color : source_color = vec4(0.5, 0.0, 0.5, 1.0);
uniform float edge_glow_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float edge_thickness : hint_range(0.0, 0.2) = 0.05;
uniform sampler2D noise_texture;

// Hash function for procedural noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Perlin-like noise
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

// Fractal Brownian Motion for organic patterns
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	
	return value;
}

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	// Flow effect - dissolve flows downward like dripping liquid
	float flow_time = TIME * flow_speed;
	vec2 flow_uv = UV * 5.0;
	flow_uv.y -= flow_time * 0.5; // Downward flow
	
	// Create organic dissolve pattern using FBM
	float dissolve_pattern = fbm(flow_uv);
	
	// Add vertical bias - dissolve from top to bottom
	float vertical_bias = UV.y * 0.3;
	dissolve_pattern = dissolve_pattern * 0.7 + vertical_bias;
	
	// Edge distortion for liquid effect
	vec2 distort_uv = UV;
	float distortion = (noise(UV * 10.0 + vec2(0.0, flow_time)) - 0.5) * 0.02;
	distort_uv.x += distortion * dissolve_amount;
	
	// Get distorted texture
	vec4 distorted_color = texture(TEXTURE, distort_uv);
	
	// Dissolve threshold with smooth edges
	float dissolve_threshold = dissolve_amount + 0.1;
	float edge_range = edge_thickness;
	
	// Calculate alpha based on dissolve
	float alpha = smoothstep(dissolve_threshold - edge_range, dissolve_threshold, dissolve_pattern);
	
	// Calculate edge glow
	float edge_factor = smoothstep(dissolve_threshold - edge_range * 2.0, dissolve_threshold - edge_range * 0.5, dissolve_pattern);
	edge_factor *= (1.0 - smoothstep(dissolve_threshold - edge_range * 0.5, dissolve_threshold, dissolve_pattern));
	
	// Apply edge glow
	vec3 final_color = distorted_color.rgb;
	
	// Shift to darker/purple at dissolving edges
	vec3 liquid_color = mix(vec3(0.05, 0.0, 0.05), vec3(0.2, 0.0, 0.3), edge_factor);
	final_color = mix(final_color, liquid_color, edge_factor * 0.5);
	
	// Add edge glow
	final_color += edge_glow_color.rgb * edge_factor * edge_glow_intensity;
	
	// Drip effect - add streaks downward
	float drip = smoothstep(0.7, 1.0, noise(vec2(UV.x * 20.0, UV.y * 5.0 - flow_time * 2.0)));
	drip *= (1.0 - alpha) * 0.5;
	alpha = max(alpha, drip);
	
	COLOR = vec4(final_color, distorted_color.a * alpha);
}
