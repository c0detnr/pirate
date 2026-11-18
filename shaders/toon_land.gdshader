shader_type spatial;
// Island toon: same cel language as toon_ship (3 bands, hard terminator),
// albedo from baked vertex colours, object-anchored hatching in the shadow band.
render_mode diffuse_toon, specular_disabled, ambient_light_disabled, cull_disabled;

global uniform float night_amount; // 0 day, 1 night

uniform float sway_amount = 0.0;   // > 0 only for palm fronds / flag
uniform float sway_speed = 1.3;
uniform float hatch_density = 2.2;
uniform float hatch_strength = 0.22;
uniform vec3 day_ambient = vec3(0.36, 0.31, 0.46);
uniform vec3 night_ambient = vec3(0.045, 0.075, 0.17);

varying vec3 obj_pos;
varying float hatch_v;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
    obj_pos = VERTEX;
    if (sway_amount > 0.0) {
        float w = COLOR.a;
        float ph = TIME * sway_speed + VERTEX.x * 0.45 + VERTEX.z * 0.35;
        VERTEX.x += sin(ph) * 0.16 * w * w * sway_amount;
        VERTEX.z += cos(ph * 0.83) * 0.12 * w * w * sway_amount;
        VERTEX.y += sin(ph * 1.7 + 1.0) * 0.07 * w * w * sway_amount;
    }
}

void fragment() {
    vec3 p = obj_pos;
    float tone = 0.94 + hash(floor(p.xz * 1.7) + floor(p.y * 1.7)) * 0.1;
    ALBEDO = COLOR.rgb * tone;
    ROUGHNESS = 1.0;
    // Diagonal pen strokes anchored to the model, fading out when they would alias.
    float k = (p.x * 0.8 + p.y * 1.25 + p.z * 0.8) * hatch_density;
    float line = abs(fract(k) - 0.5) * 2.0;
    float aa = max(fwidth(k) * 2.0, 0.02);
    float stroke = 1.0 - smoothstep(0.78 - aa, 0.78 + aa, line);
    stroke *= 1.0 - smoothstep(0.12, 0.34, fwidth(k));
    // Stroke edge breaks up a little, like uneven ink.
    stroke *= step(0.18, hash(floor(vec2(k, (p.x - p.z) * 0.6))));
    hatch_v = stroke;
    vec3 ambient = mix(day_ambient, night_ambient, night_amount);
    EMISSION = ALBEDO * ambient;
}

void light() {
    float n = max(dot(NORMAL, LIGHT), 0.0);
    float lit = n * ATTENUATION;
    float band = step(0.18, lit) * 0.30 + step(0.56, lit) * 0.36;
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * band / PI;
    // Hatching only in the shadow band, as a darker ink wash.
    float shade = 1.0 - step(0.18, lit);
    DIFFUSE_LIGHT -= ALBEDO * hatch_v * shade * hatch_strength * mix(1.0, 0.45, night_amount);
    float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0) * step(0.3, lit);
    DIFFUSE_LIGHT += ALBEDO * rim * 0.09;
}
