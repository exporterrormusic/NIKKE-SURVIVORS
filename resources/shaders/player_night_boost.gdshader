shader_type canvas_item;
// NO render_mode unshaded - we want the sprite to receive scene lighting

// Night brightness boost - adds a subtle brightness increase at night
// This compensates for CanvasModulate darkening while preserving daytime look

uniform float night_boost : hint_range(0.0, 1.0) = 0.0;
uniform float boost_strength : hint_range(0.0, 2.0) = 0.5; // How much brighter at full night

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	
	// Only apply boost when night_boost > 0
	if (night_boost > 0.001 && tex.a > 0.0) {
		// Boost RGB brightness based on night intensity
		// This counteracts the CanvasModulate darkening
		float boost = 1.0 + (boost_strength * night_boost);
		tex.rgb *= boost;
	}
	
	// Apply modulate (vertex color from node.modulate)
	COLOR = tex * COLOR;
}
