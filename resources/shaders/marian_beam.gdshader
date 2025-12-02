shader_type canvas_item;

// Epic anime-style purple laser beam shader for Marian's burst
// Features: Core beam, energy rings, particle trails, chromatic edges

uniform float time_scale : hint_range(0.5, 5.0) = 3.0;
uniform vec4 core_color : source_color = vec4(1.0, 0.9, 1.0, 1.0);  // White-pink core
uniform vec4 inner_color : source_color = vec4(0.8, 0.4, 1.0, 0.95);  // Bright purple
uniform vec4 outer_color : source_color = vec4(0.5, 0.1, 0.9, 0.7);  // Deep purple
uniform vec4 edge_color : source_color = vec4(0.3, 0.0, 0.6, 0.5);  // Dark purple edge
uniform float beam_intensity : hint_range(0.5, 3.0) = 1.5;
uniform float ring_count : hint_range(1.0, 10.0) = 5.0;
uniform float ring_speed : hint_range(1.0, 20.0) = 8.0;
uniform float distortion_strength : hint_range(0.0, 0.2) = 0.05;
uniform float chromatic_amount : hint_range(0.0, 0.05) = 0.02;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
    float time = TIME * time_scale;
    vec2 uv = UV;
    
    // UV is expected to be: x = along beam (0 to 1), y = across beam (-0.5 to 0.5 centered)
    float along = uv.x;
    float across = uv.y - 0.5;
    float dist_from_center = abs(across);
    
    // Add wavy distortion
    float wave1 = sin(along * 20.0 + time * 5.0) * 0.02;
    float wave2 = sin(along * 35.0 - time * 7.0) * 0.01;
    float wave3 = noise(vec2(along * 10.0, time)) * distortion_strength;
    across += wave1 + wave2 + wave3;
    dist_from_center = abs(across);
    
    // Beam width varies along length (narrower at edges, thicker in middle)
    float width_mod = 0.8 + 0.2 * sin(along * PI);
    float beam_width = 0.4 * width_mod;
    
    // Core beam (very bright center)
    float core = 1.0 - smoothstep(0.0, 0.08 * width_mod, dist_from_center);
    
    // Inner glow
    float inner = 1.0 - smoothstep(0.0, 0.18 * width_mod, dist_from_center);
    
    // Outer glow
    float outer = 1.0 - smoothstep(0.0, beam_width, dist_from_center);
    
    // Edge fade
    float edge = 1.0 - smoothstep(beam_width * 0.8, beam_width * 1.2, dist_from_center);
    
    // Energy rings traveling along beam
    float ring_phase = fract(along * ring_count - time * ring_speed * 0.1);
    float ring = smoothstep(0.0, 0.1, ring_phase) * (1.0 - smoothstep(0.1, 0.2, ring_phase));
    ring *= inner * 0.5;
    
    // Particle sparkles
    float sparkle_noise = noise(vec2(along * 50.0 + time * 10.0, across * 20.0));
    float sparkles = smoothstep(0.75, 0.85, sparkle_noise) * inner;
    
    // Chromatic aberration at edges
    float chroma_offset = chromatic_amount * (1.0 - inner);
    
    // Build final color
    vec3 color = vec3(0.0);
    
    // Layer colors from outside in
    color = mix(color, edge_color.rgb, edge * edge_color.a);
    color = mix(color, outer_color.rgb, outer * outer_color.a);
    color = mix(color, inner_color.rgb, inner * inner_color.a);
    color = mix(color, core_color.rgb, core * core_color.a);
    
    // Add energy rings
    color += inner_color.rgb * ring * 0.8;
    
    // Add sparkles
    color += vec3(1.0, 0.9, 1.0) * sparkles * 0.6;
    
    // Chromatic edge effect (red/blue split)
    color.r += chroma_offset * 0.5;
    color.b += chroma_offset * 0.3;
    
    // Pulsing intensity
    float pulse = 0.9 + 0.1 * sin(time * 8.0);
    color *= beam_intensity * pulse;
    
    // Alpha based on outer glow
    float alpha = edge;
    
    // Fade at beam start and end
    float end_fade = smoothstep(0.0, 0.05, along) * smoothstep(1.0, 0.95, along);
    alpha *= end_fade;
    
    COLOR = vec4(color, alpha);
}
