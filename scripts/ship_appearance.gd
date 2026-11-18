extends RefCounted
## Material-only treatment; imported meshes and interaction names stay intact.
const TOON = preload("res://shaders/toon_ship.gdshader")
const SAIL = preload("res://shaders/sail.gdshader")
const INK = preload("res://shaders/ink_outline.gdshader")
const InkPostScript = preload("res://scripts/ink_post.gd")

# Drawn-finish quality. 0 removes the corresponding shader work entirely.
const HATCH_STRENGTH := 1.0
const GRAIN_STRENGTH := 1.0
const THIN_INK_TAG := 0.35

static func apply(ship: Node3D) -> void:
    # Inverted-hull contours only where the screen-space ink pass cannot run.
    var hull_contours := not InkPostScript.is_supported()
    for child in ship.get_node("Model").find_children("*", "MeshInstance3D", true, false):
        var part := child as MeshInstance3D
        if part.mesh == null or part.name == "ShipCollider":
            continue
        if str(part.name).begins_with("Sail_"):
            _single_cloth_surface(ship, part)
        var thin := false
        for token in ["Shroud", "Ratline", "Stay", "Rope", "Sheet", "Lift", "Sail"]:
            thin = thin or str(part.name).contains(token)
        for surface in part.mesh.get_surface_count():
            var original := part.get_active_material(surface) as StandardMaterial3D
            if original == null or original.resource_name == "LanternGlass":
                continue
            var material := ShaderMaterial.new()
            if str(part.name).begins_with("Sail_"):
                _sail_material(ship, part, material)
                part.set_surface_override_material(surface, material)
                continue
            material.shader = TOON
            material.set_shader_parameter("base_color", original.albedo_color)
            material.set_shader_parameter("mesh_to_ship", ship.global_transform.affine_inverse() * part.global_transform)
            var bounds := (ship.global_transform.affine_inverse() * part.global_transform) * part.get_aabb()
            material.set_shader_parameter("cloth_bounds", Vector4(bounds.position.x, bounds.end.x, bounds.position.y, bounds.end.y))
            var kind := 0
            match original.resource_name:
                "DeckWood": kind = 1
                "HullWood", "HullBottom": kind = 2
                "DarkWood", "WaleTrim": kind = 3
                "Sail": kind = 4
                "Iron", "Gold": kind = 5
            material.set_shader_parameter("surface_kind", kind)
            var fine_line: bool = thin or original.resource_name == "Rope"
            material.set_shader_parameter("hatch_strength", 0.0 if fine_line else HATCH_STRENGTH)
            material.set_shader_parameter("grain_strength", GRAIN_STRENGTH)
            material.set_shader_parameter("ink_tag", THIN_INK_TAG if fine_line else 1.0)
            if hull_contours and not thin and original.resource_name != "Sail" and original.resource_name != "Rope":
                var ink := ShaderMaterial.new()
                ink.shader = INK
                ink.set_shader_parameter("mesh_center", part.get_aabb().get_center())
                material.next_pass = ink
            part.set_surface_override_material(surface, material)

static func _sail_material(ship: Node3D, part: MeshInstance3D, material: ShaderMaterial) -> void:
    material.shader = SAIL
    material.set_shader_parameter("hatch_strength", HATCH_STRENGTH)
    material.set_shader_parameter("grain_strength", GRAIN_STRENGTH)
    material.set_shader_parameter("furl", 1.0)
    material.set_shader_parameter("fullness", 1.0)
    var kind := 1 if str(part.name).contains("Gaff") else (2 if str(part.name).contains("Jib") else 0)
    material.set_shader_parameter("sail_kind", kind)
    material.set_shader_parameter("phase", float(part.name.hash() % 100) * 0.1)
    var local_basis := part.global_basis.inverse() * ship.global_basis
    material.set_shader_parameter("belly_axis", (local_basis * (Vector3.FORWARD if kind == 0 else Vector3.RIGHT)).normalized())
    material.set_shader_parameter("up_axis", (local_basis * Vector3.UP).normalized())
    var arrays := part.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
    var targets := [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]
    var names := ["corner_a", "corner_b", "corner_c", "corner_d"]
    for corner in 4:
        var best := INF
        var anchor := Vector3.ZERO
        for i in vertices.size():
            var distance := uvs[i].distance_squared_to(targets[corner])
            if kind == 2 and corner == 0:
                distance = -(part.global_basis * vertices[i]).y
            if distance < best:
                best = distance
                anchor = vertices[i]
        material.set_shader_parameter(names[corner], anchor)
    var belly_axis: Vector3 = material.get_shader_parameter("belly_axis")
    var anchor: Vector3 = material.get_shader_parameter("corner_a")
    var depth := 0.0
    for vertex in vertices:
        depth = maxf(depth, absf((vertex - anchor).dot(belly_axis)))
    material.set_shader_parameter("belly_depth", depth)
    # Deformation stays inside this margin; prevent off-screen/shadow culling.
    part.extra_cull_margin = 1.0

static func _single_cloth_surface(ship: Node3D, part: MeshInstance3D) -> void:
    # The export has a Solidify front/back shell. Keep its original front grid
    # in memory: cull_disabled renders both sides without intersecting shells
    # when the belly flattens. No imported mesh or GLB is written.
    var local_basis := part.global_basis.inverse() * ship.global_basis
    var axis := (local_basis * (Vector3.FORWARD if not (str(part.name).contains("Gaff") or str(part.name).contains("Jib")) else Vector3.RIGHT)).normalized()
    var cloth_mesh := ArrayMesh.new()
    for surface in part.mesh.get_surface_count():
        var arrays := part.mesh.surface_get_arrays(surface)
        var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
        var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
        var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
        var kept := PackedInt32Array()
        for triangle in range(0, indices.size(), 3):
            var a := indices[triangle]
            var b := indices[triangle+1]
            var c := indices[triangle+2]
            var area := absf((uvs[b]-uvs[a]).cross(uvs[c]-uvs[a]))
            if area > 0.0000001 and (normals[a]+normals[b]+normals[c]).dot(axis) < 0.0:
                kept.append_array(PackedInt32Array([a,b,c]))
        if kept.is_empty():
            return
        arrays[Mesh.ARRAY_INDEX] = kept
        cloth_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        cloth_mesh.surface_set_material(surface, part.get_active_material(surface))
    part.mesh = cloth_mesh
