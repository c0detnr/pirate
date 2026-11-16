extends SceneTree
## Run with --rendering-method gl_compatibility --script tests/visual_capture.gd.
## The extra camera exists only in this capture harness, never in the game scene.
const OUTPUT := "/tmp/claude-1000/-home-mami-Projects-pirate/111034f7-0459-44f0-aaec-0d86d0a4e31a/scratchpad/shots"
var capture_viewport: SubViewport

func _initialize() -> void:
    run.call_deferred()

func frames(count: int) -> void:
    for i in count:
        await process_frame
        await RenderingServer.frame_post_draw

func shoot(camera: Camera3D, ship: Node3D, eye: Vector3, target: Vector3, file: String) -> void:
    camera.global_position = ship.to_global(eye)
    camera.look_at(ship.to_global(target))
    await frames(4)
    var image := capture_viewport.get_texture().get_image()
    var result := image.save_png(OUTPUT.path_join(file))
    print("CAPTURE ", file, " ", image.get_size(), " error=", result)

func run() -> void:
    capture_viewport = SubViewport.new()
    capture_viewport.size = Vector2i(1280, 720)
    capture_viewport.own_world_3d = true
    capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(capture_viewport)
    var main := load("res://scenes/main.tscn").instantiate() as Node3D
    # Avoid requesting OS pointer capture in an automated preview.
    var player := main.get_node("Player")
    player.set_script(null)
    capture_viewport.add_child(main)
    var ship := main.get_node("Ship") as Node3D
    # Main's HUD expects the actual controller, so disable its per-frame UI here.
    main.set_process(false)
    var water: ShaderMaterial = main.get_node("Sea").material_override
    var ocean := root.get_node("Ocean")
    ship.set_physics_process(false)
    ship.rotation = Vector3.ZERO
    ship.position = Vector3.ZERO
    var wind := root.get_node("Wind")
    wind.variation_enabled = false
    wind.direction = deg_to_rad(140.0)
    wind.strength = 1.0
    ship.change_sail(3)
    ship._update_sail_wind(2.0)
    main.get_node("HUD").hide()
    player.get_node("WeaponViewmodel").set_process(false)
    player.get_node("WeaponViewmodel").hide()
    var camera := Camera3D.new()
    camera.fov = 75.0
    camera.far = 600.0
    main.add_child(camera)
    camera.make_current()
    water.set_shader_parameter("ship_position", ship.global_position)
    water.set_shader_parameter("ship_aft", Vector2(0, 1))
    ship.set("speed", 5.0)
    preload("res://scripts/world_appearance.gd").update(main, water, ship.get_node("BowSpray"))
    DirAccess.make_dir_recursive_absolute(OUTPUT)
    ship._sail_tween.custom_step(1.6)
    await frames(4)
    ocean.update_material(water)
    # Freeze navigation only in the capture harness; use the real art/state setup.
    var parrot = ship.get_node("Parrot")
    parrot.set_physics_process(false)
    parrot.position = Vector3(1.2, 6.1, -2.0)
    parrot.state = parrot.State.FLY
    parrot.velocity = Vector3(5, 1, 0)
    parrot._set_art(0)
    parrot.sprite.flip_h = false
    camera.fov = 60.0
    await shoot(camera, ship, Vector3(1.5, 3.25, 1.0), parrot.position, "parrot_flying.png")
    var parrot_rail: Dictionary
    for perch in parrot.perches:
        if perch.name == "QDRail_Mid_Top":
            parrot_rail = perch
    parrot.position = parrot_rail.point
    parrot.state = parrot.State.PERCH
    parrot._set_art(4)
    camera.fov = 55.0
    await shoot(camera, ship, parrot.position + Vector3(0.4, 0.45, 1.5), parrot.position + Vector3(0, 0.2, 0), "parrot_perched.png")
    camera.fov = 75.0
    await shoot(camera, ship, Vector3(0.4, 3.25, 4.1), Vector3(-0.3, 2.3, -7), "deck_fwd.png")
    await shoot(camera, ship, Vector3(0, 4.5, 8.6), Vector3(0, 3.1, -5), "helm_view.png")
    camera.fov = 55.0
    await shoot(camera, ship, Vector3(18, 11, 21), Vector3(0, 7.0, -1), "ship_outside.png")
    await shoot(camera, ship, Vector3(18, 11, 21), Vector3(0, 8.0, -1), "sails_full_outside.png")
    var sun := main.get_node("Sun") as DirectionalLight3D
    var old_sun_basis := sun.global_basis
    # Sun behind the foremast cloth, seen through it from the main deck.
    sun.look_at(sun.global_position + Vector3(0.1, -0.32, 1.0), Vector3.UP)
    camera.fov = 75.0
    await shoot(camera, ship, Vector3(0.7, 3.3, 1), Vector3(0, 11.5, -5), "sails_backlit.png")
    sun.global_basis = old_sun_basis
    wind.direction = 0.0
    ship.speed = 0.0
    ship._update_sail_wind(3.0)
    camera.fov = 55.0
    await shoot(camera, ship, Vector3(18, 11, 21), Vector3(0, 8, -1), "sails_luffing.png")
    ship.change_sail(-3)
    ship._sail_tween.custom_step(1.6)
    await frames(4)
    await shoot(camera, ship, Vector3(18, 11, 21), Vector3(0, 8, -1), "sails_furled.png")
    camera.fov = 75.0
    await shoot(camera, ship, Vector3(12, 3, -15), Vector3(3, 2, -100), "sea_horizon.png")
    main.queue_free()
    await frames(2)
    quit()
