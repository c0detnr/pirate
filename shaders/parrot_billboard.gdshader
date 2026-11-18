shader_type spatial;
render_mode unshaded, cull_disabled;
// Drawn characters: the parrot (full billboard) and the crew (upright).
global uniform float night_amount;
uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform float bank = 0.0;
uniform bool upright = false;
uniform vec3 day_tint = vec3(1.0);
// Moonlit by default; the scripts warm it near lanterns.
uniform vec3 night_tint = vec3(0.30, 0.35, 0.52);
void vertex() {
    if (upright) {
        // Same basis as BILLBOARD_FIXED_Y; shadows keep facing the main camera.
        vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz));
        vec3 front = normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0)));
        mat4 standing = mat4(vec4(side, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(front, 0.0), MODEL_MATRIX[3]);
        standing[0].xyz *= length(MODEL_MATRIX[0].xyz);
        standing[1].xyz *= length(MODEL_MATRIX[1].xyz);
        standing[2].xyz *= length(MODEL_MATRIX[2].xyz);
        MODELVIEW_MATRIX = VIEW_MATRIX * standing;
    } else {
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
}
void fragment() {
    vec4 ink = texture(art, UV);
    if (ink.a < 0.35) { discard; }
    ALBEDO = ink.rgb * mix(day_tint, night_tint, clamp(night_amount, 0.0, 1.0));
}
