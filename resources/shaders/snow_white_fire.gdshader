shader_type canvas_item;
render_mode blend_mix, unshaded;

// Anime-style blue fire effect for Snow White's burn trail
uniform float time = 0.0;
uniform float intensity : hint_range(0.0, 1.0, 0.01) = 1.0;

// Noise function for fire animation
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
    vec2 uv = UV;
    
    // Fire rises upward with flicker
    vec2 fire_uv = uv * vec2(3.0, 5.0) + vec2(0.0, -time * 3.0);
    float fire_noise = fbm(fire_uv);
    float fire_noise2 = fbm(fire_uv * 1.3 + vec2(time * 0.5, 0.0));
    
    // Create flame shape - wider at bottom, tapered at top
    float flame_shape = 1.0 - uv.y;  // Stronger at bottom
    flame_shape *= smoothstep(0.0, 0.3, uv.x) * smoothstep(1.0, 0.7, uv.x);  // Fade at edges
    
    // Combine noise with shape
    float fire_pattern = fire_noise * 0.6 + fire_noise2 * 0.4;
    float flame = flame_shape * fire_pattern;
    
    // Anime-style blue fire colors (icy/cold fire)
    vec3 outer_color = vec3(0.2, 0.5, 0.9);     // Blue outer flames
    vec3 mid_color = vec3(0.4, 0.8, 1.0);       // Cyan mid
    vec3 inner_color = vec3(0.7, 0.95, 1.0);    // Light cyan inner
    vec3 core_color = vec3(1.0, 1.0, 1.0);      // White hot core
    
    // Layer colors based on intensity
    vec3 final_color = outer_color;
    
    // Mid flames
    float mid_mask = smoothstep(0.3, 0.5, flame);
    final_color = mix(final_color, mid_color, mid_mask);
    
    // Inner flames
    float inner_mask = smoothstep(0.5, 0.7, flame);
    final_color = mix(final_color, inner_color, inner_mask);
    
    // Hot core
    float core_mask = smoothstep(0.7, 0.9, flame);
    final_color = mix(final_color, core_color, core_mask);
    
    // Add flickering sparks
    float spark_noise = noise(uv * 15.0 + vec2(time * 4.0, -time * 6.0));
    float spark = smoothstep(0.85, 0.95, spark_noise) * flame_shape;
    final_color = mix(final_color, core_color, spark * 0.8);
    
    // Get base texture alpha and apply fire alpha
    float tex_alpha = texture(TEXTURE, UV).a;
    float fire_alpha = flame * intensity * 1.5;
    fire_alpha = clamp(fire_alpha, 0.0, 1.0);
    
    // Add glow at edges
    float edge_glow = smoothstep(0.1, 0.3, flame) * (1.0 - smoothstep(0.3, 0.6, flame));
    fire_alpha += edge_glow * 0.3 * intensity;
    
    COLOR = vec4(final_color, fire_alpha * tex_alpha);
}
