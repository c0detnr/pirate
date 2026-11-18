extends Node3D
## Modeldeki GunP*/GunS* namlularını ateşlenebilir toplara çevirir.
## side: -1 iskele, +1 sancak.
const Cannonball = preload("res://scripts/cannonball.gd")
const Fx = preload("res://scripts/cannon_fx.gd")
const GUNS_PER_SIDE := 4
const RELOAD_TIME := 7.0
const BROADSIDE_STAGGER := 0.11
const MUZZLE_SPEED := 55.0
const ELEVATION := 0.157 # yaklaşık 9 derece, ~95 m menzil
const BARREL_HALF_LENGTH := 0.85 # namlu yerel +Y yönünde dışarı bakar
const RECOIL_DISTANCE := 0.38
const USE_DISTANCE := 2.6
const USE_FACING := 0.8

var guns: Array[Dictionary] = []
var _ship: Node3D

static func install(ship: Node3D) -> Node3D:
    var battery: Node3D = (load("res://scripts/ship_guns.gd") as GDScript).new()
    battery.name = "Guns"
    ship.add_child(battery)
    battery.setup(ship)
    return battery

func setup(ship: Node3D) -> void:
    _ship = ship
    Fx.prepare()
    for side in [-1, 1]:
        for index in GUNS_PER_SIDE:
            var part_name := "Gun%s%d_Barrel" % ["P" if side < 0 else "S", index]
            var barrel: MeshInstance3D = ship.get_model_part(part_name)
            if barrel == null:
                push_error("ship.glb is missing " + part_name)
                continue
            guns.append({"barrel": barrel, "side": side, "home": barrel.position, "reload": 0.0})

func _physics_process(delta: float) -> void:
    for gun in guns:
        gun.reload = maxf(gun.reload - delta, 0.0)

func reload_left(index: int) -> float:
    return guns[index].reload

func ready_count(side: int) -> int:
    var count := 0
    for gun in guns:
        if gun.side == side and gun.reload <= 0.0:
            count += 1
    return count

func side_toward(direction: Vector3) -> int:
    return 1 if direction.dot(_ship.global_basis.x) >= 0.0 else -1

func gun_in_view(camera: Camera3D) -> int:
    var best := -1
    var best_facing := USE_FACING
    var forward := -camera.global_basis.z
    for index in guns.size():
        var toward: Vector3 = guns[index].barrel.global_position - camera.global_position
        if toward.length() > USE_DISTANCE:
            continue
        var facing := forward.dot(toward.normalized())
        if facing > best_facing:
            best_facing = facing
            best = index
    return best

func fire(index: int) -> bool:
    if guns[index].reload > 0.0:
        return false
    guns[index].reload = RELOAD_TIME
    _discharge(index)
    return true

## Dolu topları sırayla ateşler; bekleyen toplar anında dolum sayılır ki
## ikinci tık aynı topu yeniden sıraya sokmasın.
func fire_side(side: int) -> int:
    var fired := 0
    var volley := create_tween()
    for index in guns.size():
        var gun: Dictionary = guns[index]
        if gun.side != side or gun.reload > 0.0:
            continue
        gun.reload = RELOAD_TIME
        volley.parallel().tween_callback(_discharge.bind(index)).set_delay(fired * BROADSIDE_STAGGER)
        fired += 1
    if fired == 0:
        volley.kill()
    return fired

func _discharge(index: int) -> void:
    var gun: Dictionary = guns[index]
    var barrel: MeshInstance3D = gun.barrel
    var outward := barrel.global_basis.y.normalized()
    var muzzle := barrel.global_position + outward * BARREL_HALF_LENGTH
    var aim := (outward + Vector3.UP * tan(ELEVATION)).normalized()
    var world: Node = _ship.get_parent()
    Cannonball.launch(world, muzzle, aim * MUZZLE_SPEED + _ship.hull_velocity, _ship)
    Fx.muzzle_blast(world, muzzle, outward)
    _ship.add_gun_recoil(gun.side)
    var home: Vector3 = gun.home
    var back: Vector3 = home - barrel.transform.basis.y.normalized() * RECOIL_DISTANCE
    var recoil := barrel.create_tween()
    recoil.tween_property(barrel, "position", back, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    recoil.tween_property(barrel, "position", home, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
