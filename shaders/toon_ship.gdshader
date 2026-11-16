shader_type spatial;
render_mode diffuse_toon, specular_disabled, ambient_light_disabled, cull_disabled;
uniform vec4 base_color : source_color = vec4(0.55, 0.4, 0.24, 1.0);
// 0 solid, 1 deck, 2 hull, 3 fine grain, 4 sail, 5 metal.
uniform int surface_kind = 0;
uniform mat4 mesh_to_ship;
uniform vec4 cloth_bounds;
varying vec3 plank_position;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
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
    ALBEDO = mix(base_color.rgb * tone, vec3(0.085, 0.041, 0.023), ink * 0.67);
    ROUGHNESS = 1.0;
    EMISSION = ALBEDO * vec3(0.36, 0.31, 0.46);
}
void light() {
    float n = max(dot(NORMAL, LIGHT), 0.0);
    float lit = n * ATTENUATION;
    float band = step(0.18, lit) * 0.30 + step(0.56, lit) * 0.36;
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * band / PI;
    float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0) * step(0.3, lit);
    DIFFUSE_LIGHT += base_color.rgb * rim * 0.09;
    if (surface_kind == 5) {
        float shine = step(0.94, dot(normalize(LIGHT + VIEW), NORMAL));
        SPECULAR_LIGHT += LIGHT_COLOR * shine * ATTENUATION * 0.25 / PI;
    }
}
