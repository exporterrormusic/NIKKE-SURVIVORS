shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 flash_color : source_color = vec4(20.0, 8.0, 2.0, 1.0); // Even more extreme

// Simple hash for noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    float dist = distance(UV, vec2(0.5));
    float t = TIME * 15.0;
    
    // Outer glow (less transparent, narrower)
    float glow = 1.0 - smoothstep(0.0, 0.45, dist);
    glow = pow(glow, 1.5); // Fatter curve = more opaque
    
    // Core (very opaque)
    float core = 1.0 - smoothstep(0.0, 0.25, dist);
    core = pow(core, 0.8); // Makes core much larger and "denser"
    
    // Chaotic noise flicker in core
    float noise = hash(UV + vec2(t)) * 0.5 + 0.5;
    float chaotic_core = core * noise;
    
    // Blinding spark with jitter
    vec2 jitter = vec2(sin(t), cos(t)) * 0.02;
    float spark = 1.0 - smoothstep(0.0, 0.1, distance(UV + jitter, vec2(0.5)));
    
    vec4 final_color = flash_color * glow * 0.5;
    final_color += vec4(30.0, 25.0, 20.0, 1.0) * core; // White-hot thick core
    final_color += vec4(80.0, 80.0, 80.0, 1.0) * spark; // Absolute blinding center
    final_color += flash_color * chaotic_core * 1.5;
    
    // Less transparent overall: increase the multiplier on vertex alpha or just use a higher floor
    // The user wants it "less transparent", so we'll boost the alpha multiplier
    COLOR = final_color * (COLOR.a * 1.5); 
}
