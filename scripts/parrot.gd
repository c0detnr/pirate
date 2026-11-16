extends Node3D
## All navigation and mesh bounds are in the moving ship's local frame.
enum State { FLY, APPROACH, PERCH }
const WING_CYCLE := [0, 1, 2, 1]
const PERCH_FEET := Vector2(270, 300) # Existing PNG: tail extends below the claws.
const ART := "res://assets/art/animals/"
var display_name := "Papağan"
var body_height := 0.55
var look_distance := 5.0
var state := State.FLY
var velocity := Vector3(5, 0, 0)
var perches: Array[Dictionary] = []
var landings := 0
var takeoffs := 0
@onready var sprite: Sprite3D = $Sprite3D
var _art: Array[Texture2D] = []
var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _player: Node3D
var _target := Vector3(-3, 10, -3)
var _timer := 0.0
var _flight_time := 0.0
var _wing_time := 0.0
var _glide := 0.0
var _glide_wait := 2.0
var _look_wait := 2.0
var _clock := 0.0
var _bank := 0.0
var _landing: Dictionary
var _curve: Array[Vector3] = []
var _duration := 1.0

static func select_flip(motion: Vector3, camera_right: Vector3, previous: bool) -> bool:
    if motion.length_squared() < 0.01:
        return previous
    var lateral := motion.normalized().dot(camera_right.normalized())
    return lateral < 0.0 if absf(lateral) > 0.18 else previous

static func wing_frame(tick: int) -> int:
    return WING_CYCLE[posmod(tick, WING_CYCLE.size())]

func _ready() -> void:
    add_to_group("look_names")
    sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    _rng.randomize()
    for file in ["parrot_fly_up.png", "parrot_fly_mid.png", "parrot_fly_down.png", "parrot_glide.png", "parrot_perch.png"]:
        _art.append(load(ART + file))
    _material = ShaderMaterial.new()
    _material.shader = preload("res://shaders/parrot_billboard.gdshader")
    sprite.material_override = _material
    _set_art(0)
    _build_perches()
    _flight_time = _rng.randf_range(8, 12)

func _build_perches() -> void:
    var ship := get_parent() as Node3D
    for part_name in ["ForeTop", "MainTop", "ForeYard_Course", "MainYard_Lower", "Bowsprit", "HelmStand", "QDRail_Mid_Top", "QDRail_L_Top", "QDRail_R_Top", "FcRail_Mid_Top"]:
        var mesh := ship.find_child(part_name, true, false) as MeshInstance3D
        if mesh == null:
            continue
        var bounds := AABB()
        for corner in 8:
            var point := ship.to_local(mesh.to_global(mesh.get_aabb().get_endpoint(corner)))
            bounds = AABB(point, Vector3.ZERO) if corner == 0 else bounds.expand(point)
        var top := bounds.get_center()
        top.y = bounds.end.y + 0.012
        if part_name.contains("Yard"):
            for side in [-1.0, 1.0]:
                var end := top
                end.x = bounds.get_center().x + side * bounds.size.x * 0.46
                perches.append({"name": part_name, "point": end, "social": false})
        else:
            # The bowsprit extends 17 m out: use its inboard exposed section
            # to retain the same bounded flight envelope as the rest of the bird.
            if part_name == "Bowsprit":
                top.z = maxf(bounds.end.z - 0.4, -10.0)
            perches.append({"name": part_name, "point": top, "social": part_name.contains("Rail") or part_name == "HelmStand"})

func _physics_process(delta: float) -> void:
    _clock += delta
    if not is_instance_valid(_player):
        _player = get_tree().get_first_node_in_group("player") as Node3D
    var previous_velocity := velocity
    if state == State.PERCH:
        _timer -= delta
        _look_wait -= delta
        if _look_wait <= 0.0:
            sprite.flip_h = not sprite.flip_h
            _look_wait = _rng.randf_range(1.5, 4.0)
        if _timer <= 0.0 or (is_instance_valid(_player) and global_position.distance_to(_player.global_position) < 1.5):
            take_off()
    elif state == State.APPROACH:
        _timer += delta
        var t := clampf(_timer / _duration, 0.0, 1.0)
        var before := position
        position = _curve[0].bezier_interpolate(_curve[1], _curve[2], _curve[3], t)
        velocity = (position - before) / delta
        if t >= 1.0:
            state = State.PERCH
            velocity = Vector3.ZERO
            _timer = _rng.randf_range(5.0, 15.0)
            landings += 1
    else:
        _flight_time -= delta
        _timer -= delta
        if position.distance_to(_target) < 2.5 or _timer <= 0.0:
            _choose_target()
        var desired := (_target - position).normalized() * 6.0
        velocity = velocity.lerp(desired, 1.0 - exp(-1.6 * delta))
        position += velocity * delta
        # Smooth steering is primary; these bounds also cover large frame steps.
        var horizontal := Vector2(position.x, position.z).limit_length(10.0)
        position.x = horizontal.x
        position.z = horizontal.y
        position.y = clampf(position.y, 3.0, 18.0)
        if _flight_time <= 0.0 and not perches.is_empty():
            approach_perch(_choose_perch())
    _update_art(delta, previous_velocity)

func _choose_target() -> void:
    var angle := _rng.randf_range(-PI, PI)
    var radius := _rng.randf_range(4.0, 8.5)
    _target = Vector3(cos(angle) * radius, _rng.randf_range(5, 16.5), sin(angle) * radius)
    _timer = _rng.randf_range(2.0, 3.5)

func _choose_perch() -> Dictionary:
    if is_instance_valid(_player):
        if _player.get("at_helm") == true and _rng.randf() < 0.8:
            for perch in perches:
                if perch.name == "HelmStand":
                    return perch
        if _rng.randf() < 0.45:
            var nearest: Dictionary = {}
            var distance := INF
            for perch in perches:
                if perch.social:
                    var d := _player.global_position.distance_to(get_parent().to_global(perch.point))
                    if d < distance:
                        nearest = perch
                        distance = d
            if not nearest.is_empty():
                return nearest
    return perches[_rng.randi_range(0, perches.size() - 1)]

func approach_perch(perch: Dictionary) -> void:
    _landing = perch
    var end: Vector3 = perch.point
    var lead := position + velocity.normalized() * minf(2.0, position.distance_to(end) * 0.2)
    var horizontal := Vector2(lead.x, lead.z).limit_length(10.0)
    lead = Vector3(horizontal.x, clampf(lead.y, 4.0, 18.0), horizontal.y)
    _curve = [position, lead, end + Vector3.UP * 1.8, end]
    _duration = maxf(2.0, position.distance_to(end) / 3.5)
    _timer = 0.0
    state = State.APPROACH

func take_off() -> void:
    state = State.FLY
    takeoffs += 1
    _flight_time = _rng.randf_range(9.0, 16.0)
    _target = Vector3(position.x * 0.5 + 2.0, maxf(position.y + 4.0, 7.0), position.z * 0.5)
    velocity = (_target - position).normalized() * 5.5
    _timer = 2.0

func _set_art(index: int) -> void:
    sprite.texture = _art[index]
    _material.set_shader_parameter("art", sprite.texture)
    body_height = 0.45 if index == 4 else 0.55
    sprite.pixel_size = 0.45 / 460.0 if index == 4 else 0.9 / 492.0
    # Flight canvases share a fixed beak point; no per-frame recentering.
    var feet_x := 492.0 - PERCH_FEET.x if sprite.flip_h else PERCH_FEET.x
    sprite.offset = Vector2(246.0 - feet_x, PERCH_FEET.y - 230.0) if index == 4 else Vector2.ZERO

func _update_art(delta: float, previous_velocity: Vector3) -> void:
    var camera := get_viewport().get_camera_3d()
    if state != State.PERCH and is_instance_valid(camera):
        var world_motion: Vector3 = get_parent().global_basis * velocity
        sprite.flip_h = select_flip(world_motion, camera.global_basis.x, sprite.flip_h)
        var turn := (velocity - previous_velocity).dot(get_parent().global_basis.inverse() * camera.global_basis.x)
        _bank = lerpf(_bank, clampf(-turn / maxf(delta, 0.001) * 0.025, -0.12, 0.12), 1.0 - exp(-5.0 * delta))
    else:
        _bank = lerpf(_bank, 0.0, 1.0 - exp(-8.0 * delta))
    _material.set_shader_parameter("bank", _bank)
    sprite.scale.y = 1.0 + sin(_clock * 2.4) * 0.008 if state == State.PERCH else 1.0
    _glide_wait -= delta
    _glide = maxf(0.0, _glide - delta)
    if _glide_wait <= 0.0:
        _glide = _rng.randf_range(0.4, 1.1)
        _glide_wait = _rng.randf_range(3.0, 6.0)
    _wing_time += delta * (14.0 if velocity.y > 0.8 else 10.0)
    var index := wing_frame(int(_wing_time))
    if state == State.PERCH:
        index = 4
    elif state == State.APPROACH or velocity.y < -0.8 or (_glide > 0.0 and velocity.y < 0.8):
        index = 3
    _set_art(index)
