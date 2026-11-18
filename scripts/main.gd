extends Node3D

@onready var water_material: ShaderMaterial = $Sea.material_override
@onready var controls: Label = $HUD/Controls
var _wind_arrow: Label
var _wind_label: Label
var _prompt: Label
var _spray: GPUParticles3D
var day_night: Node
const Appearance = preload("res://scripts/world_appearance.gd")
const DayNight = preload("res://scripts/day_night.gd")
const ShipLights = preload("res://scripts/ship_lights.gd")
const Ambience = preload("res://scripts/ambience.gd")

func _ready() -> void:
    Appearance.configure(self)
    _spray = Appearance.make_spray($Ship)
    $Player.global_position = $Ship.get_spawn_position()
    Ocean.configure_material(water_material)
    Ocean.update_material(water_material)
    # The surface shares Ocean's zero waterline, including after grid recentering.
    $Sea.position = Vector3.ZERO
    day_night = DayNight.new()
    day_night.name = "DayNight"
    add_child(day_night)
    day_night.setup(self, water_material, _spray)
    ShipLights.install($Ship, day_night)
    Ambience.install(self, $Ship, $Player)
    _wind_label = _label(Vector2(24, 140), 18)
    _wind_arrow = _label(Vector2(89, 200), 36)
    _wind_arrow.text = "↑"
    _wind_arrow.size = Vector2(42, 48)
    _wind_arrow.pivot_offset = Vector2(21, 24)
    _wind_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _prompt = _label(Vector2.ZERO, 22)
    _prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    _prompt.offset_left = -280
    _prompt.offset_top = -80
    _prompt.offset_right = 280
    _prompt.offset_bottom = -40
    _prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _label(at: Vector2, font_size: int) -> Label:
    var label := Label.new()
    $HUD.add_child(label)
    label.position = at
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", Color(1, 0.96, 0.83))
    label.add_theme_color_override("font_shadow_color", Color(0.04, 0.09, 0.12))
    label.add_theme_constant_override("shadow_offset_x", 2)
    label.add_theme_constant_override("shadow_offset_y", 2)
    return label

func _process(_delta: float) -> void:
    Ocean.update_material(water_material)
    Appearance.update(self, water_material, _spray)
    var eye: Vector3 = $Player/Camera3D.global_position
    $Sea.global_position = Vector3(snappedf(eye.x, 2.5), 0, snappedf(eye.z, 2.5))
    _wind_arrow.rotation = -$Ship.wind_relative_angle()
    _wind_label.text = "RÜZGÂR · %d%%\nGeldiği yön / pruva ↑" % roundi(Wind.strength * 100.0)
    if $Player.at_helm:
        var turn := "İSKELE" if $Ship.rudder < -0.05 else ("SANCAK" if $Ship.rudder > 0.05 else "ORTA")
        controls.text = "GEMİYİ SÜR\n%.1f knot  ·  Yelken %d/3  ·  Dümen %s %d%%\nA / D · Dümen    W / S · Yelken    E · Bırak\nSol tık · Baktığın bordadan ateş    Fare · Bak    Esc · Fareyi bırak    N · Gece/Gündüz" % [$Ship.speed * 1.94384, $Ship.sail_level, turn, roundi(absf($Ship.rudder) * 100.0)]
        var crew_name := _crew_look_name()
        _prompt.text = crew_name if not crew_name.is_empty() else _broadside_prompt()
    else:
        controls.text = "DENİZDE YÜRÜ\nWASD · Yürü    Shift · Koş    Space · Zıpla    N · Gece/Gündüz\nFare · Bak    Esc · Fareyi bırak    Sol tık · Kılıç / fareyi yakala"
        _prompt.text = "E — Gemiye dön" if $Player.is_swimming() else ("E — Dümene geç" if $Player.can_use_helm() else _gun_prompt())
        if _prompt.text.is_empty():
            _prompt.text = _crew_look_name()

func _broadside_prompt() -> String:
    var side: int = $Player.helm_fire_side()
    var side_name := "Sancak" if side > 0 else "İskele"
    var loaded: int = $Ship.guns.ready_count(side)
    if loaded == 0:
        return "%s topları dolduruluyor…" % side_name
    return "Sol tık — %s bordası ateş (%d/4)" % [side_name, loaded]

func _gun_prompt() -> String:
    var gun: int = $Player.aimed_gun()
    if gun < 0:
        return ""
    var wait: float = $Ship.guns.reload_left(gun)
    return "E — Topu ateşle" if wait <= 0.0 else "Top dolduruluyor… %d sn" % ceili(wait)

func _crew_look_name() -> String:
    var camera: Camera3D = $Player/Camera3D
    var closest := 5.0
    var result := ""
    for crew in get_tree().get_nodes_in_group("crew") + get_tree().get_nodes_in_group("look_names"):
        var target: Vector3 = crew.global_position + crew.global_basis.y.normalized() * crew.body_height * 0.55
        var toward := target - camera.global_position
        var distance := toward.length()
        var name_range: float = crew.look_distance if crew.is_in_group("look_names") else 3.0
        if distance > minf(closest, name_range) or (-camera.global_basis.z).dot(toward.normalized()) < 0.975:
            continue
        var ray := PhysicsRayQueryParameters3D.create(camera.global_position, target)
        ray.exclude = [$Player.get_rid()]
        if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
            continue
        closest = distance
        result = crew.display_name
    return result
