shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform float bank = 0.0;
void vertex() {
    // Full camera-facing basis, including camera pitch; bank around screen normal.
    mat4 facing = INV_VIEW_MATRIX;
    facing[0].xyz *= length(MODEL_MATRIX[0].xyz);
    facing[1].xyz *= length(MODEL_MATRIX[1].xyz);
    facing[2].xyz *= length(MODEL_MATRIX[2].xyz);
    facing[3] = MODEL_MATRIX[3];
    MODELVIEW_MATRIX = VIEW_MATRIX * facing;
    float c = cos(bank);
    float s = sin(bank);
    VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
}
void fragment() {
    vec4 ink = texture(art, UV);
    if (ink.a < 0.35) { discard; }
    ALBEDO = ink.rgb;
}
