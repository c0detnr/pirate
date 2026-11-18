extends Node3D
## Feet and routes are always in ship-local coordinates; only the art bobs.
@export_enum("bosun", "gunner", "deckhand") var role := "bosun"
@export var display_name := "Lostromo"
@export var body_height := 1.9
@export var patrol := PackedVector3Array([Vector3(-1.0, 1.6, 0.2), Vector3(-1.0, 1.6, 2.7)])
const InkPostScript = preload("res://scripts/ink_post.gd")
@onready var sprite: Sprite3D = $Sprite3D
var _textures: Dictionary = {}
var _player: Node3D
var _camera: Camera3D
var _waypoint := 0
var _wait := 1.0
var _clock := 0.0
var _facing := Vector3.FORWARD
var _walking := false
var _sun: DirectionalLight3D
var _material: ShaderMaterial
var _night_tint := InkPostScript.NIGHT_COOL
var _target_tint := InkPostScript.NIGHT_COOL
var _tint_clock := 0.0
var _lantern_clock := 0.0
var _lanterns: Array[OmniLight3D] = []
const SPEED := 0.42
const TINT_REFRESH := 0.2
const LANTERN_REFRESH := 1.5

# Positive angle means the camera sees the right profile. Angles are radians.
static func select_view(angle: float) -> Dictionary:
    var degrees := rad_to_deg(wrapf(angle, -PI, PI))
    if absf(degrees) <= 45.0:
        return {"view": "front", "flip_h": false}
    if absf(degrees) >= 135.0:
        return {"view": "back", "flip_h": false}
    return {"view": "side", "flip_h": degrees < 0.0}

func _ready() -> void:
    add_to_group("crew")
    for view in ["front", "side", "back"]:
        _textures[view] = load("res://assets/art/crew/%s_%s.png" % [role, view])
    sprite.texture = _textures.front
    sprite.pixel_size = body_height / float(sprite.texture.get_height())
    sprite.offset.y = float(sprite.texture.get_height()) * 0.5
    _player = get_tree().get_first_node_in_group("player") as Node3D
    _camera = get_viewport().get_camera_3d()
    _sun = get_tree().current_scene.get_node_or_null("Sun") as DirectionalLight3D if get_tree().current_scene != null else get_parent().get_parent().get_node_or_null("Sun") as DirectionalLight3D
    # Art keeps its ink; directional pigment tint is limited to 15%. Sprite fog stays enabled.
    sprite.shaded = false
    # The shared billboard shader follows the global night_amount.
    _material = ShaderMaterial.new()
    _material.shader = preload("res://shaders/parrot_billboard.gdshader")
    _material.set_shader_parameter("upright", true)
    _material.set_shader_parameter("art", sprite.texture)
    sprite.material_override = _material
    _tint_clock = randf() * TINT_REFRESH
    _make_shadow()

func _physics_process(delta: float) -> void:
    _clock += delta
    _update_tint(delta)
    if not is_instance_valid(_player):
        _player = get_tree().get_first_node_in_group("player") as Node3D
    _walking = false
    var toward_player := Vector3.ZERO
    if is_instance_valid(_player):
        toward_player = get_parent().to_local(_player.global_position) - position
    var near_player := is_instance_valid(_player) and toward_player.length() < 1.2
    if near_player:
        toward_player.y = 0.0
        if toward_player.length_squared() > 0.001:
            _facing = _facing.lerp(toward_player.normalized(), 1.0 - exp(-5.0 * delta)).normalized()
    elif _wait > 0.0:
        _wait -= delta
    elif not patrol.is_empty():
        var toward := patrol[_waypoint] - position
        toward.y = 0.0
        if toward.length() < 0.04:
            _waypoint = (_waypoint + 1) % patrol.size()
            _wait = 1.8 + float(_waypoint) * 0.7
        else:
            var step := toward.normalized() * minf(SPEED * delta, toward.length())
            # Never step into the player's space; pause rather than push them.
            var candidate := position + step
            var player_local: Vector3 = get_parent().to_local(_player.global_position) if is_instance_valid(_player) else Vector3(100, 100, 100)
            if candidate.distance_to(player_local) >= 1.2:
                position = candidate
                _walking = true
                _facing = _facing.lerp(toward.normalized(), 1.0 - exp(-5.0 * delta)).normalized()
    position.y = 1.6
    sprite.position.y = absf(sin(_clock * 7.0)) * 0.025 if _walking else 0.0
    sprite.scale.y = 1.0 if _walking else 1.0 + sin(_clock * 1.8) * 0.006
    if not is_instance_valid(_camera):
        _camera = get_viewport().get_camera_3d()
    if is_instance_valid(_camera):
        var camera_direction: Vector3 = get_parent().to_local(_camera.global_position) - position
        camera_direction.y = 0.0
        var angle := atan2(_facing.cross(camera_direction).y, _facing.dot(camera_direction))
        # FORWARD (-Z) cross RIGHT (+X) is -Y: negate to select the right profile.
        var view := select_view(-angle)
        if sprite.texture != _textures[view.view]:
            sprite.texture = _textures[view.view]
            _material.set_shader_parameter("art", sprite.texture)
        sprite.flip_h = view.flip_h

func _update_tint(delta: float) -> void:
    var shade := 1.0
    if is_instance_valid(_sun):
        var facing_world: Vector3 = get_parent().global_basis * _facing
        shade = lerpf(0.85, 1.0, clampf(facing_world.dot(_sun.global_basis.z), 0.0, 1.0))
    _material.set_shader_parameter("day_tint", Vector3(shade, shade * 0.98, shade * 0.95))
    # Lantern warmth moves slowly, so it is sampled a few times per second.
    _tint_clock -= delta
    if _tint_clock <= 0.0:
        _tint_clock = TINT_REFRESH
        _lantern_clock -= TINT_REFRESH
        if _lantern_clock <= 0.0:
            _lantern_clock = LANTERN_REFRESH
            _lanterns.assign(get_parent().find_children("*", "OmniLight3D", true, false))
        _target_tint = InkPostScript.night_sprite_tint(sprite.global_position + Vector3.UP * body_height * 0.5, _lanterns)
    _night_tint = _night_tint.lerp(_target_tint, 1.0 - exp(-6.0 * delta))
    _material.set_shader_parameter("night_tint", Vector3(_night_tint.r, _night_tint.g, _night_tint.b))

func _make_shadow() -> void:
    var shadow := MeshInstance3D.new()
    shadow.name = "FootShadow"
    var quad := QuadMesh.new()
    quad.size = Vector2(0.9, 0.6)
    shadow.mesh = quad
    shadow.rotation.x = -PI * 0.5
    shadow.position.y = 0.012
    shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material := ShaderMaterial.new()
    material.shader = preload("res://shaders/crew_shadow.gdshader")
    shadow.material_override = material
    add_child(shadow)
