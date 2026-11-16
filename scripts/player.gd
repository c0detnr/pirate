extends CharacterBody3D

const WALK_SPEED := 4.0
const RUN_SPEED := 6.5
const SWIM_SPEED := 2.4
const MOUSE_SENSITIVITY := 0.0024
var _ship: AnimatableBody3D
var _riding := false
var _ignore_next_motion := true
var at_helm := false
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
    add_to_group("player")
    _ship = get_tree().get_first_node_in_group("ship") as AnimatableBody3D
    # Platform hareketini kendimiz uygularız; Godot ikinci kez hız eklemez.
    platform_floor_layers = 0
    platform_wall_layers = 0
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event.is_action_pressed("attack"):
        if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
            _ignore_next_motion = true
        else:
            $WeaponViewmodel.request_attack()
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        if _ignore_next_motion:
            _ignore_next_motion = false
            return
        $WeaponViewmodel.add_mouse_motion(event.relative)
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        camera.rotation.x = clampf(camera.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
    if event.is_action_pressed("interact") and not event.is_echo() and _ship:
        if at_helm:
            leave_helm()
        elif is_swimming():
            global_position = _ship.get_spawn_position()
            velocity = Vector3.ZERO
            _riding = false
        elif can_use_helm():
            enter_helm()
    if at_helm and not event.is_echo():
        if event.is_action_pressed("move_forward"):
            _ship.change_sail(1)
        elif event.is_action_pressed("move_back"):
            _ship.change_sail(-1)

func is_swimming() -> bool:
    return not _riding and not at_helm and global_position.y < Ocean.get_wave_height(global_position.x, global_position.z, Ocean.time) + 0.15

func can_use_helm() -> bool:
    if not is_instance_valid(_ship) or at_helm or not _riding:
        return false
    var toward: Vector3 = _ship.get_helm_position() - camera.global_position
    return toward.length() <= 1.5 and (-camera.global_basis.z).dot(toward.normalized()) > 0.7

func enter_helm() -> void:
    at_helm = true
    _riding = true
    velocity = Vector3.ZERO
    global_position = _ship.get_helm_stand_position()
    rotation.y = _ship.heading

func leave_helm() -> void:
    at_helm = false
    _ship.steering_input = 0.0
    _riding = true
    velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
    if (_riding or at_helm) and is_instance_valid(_ship):
        # Tam transform konumu taşır; kamera ufku düz kalır.
        global_position = _ship.frame_motion * global_position
        rotate_y(_ship.frame_motion.basis.get_euler().y)
    if at_helm:
        global_position = _ship.get_helm_stand_position()
        velocity = Vector3.ZERO
        _ship.steering_input = Input.get_axis("move_left", "move_right")
        return
    var carried_position := global_position
    var was_riding := _riding
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
    # Suppress capsule/floor solver creep for an idle passenger. Walking/jumping
    # still uses the real collider; only a continuously grounded idle pose locks.
    if was_riding and _riding and input.is_zero_approx() and not Input.is_action_just_pressed("jump"):
        global_position = carried_position
    if global_position.y < -12.0 and _ship:
        global_position = _ship.get_spawn_position()
        velocity = Vector3.ZERO
