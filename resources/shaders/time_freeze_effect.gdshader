shader_type canvas_item;

// Time freeze effect - visible distortion + desaturation + blue tint
// Applied to enemies during Wells's Bullet Time

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset : hint_range(0.0, 100.0) = 0.0;

void fragment() {
    // Sample original color
    vec4 color = texture(TEXTURE, UV);
    
    // Apply wave distortion when intensity > 0
    if (intensity > 0.01) {
        // Visible UV wobble - enemies "rippling" in frozen time
        vec2 wave_uv = UV;
        float wave = sin(UV.y * 15.0 + time_offset * 3.0) * 0.015 * intensity;
        wave_uv.x += wave;
        color = texture(TEXTURE, wave_uv);
        
        // Strong desaturation - washed out/frozen look
        float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
        color.rgb = mix(color.rgb, vec3(gray), intensity * 0.6);
        
        // Noticeable blue/cyan tint - cold/frozen feel
        color.rgb = mix(color.rgb, color.rgb * vec3(0.7, 0.85, 1.3), intensity * 0.7);
    }
    
    COLOR = color;
}
