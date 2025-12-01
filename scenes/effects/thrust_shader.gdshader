shader_type canvas_item;

uniform float reveal = 0.0;

void fragment() {
    if (UV.x > reveal) {
        COLOR.a = 0.0;
    } else {
        COLOR = texture(TEXTURE, UV);
    }
}