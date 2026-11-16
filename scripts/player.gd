extends CharacterBody3D

const WALK_SPEED := 4.0
const RUN_SPEED := 6.5
const SWIM_SPEED := 2.4
const MOUSE_SENSITIVITY := 0.0024
var _ship: AnimatableBody3D
var _riding := false
var _ignore_next_motion := true
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
    _ship = get_tree().get_first_node_in_group("ship") as AnimatableBody3D
    # Platform hareketini kendimiz uygularız; Godot ikinci kez hız eklemez.
    platform_floor_layers = 0
    platform_wall_layers = 0
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        _ignore_next_motion = true
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        if _ignore_next_motion:
            _ignore_next_motion = false
            return
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        camera.rotation.x = clampf(camera.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
    if event.is_action_pressed("interact") and _ship:
        global_position = _ship.get_spawn_position()
        velocity = Vector3.ZERO
        _riding = false

func _physics_process(delta: float) -> void:
    if _riding and is_instance_valid(_ship):
        # Tam transform konumu taşır; kamera ufku geminin roll hareketinden bağımsızdır.
        global_position = _ship.frame_motion * global_position
        rotate_y(_ship.frame_motion.basis.get_euler().y)
    var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var direction := (global_basis * Vector3(input.x, 0.0, input.y)).normalized()
    var water := Ocean.get_wave_height(global_position.x, global_position.z, Ocean.time)
    var swimming := not _riding and global_position.y < water + 0.15
    var speed := SWIM_SPEED if swimming else (RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED)
    velocity.x = direction.x * speed
    velocity.z = direction.z * speed
    if swimming:
        global_position.y = maxf(global_position.y, water - 0.05)
        velocity.y = maxf(0.0, (water + 0.10 - global_position.y) * 5.0)
        if Input.is_action_just_pressed("jump"):
            velocity.y = 4.0
    elif is_on_floor():
        velocity.y = -0.5
        if Input.is_action_just_pressed("jump"):
            velocity.y = 5.0
    else:
        velocity.y -= 15.0 * delta
    move_and_slide()
    _riding = false
    if is_on_floor():
        for index in get_slide_collision_count():
            if get_slide_collision(index).get_collider() == _ship:
                _riding = true
                break
    if global_position.y < -12.0 and _ship:
        global_position = _ship.get_spawn_position()
        velocity = Vector3.ZERO
