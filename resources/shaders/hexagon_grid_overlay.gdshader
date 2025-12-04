shader_type canvas_item;

// Digital Screen Overlay - CRT/LCD screen effect
// Creates scanlines, brightness waves, and screen effects
// Designed to be used as an overlay on top of other content

uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.25;
uniform float scanline_count : hint_range(50.0, 400.0) = 150.0;
uniform float brightness_wave_speed : hint_range(0.0, 3.0) = 0.8;
uniform float brightness_wave_intensity : hint_range(0.0, 0.3) = 0.12;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.3;
uniform float refresh_line_speed : hint_range(0.0, 5.0) = 0.6;
uniform float refresh_line_intensity : hint_range(0.0, 0.5) = 0.2;
uniform float refresh_line_width : hint_range(0.01, 0.15) = 0.06;
uniform vec2 screen_size = vec2(1920.0, 1080.0);

void fragment() {
    vec2 uv = UV;
    vec2 screen_pos = uv * screen_size;
    float time = TIME;
    
    // === SCANLINES ===
    // Thick visible CRT horizontal scanlines
    float scanline = sin(screen_pos.y * PI * 2.0 / (screen_size.y / scanline_count));
    scanline = scanline * 0.5 + 0.5;  // Normalize to 0-1
    scanline = pow(scanline, 0.6);     // Softer, thicker lines
    float scanline_dark = scanline * scanline_intensity;
    
    // === BRIGHTNESS WAVE ===
    // Slow moving brightness variation across the screen
    float wave1 = sin(uv.y * 4.0 + time * brightness_wave_speed) * 0.5 + 0.5;
    float wave2 = sin(uv.y * 2.5 - time * brightness_wave_speed * 0.7 + 1.0) * 0.5 + 0.5;
    float wave3 = sin((uv.x + uv.y) * 3.0 + time * brightness_wave_speed * 0.5) * 0.5 + 0.5;
    float brightness_wave = (wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2);
    brightness_wave = brightness_wave * brightness_wave_intensity;
    
    // === REFRESH LINE ===
    // Single slow, thick bright horizontal line sweeping down
    // Starts above screen (-0.1) and exits below (1.1) for smooth appearance
    float refresh_cycle = fract(time * refresh_line_speed);
    float refresh_pos = mix(-0.15, 1.15, refresh_cycle);  // -0.15 to 1.15 range
    float refresh_dist = abs(uv.y - refresh_pos);
    float refresh_line = smoothstep(refresh_line_width, 0.0, refresh_dist);
    float refresh_brightness = refresh_line * refresh_line_intensity;
    
    // === VIGNETTE ===
    // Darker edges
    vec2 vignette_uv = uv * (1.0 - uv);
    float vignette = pow(vignette_uv.x * vignette_uv.y * 16.0, vignette_strength);
    vignette = clamp(vignette, 0.0, 1.0);
    float vignette_darken = (1.0 - vignette) * 0.25;
    
    // === COMBINE EFFECTS ===
    // Darkening: scanlines + vignette
    float total_darken = scanline_dark + vignette_darken;
    
    // Brightening: waves + refresh line (subtract from darken)
    float total_brighten = brightness_wave + refresh_brightness;
    
    // Net effect
    float net_darken = clamp(total_darken - total_brighten, 0.0, 0.6);
    
    // Refresh line glow color (subtle cyan)
    vec3 glow_color = vec3(0.5, 0.8, 1.0) * refresh_brightness;
    
    COLOR = vec4(glow_color, net_darken);
}
