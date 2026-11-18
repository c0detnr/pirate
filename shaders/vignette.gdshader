shader_type canvas_item;
render_mode unshaded;
global uniform float night_amount;
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float edge = smoothstep(0.38, 1.55, dot(p,p));
    vec3 tint = mix(vec3(0.10, 0.055, 0.035), vec3(0.008, 0.016, 0.04), night_amount);
    COLOR = vec4(tint, edge * mix(0.17, 0.30, night_amount));
}
