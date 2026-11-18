shader_type spatial;
render_mode cull_disabled, specular_disabled, ambient_light_disabled;
global uniform float night_amount;

uniform float furl : hint_range(0.0, 1.0) = 1.0;
uniform float fullness : hint_range(0.0, 1.0) = 1.0;
uniform float wind_strength = 1.0;
uniform float wind_side = 1.0;
// 0 square, 1 gaff, 2 jib. All anchors and directions are mesh-local.
uniform int sail_kind = 0;
uniform vec3 corner_a;
uniform vec3 corner_b;
uniform vec3 corner_c;
uniform vec3 corner_d;
uniform vec3 belly_axis = vec3(0.0, 0.0, -1.0);
uniform vec3 up_axis = vec3(0.0, 1.0, 0.0);
uniform float phase = 0.0;
uniform float belly_depth = 0.6;
uniform float hatch_strength = 1.0; // 0 skips hatching.
uniform float grain_strength = 1.0; // 0 skips the paper finish.
varying vec2 sail_size;
varying vec2 hatch_loss;
varying vec3 ambient_fill;
varying float band_rough;
const vec3 DAY_FILL = vec3(0.42, 0.41, 0.38);
const vec3 NIGHT_FILL = vec3(0.040, 0.052, 0.088);
const float HATCH_SPACING = 0.105;
const float LANTERN_GAIN = 0.11;

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    vec4 h = fract(sin(vec4(dot(i, vec2(127.1,311.7)), dot(i+vec2(1,0),vec2(127.1,311.7)), dot(i+vec2(0,1),vec2(127.1,311.7)), dot(i+vec2(1,1),vec2(127.1,311.7)))) * 43758.5453);
    return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}
// One family of hand-drawn strokes on the cloth; fades out before it can alias.
float hatch_lines(vec2 q) {
    float v = q.y + sin(q.x * 0.21 + q.y * 0.1) * 0.11 + sin(q.x * 1.1) * 0.03;
    float w = fwidth(v);
    float fade = 1.0 - smoothstep(0.14, 0.32, w);
    if (fade <= 0.0) { return 0.0; }
    float row = floor(v);
    float pen = smoothstep(-0.5, 0.4, sin(q.x * 0.16 + row * 2.4)) * (0.065 + 0.025 * sin(row * 3.7));
    return (1.0 - smoothstep(pen, pen + w + 0.025, abs(fract(v) - 0.5))) * fade;
}
vec3 cloth(vec3 original, vec2 uv) {
    vec3 plane = mix(mix(corner_a,corner_b,uv.x),mix(corner_c,corner_d,uv.x),uv.y);
    if (sail_kind == 2) { plane = mix(corner_a,mix(corner_c,corner_d,uv.x),uv.y); }
    float belly = dot(original-plane,belly_axis);
    float side = sail_kind == 0 ? 1.0 : wind_side;
    float inflation = mix(0.08, 1.0 + (wind_strength-1.0)*0.16,fullness);
    vec3 p = original + belly_axis * belly * (inflation * side - 1.0);
    float edge = sin(uv.x*3.14159265);
    float free_edge = smoothstep(0.0,0.22,uv.y) * (0.12+0.88*edge);
    if (sail_kind == 1) { free_edge = smoothstep(0.0,0.25,uv.x) * (0.16+0.84*sin(uv.y*3.14159265)); }
    if (sail_kind == 2) { free_edge *= smoothstep(0.0,0.2,uv.x); }
    float wave = sin(uv.y*9.0-uv.x*4.0-TIME*mix(7.5,1.3,fullness)+phase);
    wave += 0.36*sin(uv.x*15.0+uv.y*11.0-TIME*mix(11.0,1.8,fullness)+phase);
    p += belly_axis * wave * mix(0.16,0.018,fullness) * free_edge * clamp(wind_strength,0.15,1.5);
    vec3 gathered;
    float travel = uv.y;
    if (sail_kind == 0) {
        // Gather the foot onto the yard, retaining a thick, scalloped cloth roll.
        gathered = mix(corner_a,corner_b,uv.x);
        gathered += up_axis * (0.15 + 0.12*sin(uv.y*12.56637));
        gathered += belly_axis * (0.18*cos(uv.y*12.56637) + 0.045*sin(uv.x*25.1327));
    } else if (sail_kind == 1) {
        travel = uv.x;
        gathered = mix(corner_a,corner_c,uv.y);
        gathered += belly_axis * (0.16*cos(uv.x*12.56637)+0.035*sin(uv.y*25.1327));
        gathered += normalize(corner_b-corner_a) * (0.13+0.11*sin(uv.x*12.56637));
    } else {
        // The head slides down the forestay; the leech gathers against its luff.
        gathered = mix(corner_a,corner_c,0.66+0.34*uv.y);
        gathered += belly_axis * (0.14*cos(uv.x*12.56637)+0.03*sin(uv.y*18.8496));
        gathered += normalize(corner_d-corner_c) * (0.10+0.09*sin(uv.x*12.56637));
    }
    // Keep the square yard attachment exactly fixed, even during reefing.
    float attachment = sail_kind == 0 ? smoothstep(0.0,0.12,travel) : 1.0;
    return mix(p,gathered,furl*attachment);
}
vec3 smooth_surface(vec2 uv) {
    vec3 plane = mix(mix(corner_a,corner_b,uv.x),mix(corner_c,corner_d,uv.x),uv.y);
    float profile = sin(uv.x*3.14159265)*sin(uv.y*3.14159265);
    if (sail_kind == 2) {
        plane = mix(corner_a,mix(corner_c,corner_d,uv.x),uv.y);
        profile *= uv.y*1.7;
    }
    return plane + belly_axis*belly_depth*profile;
}
void vertex() {
    vec3 original = VERTEX;
    // Parametric differentials keep the cloth smooth instead of lighting each
    // grid triangle separately. Position still uses the exact exported belly.
    vec2 du = vec2(0.002,0.0);
    vec2 dv = vec2(0.0,0.002);
    vec3 tangent_u = cloth(smooth_surface(UV+du),UV+du)-cloth(smooth_surface(UV-du),UV-du);
    vec3 tangent_v = cloth(smooth_surface(UV+dv),UV+dv)-cloth(smooth_surface(UV-dv),UV-dv);
    vec3 smooth_normal = normalize(cross(tangent_u,tangent_v));
    float face_side = dot(NORMAL,belly_axis) < 0.0 ? -1.0 : 1.0;
    NORMAL = smooth_normal * face_side;
    VERTEX = cloth(original,UV);
    // Metres along the cloth: strokes stay attached while it billows.
    sail_size = vec2(length(corner_b-corner_a),length(corner_c-corner_a));
    if (sail_kind == 2) { sail_size.x = length(corner_d-corner_c); }
}
void fragment() {
    // Back faces receive the same cloth lighting and transmission.
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
    float panels = UV.x * (sail_kind == 0 ? 12.0 : 9.0);
    float seam_distance = min(fract(panels),1.0-fract(panels));
    float seam = 1.0-smoothstep(0.018,0.018+max(fwidth(panels),0.018),seam_distance);
    float border = min(min(UV.x,1.0-UV.x),min(UV.y,1.0-UV.y));
    if (sail_kind == 2) { border = min(min(UV.x,1.0-UV.x)*UV.y,min(UV.y,1.0-UV.y)); }
    float rope = 1.0-smoothstep(0.007,0.020,border);
    float dirt = smoothstep(0.42,1.0,UV.y) * (0.035+0.11*noise(UV*vec2(9,7)));
    dirt += (1.0-smoothstep(0.02,0.23,border))*noise(UV*vec2(17,13))*0.10;
    vec2 patch_coord = abs(UV-vec2(0.28,0.67))-vec2(0.065,0.09);
    float box = max(patch_coord.x,patch_coord.y);
    float patch = 1.0-smoothstep(-0.003,0.003,box);
    float stitch = (1.0-smoothstep(0.002,0.006,abs(box+0.009))) * step(0.45,fract((UV.x+UV.y)*180.0));
    vec2 patch2 = abs(UV-vec2(0.76,0.36))-vec2(0.045,0.065);
    float box2 = max(patch2.x,patch2.y);
    float repair = 1.0-smoothstep(-0.003,0.003,box2);
    float texture_tone = (noise(UV*vec2(180,150))-0.5)*0.025;
    vec3 canvas = vec3(0.88,0.84,0.75);
    vec2 sheet = UV * sail_size;
    float paper = 0.0;
    if (grain_strength > 0.0) {
        float fine_fade = 1.0-smoothstep(0.35,0.8,length(fwidth(sheet*11.0)));
        paper = (noise(sheet*0.9+5.0)-0.5)*0.075*grain_strength;
        if (fine_fade > 0.0) { paper += (noise(sheet*11.0)-0.5)*0.06*fine_fade*grain_strength; }
        canvas += vec3(0.012,0.0,-0.016)*(noise(sheet*0.55+17.0)-0.5)*2.0*grain_strength;
    }
    band_rough = sin(sheet.x*2.7+sin(sheet.y*1.9)*1.1)*0.5+sin(sheet.y*6.1+sheet.x*1.3)*0.5;
    hatch_loss = vec2(0.0);
    if (hatch_strength > 0.0) {
        vec2 q = sheet/HATCH_SPACING;
        float single = hatch_lines(vec2(q.x*0.819+q.y*0.574,q.y*0.819-q.x*0.574));
        float crossed = hatch_lines(vec2(q.x*0.423-q.y*0.906,q.x*0.906+q.y*0.423)*0.86+2.3);
        float gather = smoothstep(0.0,0.55,sin(sheet.x*0.7+sin(sheet.y*0.5)*1.3)*sin(sheet.y*0.6+0.9));
        hatch_loss = vec2(single*0.15,crossed*gather*0.12)*hatch_strength;
    }
    ALBEDO = canvas * (1.0-dirt-seam*0.10-rope*0.14-patch*0.075+repair*0.05-stitch*0.17+texture_tone+paper);
    ROUGHNESS = 0.62; // ink_post reads this as "cloth": silhouette only, softer.
    ambient_fill = mix(DAY_FILL,NIGHT_FILL,clamp(night_amount,0.0,1.0));
    EMISSION = ALBEDO * ambient_fill * (1.0-hatch_loss.x) * (1.0-hatch_loss.y);
}
void light() {
    float incidence = dot(NORMAL,LIGHT);
    // The engine multiplies DIFFUSE_LIGHT by ALBEDO again after this function.
    if (LIGHT_IS_DIRECTIONAL) {
        float diffuse = max(incidence,0.0)*ATTENUATION*(1.0+band_rough*0.05);
        float mid = smoothstep(0.02,0.30,diffuse);
        float full = smoothstep(0.40,0.75,diffuse);
        DIFFUSE_LIGHT += ALBEDO*LIGHT_COLOR*(0.24*mid+0.38*full)/PI;
        DIFFUSE_LIGHT += ambient_fill*(hatch_loss.y*mid+hatch_loss.x*full);
        float transmission = pow(max(dot(-LIGHT,VIEW),0.0),3.0);
        float through = smoothstep(0.05,0.65,abs(incidence));
        DIFFUSE_LIGHT += ALBEDO*vec3(1.0,0.79,0.43)*LIGHT_COLOR*transmission*through*mix(0.55,1.0,ATTENUATION)*0.65*(1.0-0.65*clamp(night_amount,0.0,1.0))/PI;
    } else {
        // Lantern light soaks through the canvas, weaker on the far side.
        float facing = max(incidence,-incidence*0.55)*0.75+0.25;
        float lit = facing*ATTENUATION*(1.0+band_rough*0.10);
        float outer = step(0.085,lit);
        float inner = step(0.25,lit);
        float core = step(0.62,lit);
        float pool = outer*0.20+inner*0.30+core*0.40;
        pool *= 1.0-(outer-inner)*clamp(hatch_loss.x+hatch_loss.y,0.0,1.0)*1.3;
        DIFFUSE_LIGHT += LIGHT_COLOR*pool*LANTERN_GAIN;
    }
}
