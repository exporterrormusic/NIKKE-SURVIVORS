shader_type canvas_item;

// Bush sway shader - skew-based warping for natural sway effect
uniform float sway_amount : hint_range(0.0, 0.5) = 0.15;
uniform float sway_speed : hint_range(0.3, 3.0) = 0.8;
uniform float bump_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset = 0.0;

void vertex() {
	// Calculate sway factor based on height (more sway at top)
	float height_factor = 1.0 - UV.y;  // 0 at bottom, 1 at top
	
	// Base wind sway
	float time = TIME * sway_speed + time_offset;
	float wind_sway = sin(time) * sway_amount;
	wind_sway += sin(time * 2.1 + 0.5) * sway_amount * 0.3;  // Secondary wave
	
	// Bump shake (fast, large movement)
	float bump_sway = sin(TIME * 20.0) * bump_intensity * 0.4;
	bump_sway += sin(TIME * 31.0) * bump_intensity * 0.2;
	
	// Apply skew - this creates a shearing effect that looks like swaying
	// The higher up the vertex, the more it moves horizontally
	float total_sway = (wind_sway + bump_sway) * height_factor;
	
	// Skew the vertex by shifting X based on height
	VERTEX.x += total_sway * VERTEX.y * 0.01;
}

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
