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
    print("SHIP_SMOKE failures=", failures)
    main.queue_free()
    await frames(2)
    quit(1 if failures else 0)
