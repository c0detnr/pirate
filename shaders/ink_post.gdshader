shader_type spatial;
// Full-screen ink pass. Runs first in the transparent queue (render_priority
// -128), so water, foot shadows and glass paint over it, and it outputs ink
// with alpha instead of reading the screen: no screen-texture copy is needed.
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, repeat_disable, filter_nearest;
uniform float line_width = 1.5;      // Pixels at 720p.
uniform float line_opacity = 0.9;
uniform float crease_strength = 0.8; // 0 skips the normal taps entirely.
uniform float wobble = 1.0;          // 0 gives a mechanically even line.
uniform float fade_start = 30.0;
uniform float fade_end = 220.0;
uniform mat4 anchor_from_world = mat4(1.0);

const vec3 INK = vec3(0.0232, 0.0103, 0.0052);
const float SILHOUETTE_GAP = 0.011; // Relative depth step that starts a line.

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
    float centre = texture(depth_tex, SCREEN_UV).r;
    if (centre < 0.000001) { discard; } // Sky and the depth-less water.
    vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, centre, 1.0);
    view.xyz /= view.w;
    float dist = -view.z;

    // Stroke character is anchored to the ship, so it never swims on screen.
    float weight = 0.0;
    float dry = 0.0;
    vec2 nudge = vec2(0.0);
    float near_detail = 1.0 - smoothstep(16.0, 55.0, dist);
    if (wobble > 0.0 && near_detail > 0.0) {
        vec3 a = (anchor_from_world * (INV_VIEW_MATRIX * vec4(view.xyz, 1.0))).xyz;
        weight = sin(a.x * 1.7 + a.y * 2.3 + sin(a.z * 1.1) * 1.6) * 0.6 + sin(a.z * 4.3 + a.x * 3.1) * 0.4;
        dry = sin(a.z * 7.3 + a.y * 5.9 + sin(a.x * 3.7) * 2.0);
        nudge = vec2(sin(a.y * 3.3 + a.z * 2.1), sin(a.x * 2.9 - a.z * 1.7)) * 0.35 * wobble * near_detail;
        weight *= wobble * near_detail;
    }
    float width = line_width * (VIEWPORT_SIZE.y / 720.0) * (1.0 + weight * 0.42);
    // Heavy near the viewer, a fine line in the distance.
    width *= mix(1.3, 0.6, smoothstep(2.5, 45.0, dist));
    vec2 texel = 1.0 / VIEWPORT_SIZE;
    vec2 step_uv = texel * max(width, 0.75);
    vec2 uv = SCREEN_UV + nudge * texel;

    float left = texture(depth_tex, uv - vec2(step_uv.x, 0.0)).r;
    float right = texture(depth_tex, uv + vec2(step_uv.x, 0.0)).r;
    float down = texture(depth_tex, uv - vec2(0.0, step_uv.y)).r;
    float up = texture(depth_tex, uv + vec2(0.0, step_uv.y)).r;

    // Raw depth is linear across any plane in screen space, so the second
    // difference ignores grazing decks. Only the positive side (this pixel is
    // nearer than its surroundings) is inked: the line stays on the object, and
    // a thin rope never grows a halo.
    float bulge = max(2.0 * centre - left - right, 2.0 * centre - down - up) / centre;
    float line = smoothstep(SILHOUETTE_GAP, SILHOUETTE_GAP * 2.4, bulge);

    vec4 own = texture(normal_tex, SCREEN_UV);
    // Materials tag themselves through roughness (measured in this buffer:
    // solids 0.86-1.0, sails 0.6, rigging 0.3): see ink_tag in toon_ship.
    float tag = own.a;
    float thin = 1.0 - smoothstep(0.42, 0.50, tag);
    float cloth = smoothstep(0.42, 0.50, tag) * (1.0 - smoothstep(0.72, 0.80, tag));

    if (crease_strength > 0.0 && thin + cloth < 0.5) {
        float crease_fade = 1.0 - smoothstep(14.0, 48.0, dist);
        if (crease_fade > 0.0) {
            vec3 n = own.xyz * 2.0 - 1.0;
            vec3 nr = texture(normal_tex, uv + vec2(step_uv.x, 0.0)).xyz * 2.0 - 1.0;
            vec3 nu = texture(normal_tex, uv + vec2(0.0, step_uv.y)).xyz * 2.0 - 1.0;
            float same_r = 1.0 - smoothstep(0.02, 0.05, abs(right - centre) / centre);
            float same_u = 1.0 - smoothstep(0.02, 0.05, abs(up - centre) / centre);
            float bend = max((1.0 - dot(n, nr)) * same_r, (1.0 - dot(n, nu)) * same_u);
            line = max(line, smoothstep(0.16, 0.42, bend) * crease_strength * crease_fade);
        }
    }

    float alpha = line * line_opacity;
    alpha *= 1.0 - smoothstep(fade_start, fade_end, dist) * 0.8;
    alpha *= 1.0 - thin * 0.62;
    alpha *= 1.0 - cloth * 0.22;
    alpha *= 1.0 - smoothstep(0.55, 1.0, dry) * 0.4 * near_detail * wobble;
    if (alpha < 0.012) { discard; }
    ALBEDO = INK;
    ALPHA = alpha;
}
