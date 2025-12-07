shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.24, 0.33, 0.26, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.16, 0.22, 0.18, 1.0);
uniform vec4 accent_color : source_color = vec4(0.48, 0.56, 0.46, 1.0);
uniform float noise_scale = 6.0;
uniform float detail_strength = 0.35;
uniform float wave_strength = 0.18;
uniform float wave_speed = 0.6;
uniform float patchwork_strength = 0.4;
uniform float color_variation = 0.25;
uniform float wind_strength = 0.4;
uniform float time_flow = 0.0;

// Procedural detail uniforms - all default to 0 (disabled)
uniform float pebble_density = 0.0;
uniform float pebble_size = 0.08;
uniform vec4 pebble_color : source_color = vec4(0.35, 0.32, 0.28, 1.0);
uniform float crack_intensity = 0.0;
uniform float highlight_spots = 0.0;
uniform vec4 spot_color : source_color = vec4(0.85, 0.78, 0.35, 1.0);
uniform float ground_shadow_strength = 0.0;
uniform float shimmer_intensity = 0.0;

// Snow uniforms
uniform float snow_cover = 0.0;
uniform float snow_brightness = 1.0;
uniform vec3 snow_tint_color = vec3(0.86, 0.92, 1.0);
uniform float snow_tint_strength = 0.08;
uniform float snow_shadow_strength = 0.18;
uniform float snow_drift_scale = 0.6;
uniform float snow_crust_strength = 0.3;
uniform float snow_ice_highlight = 0.22;
uniform float snow_sparkle_intensity = 0.2;
uniform sampler2D snow_imprint_texture : source_color;
uniform vec2 snow_imprint_texel_size = vec2(0.0, 0.0);
uniform float snow_imprint_strength = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Additional hash for variety
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
	float result = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 4; i++) {
		result += amplitude * noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	return result;
}

// Voronoi for pebbles/rocks
float voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_dist = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash(i + neighbor) * vec2(hash2(i + neighbor), hash(i + neighbor + vec2(1.0)));
			vec2 diff = neighbor + point - f;
			float dist = length(diff);
			min_dist = min(min_dist, dist);
		}
	}
	return min_dist;
}

// Cellular noise for cracks
float cellular(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_dist1 = 1.0;
	float min_dist2 = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = vec2(hash(i + neighbor), hash2(i + neighbor));
			vec2 diff = neighbor + point - f;
			float dist = length(diff);
			if (dist < min_dist1) {
				min_dist2 = min_dist1;
				min_dist1 = dist;
			} else if (dist < min_dist2) {
				min_dist2 = dist;
			}
		}
	}
	return min_dist2 - min_dist1;
}

void fragment() {
	vec2 coords = UV * noise_scale;
	float base_noise = fbm(coords + vec2(0.0, time_flow * wave_speed));
	float detail_noise = noise(coords * 2.0 + vec2(time_flow * wind_strength));
	float patch_noise = noise(coords * 0.5 + vec2(time_flow * 0.25));

	float blend = mix(base_noise, detail_noise, detail_strength);
	blend = mix(blend, patch_noise, patchwork_strength);

	vec4 layer_color = mix(base_color, secondary_color, blend);
	float accent_mask = smoothstep(0.55, 0.8, blend + detail_noise * 0.5);
	layer_color = mix(layer_color, accent_color, accent_mask * color_variation);

	// Smooth ping-pong wave using abs(sin()) for seamless loop
	float wave_phase = (UV.x + UV.y) * 6.283 + time_flow * wave_speed * 6.283;
	float subtle_wave = (abs(sin(wave_phase)) * 2.0 - 1.0) * wave_strength;
	layer_color.rgb += subtle_wave * 0.06;

	vec3 ground_color = layer_color.rgb;
	
	// === PROCEDURAL DETAILS ===
	
	// 1. Pebbles/small rocks using voronoi
	if (pebble_density > 0.001) {
		float pebble_scale = noise_scale * 12.0 / max(pebble_size, 0.01);
		float pebble_vor = voronoi(coords * pebble_scale / noise_scale);
		float pebble_mask = smoothstep(0.0, 0.12, pebble_vor);
		// Only show pebbles where hash says so (density control)
		vec2 pebble_cell = floor(coords * pebble_scale / noise_scale);
		float pebble_rand = hash(pebble_cell);
		if (pebble_rand < pebble_density) {
			// Vary pebble color slightly
			vec3 this_pebble = pebble_color.rgb * (0.85 + hash2(pebble_cell) * 0.3);
			// Add subtle shading to pebble
			this_pebble *= 0.9 + pebble_vor * 0.2;
			ground_color = mix(this_pebble, ground_color, pebble_mask);
		}
	}
	
	// 2. Ground cracks using cellular noise
	if (crack_intensity > 0.001) {
		float crack = cellular(coords * 2.5);
		float crack_line = smoothstep(0.0, 0.08, crack);
		// Darken along crack lines
		ground_color *= mix(1.0 - crack_intensity, 1.0, crack_line);
	}
	
	// 3. Highlight spots (flowers, bright patches)
	if (highlight_spots > 0.001) {
		float spot_scale = noise_scale * 8.0;
		vec2 spot_cell = floor(coords * spot_scale / noise_scale);
		float spot_rand = hash(spot_cell + vec2(42.0, 17.0));
		if (spot_rand < highlight_spots) {
			vec2 spot_center = (spot_cell + 0.5) * noise_scale / spot_scale;
			float spot_dist = length((coords / noise_scale - spot_center) * spot_scale);
			float spot_mask = smoothstep(0.4, 0.0, spot_dist);
			// Animate spots slightly with wind
			spot_mask *= 0.7 + 0.3 * sin(time_flow * 2.0 + spot_rand * 6.283);
			vec3 this_spot = spot_color.rgb * (0.9 + hash2(spot_cell) * 0.2);
			ground_color = mix(ground_color, this_spot, spot_mask * 0.6);
		}
	}
	
	// 4. Subtle ground shadows/depth using low-freq noise
	if (ground_shadow_strength > 0.001) {
		float shadow_noise = fbm(coords * 0.3);
		float shadow = smoothstep(0.3, 0.7, shadow_noise);
		ground_color *= 1.0 - (1.0 - shadow) * ground_shadow_strength;
	}
	
	// 5. Shimmer/light highlights
	if (shimmer_intensity > 0.001) {
		float shimmer_noise = noise(coords * 6.0 + vec2(time_flow * 0.8));
		float shimmer = pow(shimmer_noise, 4.0) * shimmer_intensity;
		// Tint shimmer towards highlight color
		ground_color += shimmer * vec3(1.1, 1.05, 0.95);
	}
	
	vec3 final_color = ground_color;

	// === SNOW SYSTEM (unchanged) ===
	float cover = clamp(snow_cover, 0.0, 1.0);
	if (cover > 0.001) {
		float drift_scale = max(snow_drift_scale, 0.01);
		float drift_noise = fbm(coords * drift_scale + vec2(time_flow * wind_strength * 0.12, 0.0));
		float drift_mask = smoothstep(0.2, 0.85, drift_noise);
		float crust_mask = smoothstep(0.65, 0.95, drift_noise);
		vec3 snow_color = snow_tint_color * snow_brightness;
		snow_color = mix(snow_color, snow_color + vec3(0.12, 0.16, 0.22) * snow_tint_strength, crust_mask);
		float shade = (drift_noise - 0.5) * snow_shadow_strength;
		snow_color -= shade;
		snow_color = clamp(snow_color, 0.0, 1.2);

		float imprint_sample = 0.5;
		if (snow_imprint_strength > 0.0 && snow_imprint_texel_size.x > 0.0 && snow_imprint_texel_size.y > 0.0) {
			vec2 texel = snow_imprint_texel_size;
			float center = texture(snow_imprint_texture, UV).r;
			float right = texture(snow_imprint_texture, UV + vec2(texel.x, 0.0)).r;
			float left = texture(snow_imprint_texture, UV - vec2(texel.x, 0.0)).r;
			float up = texture(snow_imprint_texture, UV + vec2(0.0, texel.y)).r;
			float down = texture(snow_imprint_texture, UV - vec2(0.0, texel.y)).r;
			float diag1 = texture(snow_imprint_texture, UV + vec2(texel.x, texel.y)).r;
			float diag2 = texture(snow_imprint_texture, UV + vec2(-texel.x, texel.y)).r;
			float diag3 = texture(snow_imprint_texture, UV + vec2(texel.x, -texel.y)).r;
			float diag4 = texture(snow_imprint_texture, UV + vec2(-texel.x, -texel.y)).r;
			imprint_sample = (center * 4.0 + (right + left + up + down) * 2.0 + (diag1 + diag2 + diag3 + diag4)) / 16.0;
		}
		float imprint_bias = (imprint_sample - 0.5) * snow_imprint_strength;
		float accumulation = max(imprint_bias, 0.0);
		float removal = max(-imprint_bias, 0.0);
		float cover_multiplier = clamp(1.0 + accumulation * 1.8 - removal * 2.6, 0.0, 2.2);
		float cover_amount = clamp(cover * drift_mask * cover_multiplier, 0.0, 1.0);

		snow_color += vec3(0.22, 0.27, 0.34) * accumulation * snow_ice_highlight;
		snow_color -= vec3(0.18, 0.15, 0.12) * removal;
		vec3 carved_ground = ground_color - vec3(0.18, 0.16, 0.11) * removal;
		carved_ground = clamp(carved_ground, 0.0, 1.0);
		final_color = mix(carved_ground, snow_color, cover_amount);

		if (snow_imprint_texel_size.x > 0.0 && snow_imprint_texel_size.y > 0.0) {
			vec2 grad = vec2(
				texture(snow_imprint_texture, UV + vec2(snow_imprint_texel_size.x, 0.0)).r - imprint_sample,
				texture(snow_imprint_texture, UV + vec2(0.0, snow_imprint_texel_size.y)).r - imprint_sample
			);
			float ridge = clamp(length(grad) * 6.0, 0.0, 1.0);
			final_color += vec3(0.1, 0.14, 0.19) * accumulation * ridge;
			final_color -= vec3(0.18, 0.15, 0.12) * removal * ridge;
		}

		float ice_mask = smoothstep(0.78, 0.98, drift_noise);
		final_color += vec3(0.25, 0.28, 0.35) * ice_mask * snow_ice_highlight * cover_amount;
		float sparkle_noise = noise(coords * 14.0 + vec2(time_flow * (0.6 + wind_strength * 0.4)));
		float sparkle = pow(max(0.0, sparkle_noise), 12.0) * snow_sparkle_intensity * cover_amount;
		final_color += vec3(sparkle);
	}

	COLOR = vec4(final_color, layer_color.a);
}
