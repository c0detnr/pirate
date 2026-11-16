shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
    float radius = length((UV - vec2(0.5)) * 2.0);
    ALBEDO = vec3(0.025, 0.018, 0.013);
    ALPHA = (1.0 - smoothstep(0.25, 1.0, radius)) * 0.28;
}
