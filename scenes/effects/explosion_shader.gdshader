shader_type canvas_item;
render_mode unshaded;

uniform float time = 0.0;
uniform float brightness_boost : hint_range(1.0, 3.0) = 1.5;

void fragment() {
    vec4 color = texture(TEXTURE, UV);
    // Add sparkle effect
    float sparkle = sin(time * 15.0 + UV.x * 30.0 + UV.y * 30.0) * 0.2;
    color.rgb += color.rgb * sparkle;  // Sparkle based on existing color
    // Boost brightness while preserving color ratios for bloom
    color.rgb *= brightness_boost;
    COLOR = color;
}