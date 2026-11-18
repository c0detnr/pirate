shader_type spatial;
// Horizon silhouettes: flat, unlit, tinted toward haze with distance, dark at night.
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

global uniform float night_amount; // 0 day, 1 night

uniform vec3 near_color : source_color = vec3(0.27, 0.27, 0.35);
uniform vec3 haze_color : source_color = vec3(0.50, 0.48, 0.55);
uniform vec3 night_near : source_color = vec3(0.025, 0.04, 0.075);
uniform vec3 night_haze : source_color = vec3(0.06, 0.09, 0.15);
uniform float haze_start = 180.0;
uniform float haze_end = 520.0;

void fragment() {
    float dist = length(VERTEX);
    float haze = smoothstep(haze_start, haze_end, dist) * 0.75;
    float height_tone = COLOR.a;
    vec3 day = mix(near_color * (0.82 + 0.3 * height_tone), haze_color, haze);
    vec3 night = mix(night_near * (0.9 + 0.4 * height_tone), night_haze, haze);
    ALBEDO = mix(day, night, night_amount);
}
