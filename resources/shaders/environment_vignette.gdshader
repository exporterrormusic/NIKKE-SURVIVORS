shader_type canvas_item;

// Vignette shader - darkens edges of screen
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.6;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.4;
uniform float softness : hint_range(0.1, 1.0) = 0.5;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = UV * 2.0 - vec2(1.0);
	float dist = length(centered);
	
	// Strong vignette with smooth falloff from inner_radius to edge
	float edge = smoothstep(inner_radius, inner_radius + softness, dist);
	// Apply quadratic curve for more natural falloff (darker at edges)
	edge = edge * edge;
	float alpha = clamp(base_alpha + (edge * vignette_strength), 0.0, 0.9);
	
	COLOR = vec4(tint.rgb, tint.a * alpha);
}
