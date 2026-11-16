extends RefCounted
## Fixed modest budget. Compatibility rendering skips SSAO/glow automatically.
const SPRAY_PARTICLES := 48
const SPRAY_LIFETIME := 0.65
const FOAM_ENABLED := true
const SSAO_ENABLED := true
const GLOW_ENABLED := true
const SHADOW_DISTANCE := 85.0

static func configure(main: Node3D) -> void:
    var environment: Environment = main.get_node("WorldEnvironment").environment
    var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
    environment.ssao_enabled = SSAO_ENABLED and forward_plus
    environment.glow_enabled = GLOW_ENABLED and forward_plus
    main.get_node("Sun").directional_shadow_max_distance = SHADOW_DISTANCE

static func make_spray(ship: Node3D) -> GPUParticles3D:
    var spray := GPUParticles3D.new()
    spray.name = "BowSpray"
    spray.amount = SPRAY_PARTICLES
    spray.lifetime = SPRAY_LIFETIME
    spray.local_coords = false
    spray.emitting = false
    spray.visibility_aabb = AABB(Vector3(-8, -4, -20), Vector3(16, 12, 40))
    var motion := ParticleProcessMaterial.new()
    motion.direction = Vector3(0, 1, -0.3)
    motion.spread = 38.0
    motion.initial_velocity_min = 1.2
    motion.initial_velocity_max = 2.8
    motion.gravity = Vector3(0, -6, 0)
    motion.scale_min = 0.035
    motion.scale_max = 0.085
    motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    motion.emission_box_extents = Vector3(1.05, 0.04, 0.15)
    spray.process_material = motion
    var drop := SphereMesh.new()
    drop.radial_segments = 6
    drop.rings = 3
    drop.radius = 0.5
    drop.height = 1.5
    var paint := StandardMaterial3D.new()
    paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    paint.albedo_color = Color(0.87, 0.91, 0.81)
    drop.material = paint
    spray.draw_pass_1 = drop
    spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    ship.add_child(spray)
    return spray

static func update(main: Node3D, water: ShaderMaterial, spray: GPUParticles3D) -> void:
    var ship = main.get_node("Ship")
    water.set_shader_parameter("ship_position", ship.global_position)
    var aft: Vector3 = ship.global_basis.z.normalized()
    water.set_shader_parameter("ship_aft", Vector2(aft.x, aft.z).normalized())
    water.set_shader_parameter("ship_speed", ship.speed)
    water.set_shader_parameter("foam_enabled", FOAM_ENABLED)
    spray.position = Vector3(0, 0.15, -9.8)
    var bow := spray.global_position
    spray.global_position.y = main.get_node("/root/Ocean").get_wave_height(bow.x, bow.z, main.get_node("/root/Ocean").time) + 0.12
    spray.emitting = ship.speed > 0.6
    spray.amount_ratio = clampf(ship.speed / 6.0, 0.0, 1.0)
