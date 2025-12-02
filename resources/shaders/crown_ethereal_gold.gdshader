shader_type canvas_item;
render_mode blend_add;

// Brilliant ethereal golden glow shader for Crown's effects
uniform float glow_intensity : hint_range(1.0, 5.0) = 2.5;
uniform float pulse_speed : hint_range(1.0, 20.0) = 8.0;
uniform float shimmer_amount : hint_range(0.0, 1.0) = 0.4;
uniform vec3 gold_color : source_color = vec3(1.0, 0.85, 0.2);
uniform vec3 highlight_color : source_color = vec3(1.0, 1.0, 0.7);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	if (tex_color.a > 0.01) {
		// Pulsing glow effect
		float pulse = 1.0 + sin(TIME * pulse_speed) * 0.3;
		
		// Shimmer based on position
		float shimmer = sin(UV.x * 20.0 + TIME * 12.0) * sin(UV.y * 20.0 - TIME * 8.0);
		shimmer = shimmer * shimmer_amount * 0.5 + 0.5;
		
		// Calculate luminance
		float lum = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
		
		// Blend between gold and highlight based on luminance
		vec3 base_color = mix(gold_color, highlight_color, lum * 0.6 + shimmer * 0.2);
		
		// Apply intensity and pulse
		vec3 final_color = base_color * glow_intensity * pulse;
		
		// Add extra bloom to bright areas
		float bloom = smoothstep(0.5, 1.0, lum) * 0.5;
		final_color += highlight_color * bloom * pulse;
		
		COLOR = vec4(final_color, tex_color.a * 0.9);
	} else {
		COLOR = vec4(0.0);
	}
}
