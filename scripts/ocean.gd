extends Node
## Tek dalga kaynağı: aynı değerler shader uniformlarına gönderilir.
const WAVE_A := Vector4(0.18, 0.42, 1.15, 0.0) # genlik, frekans, hız, yön
const WAVE_B := Vector4(0.10, 0.72, 0.85, 1.25)
const WAVE_C := Vector4(0.06, 1.10, 1.60, 2.40)
var time: float = 0.0

func _ready() -> void:
    process_physics_priority = -100

func _physics_process(delta: float) -> void:
    time += delta

func get_wave_height(x: float, z: float, at_time: float) -> float:
    var height := 0.0
    for wave: Vector4 in [WAVE_A, WAVE_B, WAVE_C]:
        var along := x * cos(wave.w) + z * sin(wave.w)
        height += wave.x * sin(along * wave.y + at_time * wave.z)
    return height

func configure_material(material: ShaderMaterial) -> void:
    material.set_shader_parameter("wave_a", WAVE_A)
    material.set_shader_parameter("wave_b", WAVE_B)
    material.set_shader_parameter("wave_c", WAVE_C)

func update_material(material: ShaderMaterial) -> void:
    material.set_shader_parameter("ocean_time", time)
