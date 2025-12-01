shader_type canvas_item;

// Rapture Core anime-style glow shader
// Creates pulsing red energy effect

uniform float glow_intensity : hint_range(0.0, 3.0) = 1.5;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_amplitude : hint_range(0.0, 1.0) = 0.3;
uniform vec4 core_color : source_color = vec4(1.0, 0.2, 0.2, 1.0);  // Red
uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.3, 1.0);  // Orange-red glow

void fragment() {
	// Get texture sample
	vec4 tex_color = texture(TEXTURE, UV);
	
	// Calculate distance from center for radial glow
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center);
	
	// Pulsing animation
	float pulse = sin(TIME * pulse_speed) * pulse_amplitude + (1.0 - pulse_amplitude);
	
	// Core brightness (center is brightest)
	float core_brightness = 1.0 - smoothstep(0.0, 0.3, dist);
	
	// Outer glow
	float glow = 1.0 - smoothstep(0.2, 0.8, dist);
	glow = pow(glow, 2.0);
	
	// Combine colors
	vec3 final_color = mix(glow_color.rgb, core_color.rgb, core_brightness);
	
	// Apply pulse to intensity
	float final_intensity = (core_brightness + glow * 0.5) * pulse * glow_intensity;
	
	// Output with alpha
	COLOR = vec4(final_color * final_intensity, tex_color.a * (core_brightness + glow * 0.7));
}
