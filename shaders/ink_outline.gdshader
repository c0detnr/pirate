shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform vec3 mesh_center = vec3(0.0);
uniform float ink_width = 0.018;
void vertex() {
    // A radial expansion shares the same displacement at split flat-normal vertices.
    vec3 radial = VERTEX - mesh_center;
    vec3 world_radial = (MODEL_MATRIX * vec4(radial, 0.0)).xyz;
    float distance_scale = clamp(length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz) / 90.0, 0.0, 0.35);
    VERTEX += radial / max(length(world_radial), 0.0001) * ink_width * (1.0 + distance_scale);
}
void fragment() { ALBEDO = vec3(0.0232, 0.0103, 0.0052); }
