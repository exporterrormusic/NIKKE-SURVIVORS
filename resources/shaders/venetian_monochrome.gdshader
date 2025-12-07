shader_type canvas_item;

// Monochrome blue cyberpunk tint for venetian blinds background
// GPU-based for maximum performance

uniform float desaturation : hint_range(0.0, 1.0) = 0.6;
uniform vec3 tint_color : source_color = vec3(0.75, 0.9, 1.0);
uniform float brightness_boost : hint_range(0.8, 1.5) = 1.15;
uniform float contrast : hint_range(0.5, 1.5) = 1.1;

void fragment() {
    vec4 pixel = texture(TEXTURE, UV);
    
    // Calculate luminance (weighted for human perception)
    float luminance = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
    
    // Apply contrast and brightness boost
    luminance = (luminance - 0.5) * contrast + 0.5;
    luminance *= brightness_boost;
    luminance = clamp(luminance, 0.0, 1.0);
    
    // Create grayscale color
    vec3 gray = vec3(luminance);
    
    // Mix original with grayscale based on desaturation amount
    vec3 desaturated = mix(pixel.rgb, gray, desaturation);
    
    // Apply tint
    vec3 final_color = desaturated * tint_color;
    
    // Preserve transparent pixels
    float final_alpha = pixel.a;
    
    COLOR = vec4(final_color, final_alpha);
}
