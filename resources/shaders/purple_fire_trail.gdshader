shader_type canvas_item;
render_mode blend_mix, unshaded;

// Dark fiery ground burn effect for Marian's beam
uniform float time = 0.0;
uniform float intensity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float max_radius = 80.0;
uniform float fade_progress : hint_range(0.0, 1.0, 0.01) = 0.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    vec2 centered_uv = UV - vec2(0.5);
    // Use box distance for square coverage instead of circular
    float dist = max(abs(centered_uv.x), abs(centered_uv.y)) * 2.0;
    float activity = clamp(1.0 - fade_progress * 0.7, 0.0, 1.0);
    
    // Animated fire noise
    vec2 fire_uv = centered_uv * 4.0 + vec2(0.0, -time * 0.5);
    float fire_noise = fbm(fire_uv);
    float fire_noise2 = fbm(fire_uv * 1.5 + vec2(time * 0.3, 0.0));
    
    // Create burning ground coverage - full square coverage
    float base_coverage = smoothstep(1.0, 0.0, dist);
    float fire_pattern = fire_noise * 0.6 + fire_noise2 * 0.4;
    
    // Dark charred base color (almost black)
    vec3 char_color = vec3(0.08, 0.02, 0.02);
    // Deep red ember color
    vec3 ember_color = vec3(0.6, 0.1, 0.0);
    // Bright orange-red for hot spots
    vec3 hot_color = vec3(1.0, 0.3, 0.0);
    // Yellow-white for brightest cinders
    vec3 cinder_color = vec3(1.0, 0.8, 0.3);
    
    // Layer the colors based on noise
    float heat = fire_pattern * activity;
    vec3 final_color = char_color;
    
    // Add ember glow in cracks
    float ember_mask = smoothstep(0.3, 0.5, fire_noise) * smoothstep(0.7, 0.5, fire_noise);
    final_color = mix(final_color, ember_color, ember_mask * 0.8 * activity);
    
    // Add hot spots
    float hot_mask = smoothstep(0.55, 0.7, fire_noise2);
    final_color = mix(final_color, hot_color, hot_mask * 0.7 * activity);
    
    // Add bright cinders (small sparks)
    float cinder_noise = noise(centered_uv * 20.0 + vec2(time * 2.0, time * 1.5));
    float cinder_mask = smoothstep(0.85, 0.95, cinder_noise) * activity;
    final_color = mix(final_color, cinder_color, cinder_mask);
    
    // Very high opacity to cover ground - full square coverage
    float tex_alpha = texture(TEXTURE, UV).a;
    float alpha = base_coverage * intensity * activity * tex_alpha;
    
    // Ensure minimum darkness even when fading
    alpha = max(alpha, base_coverage * 0.3 * tex_alpha * (1.0 - fade_progress));
    
    COLOR = vec4(final_color, alpha);
}
