shader_type canvas_item;
render_mode blend_add, unshaded;

// Colors - RAW HDR (Toned down to prevent white core)
uniform vec4 laser_color : source_color = vec4(3.0, 0.05, 0.05, 1.0); // Intense Red
uniform vec4 core_color : source_color = vec4(5.0, 0.5, 0.5, 1.0); // Hot Red Core (less white)

// Settings
uniform float pulse_speed : hint_range(0.0, 100.0) = 55.0; // Fast jitter

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float sdRhombus(vec2 p, vec2 b) {
    p = abs(p);
    float h = clamp((-2.0 * dot(p, b) + dot(b, b)) / dot(b, b), -1.0, 1.0);
    float d = length(p - 0.5 * b * vec2(1.0 - h, 1.0 + h));
    return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}

void fragment() {
    float t = TIME * pulse_speed;
    vec2 uv = UV;
    
    // 1. JAGGED EDGES: High-freq noise distortion on UVs
    // Creates a "shattered" or "raw" sharp boundary
    float jagged = hash(uv * 15.0 + vec2(t * 0.1, t * 0.05)) * 0.05;
    float sharp_jitter = hash(vec2(t, uv.x * 20.0)) * 0.03;
    uv += jagged + sharp_jitter;
    
    // 2. EXTREME ASYMMETRY
    vec2 p = (uv - 0.5);
    
    // Needle Taper: Back (Left, x=0) is extremely thin. Front (Right, x=1) is bulky.
    // Use an exponential curve for the taper to make the tail very sharp.
    float taper = mix(0.05, 1.8, pow(uv.x, 1.8)); 
    p.y /= taper;
    
    // Aspect: Shorter overall (User wants them shrunk)
    p.x *= 4.0;
    
    // 3. DIAMOND SHAPE
    vec2 size = vec2(1.8, 0.22); 
    float dist = sdRhombus(p, size);
    
    // 4. UNSTABLE CORE 
    // "Raw" look requires high-freq alpha oscillations
    float instability = hash(vec2(t * 0.5, uv.x * 5.0)) * 0.4;
    float core_alpha = 1.0 - smoothstep(0.0, 0.03, dist + instability * 0.02);
    core_alpha = pow(core_alpha, 2.5); // Sharp core
    
    // 5. RAGGED GLOW
    float glow_noise = hash(uv * 8.0 - t * 0.02) * 0.1;
    float glow_alpha = 1.0 - smoothstep(0.0, 0.45 + glow_noise, dist);
    glow_alpha = pow(glow_alpha, 3.0); // Tighter, sharper glow
    
    // 6. COMPOSITE
    vec4 final_color = vec4(0.0);
    
    // Glow
    final_color += laser_color * glow_alpha * (1.0 + instability);
    
    // Core: Broken-white intensity
    final_color += core_color * core_alpha * (1.5 + instability * 0.5);
    
    // Raw Energy Lightning (vertical streaks)
    float lightning = hash(vec2(uv.x * 30.0, floor(t * 0.5)));
    float streak = smoothstep(0.8, 0.95, lightning) * core_alpha;
    final_color += core_color * streak * 3.0;

    // Hard, raw alpha clip
    float mask = smoothstep(0.15, 0.0, dist + jagged);
    final_color.a *= mask;
    
    COLOR = final_color;
}
