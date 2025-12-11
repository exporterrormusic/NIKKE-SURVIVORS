shader_type canvas_item;

uniform vec4 liquid_color : source_color = vec4(0.05, 0.0, 0.05, 1.0); // Black/Dark Purple
uniform float speed : hint_range(0.0, 5.0) = 0.5;
uniform float turbulence : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	// Generate flowing liquid effect based on World/Screen position
	// Use UV if available, but for draw_line/poly, standard UV might be weird.
	// We'll use SCREEN_UV or FRAGCOORD for seamless world flow
	
	vec2 uv = UV; 
	// If UV is not useful (e.g. solid color geometry), fall back to world-ish coords
	// But let's assume default mapping or just use a noise texture
	
	float time = TIME * speed;
	
	// Simple procedural noise simulation
	vec2 noise_uv = uv * 20.0 + vec2(0.0, time);
	
	// Sine wave distortion
	float wave = sin(noise_uv.x * 0.5 + noise_uv.y * 0.2 + time) * 0.5 + 0.5;
	float wave2 = sin(noise_uv.x * -0.3 + noise_uv.y * 0.8 + time * 1.2) * 0.5 + 0.5;
	
	float distort = (wave + wave2) * 0.5;
	
	// Color variation: Dark Base -> Slightly Lighter Ridge
	vec3 col = liquid_color.rgb;
	// Add "shine" or "wetness"
	float shine = smoothstep(0.8, 0.9, distort);
	
	col += vec3(0.2, 0.0, 0.3) * distort * turbulence; // Purple sub-surface
	col += vec3(0.5) * shine; // Specular highlight
	
	// Alpha edge falloff (for soft round look on lines)
	// Standard line drawing has Anti-aliasing, but we want it to look like a cylinder/liquid stream
	// This is hard without varying thicknes data.
	// We'll just output the liquid color.
	
	COLOR = vec4(col, liquid_color.a);
}
