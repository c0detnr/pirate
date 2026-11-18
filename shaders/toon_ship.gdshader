shader_type spatial;
render_mode diffuse_toon, specular_disabled, ambient_light_disabled, cull_disabled;
global uniform float night_amount;
uniform vec4 base_color : source_color = vec4(0.55, 0.4, 0.24, 1.0);
// 0 solid, 1 deck, 2 hull, 3 fine grain, 4 sail, 5 metal.
uniform int surface_kind = 0;
uniform mat4 mesh_to_ship;
uniform vec4 cloth_bounds;
uniform float hatch_strength = 1.0; // 0 skips hatching.
uniform float grain_strength = 1.0; // 0 skips the paper finish.
// Stored in roughness for ink_post: 1 solid, 0.35 thin rigging.
uniform float ink_tag = 1.0;
varying vec3 plank_position;
varying vec2 hatch_loss;   // x: single hatch, y: cross hatch.
varying vec3 ambient_fill;
varying float band_rough;  // Hand-cut edge for the light bands.

const vec3 DAY_FILL = vec3(0.36, 0.31, 0.46);
const vec3 NIGHT_FILL = vec3(0.085, 0.110, 0.185);
const float HATCH_SPACING = 0.066;
const float LANTERN_GAIN = 0.2;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
// One family of hand-drawn strokes; fades out before it can alias.
float hatch_lines(vec2 q) {
    float v = q.y + sin(q.x * 0.23 + q.y * 0.11) * 0.10 + sin(q.x * 1.3) * 0.03;
    float w = fwidth(v);
    float fade = 1.0 - smoothstep(0.14, 0.32, w);
    if (fade <= 0.0) { return 0.0; }
    float row = floor(v);
    // Each stroke has its own length and pressure, tapering into gaps.
    float pen = smoothstep(-0.55, 0.35, sin(q.x * 0.19 + row * 2.4)) * (0.075 + 0.03 * sin(row * 3.7));
    return (1.0 - smoothstep(pen, pen + w + 0.025, abs(fract(v) - 0.5))) * fade;
}
void vertex() { plank_position = (mesh_to_ship * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec3 p = plank_position;
    float tone = 1.0;
    float ink = 0.0;
    if (surface_kind == 1 || surface_kind == 2) {
        float across = (surface_kind == 1 ? p.x : p.y) / 0.32;
        float row = floor(across);
        float along = p.z + mod(row, 3.0) * 1.17;
        float end = fract(along / 3.5);
        float seam = min(fract(across), 1.0 - fract(across));
        float aa = max(fwidth(across), 0.008);
        ink = 1.0 - smoothstep(0.012, 0.012 + aa, seam);
        ink = max(ink, (1.0 - smoothstep(0.003, 0.003 + fwidth(along / 3.5), min(end, 1.0-end))) * 0.8);
        tone = 0.93 + hash(vec2(row, floor(along / 3.5))) * 0.15;
        tone -= smoothstep(0.7, 0.97, sin(p.z * 2.3 + row * 7.1) * sin(p.x * 4.1 + p.y * 3.0)) * 0.06;
    }
    if (surface_kind >= 1 && surface_kind <= 3) {
        float grain = sin(p.z * 8.0 + sin(p.z * 1.7 + p.y) * 1.5 + p.x * 91.0 + p.y * 53.0);
        tone -= smoothstep(0.86, 0.98, grain) * 0.055;
    }
    if (surface_kind == 4) {
        float seam = abs(fract(p.x * 1.65) - 0.5);
        tone = 0.98 - smoothstep(0.475, 0.497, seam) * 0.13;
        float edge = min(min(p.x - cloth_bounds.x, cloth_bounds.y - p.x), min(p.y - cloth_bounds.z, cloth_bounds.w - p.y));
        tone -= (1.0 - smoothstep(0.0, 0.28, edge)) * 0.18;
        // UV-free weathered cloth: broad, irregular pigment patches.
        tone -= smoothstep(0.45, 0.9, sin(p.x * 1.9) * sin(p.y * 2.1)) * 0.06;
    }
    // Flat ship-space normal picks the plane that hatch and grain are drawn on.
    vec3 facing = abs(cross(dFdx(p), dFdy(p)));
    vec2 sheet = facing.y >= facing.x && facing.y >= facing.z ? p.xz : (facing.x >= facing.z ? p.zy : p.xy);
    vec3 pigment = vec3(1.0);
    if (grain_strength > 0.0) {
        float blotch = value_noise(sheet * 1.35 + 11.0) - 0.5;
        vec2 fine_uv = sheet * 13.0;
        float fine_fade = 1.0 - smoothstep(0.35, 0.8, length(fwidth(fine_uv)));
        float fine = fine_fade > 0.0 ? (value_noise(fine_uv) - 0.5) * fine_fade : 0.0;
        tone *= 1.0 + (blotch * 0.10 + fine * 0.075) * grain_strength;
        pigment += vec3(0.018, 0.0, -0.022) * blotch * 2.0 * grain_strength;
    }
    band_rough = sin(sheet.x * 5.1 + sin(sheet.y * 3.3) * 1.2) * 0.5 + sin(sheet.y * 11.3 + sheet.x * 2.7) * 0.5;
    hatch_loss = vec2(0.0);
    if (hatch_strength > 0.0) {
        vec2 q = sheet / HATCH_SPACING;
        float single = hatch_lines(vec2(q.x * 0.766 + q.y * 0.643, q.y * 0.766 - q.x * 0.643));
        float cross_lines = hatch_lines(vec2(q.x * 0.5 - q.y * 0.866, q.x * 0.866 + q.y * 0.5) * 0.86 + 3.1);
        // Cross hatching gathers in patches instead of a uniform net.
        float gather = smoothstep(-0.05, 0.5, sin(sheet.x * 1.1 + sin(sheet.y * 0.8) * 1.3) * sin(sheet.y * 0.9 + 1.7));
        hatch_loss = vec2(single * 0.30, cross_lines * gather * 0.24) * hatch_strength;
    }
    ALBEDO = mix(base_color.rgb * tone * pigment, vec3(0.085, 0.041, 0.023), ink * 0.67);
    ROUGHNESS = ink_tag;
    ambient_fill = mix(DAY_FILL, NIGHT_FILL, clamp(night_amount, 0.0, 1.0));
    EMISSION = ALBEDO * ambient_fill * (1.0 - hatch_loss.x) * (1.0 - hatch_loss.y);
}
void light() {
    float n = max(dot(NORMAL, LIGHT), 0.0);
    // The engine multiplies DIFFUSE_LIGHT by ALBEDO again after this function.
    if (LIGHT_IS_DIRECTIONAL) {
        float lit = n * ATTENUATION * (1.0 + band_rough * 0.07);
        float mid = step(0.18, lit);
        float full = step(0.56, lit);
        DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * (mid * 0.30 + full * 0.36) / PI;
        // Hatching is cut out of the fill: light hands back what it covers, so
        // cross hatch stays in shadow and single hatch in the half-tone band.
        DIFFUSE_LIGHT += ambient_fill * (hatch_loss.y * mid + hatch_loss.x * full);
        float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0) * step(0.3, lit);
        DIFFUSE_LIGHT += base_color.rgb * LIGHT_COLOR * rim * 0.09 / PI;
    } else {
        // Lantern pool: wrapped so it reaches the deck, three inked steps.
        float wrapped = clamp(dot(NORMAL, LIGHT) * 0.72 + 0.28, 0.0, 1.0);
        float lit = wrapped * ATTENUATION * (1.0 + band_rough * 0.10);
        float outer = step(0.085, lit);
        float inner = step(0.25, lit);
        float core = step(0.62, lit);
        float pool = outer * 0.22 + inner * 0.32 + core * 0.40;
        pool *= 1.0 - (outer - inner) * clamp(hatch_loss.x + hatch_loss.y, 0.0, 1.0) * 1.3;
        DIFFUSE_LIGHT += LIGHT_COLOR * pool * LANTERN_GAIN;
    }
    if (surface_kind == 5) {
        float shine = step(0.94, dot(normalize(LIGHT + VIEW), NORMAL));
        SPECULAR_LIGHT += LIGHT_COLOR * shine * ATTENUATION * 0.25 / PI;
    }
}
