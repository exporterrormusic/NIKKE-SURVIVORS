shader_type canvas_item;

// Holographic summoned ally shader - sci-fi hexagon pattern with silver/white theme

uniform float spawn_progress : hint_range(0.0, 1.0) = 1.0;  // 0 = invisible, 1 = fully visible
uniform float time : hint_range(0.0, 1000.0) = 0.0;
uniform vec4 hologram_color : source_color = vec4(0.85, 0.9, 1.0, 1.0);  // Silver/white tint
uniform float scanline_speed : hint_range(0.0, 5.0) = 2.0;
uniform float hex_scale : hint_range(5.0, 50.0) = 20.0;
uniform float flicker_intensity : hint_range(0.0, 0.3) = 0.1;
uniform float edge_glow : hint_range(0.0, 2.0) = 1.0;

// Hexagon SDF function
float hex_distance(vec2 p) {
    p = abs(p);
    return max(p.x * 0.866025 + p.y * 0.5, p.y);
}

// Create hexagon grid pattern
float hexagon_pattern(vec2 uv, float scale) {
    vec2 hex_uv = uv * scale;
    
    // Hexagon grid math
    vec2 r = vec2(1.0, 1.732);
    vec2 h = r * 0.5;
    vec2 a = mod(hex_uv, r) - h;
    vec2 b = mod(hex_uv - h, r) - h;
    
    vec2 gv = length(a) < length(b) ? a : b;
    
    float hex_dist = hex_distance(gv);
    float hex_edge = smoothstep(0.4, 0.45, hex_dist);
    
    return hex_edge;
}

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    // Skip transparent pixels
    if (tex_color.a < 0.01) {
        discard;
    }
    
    // Spawn animation - build up from bottom with hex dissolve
    // When spawn_progress = 0, nothing visible. When spawn_progress = 1, fully visible
    float spawn_line = spawn_progress * 1.2;  // 0 to 1.2 range
    float spawn_mask = smoothstep(0.0, 0.3, spawn_line - (1.0 - UV.y));
    
    // Hexagon pattern for spawn effect
    float hex = hexagon_pattern(UV + vec2(0.0, time * 0.1), hex_scale);
    float hex_spawn = smoothstep(0.0, 0.2, spawn_line - (1.0 - UV.y) + hex * 0.1);
    
    // Combine spawn effects - use hex pattern during spawn, solid after
    float final_spawn = spawn_progress >= 1.0 ? 1.0 : mix(hex_spawn, spawn_mask, spawn_progress);
    
    // Scanline effect
    float scanline = sin((UV.y + time * scanline_speed) * 80.0) * 0.5 + 0.5;
    scanline = mix(0.85, 1.0, scanline);
    
    // Horizontal glitch/scan bar
    float scan_bar = smoothstep(0.0, 0.02, abs(UV.y - mod(time * 0.5, 1.2)));
    scan_bar = mix(1.3, 1.0, 1.0 - scan_bar);
    
    // Flicker effect
    float flicker = 1.0 - flicker_intensity * sin(time * 30.0) * sin(time * 17.0);
    
    // Edge detection for glow (simple gradient from edges)
    float edge_x = min(UV.x, 1.0 - UV.x) * 2.0;
    float edge_y = min(UV.y, 1.0 - UV.y) * 2.0;
    float edge = 1.0 - min(edge_x, edge_y);
    float glow = edge * edge_glow * 0.3;
    
    // Hexagon overlay pattern (always visible, subtle)
    float hex_overlay = hexagon_pattern(UV + vec2(time * 0.02, time * 0.01), hex_scale * 0.7);
    hex_overlay = mix(0.9, 1.0, hex_overlay * 0.3);
    
    // Calculate holographic color
    // Convert to grayscale first, then tint with hologram color
    float luminance = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
    vec3 holo_base = mix(tex_color.rgb, hologram_color.rgb, 0.4);  // Partial tint
    
    // Add silver/white highlights
    vec3 highlight = vec3(1.0, 1.0, 1.0) * (luminance * 0.3);
    holo_base += highlight;
    
    // Apply all effects
    vec3 final_color = holo_base;
    final_color *= scanline;
    final_color *= scan_bar;
    final_color *= flicker;
    final_color *= hex_overlay;
    final_color += vec3(0.7, 0.85, 1.0) * glow;  // Blue-white edge glow
    
    // Add shimmer/sparkle at hex edges during spawn
    if (spawn_progress < 1.0) {
        float shimmer = hex * (1.0 - spawn_progress) * 2.0;
        shimmer *= sin(time * 10.0 + UV.x * 20.0) * 0.5 + 0.5;
        final_color += vec3(0.9, 0.95, 1.0) * shimmer * 0.5;
    }
    
    // Semi-transparency for hologram look
    // Base alpha is 0.85 when fully spawned, ramping up during spawn
    float base_alpha = spawn_progress >= 1.0 ? 0.85 : (0.5 + 0.35 * spawn_progress);
    float alpha = tex_color.a * final_spawn * base_alpha;
    alpha *= flicker;
    
    // Boost alpha at edges for glow effect
    alpha = min(1.0, alpha + glow * 0.2);
    
    COLOR = vec4(final_color, alpha);
}
