extends SceneTree
const Parrot = preload("res://scripts/parrot.gd")
var failures := 0
func _initialize() -> void:
    run.call_deferred()
func frames(count: int) -> void:
    for i in count:
        await physics_frame
        await process_frame
func check(ok: bool, message: String) -> void:
    print("PASS " if ok else "FAIL ", message)
    if not ok:
        failures += 1
func run() -> void:
    check(not Parrot.select_flip(Vector3.RIGHT, Vector3.RIGHT, true), "right flight faces right")
    check(Parrot.select_flip(Vector3.LEFT, Vector3.RIGHT, false), "left flight flips")
    check(Parrot.select_flip(Vector3.FORWARD, Vector3.RIGHT, true) and not Parrot.select_flip(Vector3.BACK, Vector3.RIGHT, false), "depth motion preserves either previous flip")
    check(Parrot.select_flip(Vector3(0.1, 0, -1), Vector3.RIGHT, true), "hysteresis ignores small lateral motion")
    var cycle: Array[int] = []
    for i in 8:
        cycle.append(Parrot.wing_frame(i))
    check(cycle == [0, 1, 2, 1, 0, 1, 2, 1], "ordered up mid down mid wing cycle")
    var main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)
    var ship = main.get_node("Ship")
    var bird = ship.get_node("Parrot")
    var player = main.get_node("Player")
    await frames(2)
    check(bird.get_parent() == ship and not bird.is_in_group("hittable") and not bird.has_method("take_hit"), "ship child and no sword hit interface")
    check(bird.sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED and bird.sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD and bird.sprite.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS and bird.sprite.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "full billboard / alpha cut / mipmaps / shadow")
    check(bird.perches.size() == 12, "all mesh-derived perches including both yard ends")
    var wind = root.get_node("Wind")
    wind.variation_enabled = false
    wind.direction = ship.heading + PI * 0.5
    wind.strength = 1.0
    ship.change_sail(3)
    ship.steering_input = 0.2
    var start: Vector3 = ship.global_position
    var bounded := true
    var attached := true
    var sat := false
    var flew_again := false
    for i in 3600:
        await frames(1)
        var p: Vector3 = bird.position
        if bird.state != Parrot.State.PERCH:
            bounded = bounded and Vector2(p.x, p.z).length() <= 12.0 and p.y >= 3.0 and p.y <= 20.0
        sat = sat or bird.state == Parrot.State.PERCH
        flew_again = flew_again or (sat and bird.state == Parrot.State.FLY)
        attached = attached and bird.global_position.distance_to(ship.to_global(p)) < 0.001
    check(bounded and attached and ship.global_position.distance_to(start) > 40.0, "60 s moving/turning ship: flight bounds and local attachment")
    check(sat and flew_again and bird.landings > 0 and bird.takeoffs > 0, "natural landing and subsequent takeoff within 60 s")
    ship.set_physics_process(false)
    player.set_physics_process(false)
    bird.set_physics_process(false)
    var rail: Dictionary
    for perch in bird.perches:
        if perch.name == "QDRail_Mid_Top":
            rail = perch
    bird.position = rail.point + Vector3(1, 2, 0)
    bird.approach_perch(rail)
    for i in 240:
        bird._physics_process(1.0 / 60.0)
    check(bird.state == Parrot.State.PERCH and bird.position.distance_to(rail.point) < 0.001 and bird.sprite.offset.is_equal_approx(Vector2(24 if bird.sprite.flip_h else -24, 70)), "landing ends at real rail AABB top with existing PNG claws grounded")
    player.global_position = ship.to_global(bird.position + Vector3(0, -0.4, 0.9))
    player.camera.look_at(bird.global_position + bird.global_basis.y.normalized() * bird.body_height * 0.55)
    check(main._crew_look_name() == "Papağan", "shared HUD names parrot while looking within 5 m")
    player.camera.rotate_y(PI)
    check(main._crew_look_name() != "Papağan", "HUD hides parrot when looking away")
    bird._physics_process(1.0 / 60.0)
    check(bird.state == Parrot.State.FLY and bird.velocity.y > 0, "player within 1.5 m startles perched bird into flight")
    player.at_helm = true
    bird._rng.seed = 120
    var helm_choices := 0
    for i in 100:
        if bird._choose_perch().name == "HelmStand":
            helm_choices += 1
    check(helm_choices >= 65, "helm player strongly attracts helm perch")
    main.queue_free()
    await frames(2)
    print("PARROT_SMOKE failures=", failures)
    quit(1 if failures else 0)
