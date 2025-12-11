shader_type canvas_item;
render_mode unshaded;

uniform vec4 line_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float line_thickness : hint_range(0, 10) = 1.0;

void fragment() {
	vec2 size = TEXTURE_PIXEL_SIZE;
	
	float outline = texture(TEXTURE, UV + vec2(-size.x, 0)).a;
	outline += texture(TEXTURE, UV + vec2(0, size.y)).a;
	outline += texture(TEXTURE, UV + vec2(size.x, 0)).a;
	outline += texture(TEXTURE, UV + vec2(0, -size.y)).a;
	outline += texture(TEXTURE, UV + vec2(-size.x, size.y)).a;
	outline += texture(TEXTURE, UV + vec2(size.x, size.y)).a;
	outline += texture(TEXTURE, UV + vec2(-size.x, -size.y)).a;
	outline += texture(TEXTURE, UV + vec2(size.x, -size.y)).a;
	
	outline = min(outline, 1.0);
	
	vec4 color = texture(TEXTURE, UV);
	
	// If transparent but surrounded by alpha, draw outline
	if (color.a < 0.1 && outline > 0.0) {
		COLOR = line_color;
	} else {
		COLOR = color;
	}
}
