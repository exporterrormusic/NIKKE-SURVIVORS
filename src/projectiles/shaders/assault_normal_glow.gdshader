shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float glow_size : hint_range(0.0, 0.05) = 0.005;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	// OPTIMIZATION: 8-Tap Sample (Quality + Speed)
	float alpha_sum = 0.0;
	vec2 size = vec2(glow_size);
    // Cardinals
	alpha_sum += texture(TEXTURE, UV + vec2(size.x, 0.0)).a;
	alpha_sum += texture(TEXTURE, UV - vec2(size.x, 0.0)).a;
	alpha_sum += texture(TEXTURE, UV + vec2(0.0, size.y)).a;
	alpha_sum += texture(TEXTURE, UV - vec2(0.0, size.y)).a;
    // Diagonals
    vec2 diag = size * 0.707;
    alpha_sum += texture(TEXTURE, UV + diag).a;
    alpha_sum += texture(TEXTURE, UV - diag).a;
    alpha_sum += texture(TEXTURE, UV + vec2(diag.x, -diag.y)).a;
    alpha_sum += texture(TEXTURE, UV + vec2(-diag.x, diag.y)).a;
	
	float avg_alpha = alpha_sum * 0.125;
	float glow_mask = max(0.0, avg_alpha - tex_color.a);
	vec3 glow_rgb = glow_color.rgb * glow_mask * glow_intensity * 2.0;
	
	COLOR = vec4(tex_color.rgb + glow_rgb, max(tex_color.a, glow_mask * glow_intensity));
}