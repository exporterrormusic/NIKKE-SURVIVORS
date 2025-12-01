shader_type canvas_item;
render_mode blend_add;

uniform float red_threshold : hint_range(0.0, 1.0) = 0.4;
uniform float emission_strength : hint_range(0.0, 20.0) = 2.0;
uniform vec3 glow_color : source_color = vec3(0.8, 0.0, 0.0);

void fragment() {
	// Sample the sprite texture
	vec4 albedo_tex = texture(TEXTURE, UV);
	
	// Detect red pixels: red channel dominant over green and blue
	float is_red = 0.0;
	if (albedo_tex.r > red_threshold && albedo_tex.r > albedo_tex.g * 1.2 && albedo_tex.r > albedo_tex.b * 1.2) {
		is_red = albedo_tex.r;
	}
	
	// Detect gray/silver pixels
	float is_gray = 0.0;
	float avg = (albedo_tex.r + albedo_tex.g + albedo_tex.b) / 3.0;
	float variance = abs(albedo_tex.r - avg) + abs(albedo_tex.g - avg) + abs(albedo_tex.b - avg);
	if (variance < 0.05 && avg > 0.4) {
		is_gray = avg;
	}
	
	float glow_factor = is_red + is_gray;
	COLOR = vec4(0.0, 1.0, 0.0, 1.0);
}