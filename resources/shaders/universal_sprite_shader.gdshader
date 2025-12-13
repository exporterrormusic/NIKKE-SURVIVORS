shader_type canvas_item;
render_mode unshaded;

uniform float night_boost : hint_range(0.0, 1.0) = 0.0;
uniform vec4 night_glow_color : source_color = vec4(0.2, 0.4, 1.0, 1.0); // Stronger Blue
uniform float night_glow_intensity : hint_range(0.0, 5.0) = 1.5; // High intensity

uniform bool enable_outline = false;
uniform vec4 outline_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float outline_width : hint_range(0.0, 10.0) = 0.0;

uniform bool enhance_red_core = false;
uniform vec4 core_glow_color : source_color = vec4(1.0, 0.3, 0.1, 1.0);

uniform float glow_scale : hint_range(0.1, 10.0) = 1.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 sprite_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0); // Explicit tint control

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 body_rgb = tex.rgb * sprite_tint.rgb; // Apply explicit tint
	
	// 1. Red Core (unchanged)
	if (tex.a > 0.1 && enhance_red_core && tex.r > 0.6 && tex.g < 0.4 && tex.b < 0.4) {
		float core_intensity = tex.r;
		vec3 enhanced = mix(tex.rgb, core_glow_color.rgb, 0.5);
		body_rgb = enhanced * (1.0 + core_intensity * 0.5);
	}

	// 2. Night Visuals - FIXING "Too Bright" and "No Tint"
	if (night_boost > 0.0) {
		// Instead of BOOSTING, we TINT and slight DIM to match night vibe without being pitch black.
		// Unshaded = 1.0 brightness. We want ~0.5 brightness with Blue tint.
		vec3 night_tint = vec3(0.5, 0.6, 1.2); // Cool blue push
		
		// Interpolate between Day (Original) and Night (Tinted) based on night_boost
		body_rgb = mix(body_rgb, body_rgb * night_tint, night_boost);
		
		// Global dimming to 40% brightness at full night boost
		body_rgb *= mix(1.0, 0.4, night_boost);
	}

	// 3. Radius Glow (Outer Soft Outline)
	vec4 glow_result = vec4(0.0);
	
	if (tex.a < 0.99) { 
		vec2 size = TEXTURE_PIXEL_SIZE;
		// Determine base width
		float width = enable_outline ? outline_width : 0.0;
		// Make outline glow wider for softness (multiply width)
		// If using as 'glow', we want radius ~15-20px
		if (enable_outline) {
			width *= 20.0; // Doubled/increased base width (was 12)
			width = max(width, 32.0); // Higher minimum
		}
		if (night_boost > 0.0) width = max(width, 25.0); 
		
		// Scale width by sprite/node scale to maintain relative thickness
		width *= glow_scale; 
		
		if (width > 0.0) {
			float total_alpha = 0.0;
			float total_weight = 0.0;
			
			// Wide Gaussian-ish sampling (12 samples)
			// Angle pairs + Distance layers for smoothness
			
			// IMPROVED GLOW: 16 samples for smoother quality (High Quality mode)
			
			// Layer 1: Close (8 samples ring)
            // Cardinal
			total_alpha += texture(TEXTURE, UV + vec2(size.x * width * 0.35, 0.0)).a;
			total_alpha += texture(TEXTURE, UV - vec2(size.x * width * 0.35, 0.0)).a;
			total_alpha += texture(TEXTURE, UV + vec2(0.0, size.y * width * 0.35)).a;
			total_alpha += texture(TEXTURE, UV - vec2(0.0, size.y * width * 0.35)).a;
            // Diagonal
            vec2 diag = size * width * 0.25;
            total_alpha += texture(TEXTURE, UV + diag).a;
            total_alpha += texture(TEXTURE, UV - diag).a;
            total_alpha += texture(TEXTURE, UV + vec2(diag.x, -diag.y)).a;
            total_alpha += texture(TEXTURE, UV + vec2(-diag.x, diag.y)).a;
			total_weight += 8.0;
			
			// Layer 2: Far (8 samples ring)
			if (night_boost > 0.0 || enable_outline) {
                // Outer ring
                vec2 far = size * width * 0.85;
				total_alpha += texture(TEXTURE, UV + vec2(far.x, 0.0)).a * 0.6;
				total_alpha += texture(TEXTURE, UV - vec2(far.x, 0.0)).a * 0.6;
				total_alpha += texture(TEXTURE, UV + vec2(0.0, far.y)).a * 0.6;
				total_alpha += texture(TEXTURE, UV - vec2(0.0, far.y)).a * 0.6;
                // Outer Diagonal
                vec2 far_diag = size * width * 0.6;
                total_alpha += texture(TEXTURE, UV + far_diag).a * 0.6;
                total_alpha += texture(TEXTURE, UV - far_diag).a * 0.6;
                total_alpha += texture(TEXTURE, UV + vec2(far_diag.x, -far_diag.y)).a * 0.6;
                total_alpha += texture(TEXTURE, UV + vec2(-far_diag.x, far_diag.y)).a * 0.6;
				total_weight += 4.8;
			}
			
			if (total_alpha > 0.0) {
				// Normalize
				float avg_alpha = total_alpha / total_weight;
				
				vec4 outline = vec4(0.0);
				vec3 glow_color_rgb = enable_outline ? outline_color.rgb : night_glow_color.rgb;
				
				// CALCULATE GLOW OPACITY
				// "Fade out much faster" -> Steep power curve (e.g. pow 2.0 or 1.5)
				// "Appear more smooth" -> Avoid hard clamps, let it taper naturally
				float glow_strength = 0.0;
				
				if (enable_outline) {
					// Colored Glow
					glow_strength = pow(avg_alpha, 1.5) * 1.5; 
					glow_strength = clamp(glow_strength, 0.0, 0.8);
				} else {
					// Night Blue Glow
					glow_strength = pow(avg_alpha, 1.2) * 2.0 * night_glow_intensity * night_boost;
					glow_strength = clamp(glow_strength, 0.0, 1.0);
				}
				
				outline.rgb = glow_color_rgb;
				outline.a = glow_strength;
				glow_result = outline;
			}
		}
	}
	
	// 4. Composite
	
	vec4 final_col = vec4(0.0);
	float body_alpha = tex.a;
	
	// Mix Glow and Body
	// "Glow should go both ways" -> Bleed into sprite
	// We use the glow calculation (from the blurring step) to infer if we are "near edge" even inside the sprite.
	// But the blur calculation above usually runs only if tex.a < 0.99.
	// We need to allow it to run for inner pixels OR do a simpler composition trick.
	// Since enabling blur for all pixels is expensive, we'll try a composition trick:
	// Simply ADD the glow on top of the body, but masked by body alpha?
	// No, that only affects the opaque part.
	
	// BETTER APPROACH:
	// Use standard Porter-Duff "Over" but with a twist to tint the body edge.
	
	// Background (Glow)
	vec3 bg_rgb = glow_result.rgb;
	float bg_a = glow_result.a;
	
	// Foreground (Body) applied over Background
	// Result = FG + BG * (1 - FG_A)
	// BUT we want the BG (Glow) to bleed INTO the FG.
	// We can do this by adding a fraction of BG to FG before composition?
	// Or Screen blending?
	
	// Let's try "Screen" blending for the glow onto the body to start
	// body_tinted = body + glow * (1 - body) ? No.
	
	// Simple additive bleed for "Inner Glow":
	// Since we don't have a dedicated inner distance field, we'll just soft-add the glow behind.
	// If the glow is wide/soft enough, it will look like backlighting.
	
	// Standard Composite (Glow Behind Body)
	vec3 out_rgb = mix(bg_rgb, body_rgb, body_alpha);
	float out_a = max(body_alpha, bg_a);
	
	// "Glow goes both ways" Hack:
	// Add a little bit of the glow color to the body color solely based on glow strength
	// This makes the body feel "lit" by the glow
	if (body_alpha > 0.0 && bg_a > 0.0) {
		out_rgb = mix(out_rgb, bg_rgb, 0.2 * bg_a); // Tint body with 20% of glow color
	}
	
	final_col = vec4(out_rgb, out_a);
	
	// Hit Flash (Whiteout)
	if (hit_flash > 0.0) {
		final_col.rgb = mix(final_col.rgb, vec3(1.0), hit_flash);
	}
	
	COLOR = final_col;
}
