extends SceneTree
## Dönüş hissi ve toplar, gerçek ana sahne ve oyuncu denetleyicisi üzerinde.
var failures := 0

class Target extends StaticBody3D:
    var damage := 0
    func take_hit(amount: int, _from: Node) -> void:
        damage += amount

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

func balls() -> Array[Node]:
    return get_nodes_in_group("cannonballs")

func run() -> void:
    var main := load("res://scenes/main.tscn").instantiate() as Node3D
    root.add_child(main)
    var ship: Node3D = main.get_node("Ship")
    var player: CharacterBody3D = main.get_node("Player")
    var wind := root.get_node("Wind")
    wind.variation_enabled = false
    wind.strength = 1.0
    await frames(30)
    # Steering: hull lags the rudder, carries on after it, heels out and slows.
    main.get_node("Island").position = Vector3(5000, 0, 5000)
    ship.speed = 6.0
    wind.direction = ship.heading + PI * 0.5
    ship.sail_level = 3
    await frames(300)
    var straight_speed: float = ship.speed
    ship.steering_input = 1.0
    await frames(30)
    check(ship.yaw_rate > 0.0 and ship.yaw_rate < ship.rudder * ship.MAX_YAW_RATE * 0.7,
        "hull yaw lags rudder yaw=%.3f rudder=%.2f" % [ship.yaw_rate, ship.rudder])
    await frames(240)
    check(ship.yaw_rate > 0.14, "full rudder reaches a real turn rate yaw=%.3f" % ship.yaw_rate)
    check(ship.speed < straight_speed - 0.2, "turn costs speed %.2f -> %.2f" % [straight_speed, ship.speed])
    var side_speed: float = ship.hull_velocity.dot(ship.global_basis.x)
    check(side_speed < -0.1, "hull skids outward side=%.2f" % side_speed)
    ship.steering_input = 0.0
    ship.rudder = 0.0
    await frames(20)
    check(ship.yaw_rate > 0.05, "hull keeps turning after rudder centres yaw=%.3f" % ship.yaw_rate)
    await frames(360)
    check(absf(ship.yaw_rate) < 0.01, "turn settles yaw=%.4f" % ship.yaw_rate)
    # Guns.
    ship.speed = 0.0
    ship.sail_level = 0
    var guns: Node3D = ship.guns
    check(guns.guns.size() == 8, "eight guns found")
    check(guns.ready_count(-1) == 4 and guns.ready_count(1) == 4, "all guns start loaded")
    var starboard: Vector3 = ship.global_basis.x
    check(guns.side_toward(starboard) == 1 and guns.side_toward(-starboard) == -1, "side follows look direction")
    var barrel: Node3D = guns.guns[4].barrel
    var home: Vector3 = barrel.position
    check(guns.fire_side(1) == 4 and guns.ready_count(1) == 0 and guns.ready_count(-1) == 4, "broadside uses one side")
    check(guns.fire_side(1) == 0, "second click cannot refire during volley")
    await frames(40)
    check(balls().size() == 4, "volley launches four balls count=%d" % balls().size())
    var outward := true
    var shot_from: Vector3 = ship.global_position
    for ball in balls():
        outward = outward and ball.velocity.dot(starboard) > 40.0
    check(outward, "balls leave the starboard side")
    await frames(1)
    var farthest := 0.0
    while not balls().is_empty():
        for ball in balls():
            farthest = maxf(farthest, Vector2(ball.global_position.x - shot_from.x, ball.global_position.z - shot_from.z).length())
        await frames(1)
    check(farthest > 70.0 and farthest < 140.0, "balls fall in the sea at range=%.1f m" % farthest)
    await frames(150)
    check(barrel.position.distance_to(home) < 0.01, "barrel returns after recoil")
    await frames(120)
    check(guns.ready_count(1) == 4, "guns reload")
    # Real input paths: helm click and E on an aimed deck gun.
    player.global_position = ship.get_helm_stand_position()
    player.set("_riding", true)
    player.enter_helm()
    player.rotation.y = ship.heading - PI * 0.5
    player.camera.rotation.x = 0.0
    await frames(2)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
    var click := InputEventAction.new()
    click.action = "attack"
    click.pressed = true
    if captured:
        player._unhandled_input(click)
        check(guns.ready_count(1) == 0, "helm click fires the viewed broadside")
    else:
        check(guns.fire_side(player.helm_fire_side()) == 4, "helm side resolves (headless has no mouse capture)")
    check(player.helm_fire_side() == 1, "looking starboard selects starboard")
    player.leave_helm()
    await frames(30)
    var deck_gun: Node3D = guns.guns[1].barrel
    player.global_position = ship.to_global(Vector3(-0.6, 1.7, deck_gun.position.z))
    player.set("_riding", true)
    player.velocity = Vector3.ZERO
    player.look_at(Vector3(deck_gun.global_position.x, player.global_position.y, deck_gun.global_position.z))
    player.camera.look_at(deck_gun.global_position)
    await frames(1)
    player.set("_riding", true)
    check(player.aimed_gun() == 1, "looking at a deck gun selects it got=%d" % player.aimed_gun())
    var interact := InputEventAction.new()
    interact.action = "interact"
    interact.pressed = true
    player._unhandled_input(interact)
    check(guns.reload_left(1) > 6.0 and guns.ready_count(-1) == 3, "E fires only the aimed gun")
    check(not guns.fire(1), "reloading gun cannot fire")
    while not balls().is_empty():
        await frames(1)
    # Impact contract, using a test-only target.
    var target := Target.new()
    target.add_to_group("hittable")
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(4, 8, 4)
    shape.shape = box
    target.add_child(shape)
    main.add_child(target)
    target.global_position = ship.global_position + Vector3(0, 8, 0) + starboard * 30.0
    await frames(2)
    var Ball = load("res://scripts/cannonball.gd")
    var shot: Node3D = Ball.launch(main, target.global_position - starboard * 15.0, starboard * 55.0, ship)
    await frames(30)
    check(target.damage == 100 and not is_instance_valid(shot),
        "ball damages hittable once and stops damage=%d alive=%s pos=%s target=%s" % [target.damage, is_instance_valid(shot), shot.global_position if is_instance_valid(shot) else Vector3.ZERO, target.global_position])
    # Island has no collider; the ball must still stop on it.
    var island: Node3D = main.get_node("Island")
    var land_shot: Node3D = Ball.launch(main, island.global_position + Vector3(-30, 1.5, 0), Vector3(40, 0, 0), ship)
    await frames(50)
    check(not is_instance_valid(land_shot), "ball stops at the island")
    # Ambience: seamless loops whose levels follow the sailing state.
    var ambience: Node = main.get_node("Ambience")
    for key in ["Wind", "Sea", "Wash"]:
        var layer: AudioStreamPlayer = ambience.get_node(key)
        var stream := layer.stream as AudioStreamWAV
        var last := stream.loop_end * 2 - 2
        var seam := absi(stream.data.decode_s16(0) - stream.data.decode_s16(last))
        var largest_step := 0
        for at in range(2, stream.loop_end * 2, 2):
            largest_step = maxi(largest_step, absi(stream.data.decode_s16(at) - stream.data.decode_s16(at - 2)))
        check(layer.playing and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and seam <= largest_step,
            "%s loop plays seam=%d largest step=%d" % [key, seam, largest_step])
    var wash: AudioStreamPlayer = ambience.get_node("Wash")
    ship.speed = 0.0
    await frames(150)
    var quiet := wash.volume_db
    ship.speed = 7.0
    await frames(150)
    check(wash.volume_db > quiet + 6.0, "hull wash rises with speed %.1f -> %.1f dB" % [quiet, wash.volume_db])
    print("CANNON_SMOKE failures=", failures)
    await frames(180) # Efekt zamanlayıcıları bitsin.
    main.queue_free()
    await frames(2)
    quit(1 if failures else 0)
