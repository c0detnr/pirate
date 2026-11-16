shader_type spatial;
render_mode cull_disabled;

// Ocean.configure_material bu parametreleri tek kaynaktan doldurur.
uniform vec4 wave_a;
uniform vec4 wave_b;
uniform vec4 wave_c;
uniform float ocean_time;
varying float crest;
varying vec3 water_world;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 ship_position;
uniform vec2 ship_aft = vec2(0.0, 1.0);
uniform float ship_speed = 0.0;
uniform bool foam_enabled = true;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
    return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}

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
    water_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
        ndc.z = depth * 2.0 - 1.0;
    #endif
    vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    scene_view.xyz /= scene_view.w;
    float water_depth = max(-scene_view.z + VERTEX.z, 0.0);
    vec2 offset = water_world.xz - ship_position.xz;
    float aft = dot(offset, ship_aft);
    float side = abs(dot(offset, vec2(ship_aft.y, -ship_aft.x)));
    float near_hull = (1.0 - smoothstep(3.2, 4.8, side))
        * (1.0 - smoothstep(10.5, 14.0, abs(aft)));
    vec3 shallow = vec3(0.045, 0.22, 0.20);
    vec3 deep = vec3(0.018, 0.105, 0.19);
    // Shallows occupy only the first 30 cm of the depth gap. A nearby hull
    // stays under the dark sea pigment instead of lighting up like a sandbank.
    vec3 sea = mix(shallow, deep, smoothstep(0.025, 0.30, water_depth));
    sea = mix(sea, vec3(0.016, 0.085, 0.12), near_hull * 0.85);
    float facets = step(-0.07, crest) * 0.035 + step(0.18, crest) * 0.035;
    sea += vec3(0.18, 0.45, 0.43) * facets;
    float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0);
    sea = mix(sea, vec3(0.58, 0.64, 0.60), fresnel * mix(0.65, 0.16, near_hull));
    float foam = 0.0;
    if (foam_enabled) {
        float patches = noise(water_world.xz * 1.5 + vec2(ocean_time * 0.17, 0.0));
        float edge = 1.0 - smoothstep(0.015, 0.10, water_depth);
        foam = edge * step(0.30, patches);
        foam = max(foam, smoothstep(0.26, 0.37, crest) * step(0.65, patches) * 0.75);
        float width = 2.7 + max(aft - 7.0, 0.0) * 0.24;
        float froth = noise(water_world.xz * 5.0 - vec2(ocean_time * 0.23, ocean_time * 0.11));
        // Broken, wandering edges rather than two continuous luminous ribbons.
        float edge_jitter = (patches - 0.5) * 0.85;
        float wake = 1.0 - smoothstep(0.10, 0.70, abs(side - width + edge_jitter));
        wake *= smoothstep(6.0, 9.0, aft) * (1.0 - smoothstep(12.0, 36.0, aft));
        foam = max(foam, wake * smoothstep(0.1, 4.0, ship_speed) * smoothstep(0.40, 0.68, froth) * smoothstep(0.30, 0.55, patches) * 0.425);
    }
    ALBEDO = mix(sea, vec3(0.82, 0.84, 0.78), foam);
    ROUGHNESS = 0.85;
    SPECULAR = 0.0;
    EMISSION = ALBEDO * 0.13;
}
void light() {
    float illumination = max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION;
    float toon = 0.45 + step(0.30, illumination) * 0.22 + step(0.7, illumination) * 0.17;
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * toon / PI;
    float glint = dot(normalize(LIGHT + VIEW), NORMAL);
    float bands = step(0.985, glint) * 0.12 + step(0.996, glint) * 0.24;
    SPECULAR_LIGHT += vec3(1.0, 0.83, 0.53) * bands * LIGHT_COLOR * ATTENUATION / PI;
}
