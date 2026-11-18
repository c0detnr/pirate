class_name InkPost
extends MeshInstance3D
## Screen-space ink contours for one camera. Forward+ only: other renderers keep
## the inverted-hull contour that ship_appearance.gd adds as a fallback.

# Quality switches.
const ENABLED := true
const LINE_WIDTH := 1.5       ## Pixels at 720p; scales with resolution.
const LINE_OPACITY := 0.9
const CREASE_STRENGTH := 0.85 ## 0 = silhouettes only (5 taps instead of 8).
const WOBBLE := 1.0           ## 0 = even line, slightly cheaper.
const FADE_START := 30.0
const FADE_END := 220.0

const NODE_NAME := &"InkPost"
const NIGHT_COOL := Color(0.30, 0.35, 0.52)
const LANTERN_WARM := Color(1.0, 0.70, 0.42)

var _ship: Node3D
var _material: ShaderMaterial

static func is_supported() -> bool:
    return ENABLED and RenderingServer.get_current_rendering_method() == "forward_plus"

## Safe to call repeatedly; returns null when the renderer cannot support it.
static func install(camera: Camera3D) -> MeshInstance3D:
    if camera == null or not is_supported():
        return null
    var existing := camera.get_node_or_null(NodePath(NODE_NAME)) as MeshInstance3D
    if existing != null:
        return existing
    var post: MeshInstance3D = (load("res://scripts/ink_post.gd") as GDScript).new()
    post.name = NODE_NAME
    camera.add_child(post)
    return post

## Colour for an unshaded sprite at night: cool moonlight plus nearby lanterns.
static func night_sprite_tint(at: Vector3, lanterns: Array[OmniLight3D]) -> Color:
    var warmth := 0.0
    for lantern in lanterns:
        if is_instance_valid(lantern) and lantern.is_visible_in_tree():
            var reach := 1.0 - at.distance_to(lantern.global_position) / maxf(lantern.omni_range, 0.01)
            if reach > 0.0:
                warmth += reach * reach * minf(lantern.light_energy, 2.0)
    warmth = clampf(warmth * 0.75, 0.0, 1.0)
    return Color(
        lerpf(NIGHT_COOL.r, LANTERN_WARM.r, warmth),
        lerpf(NIGHT_COOL.g, LANTERN_WARM.g, warmth),
        lerpf(NIGHT_COOL.b, LANTERN_WARM.b, warmth))

func _ready() -> void:
    var quad := QuadMesh.new()
    quad.size = Vector2(2.0, 2.0)
    mesh = quad
    # Vertices are placed in clip space, so the node must never be culled.
    custom_aabb = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    gi_mode = GeometryInstance3D.GI_MODE_DISABLED
    _material = ShaderMaterial.new()
    _material.shader = load("res://shaders/ink_post.gdshader")
    _material.render_priority = Material.RENDER_PRIORITY_MIN
    _material.set_shader_parameter("line_width", LINE_WIDTH)
    _material.set_shader_parameter("line_opacity", LINE_OPACITY)
    _material.set_shader_parameter("crease_strength", CREASE_STRENGTH)
    _material.set_shader_parameter("wobble", WOBBLE)
    _material.set_shader_parameter("fade_start", FADE_START)
    _material.set_shader_parameter("fade_end", FADE_END)
    material_override = _material

func _process(_delta: float) -> void:
    if not is_instance_valid(_ship):
        _ship = get_tree().get_first_node_in_group("ship") as Node3D
    if is_instance_valid(_ship):
        _material.set_shader_parameter("anchor_from_world", Projection(_ship.global_transform.affine_inverse()))
