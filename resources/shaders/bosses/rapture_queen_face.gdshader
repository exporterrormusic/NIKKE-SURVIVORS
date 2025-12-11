shader_type canvas_item;

// Face blending shader
// Blends the edges of the sprite into transparency/darkness using noise
// Simulates "liquid/smoke" edge

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 edge_color : source_color = vec4(0.05, 0.05, 0.08, 1.0); // Match body color
uniform float blend_width : hint_range(0.0, 0.5) = 0.1; // Reduced from 0.2 for less shadow
uniform float noise_strength : hint_range(0.0, 1.0) = 0.4;
uniform float time_speed : hint_range(0.0, 2.0) = 0.5;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    // Calculate distance from center (0.5, 0.5)
    vec2 center = vec2(0.5);
    float dist = distance(UV, center);
    
    // Moving noise
    vec2 noise_uv = UV + vec2(TIME * time_speed * 0.1, TIME * time_speed * 0.2);
    float noise_val = texture(noise_tex, noise_uv).r;
    
    // Edge threshold
    // 0.0 at center, 0.5 at edge
    // Pushing the smoothstep start closer to 0.5 reduces the shadow size
    float start = 0.5 - blend_width + (noise_val * noise_strength * 0.1);
    float mask = smoothstep(start, 0.5, dist);
    
    // Blend to darkness/transparency at edges
    // Reduce the multiplier to make the shadow less pitch black
    // mask goes 0->1. 
    vec3 final_rgb = mix(tex_color.rgb, edge_color.rgb, mask * 1.5); // Reduced from 2.0
    float final_a = tex_color.a * (1.0 - mask * 1.5); // Fade out alpha
    
    COLOR = vec4(final_rgb, final_a);
}
