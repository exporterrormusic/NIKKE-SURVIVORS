shader_type canvas_item;

// Cinematic Night Mode Shader
// Uses luminance-based tinting to preserve bright elements (projectiles, effects)
// while applying atmospheric color grading to dark areas (terrain, enemies)

// Night intensity: 0.0 = day (no effect), 1.0 = full night
uniform float night_intensity : hint_range(0.0, 1.0) = 0.9;

// Shadow tint - deep navy/purple for the darkest areas (more saturated blue)
uniform vec3 shadow_tint : source_color = vec3(0.08, 0.12, 0.35);

// Midtone tint - cool blue for mid-brightness areas
uniform vec3 midtone_tint : source_color = vec3(0.35, 0.45, 0.7);

// How much to desaturate dark areas (rod vision effect)
uniform float desaturation : hint_range(0.0, 1.0) = 0.7;

// Brightness threshold: pixels above this stay vibrant (lower = more things stay bright)
uniform float brightness_threshold : hint_range(0.1, 0.8) = 0.35;

// Transition smoothness for the brightness cutoff
uniform float transition_smoothness : hint_range(0.05, 0.5) = 0.2;

// Overall darkness multiplier for dark areas (lower = darker night)
uniform float darkness_factor : hint_range(0.2, 1.0) = 0.5;

// Contrast boost for dramatic look
uniform float contrast : hint_range(0.8, 1.5) = 1.2;

// Vignette integration
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.5;
uniform float vignette_radius : hint_range(0.3, 1.0) = 0.6;

// Screen texture sampler - required to read the rendered scene
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Calculate luminance using standard coefficients
float get_luminance(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

// Desaturate a color by a factor
vec3 desaturate_color(vec3 color, float factor) {
    float lum = get_luminance(color);
    return mix(color, vec3(lum), factor);
}

// Apply contrast adjustment
vec3 apply_contrast(vec3 color, float contrast_value) {
    return (color - 0.5) * contrast_value + 0.5;
}

void fragment() {
    // Sample the screen using the screen texture sampler
    vec4 screen_color = texture(screen_texture, SCREEN_UV);
    vec3 original = screen_color.rgb;
    
    // Calculate pixel luminance
    float lum = get_luminance(original);
    
    // Blend factor: 0 = dark pixel (apply full night effect), 1 = bright pixel (preserve)
    float blend = smoothstep(brightness_threshold - transition_smoothness, 
                             brightness_threshold + transition_smoothness, 
                             lum);
    
    // === Process ALL pixels with night grading ===
    
    // Desaturate the entire image (rod vision effect)
    vec3 desaturated = desaturate_color(original, desaturation);
    
    // Apply blue tint - stronger on darker areas
    // Use screen blending for a more natural color grade
    float tint_strength = 1.0 - lum * 0.5;  // Stronger tint on darks
    vec3 tint_color = mix(shadow_tint, midtone_tint, lum);
    
    // Blend the tint with the desaturated image
    vec3 tinted = mix(desaturated, desaturated * tint_color * 2.5, tint_strength * 0.6);
    
    // Apply overall darkness
    vec3 darkened = tinted * darkness_factor;
    
    // Apply contrast for punch
    vec3 contrasted = apply_contrast(darkened, contrast);
    
    // For bright pixels, preserve more of original color but still apply some tinting
    vec3 bright_version = original * mix(vec3(1.0), midtone_tint * 1.5, 0.2);
    
    // === Final composition ===
    
    // Blend between fully-processed dark and bright-preserved based on luminance
    vec3 night_result = mix(contrasted, bright_version, blend);
    
    // Blend between day (original) and night based on intensity
    vec3 final_color = mix(original, night_result, night_intensity);
    
    // === Vignette ===
    if (vignette_strength > 0.0) {
        vec2 center = SCREEN_UV - 0.5;
        float dist = length(center) / vignette_radius;
        float vignette = smoothstep(0.4, 1.0, dist) * vignette_strength * night_intensity;
        final_color *= (1.0 - vignette);
    }
    
    // Clamp to valid range
    COLOR = vec4(clamp(final_color, 0.0, 1.0), 1.0);
}
