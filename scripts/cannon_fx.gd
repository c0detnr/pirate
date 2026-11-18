extends RefCounted
## Top efektleri: hepsi dünyaya eklenir, gemiyle taşınmaz ve kendini temizler.
const SAMPLE_RATE := 22050
const BOOM_SECONDS := 1.5
static var _boom: AudioStreamWAV

static func prepare() -> void:
    if _boom:
        return
    # Ses dosyası yok; süzülmüş gürültüden kısa bir patlama üretilir.
    var count := int(SAMPLE_RATE * BOOM_SECONDS)
    var data := PackedByteArray()
    data.resize(count * 2)
    var noise := RandomNumberGenerator.new()
    noise.seed = 1718
    var rumble := 0.0
    for i in count:
        var t := float(i) / SAMPLE_RATE
        var white := noise.randf_range(-1.0, 1.0)
        rumble = lerpf(rumble, white, 0.035)
        var body := rumble * 7.0 * exp(-3.4 * t) + sin(TAU * 46.0 * t) * 0.55 * exp(-5.0 * t)
        var crack := white * 0.75 * exp(-55.0 * t)
        data.encode_s16(i * 2, int(clampf(body + crack, -1.0, 1.0) * 32000.0))
    _boom = AudioStreamWAV.new()
    _boom.format = AudioStreamWAV.FORMAT_16_BITS
    _boom.mix_rate = SAMPLE_RATE
    _boom.data = data

static func muzzle_blast(world: Node, at: Vector3, direction: Vector3) -> void:
    _burst(world, at, {"amount": 30, "life": 2.2, "direction": direction, "spread": 20.0,
        "speed": Vector2(2.0, 11.0), "gravity": Vector3(0, 0.6, 0), "damping": 3.5,
        "size": Vector2(0.3, 0.85), "color": Color(0.9, 0.88, 0.82)})
    _sound(world, at, randf_range(0.88, 1.08), 0.0)
    var light := OmniLight3D.new()
    light.light_color = Color(1.0, 0.68, 0.32)
    light.light_energy = 7.0
    light.omni_range = 13.0
    var fire := MeshInstance3D.new()
    var ball := SphereMesh.new()
    ball.radius = 0.5
    ball.height = 1.0
    ball.radial_segments = 8
    ball.rings = 4
    var paint := StandardMaterial3D.new()
    paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    paint.albedo_color = Color(1.0, 0.72, 0.3)
    ball.material = paint
    fire.mesh = ball
    fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    light.add_child(fire)
    world.add_child(light)
    light.global_position = at + direction * 0.3
    var fade := light.create_tween().set_parallel(true)
    fade.tween_property(light, "light_energy", 0.0, 0.16)
    fade.tween_property(fire, "scale", Vector3.ONE * 0.05, 0.12).from(Vector3.ONE * 1.1)
    fade.chain().tween_callback(light.queue_free)

static func splash(world: Node, at: Vector3) -> void:
    _burst(world, at, {"amount": 30, "life": 1.5, "direction": Vector3.UP, "spread": 12.0,
        "speed": Vector2(4.0, 11.0), "gravity": Vector3(0, -9.8, 0), "damping": 0.0,
        "size": Vector2(0.4, 1.0), "color": Color(0.88, 0.94, 0.9)})
    _sound(world, at, randf_range(2.1, 2.6), -9.0)

static func land_impact(world: Node, at: Vector3) -> void:
    _burst(world, at, {"amount": 14, "life": 1.1, "direction": Vector3.UP, "spread": 42.0,
        "speed": Vector2(1.5, 5.5), "gravity": Vector3(0, -5.0, 0), "damping": 1.5,
        "size": Vector2(0.3, 0.75), "color": Color(0.55, 0.45, 0.32)})
    _sound(world, at, randf_range(1.5, 1.8), -6.0)

static func _burst(world: Node, at: Vector3, spec: Dictionary) -> void:
    var burst := GPUParticles3D.new()
    burst.name = "CannonFx"
    burst.amount = spec.amount
    burst.lifetime = spec.life
    burst.one_shot = true
    burst.explosiveness = 0.92
    burst.local_coords = false
    burst.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 40, 60))
    burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var motion := ParticleProcessMaterial.new()
    motion.direction = spec.direction
    motion.spread = spec.spread
    motion.initial_velocity_min = spec.speed.x
    motion.initial_velocity_max = spec.speed.y
    motion.gravity = spec.gravity
    motion.damping_min = spec.damping
    motion.damping_max = spec.damping
    motion.scale_min = spec.size.x
    motion.scale_max = spec.size.y
    var curve := Curve.new()
    curve.add_point(Vector2(0.0, 0.35))
    curve.add_point(Vector2(0.22, 1.0))
    curve.add_point(Vector2(1.0, 0.0))
    var scale_texture := CurveTexture.new()
    scale_texture.curve = curve
    motion.scale_curve = scale_texture
    burst.process_material = motion
    var puff := SphereMesh.new()
    puff.radius = 0.5
    puff.height = 1.0
    puff.radial_segments = 7
    puff.rings = 4
    var paint := StandardMaterial3D.new()
    paint.albedo_color = spec.color
    paint.roughness = 1.0
    puff.material = paint
    burst.draw_pass_1 = puff
    world.add_child(burst)
    burst.global_position = at
    burst.emitting = true
    burst.get_tree().create_timer(spec.life + 0.4).timeout.connect(burst.queue_free)

static func _sound(world: Node, at: Vector3, pitch: float, volume_db: float) -> void:
    prepare()
    var player := AudioStreamPlayer3D.new()
    player.stream = _boom
    player.pitch_scale = pitch
    player.volume_db = volume_db
    player.unit_size = 22.0
    player.max_distance = 450.0
    world.add_child(player)
    player.global_position = at
    player.finished.connect(player.queue_free)
    player.play()
    player.get_tree().create_timer(BOOM_SECONDS / pitch + 0.5).timeout.connect(player.queue_free)
