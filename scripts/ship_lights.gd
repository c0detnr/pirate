extends Node3D
## Warm lamps for every `Lantern_*` mesh of the ship's Model. They wake with
## night_amount and cost nothing by day (lights are hidden at zero).
const GLASS_SHADER = preload("res://shaders/lantern_glass.gdshader")
const MAX_LIGHTS := 12
const MAX_SHADOW_LIGHTS := 1
## Frame and glass of one lantern may be separate meshes: they share a light.
const MERGE_DISTANCE := 0.45
const LIGHT_COLOR := Color(1.0, 0.64, 0.3)
const LIGHT_ENERGY := 1.5
const LIGHT_RANGE := 7.5

var _day_night: Node
var _lamps: Array[Dictionary] = []
var _time := 0.0

## Returns the rig, or null when the ship has no lanterns.
static func install(ship: Node3D, day_night: Node) -> Node3D:
	var model := ship.get_node_or_null("Model")
	if model == null:
		return null
	var meshes: Array[MeshInstance3D] = []
	for node in model.find_children("Lantern_*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null:
			meshes.append(node)
	if meshes.is_empty():
		return null
	var rig: Node3D = (load("res://scripts/ship_lights.gd") as GDScript).new()
	rig.name = "ShipLights"
	ship.add_child(rig)
	rig._build(meshes, day_night)
	return rig

func _build(meshes: Array[MeshInstance3D], day_night: Node) -> void:
	_day_night = day_night
	var ship := get_parent() as Node3D
	for mesh in meshes:
		# The lamp sits inside its own frame; the frame must not seal it in.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var center := ship.to_local(mesh.to_global(mesh.get_aabb().get_center()))
		var lamp := _lamp_at(center)
		if lamp.is_empty() and _lamps.size() < MAX_LIGHTS:
			lamp = _add_lamp(center)
		if lamp.is_empty():
			lamp = _nearest_lamp(center)
		_add_glass(mesh, lamp)
	_pick_shadow_casters()
	_update_lamps(0.0)

func _lamp_at(center: Vector3) -> Dictionary:
	for lamp in _lamps:
		if lamp.light.position.distance_to(center) < MERGE_DISTANCE:
			return lamp
	return {}

func _nearest_lamp(center: Vector3) -> Dictionary:
	var best: Dictionary = _lamps[0]
	for lamp in _lamps:
		if lamp.light.position.distance_squared_to(center) < best.light.position.distance_squared_to(center):
			best = lamp
	return best

func _add_lamp(center: Vector3) -> Dictionary:
	var light := OmniLight3D.new()
	light.name = "Lamp%d" % _lamps.size()
	light.position = center
	light.light_color = LIGHT_COLOR
	light.omni_range = LIGHT_RANGE
	light.omni_attenuation = 1.25
	light.light_specular = 0.15
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	light.visible = false
	add_child(light)
	var glass: Array[ShaderMaterial] = []
	var lamp := {"light": light, "phase": _lamps.size() * 2.399, "glass": glass}
	_lamps.append(lamp)
	return lamp

func _add_glass(mesh: MeshInstance3D, lamp: Dictionary) -> void:
	for surface in mesh.mesh.get_surface_count():
		var authored := mesh.mesh.surface_get_material(surface)
		if authored == null or authored.resource_name != "LanternGlass":
			continue
		var glass := ShaderMaterial.new()
		glass.shader = GLASS_SHADER
		mesh.set_surface_override_material(surface, glass)
		lamp.glass.append(glass)

## The midship lamp shades the deck best; the others stay shadowless for the iGPU.
func _pick_shadow_casters() -> void:
	var by_distance := _lamps.duplicate()
	by_distance.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.light.position.length_squared() < b.light.position.length_squared())
	for i in mini(MAX_SHADOW_LIGHTS, by_distance.size()):
		by_distance[i].light.shadow_enabled = true
		by_distance[i].light.shadow_bias = 0.08

func _process(delta: float) -> void:
	_time += delta
	_update_lamps(_time)

func _update_lamps(time: float) -> void:
	var night: float = _day_night.night_amount if is_instance_valid(_day_night) else 0.0
	var fade := smoothstep(0.12, 0.8, night)
	for lamp in _lamps:
		var phase: float = lamp.phase
		var flame := 0.9 + 0.06 * sin(time * 7.3 + phase) + 0.04 * sin(time * 13.1 + phase * 2.0) + 0.025 * sin(time * 23.0 + phase * 3.0)
		var light: OmniLight3D = lamp.light
		light.visible = fade > 0.005
		light.light_energy = LIGHT_ENERGY * fade * flame
		for glass: ShaderMaterial in lamp.glass:
			glass.set_shader_parameter("flame", flame)
