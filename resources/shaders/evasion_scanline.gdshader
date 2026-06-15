shader_type canvas_item;
render_mode unshaded;

// Scarlet's "Evasion" phase effect (Dodge i-frames / post-parry invincibility).
// Inspired by WoW's Evasion: the sprite goes translucent like a ghosted
// afterimage, with a faint cool shimmer sweeping across it. No red tint.

uniform float time : hint_range(0.0, 100000.0) = 0.0;
uniform float alpha = 0.42;          // overall transparency while phased
uniform vec4 shimmer : source_color = vec4(0.78, 0.9, 1.0, 1.0); // cool white-blue
uniform float desaturate = 0.4;      // pull toward grey so it reads as an afterimage
uniform float line_density = 20.0;   // slanted shimmer bands
uniform float slant = 0.7;           // band angle
uniform float scroll_speed = 2.2;    // band sweep speed
uniform float shimmer_strength = 0.22;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		discard;
	}

	// Slanted shimmer bands sweeping across the silhouette.
	float coord = UV.y + UV.x * slant - time * scroll_speed * 0.05;
	float band = sin(coord * line_density * 6.2831853) * 0.5 + 0.5;

	// Desaturate slightly so the translucent sprite reads as a "phased" image.
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 base = mix(tex.rgb, vec3(lum), desaturate);

	// Add a faint cool shimmer along the bands.
	vec3 col = base + shimmer.rgb * band * shimmer_strength;

	// Whole sprite goes translucent; bands stay a touch more opaque to read.
	float a = tex.a * alpha;
	a = clamp(a + band * 0.10 * tex.a, 0.0, 1.0);

	COLOR = vec4(col, a);
}
