shader_type canvas_item;

// Red pulse/ripple effect for DoT damage
// Performance-friendly: simple color overlay with pulse

uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
    vec4 color = texture(TEXTURE, UV);
    
    if (pulse_intensity > 0.01) {
        // Pulsing red overlay
        float pulse = sin(pulse_time * 6.0) * 0.5 + 0.5; // 0.0 to 1.0 cycle
        float red_amount = pulse_intensity * pulse * 0.6;
        
        // Add red tint - make it look like burning/damage
        color.r = min(1.0, color.r + red_amount);
        color.g *= (1.0 - red_amount * 0.5);
        color.b *= (1.0 - red_amount * 0.5);
        
        // Slight brightness pulse
        color.rgb *= 1.0 + (pulse * pulse_intensity * 0.2);
    }
    
    COLOR = color;
}
