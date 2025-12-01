shader_type canvas_item;
render_mode unshaded;

// Simple unshaded - just shows sprite at full brightness at night
void fragment() {
    COLOR = texture(TEXTURE, UV);
}
