extends SceneTree
## Real player controller on the animated GLB collider; no replacement test body.
var ship: AnimatableBody3D
var player: CharacterBody3D
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

func place(local: Vector3) -> void:
    player.global_position = ship.to_global(local)
    player.velocity = Vector3.ZERO
    player.rotation = Vector3.ZERO
    player.set("_riding", false)
    await frames(60)

func walk(action: String, count: int) -> void:
    Input.action_press(action)
    await frames(count)
    Input.action_release(action)
    await frames(12)

func run() -> void:
    var main := load("res://scenes/main.tscn").instantiate() as Node3D
    root.add_child(main)
    ship = main.get_node("Ship")
    player = main.get_node("Player")
    await frames(90)
    var collider := ship.get_node("ShipCollision") as CollisionShape3D
    check(collider.shape is ConcavePolygonShape3D, "ShipCollider -> ConcavePolygonShape3D")
    check(not ship.get_model_part("ShipCollider").visible, "ShipCollider hidden")
    check(ship.find_children("*", "CollisionShape3D", true, false).size() == 1,
        "one collider on AnimatableBody3D; visuals have no collisions")
    for part in ["Sail_ForeCourse", "HelmWheel", "HelmStand", "HatchGrate"]:
        check(ship.get_model_part(part) != null, "model name preserved: " + part)
    var start := ship.to_local(player.global_position)
    var drift := 0.0
    for i in 600:
        await frames(1)
        var here := ship.to_local(player.global_position)
        drift = maxf(drift, Vector2(here.x - start.x, here.z - start.z).length())
    check(player.is_on_floor() and absf(start.y - 1.6) < 0.08 and drift < 0.08,
        "spawn/deck 10 s max drift=%.4f m; y=%.3f" % [drift, start.y])
    for side in [-1.0, 1.0]:
        await place(Vector3(side * 1.75, 2.6, 1.7))
        await walk("move_back", 75)
        var aft := ship.to_local(player.global_position)
        check(player.is_on_floor() and absf(aft.y - 2.9) < 0.12 and aft.z > 4.7,
            "stern ramp side=%+.0f position=%s" % [side, aft])
        await place(Vector3(side * 1.3, 2.6, -5.1))
        await walk("move_forward", 65)
        var fore := ship.to_local(player.global_position)
        check(player.is_on_floor() and absf(fore.y - 2.4) < 0.12 and fore.z < -7.3,
            "bow ramp side=%+.0f position=%s" % [side, fore])
    for side in [-1.0, 1.0]:
        for deck in [Vector3(1.4 * side, 2.6, -1.2), Vector3(0.8 * side, 3.9, 7.0), Vector3(0.8 * side, 3.4, -8.8)]:
            await place(deck)
            var action := "move_left" if side < 0 else "move_right"
            var stayed_aboard := true
            Input.action_press(action)
            for i in 150:
                await frames(1)
                var point := ship.to_local(player.global_position)
                stayed_aboard = stayed_aboard and point.y > 1.5 and absf(point.x) < 3.0 and point.z > -11.0 and point.z < 10.5
            Input.action_release(action)
            await frames(12)
            var rail := ship.to_local(player.global_position)
            check(stayed_aboard and player.is_on_floor() and absf(rail.x) < 3.0 and rail.y > 1.5 and rail.z > -11.0 and rail.z < 10.5,
                "rail side=%+.0f deck z=%.1f position=%s" % [side, deck.z, rail])
    await place(Vector3(8.0, 0.0, 0.0))
    check(player.global_position.y < 0.6, "swimming away from ship")
    var interact := InputEventAction.new()
    interact.action = "interact"
    interact.pressed = true
    player._unhandled_input(interact)
    check(player.global_position.distance_to(ship.get_spawn_position()) < 0.001,
        "E returns to shared spawn")
    await frames(90)
    check(player.is_on_floor() and absf(ship.to_local(player.global_position).y - 1.6) < 0.08,
        "E return lands on main deck")
    # Deterministic sailing conditions; the live Wind normally drifts smoothly.
    var wind := root.get_node("Wind")
    wind.variation_enabled = false
    wind.strength = 1.0
    for angle in [0.0, PI * 0.5, PI]:
        wind.direction = ship.heading + angle
        ship._update_sail_wind(3.0)
        var fill_ok := true
        for sail in ship.get("_sails"):
            var value := float(sail.material.get_shader_parameter("fullness"))
            if angle == 0.0:
                fill_ok = fill_ok and value < 0.01
            elif angle == PI * 0.5 or sail.square:
                fill_ok = fill_ok and value > 0.99
            else:
                fill_ok = fill_ok and value < 0.30
        check(fill_ok, "apparent wind sail fullness at %.0f degrees" % rad_to_deg(angle))
    var rigging_ok := true
    for part in ship.get_node("Model").find_children("*", "MeshInstance3D", true, false):
        if str(part.name).begins_with("Sheet_") or str(part.name).begins_with("Lift_"):
            var material := part.get_active_material(0) as ShaderMaterial
            rigging_ok = rigging_ok and material != null and material.next_pass == null
    check(rigging_ok, "sheets and lifts receive no contour pass")
    wind.direction = ship.heading + PI * 0.5
    ship.change_sail(3)
    var sailing_start := ship.global_position
    var peak_speed := 0.0
    for i in 1200:
        await frames(1)
        peak_speed = maxf(peak_speed, ship.speed)
    check(ship.global_position.distance_to(sailing_start) > 60.0 and peak_speed <= 7.001,
        "beam wind 20 s distance=%.2f m peak=%.3f m/s" % [ship.global_position.distance_to(sailing_start), peak_speed])
    # Free-standing passenger must retain their full local position while turning.
    await place(ship.SPAWN_LOCAL)
    start = ship.to_local(player.global_position)
    ship.steering_input = 0.7
    var initial_heading: float = ship.heading
    drift = 0.0
    var stayed_on_deck := true
    for i in 600:
        await frames(1)
        drift = maxf(drift, ship.to_local(player.global_position).distance_to(start))
        stayed_on_deck = stayed_on_deck and player.is_on_floor()
    check(absf(angle_difference(initial_heading, ship.heading)) > 0.2,
        "rudder changes heading while moving")
    check(stayed_on_deck and drift < 0.05,
        "moving/turning passenger 10 s full local drift=%.5f m" % drift)
    # Jumping on a moving, turning ship must not leave the player behind.
    await place(ship.SPAWN_LOCAL)
    var jump_start := ship.to_local(player.global_position)
    Input.action_press("jump")
    await frames(2)
    Input.action_release("jump")
    var rose := false
    var jump_drift := 0.0
    for i in 60:
        await frames(1)
        var point := ship.to_local(player.global_position)
        rose = rose or point.y > jump_start.y + 0.4
        jump_drift = maxf(jump_drift, Vector2(point.x - jump_start.x, point.z - jump_start.z).length())
    check(rose and jump_drift < 0.25 and player.is_on_floor(),
        "jump on moving ship speed=%.1f drift=%.3f m" % [ship.speed, jump_drift])
    ship.steering_input = 0.0
    ship.rudder = 0.0
    ship.speed = 0.0
    wind.direction = ship.heading
    sailing_start = ship.global_position
    await frames(1200)
    check(ship.global_position.distance_to(sailing_start) < 0.1 and ship.speed < 0.01,
        "headwind 20 s: no propulsion")
    # Real E path, proximity AND look direction required, then walk lock/release.
    player.global_position = ship.get_helm_stand_position()
    player.velocity = Vector3.ZERO
    player.rotation = Vector3(0, ship.heading, 0)
    player.camera.rotation.x = -0.5
    player.set("_riding", true)
    check(player.can_use_helm(), "helm proximity/look prompt available")
    player.rotation.y += PI
    check(not player.can_use_helm(), "looking away hides helm prompt")
    player.rotation.y -= PI
    player._unhandled_input(interact)
    check(player.at_helm, "E enters helm")
    var sail_event := InputEventAction.new()
    sail_event.action = "move_back"
    sail_event.pressed = true
    player._unhandled_input(sail_event)
    check(ship.sail_level == 2, "S lowers sail exactly one level")
    sail_event.action = "move_forward"
    player._unhandled_input(sail_event)
    check(ship.sail_level == 3, "W raises sail exactly one level")
    var wheel := ship.get_model_part("HelmWheel") as MeshInstance3D
    var hub := ship.get_model_part("HelmHub") as MeshInstance3D
    var hub_center := ship.to_local(hub.to_global(hub.get_aabb().get_center()))
    var spoke_start := wheel.transform
    Input.action_press("move_right")
    await frames(60) # Tam dümen çarkı tam 360° çevirir; ara açıda ölç.
    Input.action_release("move_right")
    check(player.global_position.distance_to(ship.get_helm_stand_position()) < 0.001 and ship.rudder > 0.5,
        "helm locks feet and A/D steers")
    check(ship.to_local(hub.to_global(hub.get_aabb().get_center())).distance_to(hub_center) < 0.001 and
        not wheel.get_parent().basis.is_equal_approx(Basis.IDENTITY) and wheel.transform.is_equal_approx(spoke_start),
        "helm rotates around hub without shifting mesh origin")
    for sail in ship.get("_sails"):
        check(float(sail.material.get_shader_parameter("furl")) < 0.01, "level 3 opens every sail")
    ship.change_sail(-3)
    await frames(150)
    for sail in ship.get("_sails"):
        check(float(sail.material.get_shader_parameter("furl")) > 0.99, "level 0 gathers every sail")
    ship.change_sail(1)
    await frames(120)
    for sail in ship.get("_sails"):
        var expected := 0.0 if int(sail.level) == 1 else 1.0
        check(absf(float(sail.material.get_shader_parameter("furl")) - expected) < 0.01, "level 1 opens topsails only")
    ship.change_sail(1)
    await frames(120)
    for sail in ship.get("_sails"):
        var expected := 0.0 if int(sail.level) <= 2 else 1.0
        check(absf(float(sail.material.get_shader_parameter("furl")) - expected) < 0.01, "level 2 adds course and gaff")
    ship.change_sail(-2)
    await frames(120)
    player._unhandled_input(interact)
    check(not player.at_helm and ship.steering_input == 0.0, "E leaves helm and releases steering")
    await frames(90)
    check(player.is_on_floor(), "leaving helm returns walking on deck")
    # Collision guard includes the entire hull, regardless of its heading.
    var island: Node3D = main.get_node("Island")
    ship.global_position.x = island.global_position.x + 20.0
    ship.global_position.z = island.global_position.z
    ship.speed = 5.0
    await frames(1)
    var coast_distance := Vector2(ship.global_position.x - island.global_position.x, ship.global_position.z - island.global_position.z).length()
    check(coast_distance >= ship.ISLAND_CLEARANCE - 0.01 and ship.speed == 0.0,
        "island stops and pushes hull clear")
    # Ocean follows the eye on a grid; CPU/shader both use world coordinates.
    player.global_position = Vector3(900, 2, -850)
    await frames(2)
    var sea: Node3D = main.get_node("Sea")
    check(absf(sea.global_position.x - player.global_position.x) <= 1.3 and absf(sea.global_position.z - player.global_position.z) <= 1.3 and sea.global_position.y == 0.0,
        "ocean follows distant player on wave waterline")
    print("SHIP_SMOKE failures=", failures)
    main.queue_free()
    await frames(2)
    quit(1 if failures else 0)
