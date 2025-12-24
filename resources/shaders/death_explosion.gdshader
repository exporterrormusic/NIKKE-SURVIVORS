shader_type canvas_item;
render_mode blend_add, unshaded;

// CINEMATIC GPU Explosion Shader (v2)
// Handles flash, distorted shockwaves, fractal shrapnel, and heat haze.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 10.0) = 2.0;

// Colors
uniform vec4 color_flash : source_color = vec4(1.5, 1.5, 2.0, 1.0); // HDR Blue-White
uniform vec4 color_core : source_color = vec4(2.0, 1.5, 0.2, 1.0); // Blinding Gold
uniform vec4 color_outer : source_color = vec4(1.5, 0.4, 0.1, 1.0); // Intense Orange
uniform vec4 color_smoke : source_color = vec4(0.3, 0.15, 0.15, 0.8); // Fading embers

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
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

void fragment() {
    vec2 uv = UV - 0.5;
    float dist_raw = length(uv) * 2.0;
    
    // 1. NOISE DISTORTION (Heat Haze)
    // Perturb the distance calculation to create organic, unstable edges
    float turbulence = noise(uv * 12.0 - progress * 5.0) * 0.15;
    float dist = dist_raw + turbulence * progress;
    
    vec4 final_color = vec4(0.0);
    float fade_pow = pow(1.0 - progress, 2.0);
    
    // 2. PRIMARY SHOCKWAVE (Distorted Ring)
    float ring_pos = progress * 1.0;
    float ring_width = 0.05 + (1.0 - progress) * 0.1;
    float ring_mask = smoothstep(ring_pos - ring_width, ring_pos, dist) * 
                     smoothstep(ring_pos + ring_width, ring_pos, dist);
    
    // Fractal Edge Glow
    float fractal = noise(uv * 25.0 + progress * 10.0) * 0.2;
    ring_mask *= (0.8 + fractal);
    
    final_color += color_core * ring_mask * 3.0 * fade_pow;
    
    // 3. CORE VOLUMETRIC BURST
    float core_radius = 0.45 * (1.0 - pow(progress, 0.5));
    float core_mask = smoothstep(core_radius, 0.0, dist_raw + turbulence * 0.1);
    final_color += color_flash * core_mask * pow(1.0 - progress, 4.0) * 2.0;
    final_color += color_outer * core_mask * fade_pow;

    // 4. SHATtered SHRAPNEL (Radial Streaks)
    float angle = atan(uv.y, uv.x);
    float streaks = noise(vec2(angle * 5.0, progress * 2.0)) * noise(vec2(angle * 2.0, progress * 4.0));
    float streak_mask = smoothstep(0.4, 0.7, streaks) * smoothstep(progress + 0.2, progress, dist);
    final_color += color_core * streak_mask * 0.6 * fade_pow;

    // 5. EMBERS / SPARKS (Procedural Dots)
    float spark_noise = hash(floor(uv * 50.0) + vec2(floor(progress * 12.0)));
    float spark_mask = smoothstep(0.99, 1.0, spark_noise);
    // Sparks lead the shockwave slightly
    float spark_dist_mask = smoothstep(progress - 0.2, progress + 0.1, dist) * 
                            smoothstep(progress + 0.15, progress + 0.1, dist);
    final_color += color_flash * spark_mask * spark_dist_mask * 10.0 * fade_pow;

    // 6. AFTERGLOW (Heat Haze Ring)
    float haze_mask = smoothstep(progress * 0.7, 0.0, dist_raw) * 0.3 * fade_pow;
    final_color += color_smoke * haze_mask;

    // Output with final intensity alpha
    final_color.a = clamp(max(max(final_color.r, final_color.g), final_color.b), 0.0, 1.0);
    COLOR = final_color;
}
