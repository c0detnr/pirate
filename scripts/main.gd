extends Node3D

@onready var water_material: ShaderMaterial = $Sea.material_override

func _ready() -> void:
    $Player.global_position = $Ship.get_spawn_position()
    Ocean.configure_material(water_material)
    Ocean.update_material(water_material)

func _process(_delta: float) -> void:
    Ocean.update_material(water_material)
