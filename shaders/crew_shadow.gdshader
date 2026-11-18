shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
global uniform float night_amount;
void fragment() {
    float radius = length((UV - vec2(0.5)) * 2.0);
    // A pool of ink strokes rather than an airbrushed blob.
    float v = (UV.x * 0.8 + UV.y * 0.6) * 15.0 + sin(UV.y * 9.0) * 0.25;
    float aa = fwidth(v);
    float strokes = 1.0 - smoothstep(0.26, 0.26 + aa + 0.04, abs(fract(v) - 0.5));
    strokes = mix(strokes, 0.5, smoothstep(0.25, 0.5, aa));
    ALBEDO = vec3(0.025, 0.018, 0.013);
    float pool = 1.0 - smoothstep(0.25, 1.0, radius);
    // Moonlight casts a fainter, softer shadow than the sun.
    ALPHA = pool * mix(0.20 + strokes * 0.16, 0.16, clamp(night_amount, 0.0, 1.0));
}
