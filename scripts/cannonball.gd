extends Node3D
## Balistik gülle. Her fizik adımında ışın atar, böylece hızlıyken hedef atlamaz.
const Fx = preload("res://scripts/cannon_fx.gd")
const GRAVITY := 9.8
const RADIUS := 0.13
const MAX_LIFETIME := 10.0
const DAMAGE := 100
const ISLAND_SHORE := 21.0 # ship.gd kıyı sınırıyla aynı

var velocity := Vector3.ZERO
var _source: CollisionObject3D
var _age := 0.0

static func launch(world: Node, from: Vector3, start_velocity: Vector3, source: CollisionObject3D) -> Node3D:
    var ball: Node3D = (load("res://scripts/cannonball.gd") as GDScript).new()
    ball.name = "Cannonball"
    ball.velocity = start_velocity
    ball._source = source
    ball.add_to_group("cannonballs")
    var mesh := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = RADIUS
    sphere.height = RADIUS * 2.0
    sphere.radial_segments = 10
    sphere.rings = 5
    var iron := StandardMaterial3D.new()
    iron.albedo_color = Color(0.07, 0.07, 0.08)
    iron.roughness = 0.5
    sphere.material = iron
    mesh.mesh = sphere
    ball.add_child(mesh)
    world.add_child(ball)
    ball.global_position = from
    return ball

func _physics_process(delta: float) -> void:
    _age += delta
    if _age > MAX_LIFETIME:
        queue_free()
        return
    velocity.y -= GRAVITY * delta
    var from := global_position
    var to := from + velocity * delta
    var query := PhysicsRayQueryParameters3D.create(from, to)
    query.collide_with_areas = true
    if is_instance_valid(_source):
        query.exclude = [_source.get_rid()]
    var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
    if player:
        query.exclude += [player.get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        _strike(hit.collider, hit.position)
        return
    global_position = to
    if _over_land(to):
        Fx.land_impact(get_parent(), to)
        queue_free()
    elif to.y <= Ocean.get_wave_height(to.x, to.z, Ocean.time):
        Fx.splash(get_parent(), to)
        queue_free()

func _strike(collider: Object, at: Vector3) -> void:
    var target := collider as Node
    while target:
        if target.is_in_group("hittable") and target.has_method("take_hit"):
            target.take_hit(DAMAGE, _source if is_instance_valid(_source) else null)
            break
        target = target.get_parent()
    Fx.land_impact(get_parent(), at)
    queue_free()

## Adanın çarpışma şekli yok; kubbe yaklaşımı tepeyi ve kıyıyı yeterince karşılar.
func _over_land(at: Vector3) -> bool:
    var island := get_parent().get_node_or_null("Island") as Node3D
    if island == null:
        return false
    var land := island.find_child("Land", true, false) as MeshInstance3D
    if land == null:
        return false
    var ratio := Vector2(at.x - island.global_position.x, at.z - island.global_position.z).length() / ISLAND_SHORE
    if ratio >= 1.0:
        return false
    var top := land.global_transform * land.get_aabb().end
    return at.y <= lerpf(island.global_position.y, top.y, 1.0 - ratio * ratio)
