shader_type canvas_item;

// Purple burning trail effect for Marian's burst upgrade
// Ground fire with mystical purple flames

uniform float time_scale : hint_range(0.5, 5.0) = 2.5;
uniform vec4 flame_color_1 : source_color = vec4(0.6, 0.1, 0.9, 1.0);  // Deep purple
uniform vec4 flame_color_2 : source_color = vec4(0.9, 0.4, 1.0, 1.0);  // Bright magenta
uniform vec4 flame_color_3 : source_color = vec4(0.3, 0.0, 0.5, 0.8);  // Dark purple base
uniform float flame_height : hint_range(0.3, 1.0) = 0.7;
uniform float turbulence : hint_range(1.0, 10.0) = 5.0;

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

float fbm(vec2 p, float time) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p);
        p = p * 2.0 + vec2(time * 0.5);
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    float time = TIME * time_scale;
    vec2 uv = UV;
    
    // Flame rises upward (inverted Y)
    float y = 1.0 - uv.y;
    
    // Add horizontal movement
    float x_offset = fbm(vec2(uv.x * 3.0, time * 0.5), time) * 0.2;
    float x = uv.x + x_offset;
    
    // Create flame shape with noise
    float flame_noise = fbm(vec2(x * turbulence, y * turbulence - time * 2.0), time);
    float flame_noise2 = fbm(vec2(x * turbulence * 1.5 + 100.0, y * turbulence * 1.2 - time * 2.5), time);
    
    // Combine noise layers
    float combined = flame_noise * 0.6 + flame_noise2 * 0.4;
    
    // Flame shape - wider at bottom, narrow at top
    float width = 0.5 - y * 0.3;
    float dist_from_center = abs(uv.x - 0.5);
    float horizontal_mask = 1.0 - smoothstep(width * 0.5, width, dist_from_center);
    
    // Vertical flame gradient
    float flame = combined * horizontal_mask;
    flame *= 1.0 - smoothstep(0.0, flame_height, y);
    
    // Color based on height (dark at base, bright in middle, fading at top)
    vec3 color;
    if (y < 0.3) {
        color = mix(flame_color_3.rgb, flame_color_1.rgb, y / 0.3);
    } else if (y < 0.6) {
        color = mix(flame_color_1.rgb, flame_color_2.rgb, (y - 0.3) / 0.3);
    } else {
        color = mix(flame_color_2.rgb, vec3(1.0, 0.8, 1.0), (y - 0.6) / 0.4);
    }
    
    // Add bright spots
    float sparks = smoothstep(0.7, 0.9, fbm(vec2(x * 20.0, y * 10.0 - time * 5.0), time));
    color = mix(color, vec3(1.0, 0.9, 1.0), sparks * 0.5 * horizontal_mask);
    
    // Calculate alpha
    float alpha = flame * flame_color_1.a;
    alpha *= smoothstep(0.0, 0.1, flame);  // Cut off very low values
    
    COLOR = vec4(color, alpha);
}
