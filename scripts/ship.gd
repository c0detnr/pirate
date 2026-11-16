extends AnimatableBody3D
## Yerinde duran kinematik platform. Fizik sırası: Ocean -> gemi -> oyuncu.
const FORE_AFT_SAMPLE := 9.0
const SIDE_SAMPLE := 2.8
const SPAWN_LOCAL := Vector3(0.8, 2.6, 0.5)

var frame_motion := Transform3D.IDENTITY
var _anchor := Vector3.ZERO

func _ready() -> void:
    process_physics_priority = -50
    sync_to_physics = false
    _setup_collision()
    _anchor = global_position
    add_to_group("ship")

func _physics_process(delta: float) -> void:
    var before := global_transform
    var t := Ocean.time
    var fore := Ocean.get_wave_height(_anchor.x, _anchor.z - FORE_AFT_SAMPLE, t)
    var aft := Ocean.get_wave_height(_anchor.x, _anchor.z + FORE_AFT_SAMPLE, t)
    var port := Ocean.get_wave_height(_anchor.x - SIDE_SAMPLE, _anchor.z, t)
    var starboard := Ocean.get_wave_height(_anchor.x + SIDE_SAMPLE, _anchor.z, t)
    var blend := 1.0 - exp(-3.0 * delta)
    position.y = lerpf(position.y, _anchor.y + (fore + aft + port + starboard) * 0.25, blend)
    rotation.x = lerp_angle(rotation.x, atan2(fore - aft, FORE_AFT_SAMPLE * 2.0), blend)
    rotation.z = lerp_angle(rotation.z, atan2(starboard - port, SIDE_SAMPLE * 2.0), blend)
    frame_motion = global_transform * before.affine_inverse()

func get_spawn_position() -> Vector3:
    return to_global(SPAWN_LOCAL)

# Keep Blender names intact for sail, helm, gun and hatch interactions.
func get_model_part(part_name: String) -> MeshInstance3D:
    return $Model.find_child(part_name, true, false) as MeshInstance3D

func _setup_collision() -> void:
    var collider := get_model_part("ShipCollider")
    if collider == null or collider.mesh == null:
        push_error("ship.glb must contain the ShipCollider mesh")
        return
    collider.hide()
    var collision := CollisionShape3D.new()
    collision.name = "ShipCollision"
    var shape := collider.mesh.create_trimesh_shape()
    shape.set_faces(_open_ramp_exits(shape.get_faces()))
    collision.shape = shape
    add_child(collision)
    # Preserve the complete imported transform, including any parent transforms.
    collision.transform = global_transform.affine_inverse() * collider.global_transform

# The exported ramps overlap closed deck solids. Remove their internal end walls
# at the exits so a capsule can cross the seam without hitting a vertical face.
# The outer hull, protective rails and original ramps remain unchanged.
func _open_ramp_exits(faces: PackedVector3Array) -> PackedVector3Array:
    var result := PackedVector3Array()
    for index in range(0, faces.size(), 3):
        var triangle := PackedVector3Array([faces[index], faces[index + 1], faces[index + 2]])
        var stern := true
        var bow := true
        for vertex in triangle:
            stern = stern and absf(vertex.z - 4.5) < 0.061 and vertex.y <= 2.901
            bow = bow and absf(vertex.z + 7.0) < 0.061 and vertex.y <= 2.401
        if not stern and not bow:
            result.append_array(triangle)
            continue
        var inner := 1.25 if stern else 0.85
        var outer := 2.25 if stern else 1.75
        for interval in [Vector2(-100.0, -outer), Vector2(-inner, inner), Vector2(outer, 100.0)]:
            var polygon := _clip_x(_clip_x(triangle, interval.x, true), interval.y, false)
            for point in range(1, polygon.size() - 1):
                result.append_array(PackedVector3Array([polygon[0], polygon[point], polygon[point + 1]]))
    return result

func _clip_x(polygon: PackedVector3Array, boundary: float, keep_greater: bool) -> PackedVector3Array:
    var result := PackedVector3Array()
    if polygon.is_empty():
        return result
    var previous := polygon[polygon.size() - 1]
    var previous_inside := previous.x >= boundary if keep_greater else previous.x <= boundary
    for current in polygon:
        var inside := current.x >= boundary if keep_greater else current.x <= boundary
        if inside != previous_inside:
            result.append(previous.lerp(current, (boundary - previous.x) / (current.x - previous.x)))
        if inside:
            result.append(current)
        previous = current
        previous_inside = inside
    return result
