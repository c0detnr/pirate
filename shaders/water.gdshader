shader_type spatial;
render_mode cull_disabled, fog_disabled;

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
// Day/night: set by day_night.gd; horizon_tint() mirrors sky.gdshader.
global uniform float night_amount;
uniform vec3 sun_direction = vec3(-0.6185, 0.2693, 0.7382);
uniform vec3 moon_direction = vec3(0.6211, 0.4208, -0.6612);
varying vec3 glitter_normal;
varying float sea_far;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
    return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}

vec3 horizon_tint(vec3 dir) {
    vec2 flat_dir = normalize(dir.xz + vec2(0.00001));
    float sunward = dot(flat_dir, normalize(sun_direction.xz)) * 0.5 + 0.5;
    float moonward = dot(flat_dir, normalize(moon_direction.xz)) * 0.5 + 0.5;
    vec3 day = mix(vec3(0.17, 0.165, 0.195), vec3(0.66, 0.33, 0.14), sunward * sunward * sunward);
    vec3 night = mix(vec3(0.012, 0.024, 0.045), vec3(0.030, 0.050, 0.085), pow(moonward, 5.0));
    return mix(day, night, night_amount);
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
    float night = clamp(night_amount, 0.0, 1.0);
    vec3 shallow = mix(vec3(0.05, 0.20, 0.19), vec3(0.010, 0.038, 0.058), night);
    vec3 deep = mix(vec3(0.022, 0.095, 0.155), vec3(0.006, 0.024, 0.050), night);
    // Shallows occupy only the first 30 cm of the depth gap. A nearby hull
    // stays under the dark sea pigment instead of lighting up like a sandbank.
    vec3 sea = mix(shallow, deep, smoothstep(0.025, 0.30, water_depth));
    sea = mix(sea, mix(vec3(0.016, 0.075, 0.105), vec3(0.003, 0.012, 0.026), night), near_hull * 0.85);
    float facets = step(-0.07, crest) * 0.035 + step(0.18, crest) * 0.035;
    sea += mix(vec3(0.20, 0.40, 0.38), vec3(0.07, 0.14, 0.24), night) * facets;
    vec3 ray = normalize(water_world - CAMERA_POSITION_WORLD);
    float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0) * mix(0.65, 0.16, near_hull);
    vec3 sky_mirror = horizon_tint(ray) * fresnel;
    sea *= 1.0 - fresnel;
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
    vec3 foam_color = mix(vec3(0.80, 0.76, 0.66), vec3(0.20, 0.27, 0.36), night);
    vec3 painted = mix(sea, foam_color, foam);
    // Hand-made aerial perspective: the far sea becomes exactly the sky's horizon.
    float distance_to_eye = length(water_world - CAMERA_POSITION_WORLD);
    sea_far = smoothstep(70.0, 285.0, distance_to_eye);
    ALBEDO = painted * (1.0 - sea_far);
    ROUGHNESS = 0.85;
    SPECULAR = 0.0;
    EMISSION = mix(painted * mix(0.13, 0.10, night) + sky_mirror * (1.0 - foam), horizon_tint(ray) * mix(1.0, 0.66, night), sea_far);
    // Sparkle normal: small drifting chop that breaks reflections into a path.
    float t = ocean_time;
    vec2 chop = vec2(noise(water_world.xz * 1.9 + vec2(t * 0.55, t * 0.3)), noise(water_world.xz * 2.7 - vec2(t * 0.4, -t * 0.62))) - 0.5;
    glitter_normal = normalize(NORMAL + (VIEW_MATRIX * vec4(chop.x, 0.0, chop.y, 0.0)).xyz * 0.62);
}
void light() {
    float illumination = max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION;
    float toon = 0.45 + step(0.30, illumination) * 0.22 + step(0.7, illumination) * 0.17;
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * toon / PI;
    float glint = dot(normalize(LIGHT + VIEW), glitter_normal);
    if (LIGHT_IS_DIRECTIONAL) {
        // Two hard tones keep the sun and moon paths drawn rather than photographic.
        float bands = step(0.9925, glint) * 0.16 + step(0.9975, glint) * 0.42;
        vec3 tint = mix(vec3(1.0, 0.80, 0.56), vec3(0.86, 0.94, 1.0), night_amount);
        SPECULAR_LIGHT += tint * bands * LIGHT_COLOR * ATTENUATION * mix(1.0, 3.2, night_amount) * (1.0 - sea_far * 0.55) / PI;
    } else {
        // Lantern light breaks into warm flecks on the swell beside the hull.
        SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * step(0.992, glint) * 0.22 / PI;
    }
}
