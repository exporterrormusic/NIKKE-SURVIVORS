shader_type canvas_item;

// Red to Blue color swap shader for Marian's charm effect
// Changes red hues to blue while preserving other colors

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.0;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    
    // Calculate perceived luminance
    float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
    
    // Detect red-ish colors
    // Red has high R, low G and B
    float red_amount = tex.r - max(tex.g, tex.b);
    float is_red = smoothstep(0.1, 0.3, red_amount);
    
    // Also detect orange/pink (high R, medium others)
    float warm_amount = tex.r - (tex.g + tex.b) * 0.5;
    float is_warm = smoothstep(0.0, 0.2, warm_amount);
    
    // Combine detection
    float color_shift = max(is_red, is_warm * 0.7);
    
    // Create blue version - swap R and B channels, adjust for cyan-blue
    vec3 blue_version;
    blue_version.r = tex.b * 0.3 + tex.g * 0.2;  // Low red
    blue_version.g = tex.g * 0.6 + tex.b * 0.3;  // Teal-ish green
    blue_version.b = tex.r * 0.8 + tex.b * 0.2;  // High blue from original red
    
    // Preserve brightness
    float blue_luma = dot(blue_version, vec3(0.299, 0.587, 0.114));
    blue_version *= luma / max(blue_luma, 0.001);
    
    // Apply color shift with intensity
    vec3 final_color = mix(tex.rgb, blue_version, color_shift * intensity);
    
    // Add pulsing glow effect
    float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
    float glow = glow_strength * pulse * color_shift;
    final_color += vec3(0.2, 0.5, 1.0) * glow;
    
    COLOR = vec4(final_color, tex.a);
}
