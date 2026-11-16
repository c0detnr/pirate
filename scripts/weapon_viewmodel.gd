extends CanvasLayer
## The player owns input so the capture click can never also attack.
const IDLE = preload("res://assets/art/weapons/cutlass_idle.png")
const SWING = preload("res://assets/art/weapons/cutlass_swing.png")
const DURATION := 0.52
const HIT_TIME := 0.20
@onready var player = get_parent()
@onready var art: TextureRect = $Cutlass
var state := "idle"
var elapsed := 0.0
var attacks_started := 0
var _hit_sent := false
var _clock := 0.0
var _sway := Vector2.ZERO
var _mouse := Vector2.ZERO
var _lower := 0.0
var _pose := Vector2.ZERO
var _angle := 0.0
var _animation: Tween

func add_mouse_motion(relative: Vector2) -> void:
    _mouse += relative

func can_attack() -> bool:
    return not player.at_helm and not player.is_swimming()

func request_attack() -> bool:
    if state != "idle" or not can_attack():
        return false
    state = "anticipation"
    elapsed = 0.0
    _hit_sent = false
    attacks_started += 1
    _animation = create_tween()
    _animation.tween_property(self, "_pose", Vector2(0.045, -0.035), 0.09).set_trans(Tween.TRANS_SINE)
    _animation.tween_callback(_begin_swing)
    _animation.tween_property(self, "_pose", Vector2(-0.34, 0.06), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    _animation.parallel().tween_property(self, "_angle", -0.16, 0.25)
    _animation.tween_callback(_begin_recovery)
    _animation.tween_property(self, "_pose", Vector2.ZERO, 0.18).set_trans(Tween.TRANS_SINE)
    _animation.parallel().tween_property(self, "_angle", 0.0, 0.18)
    _animation.tween_callback(func(): state = "idle")
    return true

func _begin_swing() -> void:
    state = "swing"

func _begin_recovery() -> void:
    state = "recovery"

func _process(delta: float) -> void:
    _clock += delta
    if state != "idle":
        elapsed += delta
        if elapsed >= HIT_TIME and not _hit_sent:
            _hit_sent = true
            if can_attack():
                _check_hit()
    _lower = move_toward(_lower, 0.0 if can_attack() else 1.0, delta * 5.0)
    _sway = _sway.lerp((-_mouse * 0.0012).limit_length(0.035), 1.0 - exp(-9.0 * delta))
    _mouse = Vector2.ZERO
    var viewport := get_viewport().get_visible_rect().size
    var moving: float = clampf(Vector2(player.velocity.x, player.velocity.z).length() / 4.0, 0.0, 1.0)
    var bob := Vector2(sin(_clock * 7.5) * 0.006, absf(cos(_clock * 7.5)) * 0.008) * moving
    bob.y += sin(_clock * 1.7) * 0.002
    art.texture = SWING if state == "swing" else IDLE
    var height := viewport.y * 0.55
    art.size = Vector2(height * art.texture.get_width() / art.texture.get_height(), height)
    art.position = Vector2(viewport.x - art.size.x * 0.88, viewport.y - height * 0.90) + (_pose + _sway + bob + Vector2(0, _lower * 0.85)) * viewport.y
    art.pivot_offset = art.size * Vector2(0.85, 0.9)
    art.rotation = _angle
    art.visible = _lower < 1.0

func _check_hit() -> void:
    var camera: Camera3D = player.camera
    var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 2.0)
    query.exclude = [player.get_rid()]
    query.collide_with_areas = true
    var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return
    var target: Node = hit.collider
    while target:
        if target.is_in_group("hittable") and target.has_method("take_hit"):
            target.take_hit(25, player)
            return
        target = target.get_parent()
