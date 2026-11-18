shader_type sky;
render_mode use_debanding;
// Painted sky: banded gradient, inked cel clouds, sun by day, moon and stars by night.
// horizon_tint() is mirrored in water.gdshader so the sea dissolves into this horizon.
// Palette is linear: it stays well below the sail cream so canvas reads against it.
global uniform float night_amount;
uniform vec3 sun_direction = vec3(-0.6185, 0.2693, 0.7382);
uniform vec3 moon_direction = vec3(0.6211, 0.4208, -0.6612);

const vec3 INK = vec3(0.028, 0.017, 0.016);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1,311.7,74.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i), hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
float billow(vec2 p) { return 1.0 - abs(noise(p) * 2.0 - 1.0); }
// Broad masses with rounded, cumulus-like lobes on their edges.
float cloud_field(vec2 p) {
    return noise(p) * 0.72 + billow(p * 2.1 + 4.7) * 0.20 + billow(p * 4.5 + 9.2) * 0.08;
}
vec3 horizon_tint(vec3 dir) {
    vec2 flat_dir = normalize(dir.xz + vec2(0.00001));
    float sunward = dot(flat_dir, normalize(sun_direction.xz)) * 0.5 + 0.5;
    float moonward = dot(flat_dir, normalize(moon_direction.xz)) * 0.5 + 0.5;
    vec3 day = mix(vec3(0.17, 0.165, 0.195), vec3(0.66, 0.33, 0.14), sunward * sunward * sunward);
    vec3 night = mix(vec3(0.012, 0.024, 0.045), vec3(0.030, 0.050, 0.085), pow(moonward, 5.0));
    return mix(day, night, night_amount);
}
vec3 sky_gradient(vec3 dir, float height) {
    vec3 zenith = mix(vec3(0.025, 0.06, 0.12), vec3(0.0015, 0.0035, 0.010), night_amount);
    vec3 middle = mix(vec3(0.06, 0.12, 0.19), vec3(0.004, 0.010, 0.022), night_amount);
    float t = smoothstep(0.0, 0.62, height);
    vec3 color = mix(horizon_tint(dir), middle, smoothstep(0.0, 0.42, t));
    return mix(color, zenith, smoothstep(0.35, 1.0, t));
}
void sky() {
    vec3 dir = normalize(EYEDIR);
    float height = max(dir.y, 0.0);
    float night = night_amount;
    if (AT_CUBEMAP_PASS) {
        COLOR = sky_gradient(dir, height);
    } else if (dir.y < 0.0) {
        // Beyond the sea mesh: the same haze the far water fades into.
        COLOR = horizon_tint(dir) * mix(1.0, 0.66, night);
    } else {
        // Soft painted bands, wobbling like loaded-brush strokes.
        float wobble = noise(dir.xz * 7.0 / (height + 0.35)) * 0.05;
        float band = floor((height + wobble) * 15.0) / 15.0;
        vec3 color = mix(sky_gradient(dir, height), sky_gradient(dir, band), 0.6 * step(0.004, height));

        float sun_dot = dot(dir, sun_direction);
        float moon_dot = dot(dir, moon_direction);
        float day = 1.0 - night;

        // Stars sit behind everything else and thin out towards the horizon.
        if (night > 0.01) {
            vec3 cell = dir * 170.0;
            vec3 id = floor(cell);
            float pick = hash3(id);
            if (pick > 0.988) {
                vec3 centre = id + 0.5 + (vec3(hash3(id + 1.0), hash3(id + 2.0), hash3(id + 3.0)) - 0.5) * 0.55;
                float size = pick > 0.997 ? 0.42 : 0.27;
                float star = 1.0 - smoothstep(size * 0.35, size, length(cell - centre));
                float twinkle = 0.72 + 0.28 * sin(TIME * (0.7 + pick * 2.0) + pick * 90.0);
                color += vec3(0.70, 0.74, 0.66) * star * twinkle * night * smoothstep(0.05, 0.3, height) * 0.6;
            }
        }

        // Low sun: a pale core inside a wide brass haze.
        color += vec3(0.55, 0.26, 0.09) * pow(max(sun_dot, 0.0), 18.0) * 0.35 * day;
        color += vec3(0.70, 0.38, 0.15) * pow(max(sun_dot, 0.0), 180.0) * 0.6 * day;
        color = mix(color, vec3(1.35, 0.85, 0.42), smoothstep(0.99925, 0.99950, sun_dot) * day);

        // Moon: flat disc, ink ring, a few painted maria, thin halo.
        color += vec3(0.06, 0.09, 0.14) * pow(max(moon_dot, 0.0), 260.0) * 0.6 * night;
        color += vec3(0.025, 0.04, 0.07) * pow(max(moon_dot, 0.0), 26.0) * 0.4 * night;
        float moon_disc = smoothstep(0.99905, 0.99925, moon_dot);
        if (moon_disc > 0.0) {
            vec3 side = normalize(cross(moon_direction, vec3(0.0, 1.0, 0.0)));
            vec3 up = cross(side, moon_direction);
            vec2 m = vec2(dot(dir, side), dot(dir, up)) * 42.0;
            float maria = smoothstep(0.52, 0.56, noise(m + 3.1) * 0.7 + noise(m * 2.3) * 0.3);
            vec3 face = mix(vec3(1.05, 1.07, 0.96), vec3(0.50, 0.55, 0.58), maria);
            float rim = smoothstep(0.99925, 0.99945, moon_dot);
            color = mix(color, mix(INK, face, rim), moon_disc * night);
        }

        // Inked clouds drifting slowly with the trade wind.
        float cloud_fade = smoothstep(0.015, 0.13, dir.y);
        if (cloud_fade > 0.0) {
            vec2 p = dir.xz / (height + 0.2) * 1.55 + vec2(0.0080, 0.0030) * TIME;
            float c = cloud_field(p);
            float grad = max(length(vec2(dFdx(c), dFdy(c))), 0.00001);
            // The sky keeps itself clear around the sun and moon.
            float clearing = smoothstep(0.975, 0.998, sun_dot) * day + smoothstep(0.975, 0.998, moon_dot) * night;
            float edge = 0.63 + clearing * 0.25;
            // Distances are in pixels, so ink keeps one line weight at any range.
            float d = (c - edge) / grad;
            if (d > -4.0) {
                float body = smoothstep(-0.7, 0.7, d);
                vec3 key = normalize(mix(sun_direction, moon_direction, step(0.5, night)));
                // Sample towards the key light: what falls away from it is the lit rim.
                float toward = cloud_field(p + normalize(key.xz + vec2(0.00001)) * 0.13);
                float lit = smoothstep(-0.7, 0.7, (c - toward - 0.028) / grad);
                float inner = smoothstep(-0.7, 0.7, (c - edge - 0.06) / grad);
                float glow_side = max(dot(dir, key), 0.0);
                vec3 shade = mix(vec3(0.066, 0.070, 0.098), vec3(0.0035, 0.006, 0.012), night);
                vec3 mid = mix(vec3(0.125, 0.112, 0.128), vec3(0.007, 0.012, 0.022), night);
                vec3 rim_day = mix(vec3(0.20, 0.135, 0.12), vec3(0.72, 0.36, 0.15), glow_side * glow_side);
                vec3 rim_night = mix(vec3(0.018, 0.030, 0.052), vec3(0.085, 0.115, 0.165), pow(glow_side, 4.0));
                vec3 cloud = mix(mix(shade, mid, inner), mix(rim_day, rim_night, night), lit);
                color = mix(color, cloud, body * cloud_fade);
                float weight = 0.9 + noise(p * 3.0) * 1.3;
                float line = 1.0 - smoothstep(weight - 0.6, weight + 0.6, abs(d));
                line *= 1.0 - smoothstep(0.02, 0.09, grad);
                color = mix(color, mix(INK, vec3(0.002, 0.003, 0.007), night), line * cloud_fade * 0.8);
            }
        }
        COLOR = color;
    }
}
