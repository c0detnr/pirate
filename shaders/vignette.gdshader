shader_type canvas_item;
render_mode unshaded;
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float edge = smoothstep(0.38, 1.55, dot(p,p));
    COLOR = vec4(0.10, 0.055, 0.035, edge * 0.17);
}
