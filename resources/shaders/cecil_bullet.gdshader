shader_type canvas_item;

// Intense glowing gold sphere shader for Cecil's SMG bullets

uniform float time_scale : hint_range(0.5, 5.0) = 3.0;
uniform vec4 primary_color : source_color = vec4(1.0, 0.75, 0.0, 1.0);  // Pure gold
uniform vec4 secondary_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);  // Deep orange-gold
uniform vec4 accent_color : source_color = vec4(1.0, 1.0, 0.4, 1.0);  // Bright gold highlight
uniform float swirl_intensity : hint_range(1.0, 10.0) = 5.0;
uniform float glow_intensity : hint_range(0.0, 3.0) = 2.0;

// Noise function for organic swirling
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

float fbm(vec2 p, float time) {
    float value = 0.0;
    float amplitude = 0.5;
    vec2 shift = vec2(100.0);
    
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p);
        p = p * 2.0 + shift;
        p += vec2(time * 0.5, time * 0.3);
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    float time = TIME * time_scale;
    
    // Center UV coordinates
    vec2 uv = UV - 0.5;
    float dist = length(uv);
    
    // Create spherical distortion with softer edges
    float sphere_mask = 1.0 - smoothstep(0.25, 0.5, dist);
    
    // Swirling effect
    float angle = atan(uv.y, uv.x);
    float swirl = angle + dist * swirl_intensity + time * 3.0;
    
    // Create swirling coordinates
    vec2 swirl_uv = vec2(cos(swirl), sin(swirl)) * dist + 0.5;
    
    // Layered noise for fiery effect
    float n1 = fbm(swirl_uv * 4.0, time);
    float n2 = fbm(swirl_uv * 6.0 + vec2(time * 0.9), time * 1.5);
    float n3 = fbm(uv * 10.0 + vec2(time * -0.7, time * 1.0), time);
    
    // Combine noise layers
    float combined = n1 * 0.5 + n2 * 0.3 + n3 * 0.2;
    
    // Color mixing - deep orange-gold to bright gold gradient (NO BLUE)
    vec3 color = mix(secondary_color.rgb, primary_color.rgb, combined);
    
    // Add bright gold accent streaks
    float streaks = smoothstep(0.5, 0.7, n2);
    color = mix(color, accent_color.rgb, streaks * 0.9);
    
    // INTENSE inner glow - very bright gold core
    float inner_glow = 1.0 - smoothstep(0.0, 0.35, dist);
    color += vec3(1.0, 0.85, 0.2) * inner_glow * glow_intensity;
    
    // Strong edge glow - golden rim
    float edge_glow = smoothstep(0.15, 0.35, dist) * (1.0 - smoothstep(0.35, 0.5, dist));
    color += primary_color.rgb * edge_glow * glow_intensity * 1.5;
    
    // Outer aura glow
    float outer_aura = smoothstep(0.5, 0.3, dist) * 0.5;
    color += vec3(1.0, 0.7, 0.1) * outer_aura * glow_intensity;
    
    // Apply sphere mask with subtle flicker
    float flicker = 0.9 + 0.1 * sin(time * 10.0 + dist * 20.0);
    float alpha = sphere_mask * flicker;
    
    // WHITE-HOT pulsing core center
    float pulse = 0.8 + 0.2 * sin(time * 8.0);
    float core = 1.0 - smoothstep(0.0, 0.1, dist);
    color = mix(color, vec3(1.0, 1.0, 0.85), core * pulse);  // White-gold core
    
    // Boost overall saturation and brightness
    color = color * 1.3;  // Make it really pop
    
    COLOR = vec4(color, alpha);
}
