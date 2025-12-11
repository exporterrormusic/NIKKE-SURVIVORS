shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float outer_radius : hint_range(0.0, 50.0) = 10.0;
uniform float inner_radius : hint_range(0.0, 50.0) = 5.0;
uniform float soft_edge : hint_range(0.0, 10.0) = 2.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	// Create a signed distance field approximation or simple neighbor sampling for glow
	vec2 size = TEXTURE_PIXEL_SIZE;
	
	// OUTER GLOW 
	// Sample around the pixel to find alpha
	float outer_alpha = 0.0;
	float weights = 0.0;
	
	// Wide sampling for softness
	float r = outer_radius;
	for(float x = -r; x <= r; x+=2.0) {
		for(float y = -r; y <= r; y+=2.0) {
			vec2 offset = vec2(x, y) * size;
			float dist = length(vec2(x,y));
			if (dist <= r) {
				float a = texture(TEXTURE, UV + offset).a;
				float w = 1.0 - smoothstep(0.0, r, dist); // Soften with distance
				outer_alpha += a * w;
				weights += w;
			}
		}
	}
	
	if (weights > 0.0) outer_alpha /= weights;
	
	// INNER GLOW
	// Detect if we are inside the sprite but near edge
	// We use the INVERSE of the distance field concept: 
	// If we are opaque, how close are we to transparent pixels?
	float inner_intensity = 0.0;
	if (tex_color.a > 0.1) {
		float inner_dist_sum = 0.0;
		float inner_w_sum = 0.0;
		float ir = inner_radius;
		
		for(float x = -ir; x <= ir; x+=2.0) {
			for(float y = -ir; y <= ir; y+=2.0) {
				vec2 offset = vec2(x, y) * size;
				float dist = length(vec2(x,y));
				if (dist <= ir) {
					float a = texture(TEXTURE, UV + offset).a;
					// We want to find transparent pixels
					float is_transparent = 1.0 - a;
					float w = 1.0 - smoothstep(0.0, ir, dist);
					inner_dist_sum += is_transparent * w;
					inner_w_sum += w;
				}
			}
		}
		if (inner_w_sum > 0.0) inner_intensity = inner_dist_sum / inner_w_sum;
		// Boost inner intensity
		inner_intensity = pow(inner_intensity, 0.5) * 2.0;
	}
	
	// COMPOSITE AND OUTPUT
	
	// 1. Calculate Glow Color (Outer)
	vec4 final_glow = glow_color;
	// Boost outer alpha curve
	final_glow.a = pow(outer_alpha, 0.8) * 1.5;
	final_glow.a = clamp(final_glow.a, 0.0, 1.0);
	
	// 2. Mix Body and Inner Glow
	vec3 body_rgb = tex_color.rgb;
	// Apply inner glow as tint
	body_rgb = mix(body_rgb, glow_color.rgb, min(inner_intensity, 0.8));
	
	// 3. Mix Outer Glow (Background) with Body (Foreground)
	// Outer Glow is behind body.
	// Result = Body * BodyA + Glow * (1-BodyA)
	// But Inner Glow is part of body.
	
	// Standard premultiplied alpha composition logic:
	vec3 final_rgb = mix(final_glow.rgb, body_rgb, tex_color.a);
	float final_a = max(tex_color.a, final_glow.a);
	
	COLOR = vec4(final_rgb, final_a);
}
