shader_type canvas_item;

uniform vec3 rock_base_color : source_color = vec3(0.65, 0.67, 0.7);
uniform vec3 rock_highlight : source_color = vec3(0.9, 0.92, 0.95);
uniform vec3 rock_shadow : source_color = vec3(0.4, 0.42, 0.45);

varying float v_seed;

void vertex() {
	// Pass the random seed via the instance's Modulate Red channel
	// This allows unique variations while sharing a single material
	v_seed = COLOR.r;
}

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
	// Use v_seed for variation
	vec2 noisy_uv = uv * 3.0 + vec2(v_seed * 10.0);
	
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
