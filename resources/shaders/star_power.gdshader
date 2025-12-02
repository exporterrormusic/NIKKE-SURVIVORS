shader_type canvas_item;

// Mario Star Power effect - rapid rainbow color cycling
uniform float time_scale : hint_range(1.0, 20.0) = 8.0;
uniform float saturation : hint_range(0.5, 1.0) = 0.9;
uniform float brightness : hint_range(1.0, 2.0) = 1.4;
uniform float flash_intensity : hint_range(0.0, 1.0) = 0.7;

// Convert HSV to RGB
vec3 hsv_to_rgb(float h, float s, float v) {
    vec3 rgb;
    float c = v * s;
    float x = c * (1.0 - abs(mod(h * 6.0, 2.0) - 1.0));
    float m = v - c;
    
    if (h < 1.0/6.0) {
        rgb = vec3(c, x, 0.0);
    } else if (h < 2.0/6.0) {
        rgb = vec3(x, c, 0.0);
    } else if (h < 3.0/6.0) {
        rgb = vec3(0.0, c, x);
    } else if (h < 4.0/6.0) {
        rgb = vec3(0.0, x, c);
    } else if (h < 5.0/6.0) {
        rgb = vec3(x, 0.0, c);
    } else {
        rgb = vec3(c, 0.0, x);
    }
    
    return rgb + m;
}

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    // Only affect visible pixels
    if (tex_color.a > 0.01) {
        // Rapid hue cycling like Mario star
        float hue = fract(TIME * time_scale * 0.1);
        
        // Get rainbow color
        vec3 rainbow = hsv_to_rgb(hue, saturation, brightness);
        
        // Flash effect - alternating bright/normal
        float flash = 0.5 + 0.5 * sin(TIME * time_scale * 2.0);
        
        // Mix original color with rainbow, keeping luminance structure
        float lum = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
        vec3 tinted = rainbow * (0.5 + lum * 0.8);
        
        // Apply flash - blend between tinted and bright white
        vec3 flash_color = mix(tinted, vec3(1.0, 1.0, 0.9), flash * flash_intensity * 0.4);
        
        // Boost overall brightness
        flash_color = flash_color * brightness;
        
        COLOR = vec4(flash_color, tex_color.a);
    } else {
        COLOR = tex_color;
    }
}
