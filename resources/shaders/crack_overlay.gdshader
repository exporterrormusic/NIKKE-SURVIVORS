shader_type canvas_item;

// Overlay-only crack shader for HP bars
// Does NOT sample TEXTURE - draws cracks directly on transparent background

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.0;
uniform float crack_density : hint_range(1.0, 10.0) = 3.0;
uniform vec3 crack_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);

// Simple pseudo-random
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Noise function
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

// Ridged Noise for sharp cracks
float cracks(vec2 uv, float time) {
    float acc = 0.0;
    float amp = 1.0;
    float freq = 2.0;
    
    for (int i = 0; i < 3; i++) {
        vec2 p = uv * freq;
        p += vec2(float(i) * 12.0, float(i) * 7.0);
        float n = noise(p + vec2(time * 0.1 * float(i+1)));
        float ridge = 1.0 - abs(2.0 * n - 1.0);
        ridge = pow(ridge, 8.0);
        acc += ridge * amp;
        freq *= 2.0;
        amp *= 0.5;
    }
    
    return acc;
}

void fragment() {
    // Pulsing intensity
    float pulse = 0.7 + 0.3 * sin(TIME * pulse_speed);
    float applied_intensity = intensity * pulse;
    
    // UV Correction
    vec2 corrected_uv = UV * uv_scale;
    
    // Generate Cracks
    float crack = cracks(corrected_uv * crack_density, TIME);
    
    // Sharp threshold - only peaks show
    float crack_mask = smoothstep(0.85, 1.0, crack);
    
    // Output: Only where cracks exist, draw white with some alpha
    // Background is fully transparent
    COLOR = vec4(crack_color, crack_mask * applied_intensity);
}
