extends Node
## Direction = wind FROM, radians around +Y from world -Z; strength normalized.
var direction := deg_to_rad(110.0)
var strength := 1.0
var variation_enabled := true
var _time := 0.0
var _base_direction := deg_to_rad(110.0)

func _ready() -> void:
    process_physics_priority = -100

func _physics_process(delta: float) -> void:
    if not variation_enabled:
        return
    _time += delta
    # Smooth bounded +/-30 degrees; a full cycle takes several minutes.
    direction = _base_direction + deg_to_rad(30.0) * sin(_time * TAU / 360.0)
    strength = 0.9 + 0.1 * cos(_time * TAU / 240.0)
