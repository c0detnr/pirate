shader_type sky;
render_mode use_debanding;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i), hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void sky() {
    float height = max(EYEDIR.y, 0.0);
    vec3 horizon = vec3(0.82, 0.73, 0.57);
    vec3 zenith = vec3(0.065, 0.25, 0.50);
    vec3 color = mix(horizon, zenith, pow(smoothstep(0.0, 0.52, height), 0.65));
    vec2 p = EYEDIR.xz / max(EYEDIR.y + 0.22, 0.08) * 2.7;
    float cloud = noise(p) * 0.65 + noise(p * 2.1) * 0.25 + noise(p * 4.2) * 0.10;
    float mask = smoothstep(0.63, 0.66, cloud) * smoothstep(0.03, 0.15, height);
    vec3 cloud_color = mix(vec3(0.72,0.71,0.66),vec3(0.96,0.87,0.68), smoothstep(0.70,0.73,cloud));
    color = mix(color, cloud_color, mask * 0.91);
    float sun = dot(EYEDIR, LIGHT0_DIRECTION);
    color += vec3(1.0,0.63,0.25) * pow(max(sun,0.0), 64.0) * 0.18;
    color = mix(color, vec3(1.8,1.35,0.73), smoothstep(0.99945,0.99965,sun));
    COLOR = color;
}
