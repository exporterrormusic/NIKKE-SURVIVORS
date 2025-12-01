shader_type canvas_item;

uniform float reveal_angle = -0.785; // -45 degrees in radians

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    vec2 dir = UV - center;
    float angle = atan(dir.y, dir.x);
    
    if (angle > reveal_angle) {
        discard;
    }
    
    COLOR = texture(TEXTURE, UV);
}