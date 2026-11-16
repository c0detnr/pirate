extends AnimatableBody3D
## Fizik sırası: Ocean/Wind -> gemi -> oyuncu. Pruva yerel -Z.
const FORE_AFT_SAMPLE := 9.0
const SIDE_SAMPLE := 2.8
const SPAWN_LOCAL := Vector3(0.8, 2.6, 0.5)
const MAX_SPEED := 7.0
const ISLAND_CLEARANCE := 29.5 # 18 m kıyı + geminin çevre yarıçapı

var frame_motion := Transform3D.IDENTITY
var heading := 0.0
var speed := 0.0
var sail_level := 0
var rudder := 0.0
var steering_input := 0.0
var _waterline := 0.0
var _helm_pivot: Node3D
var _sails: Array[Dictionary] = []
var _sail_tween: Tween

func _ready() -> void:
	process_physics_priority = -50
	sync_to_physics = false
	_setup_collision()
	preload("res://scripts/ship_appearance.gd").apply(self)
	_setup_rigging()
	heading = rotation.y
	_waterline = global_position.y
	add_to_group("ship")

func wind_relative_angle() -> float:
	# Wind.direction is where the wind comes FROM, measured from world -Z.
	return wrapf(Wind.direction - heading, -PI, PI)

func sail_efficiency() -> float:
	var angle := absf(rad_to_deg(wind_relative_angle()))
	if angle <= 40.0:
		return 0.0
	if angle < 90.0:
		return smoothstep(40.0, 90.0, angle)
	if angle <= 135.0:
		return 1.0
	return lerpf(1.0, 0.75, (angle - 135.0) / 45.0)

func change_sail(steps: int) -> void:
	sail_level = clampi(sail_level + steps, 0, 3)
	if _sail_tween:
		_sail_tween.kill()
	_sail_tween = create_tween().set_parallel(true)
	_sail_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for sail in _sails:
		var material: ShaderMaterial = sail.material
		var target := 0.0 if sail_level >= int(sail.level) else 1.0
		var current: float = material.get_shader_parameter("furl")
		_sail_tween.tween_method(func(value: float): material.set_shader_parameter("furl", value), current, target, 1.5)

func _physics_process(delta: float) -> void:
	var before := global_transform
	rudder = move_toward(rudder, clampf(steering_input, -1.0, 1.0), delta * (0.45 if steering_input != 0.0 else 0.25))
	var thrust := float(sail_level) / 3.0 * clampf(Wind.strength, 0.0, 1.5) * sail_efficiency()
	speed = clampf(speed + (0.7 * thrust - 0.1 * speed) * delta, 0.0, MAX_SPEED)
	heading = wrapf(heading - rudder * (0.006 + speed * 0.022) * delta, -PI, PI)
	var yaw_basis := Basis(Vector3.UP, heading)
	global_position += -yaw_basis.z * speed * delta
	_avoid_island()
	var center := global_position
	var fore_pos := center - yaw_basis.z * FORE_AFT_SAMPLE
	var aft_pos := center + yaw_basis.z * FORE_AFT_SAMPLE
	var port_pos := center - yaw_basis.x * SIDE_SAMPLE
	var starboard_pos := center + yaw_basis.x * SIDE_SAMPLE
	var t := Ocean.time
	var fore := Ocean.get_wave_height(fore_pos.x, fore_pos.z, t)
	var aft := Ocean.get_wave_height(aft_pos.x, aft_pos.z, t)
	var port := Ocean.get_wave_height(port_pos.x, port_pos.z, t)
	var starboard := Ocean.get_wave_height(starboard_pos.x, starboard_pos.z, t)
	var blend := 1.0 - exp(-3.0 * delta)
	global_position.y = lerpf(global_position.y, _waterline + (fore + aft + port + starboard) * 0.25, blend)
	var heel := -sin(wind_relative_angle()) * thrust * deg_to_rad(4.0)
	rotation = Vector3(
		lerp_angle(rotation.x, atan2(aft - fore, FORE_AFT_SAMPLE * 2.0), blend),
		heading,
		lerp_angle(rotation.z, atan2(starboard - port, SIDE_SAMPLE * 2.0) + heel, blend))
	frame_motion = global_transform * before.affine_inverse()
	_helm_pivot.rotation.z = -rudder * TAU
	_update_sail_wind(delta)

func _avoid_island() -> void:
	var island := get_parent().get_node_or_null("Island") as Node3D
	if island == null:
		return
	var offset := Vector2(global_position.x - island.global_position.x, global_position.z - island.global_position.z)
	if offset.length() < ISLAND_CLEARANCE:
		if offset.length_squared() < 0.001:
			offset = Vector2.RIGHT
		offset = offset.normalized() * ISLAND_CLEARANCE
		global_position.x = island.global_position.x + offset.x
		global_position.z = island.global_position.z + offset.y
		speed = 0.0

func get_helm_position() -> Vector3:
	return _helm_pivot.global_position

func get_helm_stand_position() -> Vector3:
	# Kıç kasara zemini 2.9 m; dümenin arkasında, pruvaya dönük.
	return to_global(Vector3(0.0, 2.91, 7.65))

func _setup_rigging() -> void:
	var hub := get_model_part("HelmHub")
	_helm_pivot = Node3D.new()
	_helm_pivot.name = "HelmPivot"
	add_child(_helm_pivot)
	_helm_pivot.position = to_local(hub.to_global(hub.get_aabb().get_center()))
	var parts := $Model.find_children("*", "MeshInstance3D", true, false)
	for node in parts:
		var part := node as MeshInstance3D
		if part.name == "HelmWheel" or part.name == "HelmHub" or str(part.name).begins_with("HelmSpoke_"):
			part.reparent(_helm_pivot, true)
		elif str(part.name).begins_with("Sail_"):
			var level := 3
			if str(part.name).contains("Topsail"):
				level = 1
			elif str(part.name).contains("Course") or str(part.name).contains("Gaff"):
				level = 2
			for surface in part.mesh.get_surface_count():
				var material := part.get_active_material(surface) as ShaderMaterial
				_sails.append({"material": material, "level": level, "square": not (str(part.name).contains("Gaff") or str(part.name).contains("Jib"))})
	_update_sail_wind(1.0)

func _update_sail_wind(delta: float) -> void:
	# Apparent wind: air velocity minus hull velocity, converted back to FROM.
	var from_direction := Basis(Vector3.UP, Wind.direction) * Vector3.FORWARD
	var apparent_from := from_direction * Wind.strength * 12.0 + (-global_basis.z * speed)
	var relative := global_basis.inverse() * apparent_from
	var angle := absf(atan2(relative.x, -relative.z))
	var square_fill := smoothstep(deg_to_rad(40.0), deg_to_rad(90.0), angle)
	var fore_aft_fill := smoothstep(deg_to_rad(25.0), deg_to_rad(70.0), angle) * (1.0 - 0.72 * smoothstep(deg_to_rad(125.0), PI, angle))
	var blend := 1.0 - exp(-delta * 4.0)
	for sail in _sails:
		var material: ShaderMaterial = sail.material
		var target := square_fill if sail.square else fore_aft_fill
		var current: float = material.get_shader_parameter("fullness")
		material.set_shader_parameter("fullness", lerpf(current, target, blend))
		material.set_shader_parameter("wind_strength", clampf(apparent_from.length() / 12.0, 0.0, 1.5))
		material.set_shader_parameter("wind_side", -1.0 if relative.x > 0.0 else 1.0)

func get_spawn_position() -> Vector3:
	return to_global(SPAWN_LOCAL)

# Keep Blender names intact for sail, helm, gun and hatch interactions.
func get_model_part(part_name: String) -> MeshInstance3D:
	return find_child(part_name, true, false) as MeshInstance3D

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
