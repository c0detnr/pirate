extends Node
## Owns the global `night_amount` shader parameter (0 = golden hour, 1 = moonlit)
## and keeps light, environment and sky-facing materials on the same curve.
## Tests and captures: set_night(true, true) or set_night_amount(0.5).
signal night_amount_changed(amount: float)

const TRANSITION_SECONDS := 3.0
const SUN_DIRECTION := Vector3(-0.6185, 0.2693, 0.7382)
const MOON_DIRECTION := Vector3(0.6211, 0.4208, -0.6612)

const DAY := {
	"light": Color(1.0, 0.72, 0.46), "energy": 1.45,
	"ambient": Color(0.47, 0.5, 0.62), "ambient_energy": 0.5,
	"fog": Color(0.56, 0.5, 0.46), "fog_density": 0.0028,
	"exposure": 1.0, "contrast": 1.05, "saturation": 0.94, "glow": 0.18,
	"spray": Color(0.82, 0.78, 0.68),
}
const NIGHT := {
	"light": Color(0.56, 0.68, 0.95), "energy": 0.4,
	"ambient": Color(0.2, 0.27, 0.42), "ambient_energy": 0.42,
	"fog": Color(0.12, 0.17, 0.24), "fog_density": 0.0042,
	"exposure": 1.0, "contrast": 1.08, "saturation": 0.86, "glow": 0.34,
	"spray": Color(0.2, 0.26, 0.34),
}

## Eased value published to shaders.
var night_amount := 0.0
var is_night := false

var _progress := 0.0
var _target := 0.0
var _environment: Environment
var _sun: DirectionalLight3D
var _spray_paint: StandardMaterial3D

func setup(main: Node3D, water: ShaderMaterial, spray: GPUParticles3D = null) -> void:
	_environment = main.get_node("WorldEnvironment").environment
	_sun = main.get_node("Sun")
	var sky_material := _environment.sky.sky_material as ShaderMaterial
	for material: ShaderMaterial in [sky_material, water]:
		material.set_shader_parameter("sun_direction", SUN_DIRECTION)
		material.set_shader_parameter("moon_direction", MOON_DIRECTION)
	if spray != null and spray.draw_pass_1 != null:
		_spray_paint = spray.draw_pass_1.material as StandardMaterial3D
	_apply()

func toggle() -> void:
	set_night(not is_night)

func set_night(night: bool, instant := false) -> void:
	is_night = night
	_target = 1.0 if night else 0.0
	if instant:
		set_night_amount(1.0 if night else 0.0)

## Jumps to an eased amount and holds it; a later toggle continues smoothly from it.
func set_night_amount(amount: float) -> void:
	night_amount = clampf(amount, 0.0, 1.0)
	_progress = _progress_for(night_amount)
	_target = _progress
	is_night = night_amount >= 0.5
	_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_night", false):
		toggle()

func _process(delta: float) -> void:
	if is_equal_approx(_progress, _target):
		return
	_progress = move_toward(_progress, _target, delta / TRANSITION_SECONDS)
	night_amount = smoothstep(0.0, 1.0, _progress)
	_apply()

## Inverse of smoothstep, so a jump does not pop when a transition resumes.
func _progress_for(amount: float) -> float:
	return 0.5 - sin(asin(1.0 - 2.0 * amount) / 3.0)

func _apply() -> void:
	var n := night_amount
	RenderingServer.global_shader_parameter_set("night_amount", n)
	if _sun != null:
		# The sun sets out, the moon rises in: the light only swings while dark,
		# so shadows never visibly sweep across the deck.
		var sun_part := 1.0 - smoothstep(0.0, 0.46, n)
		var moon_part := smoothstep(0.54, 1.0, n)
		_sun.light_energy = DAY.energy * sun_part + NIGHT.energy * moon_part
		_sun.light_color = DAY.light.lerp(NIGHT.light, smoothstep(0.3, 0.7, n))
		var to_light := SUN_DIRECTION.slerp(MOON_DIRECTION, smoothstep(0.46, 0.54, n)).normalized()
		_sun.global_basis = Basis.looking_at(-to_light, Vector3.UP)
	if _environment != null:
		_environment.ambient_light_color = DAY.ambient.lerp(NIGHT.ambient, n)
		_environment.ambient_light_energy = lerpf(DAY.ambient_energy, NIGHT.ambient_energy, n)
		_environment.fog_light_color = DAY.fog.lerp(NIGHT.fog, n)
		_environment.fog_density = lerpf(DAY.fog_density, NIGHT.fog_density, n)
		_environment.tonemap_exposure = lerpf(DAY.exposure, NIGHT.exposure, n)
		_environment.adjustment_contrast = lerpf(DAY.contrast, NIGHT.contrast, n)
		_environment.adjustment_saturation = lerpf(DAY.saturation, NIGHT.saturation, n)
		_environment.glow_intensity = lerpf(DAY.glow, NIGHT.glow, n)
	if _spray_paint != null:
		_spray_paint.albedo_color = DAY.spray.lerp(NIGHT.spray, n)
	night_amount_changed.emit(n)
