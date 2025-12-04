shader_type canvas_item;

// Monochrome Tint Shader
// Converts image to grayscale then applies a color tint
// Creates a unified look across different source images

uniform vec3 tint_color : source_color = vec3(0.6, 0.85, 1.0);
uniform float desaturation : hint_range(0.0, 1.0) = 0.9;
uniform float brightness : hint_range(0.5, 2.0) = 1.1;
uniform float contrast : hint_range(0.5, 2.0) = 1.05;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    // Calculate luminance (grayscale value)
    float luminance = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
    
    // Apply contrast
    luminance = (luminance - 0.5) * contrast + 0.5;
    
    // Apply brightness
    luminance *= brightness;
    
    // Clamp luminance
    luminance = clamp(luminance, 0.0, 1.0);
    
    // Create grayscale color
    vec3 grayscale = vec3(luminance);
    
    // Mix original with grayscale based on desaturation
    vec3 desaturated = mix(tex_color.rgb, grayscale, desaturation);
    
    // Apply tint by multiplying with tint color
    vec3 tinted = desaturated * tint_color;
    
    // Output with original alpha
    COLOR = vec4(tinted, tex_color.a);
}
