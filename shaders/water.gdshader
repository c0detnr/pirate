shader_type spatial;
render_mode cull_disabled;

// Ocean.configure_material bu parametreleri tek kaynaktan doldurur.
uniform vec4 wave_a;
uniform vec4 wave_b;
uniform vec4 wave_c;
uniform float ocean_time;
varying float crest;

float wave_height(vec2 p, vec4 w) {
    return w.x * sin(dot(p, vec2(cos(w.w), sin(w.w))) * w.y + ocean_time * w.z);
}
vec2 wave_slope(vec2 p, vec4 w) {
    vec2 direction = vec2(cos(w.w), sin(w.w));
    return direction * w.x * w.y * cos(dot(p, direction) * w.y + ocean_time * w.z);
}
void vertex() {
    vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
    float h = wave_height(p, wave_a) + wave_height(p, wave_b) + wave_height(p, wave_c);
    VERTEX.y += h;
    vec2 slope = wave_slope(p, wave_a) + wave_slope(p, wave_b) + wave_slope(p, wave_c);
    NORMAL = normalize(vec3(-slope.x, 1.0, -slope.y));
    crest = h;
}
void fragment() {
    vec3 deep_blue = vec3(0.025, 0.24, 0.39);
    vec3 light_blue = vec3(0.04, 0.48, 0.61);
    float band = step(0.02, crest) * 0.55 + step(0.20, crest) * 0.45;
    ALBEDO = mix(deep_blue, light_blue, band);
    ALBEDO = mix(ALBEDO, vec3(0.68, 0.90, 0.89), smoothstep(0.29, 0.32, crest) * 0.7);
    ROUGHNESS = 0.65;
    SPECULAR = 0.35;
}
void light() {
    float toon = floor(max(dot(NORMAL, LIGHT), 0.0) * 3.0) / 3.0;
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * (0.25 + toon * 0.75);
}
