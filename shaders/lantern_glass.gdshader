shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Dull horn by day; a hot, blooming flame colour once night_amount rises.
global uniform float night_amount;
uniform float flame = 1.0;
uniform vec3 day_color : source_color = vec3(0.42, 0.33, 0.2);
void fragment() {
    float lit = smoothstep(0.12, 0.8, night_amount) * flame;
    float core = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
    vec3 glow = mix(vec3(1.1, 0.46, 0.14), vec3(2.2, 1.25, 0.5), core);
    ALBEDO = mix(day_color, glow, lit);
}
