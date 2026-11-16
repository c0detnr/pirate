extends SceneTree
const Crew = preload("res://scripts/crew_member.gd")
var failures := 0

class Target extends StaticBody3D:
    var hits := 0
    var damage_received := 0
    var attacker: Node
    func take_hit(damage: int, from: Node) -> void:
        hits += 1
        damage_received = damage
        attacker = from

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
    for example in [[0.0, "front", false], [90.0, "side", false], [-90.0, "side", true], [180.0, "back", false], [45.0, "front", false], [-135.0, "back", false], [450.0, "side", false]]:
        var view := Crew.select_view(deg_to_rad(example[0]))
        check(view.view == example[1] and view.flip_h == example[2], "direction %s degrees -> %s / flip=%s" % example)
    var main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)
    var ship = main.get_node("Ship")
    var player = main.get_node("Player")
    var weapon = player.get_node("WeaponViewmodel")
    await frames(90)
    var crew := get_nodes_in_group("crew")
    check(crew.size() == 3, "three crew members")
    var starts: Array[Vector3] = []
    for member in crew:
        starts.append(member.position)
        check(member.get_parent() == ship and not member.is_in_group("hittable"), "%s is ship child, not hittable" % member.role)
        check(member.sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y and member.sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD and member.sprite.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s billboard/depth/shadow" % member.role)
        check(absf(member.sprite.pixel_size * member.sprite.texture.get_height() - member.body_height) < 0.001 and absf(member.sprite.get_aabb().position.y) < 0.001, "%s canvas height and grounded feet" % member.role)
    # One 20-second continuous moving/turning voyage, checking every frame.
    var wind = root.get_node("Wind")
    wind.variation_enabled = false
    wind.strength = 1.0
    wind.direction = ship.heading + PI * 0.5
    ship.change_sail(3)
    ship.steering_input = 0.3
    var start: Vector3 = ship.global_position
    var safe := true
    var moved := [false, false, false]
    for i in 1200:
        await frames(1)
        for index in crew.size():
            var member = crew[index]
            var p: Vector3 = member.position
            safe = safe and member.get_parent() == ship and absf(p.y - 1.6) < 0.001 and absf(p.x) <= 1.3 and p.z >= -6.3 and p.z <= 3.6
            safe = safe and member.global_position.distance_to(ship.to_global(p)) < 0.001
            moved[index] = moved[index] or p.distance_to(starts[index]) > 0.2
    check(safe and ship.global_position.distance_to(start) > 40.0, "20 s sailing/turning: local deck bounds, y=1.6, full ship transform")
    check(moved.all(func(value): return value), "all three patrols move")
    var member = crew[0]
    player.set_physics_process(false)
    player.global_position = ship.to_global(member.position + Vector3(0.6, 0.0, 0.0))
    var before: Vector3 = member.position
    await frames(60)
    var toward: Vector3 = ship.to_local(player.global_position) - member.position
    toward.y = 0.0
    check(member.position.distance_to(before) < 0.001 and member.get("_facing").dot(toward.normalized()) > 0.9, "near player: stop and face player")
    # Stop the ship so the hit target, camera and hidden-state tests stay aligned.
    ship.set_physics_process(false)
    var named_crew = crew[2]
    player.global_position = ship.to_global(named_crew.position + Vector3(-0.8, 0.0, -0.8))
    player.camera.look_at(named_crew.global_position + named_crew.global_basis.y.normalized() * named_crew.body_height * 0.55)
    check(main._crew_look_name() == named_crew.display_name, "HUD shows crew name within 3 m while looking")
    player.camera.rotate_y(PI)
    check(main._crew_look_name().is_empty(), "HUD hides name when looking away")
    player.global_position = ship.to_global(named_crew.position + Vector3(-4.0, 0.0, -4.0))
    player.camera.look_at(named_crew.global_position + named_crew.global_basis.y.normalized() * named_crew.body_height * 0.55)
    check(main._crew_look_name().is_empty(), "HUD hides distant crew name")
    player.global_position = ship.to_global(Vector3(0.7, 1.6, 0.0))
    player.set("_riding", true)
    player.at_helm = false
    player.rotation = Vector3.ZERO
    player.camera.rotation = Vector3.ZERO
    var click := InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_LEFT
    click.pressed = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    player._unhandled_input(click)
    check(weapon.state == "idle" and weapon.attacks_started == 0, "capture click does not attack (headless cannot capture OS mouse)")
    var target := Target.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(0.5, 0.5, 0.5)
    shape.shape = box
    target.add_child(shape)
    main.add_child(target)
    target.add_to_group("hittable")
    target.global_position = player.camera.global_position - player.camera.global_basis.z * 1.5
    await frames(2)
    weapon.request_attack() # Input capture gate belongs to player; headless has no pointer.
    check(weapon.state == "anticipation" and weapon.attacks_started == 1, "idle -> anticipation on captured click")
    check(not weapon.request_attack() and weapon.attacks_started == 1, "cooldown rejects second swing")
    await frames(9)
    check(weapon.state == "swing", "anticipation -> swing")
    check(not weapon.request_attack(), "swing rejects attack")
    await frames(8)
    check(target.hits == 1 and target.damage_received == 25 and target.attacker == player, "mid-swing 2 m ray calls hittable.take_hit once")
    await frames(8)
    check(weapon.state == "recovery" and not weapon.request_attack(), "recovery still rejects attack")
    await frames(12)
    check(weapon.state == "idle" and target.hits == 1, "swing -> idle with one hit")
    check(weapon.request_attack(), "new swing accepted after cooldown")
    await frames(40)
    player.at_helm = true
    await frames(20)
    check(not weapon.art.visible and not weapon.request_attack(), "helm lowers and hides sword, blocks attack")
    player.at_helm = false
    player.set("_riding", false)
    player.global_position = Vector3(30, -0.1, 30)
    await frames(20)
    check(player.is_swimming() and not weapon.art.visible and not weapon.request_attack(), "swimming hides sword, blocks attack")
    player.set("_riding", true)
    await frames(20)
    check(weapon.art.visible, "sword returns after walking resumes")
    target.queue_free()
    main.queue_free()
    await frames(2)
    print("CREW_WEAPON_SMOKE failures=", failures)
    quit(1 if failures else 0)
