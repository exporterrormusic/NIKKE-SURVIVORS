shader_type canvas_item;
render_mode blend_mix, unshaded;

// Anime-style blue ice fire for burn trail
// Designed to work on a horizontal trail polygon strip

uniform float time = 0.0;
uniform float fade : hint_range(0.0, 1.0, 0.01) = 1.0;

// Simple hash for noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
    vec2 uv = UV;
    
    // UV.x = along the trail (0 = back/tail, 1 = front/tip)
    // UV.y = across the trail (0 = edge, 0.5 = center, 1 = other edge)
    
    // Distance from center (0 at center, 1 at edges)
    float center_dist = abs(uv.y - 0.5) * 2.0;
    
    // Triangular taper at the back (tail end)
    float back_taper = smoothstep(0.0, 0.15, uv.x);
    // Slight taper at front too
    float front_taper = smoothstep(1.0, 0.9, uv.x);
    float taper = back_taper * front_taper;
    
    // Edge fade - stronger at edges
    float edge_fade = 1.0 - smoothstep(0.0, 0.5, center_dist);
    edge_fade = pow(edge_fade, 0.7);  // Softer falloff
    
    // Apply taper to edge fade
    float effective_edge = edge_fade * taper;
    
    // Animated fire noise
    vec2 fire_uv = vec2(uv.x * 4.0 - time * 2.0, uv.y * 2.0);
    float n1 = noise(fire_uv);
    float n2 = noise(fire_uv * 2.3 + vec2(time * 1.5, 0.0));
    float fire_noise = n1 * 0.6 + n2 * 0.4;
    
    // Add waviness to edges
    float edge_wave = noise(vec2(uv.x * 8.0 - time * 3.0, uv.y)) * 0.15;
    effective_edge = clamp(effective_edge + edge_wave * (1.0 - center_dist), 0.0, 1.0);
    
    // Anime ice fire color layers
    vec3 outer_color = vec3(0.15, 0.4, 0.9);    // Deep blue outer
    vec3 mid_color = vec3(0.35, 0.7, 1.0);      // Cyan mid
    vec3 inner_color = vec3(0.6, 0.9, 1.0);     // Light cyan inner
    vec3 core_color = vec3(0.95, 1.0, 1.0);     // White core
    
    // Layer based on distance from center
    float intensity = effective_edge * fire_noise;
    
    vec3 color = outer_color;
    color = mix(color, mid_color, smoothstep(0.2, 0.4, effective_edge));
    color = mix(color, inner_color, smoothstep(0.5, 0.7, effective_edge));
    color = mix(color, core_color, smoothstep(0.75, 0.95, effective_edge));
    
    // Add subtle flicker
    float flicker = 0.9 + 0.1 * sin(time * 12.0 + uv.x * 5.0);
    
    // Final alpha
    float alpha = effective_edge * fade * flicker;
    alpha = clamp(alpha * 1.3, 0.0, 1.0);
    
    COLOR = vec4(color, alpha);
}
