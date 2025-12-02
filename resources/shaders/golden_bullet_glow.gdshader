shader_type canvas_item;

// Golden glow effect for Crown's minigun bullets
uniform float glow_intensity : hint_range(0.5, 3.0) = 1.8;
uniform float pulse_speed : hint_range(0.0, 10.0) = 4.0;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.15;
uniform vec3 gold_color : source_color = vec3(1.0, 0.85, 0.3);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	if (tex_color.a > 0.01) {
		// Pulsing glow
		float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;
		
		// Calculate luminance to preserve structure
		float lum = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
		
		// Apply golden tint with luminance
		vec3 golden = gold_color * (0.6 + lum * 0.8) * glow_intensity * pulse;
		
		// Add a subtle white core for the brightest parts
		float white_blend = smoothstep(0.7, 1.0, lum) * 0.3;
		golden = mix(golden, vec3(1.0, 0.95, 0.8), white_blend);
		
		COLOR = vec4(golden, tex_color.a);
	} else {
		COLOR = tex_color;
	}
}
