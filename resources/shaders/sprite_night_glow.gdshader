shader_type canvas_item;

// Night glow shader for sprites
// Adds a subtle luminous glow and brightness boost to sprites at night

uniform float glow_intensity : hint_range(0.0, 1.0) = 0.3;
uniform vec4 glow_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float glow_size : hint_range(0.0, 5.0) = 2.0;
uniform float enabled_float : hint_range(0.0, 1.0) = 0.0;  // Use float instead of bool

void fragment() {
	vec4 original = texture(TEXTURE, UV);
	
	// If not enabled, just output original
	float enable_factor = step(0.5, enabled_float) * glow_intensity;
	
	// Sample pixels in 4 directions to detect edges for glow
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 pixel_size = glow_size / tex_size;
	
	float alpha_sum = 0.0;
	alpha_sum += texture(TEXTURE, UV + vec2(pixel_size.x, 0.0)).a;
	alpha_sum += texture(TEXTURE, UV + vec2(-pixel_size.x, 0.0)).a;
	alpha_sum += texture(TEXTURE, UV + vec2(0.0, pixel_size.y)).a;
	alpha_sum += texture(TEXTURE, UV + vec2(0.0, -pixel_size.y)).a;
	alpha_sum += texture(TEXTURE, UV + vec2(pixel_size.x, pixel_size.y)).a * 0.7;
	alpha_sum += texture(TEXTURE, UV + vec2(-pixel_size.x, pixel_size.y)).a * 0.7;
	alpha_sum += texture(TEXTURE, UV + vec2(pixel_size.x, -pixel_size.y)).a * 0.7;
	alpha_sum += texture(TEXTURE, UV + vec2(-pixel_size.x, -pixel_size.y)).a * 0.7;
	
	float outline = alpha_sum / 6.8;  // Normalize
	
	// Glow only appears on transparent pixels near opaque ones
	float glow_alpha = outline * (1.0 - original.a) * enable_factor;
	vec4 glow = vec4(glow_color.rgb, glow_alpha);
	
	// Boost sprite brightness slightly
	vec3 boosted = original.rgb * (1.0 + enable_factor * 0.4);
	vec4 boosted_sprite = vec4(boosted, original.a);
	
	// Composite: glow behind, boosted sprite on top
	COLOR = mix(glow, boosted_sprite, original.a);
}
