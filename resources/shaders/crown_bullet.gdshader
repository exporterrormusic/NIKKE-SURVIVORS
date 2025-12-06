shader_type canvas_item;

// Simple gold tint shader for Crown's bullets
// Preserves original sprite details including white border

uniform vec4 gold_tint : source_color = vec4(1.0, 0.85, 0.3, 1.0);  // Warm gold
uniform float tint_strength : hint_range(0.0, 1.0) = 0.6;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    
    // Preserve luminance/brightness of original sprite
    float luminance = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
    
    // Tint towards gold while preserving details
    vec3 tinted = mix(tex.rgb, gold_tint.rgb * luminance * 1.5, tint_strength);
    
    // Keep bright areas (like white borders) mostly white
    float brightness = max(max(tex.r, tex.g), tex.b);
    tinted = mix(tinted, tex.rgb, smoothstep(0.7, 1.0, brightness) * 0.5);
    
    COLOR = vec4(tinted, tex.a);
}
