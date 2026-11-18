extends Node
## Rüzgâr, deniz ve gövde suyu. Ses dosyası yerine dikişsiz gürültü döngüleri üretir.
const SAMPLE_RATE := 16000
const LOOP_SECONDS := 7.0
const CROSSFADE_SECONDS := 0.5
const FADE_SPEED := 6.0 # dB/sn

var _ship: Node3D
var _player: Node3D
var _wind: AudioStreamPlayer
var _sea: AudioStreamPlayer
var _wash: AudioStreamPlayer

static func install(parent: Node, ship: Node3D, player: Node3D) -> Node:
    var ambience: Node = (load("res://scripts/ambience.gd") as GDScript).new()
    ambience.name = "Ambience"
    ambience._ship = ship
    ambience._player = player
    parent.add_child(ambience)
    return ambience

func _ready() -> void:
    # low/high: bant sınırları; swells: döngüde tam sayı tekrar eden kabarmalar.
    _wind = _layer("Wind", _noise_loop(11, 0.17, 0.018, [1.0, 3.0], 0.38), -19.0)
    _sea = _layer("Sea", _noise_loop(23, 0.055, 0.004, [2.0, 3.0], 0.55), -13.0)
    _wash = _layer("Wash", _noise_loop(37, 0.55, 0.12, [5.0, 9.0], 0.22), -38.0)

func _exit_tree() -> void:
    for layer in [_wind, _sea, _wash]:
        layer.stop()
        layer.stream = null

func _layer(layer_name: String, stream: AudioStreamWAV, volume: float) -> AudioStreamPlayer:
    var layer := AudioStreamPlayer.new()
    layer.name = layer_name
    layer.stream = stream
    layer.volume_db = volume
    add_child(layer)
    layer.play()
    return layer

func _process(delta: float) -> void:
    var flow := clampf(_ship.speed / _ship.MAX_SPEED, 0.0, 1.0)
    var gust := clampf(Wind.strength, 0.0, 1.5)
    var submerged: bool = _player.is_swimming()
    var step := FADE_SPEED * delta
    _wind.volume_db = move_toward(_wind.volume_db, lerpf(-30.0, -17.0, gust / 1.5) - (6.0 if submerged else 0.0), step)
    _wind.pitch_scale = lerpf(0.85, 1.12, gust / 1.5) + flow * 0.06
    _sea.volume_db = move_toward(_sea.volume_db, -7.0 if submerged else -13.0, step)
    _wash.volume_db = move_toward(_wash.volume_db, lerpf(-38.0, -15.0, sqrt(flow)), step)
    _wash.pitch_scale = lerpf(0.8, 1.1, flow)

static func _noise_loop(seed_value: int, low: float, high: float, swells: Array, depth: float) -> AudioStreamWAV:
    var loop_size := int(SAMPLE_RATE * LOOP_SECONDS)
    var fade_size := int(SAMPLE_RATE * CROSSFADE_SECONDS)
    var samples := PackedFloat32Array()
    samples.resize(loop_size + fade_size)
    var noise := RandomNumberGenerator.new()
    noise.seed = seed_value
    var fast := 0.0
    var slow := 0.0
    var phase_step := TAU / loop_size
    for i in samples.size():
        var white := noise.randf_range(-1.0, 1.0)
        fast += (white - fast) * low
        slow += (white - slow) * high
        var phase := i * phase_step
        var swell := 0.0
        for cycles: float in swells:
            swell += sin(phase * cycles + cycles)
        samples[i] = (fast - slow) * (1.0 + depth * swell * 0.5)
    # Döngü sonundaki fazlalık başa eşit güçle karıştırılır, dikiş duyulmaz.
    for i in fade_size:
        var t := float(i) / fade_size
        samples[i] = samples[i] * sqrt(t) + samples[loop_size + i] * sqrt(1.0 - t)
    var peak := 0.001
    for i in loop_size:
        peak = maxf(peak, absf(samples[i]))
    var data := PackedByteArray()
    data.resize(loop_size * 2)
    for i in loop_size:
        data.encode_s16(i * 2, int(samples[i] / peak * 26000.0))
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = SAMPLE_RATE
    stream.data = data
    stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    stream.loop_begin = 0
    stream.loop_end = loop_size
    return stream
