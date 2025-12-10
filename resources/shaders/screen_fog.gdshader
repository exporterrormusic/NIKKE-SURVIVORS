shader_type canvas_item;

// World-space fog overlay - locked to ground level
// Very thin subtle base fog with rare thick clumps (like clouds in clear sky)

uniform sampler2D noise_texture : hint_default_white, repeat_enable;
uniform float fog_density : hint_range(0.0, 1.0) = 0.5;
uniform vec4 fog_color : source_color = vec4(0.35, 0.4, 0.55, 1.0);
uniform float time : hint_range(0.0, 10000.0) = 0.0;

// World-space parameters
uniform vec2 camera_position = vec2(0.0);
uniform vec2 viewport_size = vec2(1920.0, 1080.0);

void fragment() {
	// Convert screen position to world position (1:1 with ground)
	vec2 screen_offset = (UV - 0.5) * viewport_size;
	vec2 world_pos = camera_position + screen_offset;
	
	// Normalize world position for texture sampling (1 texture repeat per 1000 pixels)
	vec2 fog_uv = world_pos / 1000.0;
	
	// Layer 1: Very slow-moving large fog patches
	vec2 scroll1 = vec2(time * 0.015, time * 0.008);
	float noise1 = texture(noise_texture, fog_uv * 0.4 + scroll1).r;
	
	// Layer 2: Medium fog detail
	vec2 scroll2 = vec2(-time * 0.022, time * 0.012);
	float noise2 = texture(noise_texture, fog_uv * 0.8 + scroll2).r;
	
	// Layer 3: Fine wisps
	vec2 scroll3 = vec2(time * 0.035, -time * 0.02);
	float noise3 = texture(noise_texture, fog_uv * 1.6 + scroll3).r;
	
	// Combine for base thickness
	float combined = noise1 * 0.5 + noise2 * 0.3 + noise3 * 0.2;
	
	// Very thin subtle base fog everywhere (constant low alpha)
	float base_fog = 0.08 * fog_density;
	
	// Thick clumps: only show when ALL layers agree it's foggy
	// High power + high threshold = very rare thick patches
	float thick_mask = pow(combined, 2.0);  // Square to make high values rarer
	thick_mask = smoothstep(0.5, 0.85, thick_mask);  // Only show very high density areas
	float thick_fog = thick_mask * fog_density * 0.7;
	
	// Ground bias: slightly heavier at bottom
	float ground_bias = smoothstep(0.2, 0.8, UV.y) * 0.15;
	
	// Combine: subtle base + rare thick clumps + ground bias
	float final_fog = base_fog + thick_fog + (combined * ground_bias * fog_density * 0.3);
	final_fog = clamp(final_fog, 0.0, fog_density * 0.85);
	
	COLOR = vec4(fog_color.rgb, final_fog);
}
