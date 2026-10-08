extends Control

const ROWS := 10
const COLS := 8
const FOOTBALL_TEAM_SIZE := 5
const BLUE := Color("#4ac5e8")
const RED := Color("#e45a78")
const BALL := Color("#f6cf65")

var pieces: Array[Dictionary] = []
var ball_cell := Vector2i(4, 4)
var ball_holder := -1
var turn := 1
var selected := -1
var scores := [0, 0]
var message := "Ход голубых"
var game_mode := 0 # 0 = bot, 1 = two players
var bot_difficulty: int = 1
var game_over := false
var bot_pending := false
var winner := 0

# The goal is celebrated BEFORE resetting the pitch or showing the winner panel.
var celebrating: bool = false
var celebration_time: float = 0.0
var celebration_duration: float = 3.2
var celebration_team: int = 1
var celebration_reason: String = ""
var celebration_final: bool = false



# High-detail fantasy assets are loaded from the local assets folder.
var fantasy_textures: Dictionary = {}
const BLUE_SKINS := ["blue_wizard", "blue_rogue", "blue_knight", "blue_dwarf"]
const RED_SKINS := ["red_skull", "red_orc", "red_goblin", "red_vampire"]
var piece_skins: Array[int] = [0, 1, 2, 3, 0, 0, 1, 2, 3, 0]
var customization_open: bool = false
var customization_team: int = 1
var customization_slot: int = 0


func _load_fantasy_assets() -> void:
    for key in ["stone_dark", "stone_light", "blue_wizard", "blue_rogue", "blue_knight", "blue_dwarf", "red_skull", "red_orc", "red_goblin", "red_vampire", "ghost_pumpkin"]:
        var path := "res://assets/%s.png" % key
        if ResourceLoader.exists(path):
            fantasy_textures[key] = load(path)

func _draw_asset(key: String, rect: Rect2) -> bool:
    if not fantasy_textures.has(key):
        return false
    draw_texture_rect(fantasy_textures[key], rect, false)
    return true

var pending_skin: int = -1
var flame_time: float = 0.0
var fancy_font: Font


# Halloween Sound Edition: shared per-scene sound system. No autoload required.
var sound_library: Dictionary = {}
var arena_music: AudioStreamPlayer

func _setup_game_audio() -> void:
    for sound_name in ["stone_move", "king_move", "capture", "pass", "goal", "crowd", "victory", "arena_ambience"]:
        var audio_path: String = "res://audio/%s.wav" % sound_name
        if ResourceLoader.exists(audio_path):
            sound_library[sound_name] = load(audio_path)
    arena_music = AudioStreamPlayer.new()
    arena_music.name = "HalloweenAmbience"
    add_child(arena_music)
    if sound_library.has("arena_ambience"):
        var ambience: AudioStream = sound_library["arena_ambience"]
        var wav_ambience: AudioStreamWAV = ambience as AudioStreamWAV
        if wav_ambience != null:
            wav_ambience.loop_mode = AudioStreamWAV.LOOP_FORWARD
        arena_music.stream = ambience
        arena_music.volume_db = linear_to_db(maxf(0.001, float(get_tree().root.get_meta("mb_vol_music", 0.55)) * 0.23))
        if not bool(get_tree().root.get_meta("mb_muted", false)):
            arena_music.play()

func _play_sfx(sound_name: String, channel: String = "effects") -> void:
    if not sound_library.has(sound_name) or bool(get_tree().root.get_meta("mb_muted", false)):
        return
    var volume_key: String = "mb_vol_crowd" if channel == "crowd" else "mb_vol_effects"
    var v: float = float(get_tree().root.get_meta(volume_key, 0.78))
    if v <= 0.005:
        return
    var player: AudioStreamPlayer = AudioStreamPlayer.new()
    add_child(player)
    player.stream = sound_library[sound_name]
    player.volume_db = linear_to_db(maxf(0.001, v * (0.68 if channel == "crowd" else 0.85)))
    player.finished.connect(func(): player.queue_free())
    player.play()

func _process(delta: float) -> void:
    if celebrating:
        celebration_time = maxf(0.0, celebration_time - delta)
        if celebration_time <= 0.0:
            celebrating = false
            if not game_over:
                var completed_reason: String = celebration_reason
                _reset_board()
                message = "%s  %d : %d" % [completed_reason, scores[0], scores[1]]
        queue_redraw()
    magic_clock += delta
    if fmod(magic_clock, 0.11) < delta: queue_redraw()
    if fx_progress < 1.0:
        fx_progress = minf(1.0, fx_progress + delta / fx_duration)
        queue_redraw()
    if fx_impact_time > 0.0:
        fx_impact_time = maxf(0.0, fx_impact_time - delta)
        queue_redraw()
    if fx_bounce_time > 0.0:
        fx_bounce_time = maxf(0.0, fx_bounce_time - delta)
        queue_redraw()
    if pass_fx_progress < 1.0:
        pass_fx_progress = minf(1.0, pass_fx_progress + delta / 0.26)
        queue_redraw()
    if selected >= 0 or drag_active: queue_redraw()
    if customization_open:
        flame_time += delta
        queue_redraw()

func _ui_font() -> Font:
    return fancy_font if fancy_font != null else ThemeDB.fallback_font

func _flame_frame(rect: Rect2, active: bool) -> void:
    if not active:
        draw_rect(rect, Color("#617589"), false, 2.0)
        return
    var pulse: float = 0.5 + 0.5 * sin(flame_time * 4.5)
    draw_rect(rect.grow(5.0), Color("#ef5720", 0.18 + pulse * 0.20), false, 6.0)
    draw_rect(rect.grow(2.0), Color("#ffb84b"), false, 3.0)
    for k in 14:
        var t: float = fmod(float(k) / 14.0 + flame_time * 0.24, 1.0)
        var perimeter: float = 2.0 * (rect.size.x + rect.size.y)
        var dist: float = t * perimeter
        var p: Vector2 = rect.position
        if dist < rect.size.x:
            p += Vector2(dist, 0)
        elif dist < rect.size.x + rect.size.y:
            p += Vector2(rect.size.x, dist - rect.size.x)
        elif dist < rect.size.x * 2.0 + rect.size.y:
            p += Vector2(rect.size.x - (dist - rect.size.x - rect.size.y), rect.size.y)
        else:
            p += Vector2(0, rect.size.y - (dist - rect.size.x * 2.0 - rect.size.y))
        draw_circle(p, 2.0 + pulse * 1.5, Color("#ff9c2b", 0.65))

func _confirmation_ui() -> void:
    if pending_skin < 0:
        return
    var font: Font = _ui_font()
    var w: float = minf(size.x - 24.0, 430.0)
    var h: float = 210.0
    var r := Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)
    draw_rect(Rect2(Vector2.ZERO, size), Color("#050810", 0.78))
    draw_rect(r, Color("#1a1724"))
    _flame_frame(r, true)
    draw_string(font, r.position + Vector2(20, 48), "СМЕНА ОБЛИКА", HORIZONTAL_ALIGNMENT_LEFT, w - 40, 23, Color("#ffcf83"))
    draw_string(font, r.position + Vector2(20, 89), "Вы уверены?", HORIZONTAL_ALIGNMENT_LEFT, w - 40, 20, Color.WHITE)
    var by: float = r.end.y - 65.0
    draw_rect(Rect2(r.position.x + 14, by, (w - 38) * 0.5, 45), Color("#444351"))
    draw_rect(Rect2(r.position.x + 24 + (w - 38) * 0.5, by, (w - 38) * 0.5, 45), Color("#8e4a20"))
    draw_string(font, Vector2(r.position.x + 27, by + 29), "ОТМЕНА", HORIZONTAL_ALIGNMENT_LEFT, (w - 38) * 0.5 - 16, 15, Color.WHITE)
    draw_string(font, Vector2(r.position.x + 37 + (w - 38) * 0.5, by + 29), "ПОДТВЕРДИТЬ", HORIZONTAL_ALIGNMENT_LEFT, (w - 38) * 0.5 - 16, 14, Color.WHITE)

func _confirmation_tap(point: Vector2) -> void:
    var w: float = minf(size.x - 24.0, 430.0)
    var h: float = 210.0
    var r := Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)
    var by: float = r.end.y - 65.0
    if point.y >= by and point.y <= by + 45.0 and point.x > size.x * 0.5:
        piece_skins[(customization_team - 1) * FOOTBALL_TEAM_SIZE + customization_slot] = pending_skin
        get_tree().root.set_meta("mb_football_skins", piece_skins.duplicate())
    pending_skin = -1
    queue_redraw()


# Touch/mouse drag: the board piece follows the pointer; release validates the move.
var drag_active: bool = false
var drag_input_touch: bool = false
var drag_moved: bool = false
var drag_pointer: Vector2 = Vector2.ZERO
var drag_origin: Vector2i = Vector2i(-1, -1)
var magic_clock: float = 0.0


# HALLOWEEN: lightweight hand-drawn arena; no new assets or scenes required.
# It stays behind the interactive board, so board coordinates are untouched.
func _halloween_pumpkin(center: Vector2, radius: float) -> void:
    draw_circle(center + Vector2(0.0, radius * 0.18), radius * 1.16, Color("#050713", 0.55))
    draw_circle(center, radius, Color("#c05a22"))
    draw_circle(center + Vector2(-radius * 0.15, -radius * 0.18), radius * 0.75, Color("#ed8730"))
    draw_rect(Rect2(center + Vector2(-radius * 0.10, -radius * 1.26), Vector2(radius * 0.22, radius * 0.38)), Color("#507b3d"))
    var ink := Color("#301321")
    draw_colored_polygon(PackedVector2Array([center + Vector2(-radius * 0.72,-radius * 0.10), center + Vector2(-radius * 0.38,-radius * 0.46), center + Vector2(-radius * 0.20,-radius * 0.04)]), ink)
    draw_colored_polygon(PackedVector2Array([center + Vector2(radius * 0.23,-radius * 0.06), center + Vector2(radius * 0.46,-radius * 0.49), center + Vector2(radius * 0.72,-radius * 0.08)]), ink)
    draw_line(center + Vector2(-radius * 0.58,radius * 0.27), center + Vector2(radius * 0.56,radius * 0.30), ink, maxf(1.5, radius * 0.18))
    draw_circle(center + Vector2(radius * 0.50,-radius * 0.68), radius * 0.21, Color("#ffbb50", 0.45))


# Halloween decorations are vector-drawn so the GitHub upload needs only two scripts.
func _halloween_ghost(center: Vector2, radius: float, seed: float) -> void:
    var wobble: float = sin(magic_clock * 1.5 + seed) * radius * 0.16
    var p: Vector2 = center + Vector2(0, wobble)
    var aura: Color = Color("#90e8e4", 0.13)
    draw_circle(p, radius * 1.55, aura)
    draw_circle(p + Vector2(0, -radius * 0.27), radius * 0.87, Color("#c7fff4", 0.87))
    draw_colored_polygon(PackedVector2Array([
        p + Vector2(-radius * 0.88, -radius * 0.20),
        p + Vector2(radius * 0.87, -radius * 0.20),
        p + Vector2(radius * 0.95, radius * 0.75),
        p + Vector2(radius * 0.48, radius * 0.44),
        p + Vector2(0, radius * 0.91),
        p + Vector2(-radius * 0.50, radius * 0.47),
        p + Vector2(-radius * 0.95, radius * 0.75)
    ]), Color("#bff6e9", 0.82))
    draw_circle(p + Vector2(-radius * 0.30, -radius * 0.25), maxf(1.2, radius * 0.13), Color("#12243a"))
    draw_circle(p + Vector2(radius * 0.30, -radius * 0.25), maxf(1.2, radius * 0.13), Color("#12243a"))

func _halloween_grave(center: Vector2, scale: float) -> void:
    var w: float = 14.0 * scale
    var h: float = 17.0 * scale
    var r := Rect2(center - Vector2(w * 0.5, h), Vector2(w, h))
    draw_rect(Rect2(r.position + Vector2(1, 3), r.size), Color("#080b16", 0.75))
    draw_rect(r, Color("#586273"))
    draw_circle(Vector2(center.x, r.position.y), w * 0.5, Color("#7d8090"))
    draw_line(Vector2(center.x, r.position.y - w * 0.27), Vector2(center.x, r.position.y + w * 0.28), Color("#232b3c"), 2.0)
    draw_line(Vector2(center.x - w * 0.23, r.position.y), Vector2(center.x + w * 0.23, r.position.y), Color("#232b3c"), 2.0)

func _halloween_spectator_shadow(center: Vector2, scale: float) -> void:
    draw_colored_polygon(PackedVector2Array([
        center + Vector2(-18.0 * scale, 0),
        center + Vector2(-10.0 * scale, 5.0 * scale),
        center + Vector2(10.0 * scale, 5.0 * scale),
        center + Vector2(18.0 * scale, 0),
        center + Vector2(10.0 * scale, -4.0 * scale),
        center + Vector2(-10.0 * scale, -4.0 * scale)
    ]), Color("#04050b", 0.40))

func _halloween_zombie(center: Vector2, scale: float, seed: float) -> void:
    var bob: float = sin(magic_clock * 1.7 + seed) * 2.2 * scale
    var p: Vector2 = center + Vector2(0, bob)
    _halloween_spectator_shadow(p + Vector2(0, 22.0 * scale), scale)
    draw_rect(Rect2(p + Vector2(-10.0 * scale, -5.0 * scale), Vector2(20.0 * scale, 25.0 * scale)), Color("#3f4761"))
    draw_colored_polygon(PackedVector2Array([
        p + Vector2(-11.0 * scale, 2.0 * scale),
        p + Vector2(-3.0 * scale, -8.0 * scale),
        p + Vector2(2.0 * scale, 1.0 * scale),
        p + Vector2(10.0 * scale, -8.0 * scale),
        p + Vector2(13.0 * scale, 1.0 * scale),
        p + Vector2(10.0 * scale, 22.0 * scale),
        p + Vector2(-10.0 * scale, 22.0 * scale)
    ]), Color("#5b6b7d"))
    draw_line(p + Vector2(-8.0 * scale, 4.0 * scale), p + Vector2(-18.0 * scale, 12.0 * scale), Color("#79b16d"), 4.0 * scale)
    draw_line(p + Vector2(8.0 * scale, 4.0 * scale), p + Vector2(18.0 * scale, 10.0 * scale), Color("#79b16d"), 4.0 * scale)
    draw_line(p + Vector2(-4.0 * scale, 21.0 * scale), p + Vector2(-7.0 * scale, 32.0 * scale), Color("#4e5e69"), 4.0 * scale)
    draw_line(p + Vector2(4.0 * scale, 21.0 * scale), p + Vector2(8.0 * scale, 31.0 * scale), Color("#4e5e69"), 4.0 * scale)
    draw_circle(p + Vector2(0, -17.0 * scale), 9.0 * scale, Color("#7fb573"))
    draw_circle(p + Vector2(-3.2 * scale, -18.0 * scale), 1.7 * scale, Color("#081109"))
    draw_circle(p + Vector2(3.0 * scale, -18.0 * scale), 1.7 * scale, Color("#081109"))
    draw_line(p + Vector2(-4.0 * scale, -12.0 * scale), p + Vector2(4.0 * scale, -11.0 * scale), Color("#40242b"), 2.0 * scale)

func _halloween_witch(center: Vector2, scale: float, seed: float) -> void:
    var bob: float = sin(magic_clock * 1.35 + seed) * 2.5 * scale
    var p: Vector2 = center + Vector2(0, bob)
    _halloween_spectator_shadow(p + Vector2(0, 23.0 * scale), scale)
    draw_colored_polygon(PackedVector2Array([
        p + Vector2(-13.0 * scale, 20.0 * scale),
        p + Vector2(13.0 * scale, 20.0 * scale),
        p + Vector2(8.0 * scale, -2.0 * scale),
        p + Vector2(0, -8.0 * scale),
        p + Vector2(-8.0 * scale, -2.0 * scale)
    ]), Color("#332249"))
    draw_rect(Rect2(p + Vector2(-3.0 * scale, -2.0 * scale), Vector2(6.0 * scale, 26.0 * scale)), Color("#5a2e67"))
    draw_circle(p + Vector2(0, -15.0 * scale), 8.0 * scale, Color("#d2c2b5"))
    draw_colored_polygon(PackedVector2Array([
        p + Vector2(-14.0 * scale, -18.0 * scale),
        p + Vector2(14.0 * scale, -18.0 * scale),
        p + Vector2(0, -22.0 * scale)
    ]), Color("#171121"))
    draw_colored_polygon(PackedVector2Array([
        p + Vector2(-2.0 * scale, -39.0 * scale),
        p + Vector2(10.0 * scale, -18.0 * scale),
        p + Vector2(-6.0 * scale, -18.0 * scale)
    ]), Color("#171121"))
    draw_line(p + Vector2(-14.0 * scale, 2.0 * scale), p + Vector2(-24.0 * scale, 12.0 * scale), Color("#d99143"), 2.0 * scale)
    draw_line(p + Vector2(-24.0 * scale, 12.0 * scale), p + Vector2(-20.0 * scale, 16.0 * scale), Color("#d99143"), 2.0 * scale)
    draw_circle(p + Vector2(-26.0 * scale, 13.0 * scale), 3.0 * scale, Color("#7af0ff", 0.55))

func _halloween_skeleton(center: Vector2, scale: float, seed: float) -> void:
    var bob: float = sin(magic_clock * 1.9 + seed) * 2.0 * scale
    var p: Vector2 = center + Vector2(0, bob)
    _halloween_spectator_shadow(p + Vector2(0, 23.0 * scale), scale)
    var bone := Color("#e8e4da")
    draw_circle(p + Vector2(0, -16.0 * scale), 8.0 * scale, bone)
    draw_circle(p + Vector2(-2.6 * scale, -17.0 * scale), 1.5 * scale, Color("#111420"))
    draw_circle(p + Vector2(2.6 * scale, -17.0 * scale), 1.5 * scale, Color("#111420"))
    draw_line(p + Vector2(0, -8.0 * scale), p + Vector2(0, 18.0 * scale), bone, 3.0 * scale)
    draw_line(p + Vector2(-9.0 * scale, -2.0 * scale), p + Vector2(9.0 * scale, -2.0 * scale), bone, 3.0 * scale)
    draw_line(p + Vector2(-8.0 * scale, -1.0 * scale), p + Vector2(-15.0 * scale, 11.0 * scale), bone, 2.0 * scale)
    draw_line(p + Vector2(8.0 * scale, -1.0 * scale), p + Vector2(15.0 * scale, 11.0 * scale), bone, 2.0 * scale)
    draw_line(p + Vector2(-1.0 * scale, 17.0 * scale), p + Vector2(-8.0 * scale, 31.0 * scale), bone, 2.0 * scale)
    draw_line(p + Vector2(1.0 * scale, 17.0 * scale), p + Vector2(8.0 * scale, 31.0 * scale), bone, 2.0 * scale)
    for r in 4:
        draw_line(p + Vector2(-4.0 * scale, float(r) * 4.0 * scale + 1.0 * scale), p + Vector2(4.0 * scale, float(r) * 4.0 * scale + 1.0 * scale), bone, 1.0 * scale)

func _halloween_vampire(center: Vector2, scale: float, seed: float) -> void:
    var bob: float = sin(magic_clock * 1.45 + seed) * 2.1 * scale
    var p: Vector2 = center + Vector2(0, bob)
    _halloween_spectator_shadow(p + Vector2(0, 23.0 * scale), scale)
    draw_colored_polygon(PackedVector2Array([
        p + Vector2(-16.0 * scale, 18.0 * scale),
        p + Vector2(-10.0 * scale, -6.0 * scale),
        p + Vector2(-1.0 * scale, 7.0 * scale),
        p + Vector2(0, 22.0 * scale),
        p + Vector2(1.0 * scale, 7.0 * scale),
        p + Vector2(10.0 * scale, -6.0 * scale),
        p + Vector2(16.0 * scale, 18.0 * scale),
        p + Vector2(8.0 * scale, 18.0 * scale),
        p + Vector2(4.0 * scale, 25.0 * scale),
        p + Vector2(-4.0 * scale, 25.0 * scale),
        p + Vector2(-8.0 * scale, 18.0 * scale)
    ]), Color("#5a1028"))
    draw_rect(Rect2(p + Vector2(-6.0 * scale, -2.0 * scale), Vector2(12.0 * scale, 20.0 * scale)), Color("#1e1c2c"))
    draw_circle(p + Vector2(0, -15.0 * scale), 8.0 * scale, Color("#eadccf"))
    draw_circle(p + Vector2(-2.5 * scale, -16.0 * scale), 1.5 * scale, Color("#2a0e17"))
    draw_circle(p + Vector2(2.5 * scale, -16.0 * scale), 1.5 * scale, Color("#2a0e17"))
    draw_line(p + Vector2(-4.0 * scale, -12.0 * scale), p + Vector2(4.0 * scale, -12.0 * scale), Color("#7a203f"), 1.5 * scale)
    draw_line(p + Vector2(-2.0 * scale, -11.0 * scale), p + Vector2(-1.0 * scale, -9.0 * scale), Color.WHITE, 1.0 * scale)
    draw_line(p + Vector2(2.0 * scale, -11.0 * scale), p + Vector2(1.0 * scale, -9.0 * scale), Color.WHITE, 1.0 * scale)

func _halloween_torch(center: Vector2, scale: float) -> void:
    draw_rect(Rect2(center + Vector2(-2.0 * scale, -2.0 * scale), Vector2(4.0 * scale, 18.0 * scale)), Color("#61422b"))
    draw_circle(center + Vector2(0, -7.0 * scale), 4.2 * scale, Color("#ff9e43", 0.45))
    draw_colored_polygon(PackedVector2Array([
        center + Vector2(0, -18.0 * scale),
        center + Vector2(5.0 * scale, -8.0 * scale),
        center + Vector2(0, -3.0 * scale),
        center + Vector2(-5.0 * scale, -8.0 * scale)
    ]), Color("#ffbb54", 0.9))
    draw_colored_polygon(PackedVector2Array([
        center + Vector2(0, -14.0 * scale),
        center + Vector2(3.0 * scale, -8.0 * scale),
        center + Vector2(0, -5.0 * scale),
        center + Vector2(-3.0 * scale, -8.0 * scale)
    ]), Color("#ff6f2f", 0.9))

func _draw_halloween_spectator(kind: int, center: Vector2, scale: float, seed: float) -> void:
    match kind:
        0:
            _halloween_zombie(center, scale, seed)
        1:
            _halloween_witch(center, scale, seed)
        2:
            _halloween_skeleton(center, scale, seed)
        3:
            _halloween_vampire(center, scale, seed)
        _:
            _halloween_ghost(center, 9.0 * scale, seed)


# Visible Halloween castle rising behind the raised arena, drawn without external sprites.
func _draw_halloween_castle(center: Vector2, scale: float) -> void:
    var p: Vector2 = center
    var castle_stone := Color("#28223b")
    var castle_light := Color("#4d4058")
    draw_colored_polygon(PackedVector2Array([
        p + Vector2(-100.0, 42.0) * scale,
        p + Vector2(-96.0, 11.0) * scale,
        p + Vector2(96.0, 11.0) * scale,
        p + Vector2(100.0, 42.0) * scale
    ]), Color("#0c0c1e", 0.8))
    draw_rect(Rect2(p + Vector2(-63, -20) * scale, Vector2(126, 62) * scale), castle_stone)
    draw_rect(Rect2(p + Vector2(-25, -50) * scale, Vector2(50, 92) * scale), Color("#322940"))
    for index in 4:
        var xx: float = -85.0 + float(index) * 56.0
        var tower_h: float = 74.0 if index == 0 or index == 3 else 105.0
        var origin: Vector2 = p + Vector2(xx, 42.0 - tower_h) * scale
        draw_rect(Rect2(origin, Vector2(29, tower_h) * scale), castle_stone)
        draw_rect(Rect2(origin + Vector2(3, 2) * scale, Vector2(4, tower_h - 4) * scale), castle_light)
        draw_colored_polygon(PackedVector2Array([
            origin + Vector2(-9, 4) * scale,
            origin + Vector2(14.5, -32) * scale,
            origin + Vector2(38, 4) * scale
        ]), Color("#151426"))
        draw_rect(Rect2(origin + Vector2(10, 18) * scale, Vector2(7, 17) * scale), Color("#ffba65", 0.88))
        draw_line(origin + Vector2(13.5,18) * scale, origin + Vector2(13.5,35) * scale, Color("#613845"), 2.0)
    for battlement in 11:
        draw_rect(Rect2(p + Vector2(-66 + battlement * 12.3, -25) * scale, Vector2(8, 9) * scale), castle_stone)
    draw_rect(Rect2(p + Vector2(-13, 13) * scale, Vector2(26, 29) * scale), Color("#0d1020"))
    draw_circle(p + Vector2(0, 15) * scale, 13.0 * scale, Color("#0d1020"))
    for x in [-45.0, -10.0, 29.0]:
        draw_rect(Rect2(p + Vector2(x, -7) * scale, Vector2(8, 16) * scale), Color("#ffc06c", 0.8))

func _halloween_arena(origin: Vector2, board_extent: Vector2) -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#100d1d"))
    var board_end: float = origin.y + board_extent.y
    var sky_base: float = maxf(125.0, origin.y - 12.0)
    draw_rect(Rect2(Vector2(0, 88), Vector2(size.x, maxf(12.0, sky_base - 88.0))), Color("#251632"))
    var moon: Vector2 = Vector2(size.x * 0.78, maxf(111.0, origin.y - 88.0))
    draw_circle(moon, 46.0, Color("#ffe6b2", 0.08))
    draw_circle(moon, 31.0, Color("#f9dbb3", 0.20))
    draw_circle(moon, 23.0, Color("#ffe6bd", 0.95))
    draw_circle(moon + Vector2(5, -4), 6.0, Color("#e0c9a1", 0.18))
    # Gothic village and castle towers in the distance.
    for i in 13:
        var x: float = float(i) * size.x / 12.0 - 10.0
        var h: float = 17.0 + float((i * 19) % 33)
        var width: float = 18.0 + float(i % 3) * 4.0
        var peak: float = sky_base - h
        draw_rect(Rect2(x, peak, width, h + 14.0), Color("#10101f"))
        draw_colored_polygon(PackedVector2Array([Vector2(x - 3, peak), Vector2(x + width * 0.5, peak - 15), Vector2(x + width + 3, peak)]), Color("#10101f"))
        if i % 3 != 1:
            draw_rect(Rect2(x + width * 0.42, peak + 9, 3, 7), Color("#ffa456", 0.84))
    _draw_halloween_castle(Vector2(size.x * 0.49, sky_base - 16.0), minf(1.0, size.x / 465.0))
    # Silhouetted flying bats.
    for i in 6:
        var x: float = 19.0 + float(i) * (size.x - 43.0) / 5.0
        var y: float = maxf(106.0, origin.y - 89.0) - float((i * 11) % 23)
        var wing: float = 5.0 + float(i % 3)
        draw_line(Vector2(x - wing, y - 3), Vector2(x, y + 1), Color("#050611"), 2.2)
        draw_line(Vector2(x, y + 1), Vector2(x + wing, y - 3), Color("#050611"), 2.2)
    # Far arena floor and stands.
    var arena_floor_y: float = board_end + 22.0
    draw_rect(Rect2(0, arena_floor_y, size.x, size.y - arena_floor_y), Color("#120f1d"))
    var upper: float = origin.y - 56.0
    if upper >= 152.0:
        var upper_rect := Rect2(10.0, upper - 32.0, size.x - 20.0, 58.0)
        draw_rect(upper_rect, Color("#181729", 0.92))
        draw_rect(Rect2(upper_rect.position.x, upper_rect.end.y - 12.0, upper_rect.size.x, 10.0), Color("#2b2233"))
        draw_line(Vector2(upper_rect.position.x + 4.0, upper_rect.end.y - 3.0), Vector2(upper_rect.end.x - 4.0, upper_rect.end.y - 3.0), Color("#bd7240"), 3.0)
        for i in 9:
            var x: float = upper_rect.position.x + 18.0 + float(i) * (upper_rect.size.x - 36.0) / 8.0
            var kind: int = i % 5
            _draw_halloween_spectator(kind, Vector2(x, upper_rect.position.y + 27.0 + float(i % 2) * 3.0), 0.85 + float(i % 3) * 0.08, float(i) * 0.7)
        _halloween_torch(Vector2(24.0, upper_rect.end.y - 2.0), 0.95)
        _halloween_torch(Vector2(size.x - 24.0, upper_rect.end.y - 2.0), 0.95)
    var lower: float = board_end + 48.0
    if lower + 36.0 < size.y - 72.0:
        var lower_rect := Rect2(9.0, lower - 28.0, size.x - 18.0, 66.0)
        draw_rect(lower_rect, Color("#1d1827", 0.96))
        draw_rect(Rect2(lower_rect.position.x, lower_rect.position.y, lower_rect.size.x, 11.0), Color("#2d2437"))
        draw_line(Vector2(lower_rect.position.x + 3.0, lower_rect.position.y + 10.0), Vector2(lower_rect.end.x - 3.0, lower_rect.position.y + 10.0), Color("#ad6b4b"), 3.0)
        for i in 8:
            var x: float = lower_rect.position.x + 18.0 + float(i) * (lower_rect.size.x - 36.0) / 7.0
            var kind: int = (i + 2) % 5
            if i == 0 or i == 7:
                _halloween_pumpkin(Vector2(x, lower_rect.end.y - 9.0), 13.0)
            elif i % 4 == 0:
                _halloween_grave(Vector2(x, lower_rect.end.y - 4.0), 1.10)
            else:
                _draw_halloween_spectator(kind, Vector2(x, lower_rect.position.y + 30.0), 0.88 + float(i % 2) * 0.12, float(i) * 0.9 + 11.0)
    # Thick raised stone platform, with visible front and side bevels (pseudo-3D).
    var depth: float = minf(22.0, maxf(10.0, board_extent.x * 0.052))
    var side_depth: float = maxf(8.0, depth * 0.78)
    var back := Rect2(origin - Vector2(10, 10), board_extent + Vector2(20, 20))
    draw_colored_polygon(PackedVector2Array([
        back.position + Vector2(18.0, back.size.y + depth + 10.0),
        back.position + Vector2(back.size.x + 18.0, back.size.y + depth + 10.0),
        back.position + Vector2(back.size.x - 16.0, back.size.y + 2.0),
        back.position + Vector2(16.0, back.size.y + 2.0)
    ]), Color("#03040a", 0.42))
    draw_colored_polygon(PackedVector2Array([
        Vector2(back.position.x, back.end.y),
        Vector2(back.end.x, back.end.y),
        Vector2(back.end.x - side_depth, back.end.y + depth),
        Vector2(back.position.x + side_depth, back.end.y + depth)
    ]), Color("#6b473f"))
    draw_colored_polygon(PackedVector2Array([
        Vector2(back.end.x, back.position.y),
        Vector2(back.end.x, back.end.y),
        Vector2(back.end.x - side_depth, back.end.y + depth),
        Vector2(back.end.x - side_depth, back.position.y + depth)
    ]), Color("#3f2d37"))
    draw_rect(back.grow(4.0), Color("#06060f"))
    draw_rect(back, Color("#24172e"))
    draw_rect(back, Color("#dd9c57"), false, 4.0)
    draw_line(Vector2(back.position.x + side_depth, back.end.y + depth), Vector2(back.end.x - side_depth, back.end.y + depth), Color("#f5a650"), 2.0)
    draw_line(Vector2(back.end.x - side_depth, back.position.y + depth), Vector2(back.end.x - side_depth, back.end.y + depth), Color("#91606f"), 2.0)
    # Side spectators in vertical mini-stands.
    var side_top: float = origin.y + 18.0
    var side_bottom: float = origin.y + board_extent.y - 20.0
    for side_id in 2:
        var left_side: bool = side_id == 0
        var stand_x: float = origin.x - 49.0 if left_side else origin.x + board_extent.x + 13.0
        var stand_rect := Rect2(stand_x, origin.y + 8.0, 36.0, board_extent.y - 16.0)
        draw_rect(stand_rect, Color("#171521", 0.90))
        draw_line(Vector2(stand_rect.position.x + 4.0, stand_rect.position.y + 6.0), Vector2(stand_rect.position.x + 4.0, stand_rect.end.y - 6.0), Color("#8f5c41"), 2.0)
        draw_line(Vector2(stand_rect.end.x - 4.0, stand_rect.position.y + 6.0), Vector2(stand_rect.end.x - 4.0, stand_rect.end.y - 6.0), Color("#8f5c41"), 2.0)
        for j in 5:
            var yy: float = side_top + float(j) * (side_bottom - side_top) / 4.0
            var kind: int = (j + side_id) % 5
            var cx: float = stand_rect.position.x + stand_rect.size.x * 0.5
            _draw_halloween_spectator(kind, Vector2(cx, yy), 0.68, float(j) + float(side_id) * 2.2)
        _halloween_torch(Vector2(stand_rect.position.x + stand_rect.size.x * 0.5, stand_rect.position.y + 10.0), 0.70)
        _halloween_torch(Vector2(stand_rect.position.x + stand_rect.size.x * 0.5, stand_rect.end.y - 2.0), 0.70)


# Bat-shaped sparkles, confetti, tumbling discs and fanfare during celebrations.
func _draw_halloween_party(progress: float, team_id: int, final_win: bool) -> void:
    var elapsed: float = clampf(progress, 0.0, 1.0)
    var winner_color: Color = Color("#4ac5e8") if team_id == 1 else Color("#f36f7e")
    draw_rect(Rect2(Vector2.ZERO, size), Color("#090b17", 0.14 + 0.12 * sin(elapsed * PI)))
    for index in 95:
        var fall_speed: float = 0.73 + float(index % 6) * 0.18
        var x: float = 6.0 + fposmod(float(index * 67) + 10.0 * sin(elapsed * 13.0 + index), maxf(1.0, size.x - 12.0))
        var y: float = fposmod(float(index * 107) + elapsed * size.y * fall_speed, size.y + 130.0) - 65.0
        var spin: float = elapsed * 14.0 + float(index) * 0.82
        var dx: Vector2 = Vector2(cos(spin), sin(spin)) * (2.5 + float(index % 3))
        var dy: Vector2 = Vector2(-sin(spin), cos(spin)) * (4.5 + float(index % 4))
        var color: Color = Color("#ffac4e") if index % 4 == 0 else (winner_color if index % 4 == 1 else (Color("#aaf2b4") if index % 4 == 2 else Color("#f7e5d2")))
        draw_colored_polygon(PackedVector2Array([
            Vector2(x,y) - dx - dy, Vector2(x,y) + dx - dy,
            Vector2(x,y) + dx + dy, Vector2(x,y) - dx + dy
        ]), color)
    var pulse: float = 1.0 + 0.15 * sin(elapsed * 19.0)
    for index in 6:
        var center: Vector2 = Vector2(size.x * (0.13 + 0.15 * float(index)), size.y * (0.25 if index % 2 == 0 else 0.68))
        var radius: float = (16.0 + float(index % 3) * 6.0) * pulse
        draw_arc(center, radius, elapsed * 1.5, elapsed * 1.5 + TAU * 0.92, 24, Color("#ffa646", 0.75), 3.0)
    var banner_y: float = size.y * 0.44
    draw_rect(Rect2(12.0, banner_y - 51.0, size.x - 24.0, 119.0), Color("#130e25", 0.94))
    draw_rect(Rect2(12.0, banner_y - 51.0, size.x - 24.0, 119.0), Color("#efaa5b"), false, 3.0)
    var font: Font = ThemeDB.fallback_font
    draw_string(font, Vector2(20, banner_y + 3.0), "ПОБЕДА!" if final_win else "ГООООЛ!", HORIZONTAL_ALIGNMENT_CENTER, size.x - 40.0, 38, Color("#ffcf76"))
    draw_string(font, Vector2(20, banner_y + 39.0), "СИНИЕ ПРАЗДНУЮТ!" if team_id == 1 else "КРАСНЫЕ ПРАЗДНУЮТ!", HORIZONTAL_ALIGNMENT_CENTER, size.x - 40.0, 18, winner_color)

func _magic_ring(center: Vector2, radius: float, hue: Color, strong: bool = false) -> void:
    var wave: float = 0.5 + 0.5 * sin(magic_clock * 5.0)
    draw_circle(center, radius * 1.17, Color(hue.r, hue.g, hue.b, 0.05 + wave * 0.07))
    draw_arc(center, radius, 0.0, TAU, 56, Color(hue.r, hue.g, hue.b, 0.75), 2.8 if strong else 2.0)
    draw_arc(center, radius * 1.10, magic_clock, magic_clock + PI * 1.35, 35, Color(hue.r, hue.g, hue.b, 0.7), 2.2)
    for j in 6:
        var angle: float = float(j) * TAU / 6.0 + magic_clock * 0.7
        var dot: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius * 1.10
        draw_circle(dot, 2.4 if strong else 1.7, hue)

func _drag_event(event: InputEvent) -> bool:
    var point: Vector2 = Vector2.ZERO
    var pressed: bool = false
    var released: bool = false
    var moving: bool = false
    if event is InputEventScreenTouch:
        if event.index != 0: return true
        point = event.position
        pressed = event.pressed
        released = not event.pressed
    elif event is InputEventScreenDrag:
        if event.index != 0: return true
        point = event.position
        moving = true
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if drag_active and drag_input_touch: return true
        point = event.position
        pressed = event.pressed
        released = not event.pressed
    elif event is InputEventMouseMotion and drag_active and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
        if drag_input_touch: return true
        point = event.position
        moving = true
    else:
        return false
    if moving:
        if drag_active:
            drag_pointer = point
            if drag_pointer.distance_to(_drag_cell_center(drag_origin)) > 8.0:
                drag_moved = true
            queue_redraw()
        return true
    if released:
        if drag_active:
            drag_active = false
            drag_input_touch = false
            var old: Vector2i = drag_origin
            drag_origin = Vector2i(-1, -1)
            if drag_moved:
                var target: Vector2i = _drag_point_to_cell(point)
                if _valid_drop(target) and target != old:
                    var carried_piece: int = selected
                    _tap(target)
                    # Drop/impact only; do not animate a second trip from the source.
                    if carried_piece >= 0 and fx_piece == carried_piece and fx_to == target and fx_progress < 1.0:
                        if pieces[carried_piece]["alive"] and pieces[carried_piece]["cell"] == target:
                            fx_from = target
                            fx_duration = 0.20
                            fx_progress = 0.0
                else:
                    fx_bounce_from = _drag_cell_center(old)
                    fx_bounce_start = point
                    fx_bounce_piece = selected
                    fx_bounce_time = 0.22
            drag_moved = false
            queue_redraw()
        return true
    if pressed and _drag_can_start(point):
        var cell: Vector2i = _drag_point_to_cell(point)
        if _drag_cell_valid(cell) and _drag_is_own_piece(cell):
            drag_active = true
            drag_input_touch = event is InputEventScreenTouch
            drag_moved = false
            drag_origin = cell
            drag_pointer = point
            _tap(cell)
            queue_redraw()
            return true
    return false

func _valid_drop(cell: Vector2i) -> bool:
    if selected < 0 or not _inside(cell):
        return false
    var target_player: int = _piece_at(cell)
    # The ball can be dragged onto an adjacent diagonal teammate to pass.
    if target_player >= 0:
        return _can_pass(selected, target_player) and not _team_must_capture(turn)
    for capture in _captures(selected):
        if capture["cell"] == cell:
            return true
    if _team_must_capture(turn):
        return false
    var source: Vector2i = pieces[selected]["cell"]
    var dr: int = cell.x - source.x
    var dc: int = absi(cell.y - source.y)
    return absi(dr) == 1 and dc == 1 and (ball_holder != selected or dr == (-1 if turn == 1 else 1))

func _drag_point_to_cell(point: Vector2) -> Vector2i:
    var g: Dictionary = _geometry()
    var side: float = g["cell_size"]
    var origin: Vector2 = g["offset"]
    return Vector2i(int(floor((point.y - origin.y) / side)), int(floor((point.x - origin.x) / side)))

func _drag_cell_center(cell: Vector2i) -> Vector2:
    var g: Dictionary = _geometry()
    var side: float = g["cell_size"]
    var origin: Vector2 = g["offset"]
    return origin + Vector2(cell.y + 0.5, cell.x + 0.5) * side

func _drag_cell_valid(cell: Vector2i) -> bool:
    return _inside(cell)

func _drag_is_own_piece(cell: Vector2i) -> bool:
    var i: int = _piece_at(cell)
    return i >= 0 and int(pieces[i]["team"]) == turn

func _drag_can_start(point: Vector2) -> bool:
    return not celebrating and not customization_open and pending_skin < 0 and not game_over and not bot_pending and (game_mode != 0 or turn == 1)

func _draw_drag_piece_overlay(side: float) -> void:
    if not drag_active or not drag_moved or selected < 0 or selected >= pieces.size():
        return
    if not bool(pieces[selected]["alive"]):
        return
    var center: Vector2 = drag_pointer
    draw_circle(center + Vector2(0, side * 0.17), side * 0.43, Color("#05040d", 0.60))
    draw_arc(center, side * 0.46, 0, TAU, 40, Color("#ffa74e", 0.83), 2.6)
    var team: int = int(pieces[selected]["team"])
    var key: String = BLUE_SKINS[piece_skins[selected]] if team == 1 else RED_SKINS[piece_skins[selected]]
    var token_side: float = side * 0.93
    if not _draw_asset(key, Rect2(center - Vector2.ONE * token_side * 0.5, Vector2.ONE * token_side)):
        _draw_fantasy_token(center, side * 0.37, team, selected)
    if ball_holder == selected:
        var pumpkin_center: Vector2 = center + Vector2(side * 0.17, -side * 0.20)
        var pumpkin_size: float = side * 0.50
        if not _draw_asset("ghost_pumpkin", Rect2(pumpkin_center - Vector2.ONE * pumpkin_size * 0.5, Vector2.ONE * pumpkin_size)):
            _draw_ghost_pumpkin(pumpkin_center, side * 0.16)

func _draw_drag_hints() -> void:
    if selected < 0 or selected >= pieces.size(): return
    if not pieces[selected]["alive"]: return
    var g: Dictionary = _geometry()
    var side: float = g["cell_size"]
    var origin: Vector2 = g["offset"]
    var origin_cell: Vector2i = pieces[selected]["cell"]
    var mandatory: bool = _team_must_capture(turn)
    for capture in _captures(selected):
        var target: Vector2i = capture["cell"]
        _magic_ring(origin + Vector2(target.y + 0.5, target.x + 0.5) * side, side * 0.28, Color("#ff6835"))
    if mandatory: return
    if ball_holder == selected:
        for teammate in pieces.size():
            if _can_pass(selected, teammate):
                var receiver_cell: Vector2i = pieces[teammate]["cell"]
                _magic_ring(origin + Vector2(receiver_cell.y + 0.5, receiver_cell.x + 0.5) * side, side * 0.39, Color("#ffca62"), true)
    for direction in [Vector2i(-1,-1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(1,1)]:
        var target: Vector2i = origin_cell + direction
        var forward: int = -1 if turn == 1 else 1
        if _inside(target) and _piece_at(target) < 0 and (ball_holder != selected or direction.x == forward):
            _magic_ring(origin + Vector2(target.y + 0.5, target.x + 0.5) * side, side * 0.28, Color("#71f9b0"))


# Visual-only animations; the board rules update immediately.
var fx_piece: int = -1
var fx_from: Vector2i = Vector2i(-1, -1)
var fx_to: Vector2i = Vector2i(-1, -1)
var fx_progress: float = 1.0
var fx_duration: float = 0.60
var fx_impact: Vector2i = Vector2i(-1, -1)
var fx_impact_time: float = 0.0
var fx_bounce_from: Vector2 = Vector2.ZERO
var fx_bounce_start: Vector2 = Vector2.ZERO
var fx_bounce_piece: int = -1
var fx_bounce_time: float = 0.0
var pass_fx_from: Vector2i = Vector2i(-1, -1)
var pass_fx_to: Vector2i = Vector2i(-1, -1)
var pass_fx_progress: float = 1.0

func _start_move_fx(index: int, origin: Vector2i, destination: Vector2i) -> void:
    _play_sfx("stone_move")
    fx_piece = index
    fx_from = origin
    fx_to = destination
    fx_progress = 0.0
    fx_duration = 0.60

func _start_hit_fx(cell: Vector2i) -> void:
    _play_sfx("capture")
    fx_impact = cell
    fx_impact_time = 0.55

func _draw_game_fx() -> void:
    var g: Dictionary = _geometry()
    var side: float = g["cell_size"]
    if pass_fx_progress < 1.0 and _inside(pass_fx_from) and _inside(pass_fx_to):
        var start: Vector2 = _drag_cell_center(pass_fx_from)
        var finish: Vector2 = _drag_cell_center(pass_fx_to)
        var t: float = pass_fx_progress
        var center: Vector2 = start.lerp(finish, t) + Vector2(0.0, -sin(t * PI) * side * 0.25)
        draw_line(start, finish, Color("#ffb958", 0.47 * (1.0 - t)), 3.0)
        draw_circle(center, side * 0.23, Color("#ff9c30", 0.3))
        if not _draw_asset("ghost_pumpkin", Rect2(center - Vector2.ONE * side * 0.24, Vector2.ONE * side * 0.48)):
            _draw_ghost_pumpkin(center, side * 0.17)
    if fx_impact_time > 0.0 and _inside(fx_impact):
        var center: Vector2 = _drag_cell_center(fx_impact)
        var t: float = 1.0 - fx_impact_time / 0.55
        draw_arc(center, side * (0.14 + t * 0.45), 0.0, TAU, 42, Color(1.0, 0.45, 0.13, 1.0-t), 3.0)
        for j in 8:
            var a: float = TAU * float(j) / 8.0 + t * 0.5
            var d: Vector2 = Vector2(cos(a), sin(a))
            draw_line(center + d * side * t * 0.20, center + d * side * (0.18 + t * 0.42), Color(1.0, 0.75, 0.25, 1.0-t), 2.5)
    if fx_bounce_time > 0.0:
        var t: float = 1.0 - fx_bounce_time / 0.22
        var c: Vector2 = fx_bounce_start.lerp(fx_bounce_from, t)
        if fx_bounce_piece >= 0 and fx_bounce_piece < pieces.size():
            var team_id: int = int(pieces[fx_bounce_piece]["team"])
            var key: String = BLUE_SKINS[piece_skins[fx_bounce_piece]] if team_id == 1 else RED_SKINS[piece_skins[fx_bounce_piece]]
            _draw_asset(key, Rect2(c - Vector2.ONE * side * 0.44, Vector2.ONE * side * 0.88))
        draw_arc(c, side * (0.25 + 0.22 * t), 0.0, TAU, 36, Color(0.45, 0.95, 1.0, 0.65 * (1.0-t)), 2.5)

func _living(team_id: int) -> int:
    var n: int = 0
    for p in pieces:
        if bool(p["alive"]) and int(p["team"]) == team_id:
            n += 1
    return n

func _award_point(team_id: int, reason: String) -> void:
    if celebrating or game_over:
        return
    scores[team_id - 1] += 1
    celebrating = true
    celebration_team = team_id
    celebration_reason = reason
    celebration_final = scores[team_id - 1] >= 3
    celebration_duration = 4.2 if celebration_final else 3.2
    celebration_time = celebration_duration
    selected = -1
    bot_pending = false
    message = "%s  %d : %d" % [reason, scores[0], scores[1]]
    if celebration_final:
        winner = team_id
        game_over = true
    _play_sfx("goal")
    _play_sfx("crowd", "crowd")
    if celebration_final:
        _play_sfx("victory")
    queue_redraw()

func _check_elimination() -> bool:
    if _living(1) == 0:
        _award_point(2, "ВСЕ СИНИЕ ФИШКИ СЪЕДЕНЫ!")
        return true
    if _living(2) == 0:
        _award_point(1, "ВСЕ КРАСНЫЕ ФИШКИ СЪЕДЕНЫ!")
        return true
    return false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    _setup_game_audio()
    if ResourceLoader.exists("res://assets/game_font.ttf"):
        fancy_font = load("res://assets/game_font.ttf")
    _load_fantasy_assets()
    _reset_board()
    game_mode = int(get_tree().root.get_meta("mb_mode", 0))
    bot_difficulty = clampi(int(get_tree().root.get_meta("mb_bot_difficulty", 1)), 0, 2)
    customization_open = bool(get_tree().root.get_meta("mb_customize", false))
    if get_tree().root.has_meta("mb_football_skins"):
        var saved: Array = get_tree().root.get_meta("mb_football_skins")
        # Keep the original four outfits for each side when upgrading from 4v4.
        # Old saved order: blue 0..3, red 4..7. New order: blue 0..4, red 5..9.
        if saved.size() == 8:
            for slot in 4:
                piece_skins[slot] = clampi(int(saved[slot]), 0, 3)
                piece_skins[FOOTBALL_TEAM_SIZE + slot] = clampi(int(saved[4 + slot]), 0, 3)
        else:
            for j in mini(saved.size(), piece_skins.size()):
                piece_skins[j] = clampi(int(saved[j]), 0, 3)

func _reset_board() -> void:
    celebrating = false
    celebration_time = 0.0
    pieces.clear()
    fx_progress = 1.0
    fx_impact_time = 0.0
    pass_fx_progress = 1.0
    # Football: five players per side; second-line players mirror each other.
    # All starting cells are distinct playable diagonal-board cells.
    for cell in [Vector2i(9, 1), Vector2i(9, 3), Vector2i(9, 5), Vector2i(9, 7), Vector2i(8, 4)]:
        pieces.append({"team": 1, "cell": cell, "alive": true})
    for cell in [Vector2i(0, 0), Vector2i(0, 2), Vector2i(0, 4), Vector2i(0, 6), Vector2i(1, 3)]:
        pieces.append({"team": 2, "cell": cell, "alive": true})
    ball_cell = Vector2i(4, 4)
    ball_holder = -1
    selected = -1
    turn = 1
    game_over = false
    winner = 0
    bot_pending = false
    message = "Ход голубых"
    queue_redraw()

func _geometry() -> Dictionary:
    var top_margin := 154.0
    var bottom_margin := 85.0
    var side_margin := 29.0
    var usable := Vector2(max(1.0, size.x - 2.0 * side_margin), max(1.0, size.y - top_margin - bottom_margin))
    var cell_size: float = floor(min(usable.x / COLS, usable.y / ROWS))
    var offset := Vector2(floor((size.x - COLS * cell_size) / 2.0), floor(top_margin + (usable.y - ROWS * cell_size) / 2.0))
    return {"cell_size": cell_size, "offset": offset}

func _piece_at(cell: Vector2i) -> int:
    for i in pieces.size():
        if pieces[i]["alive"] and pieces[i]["cell"] == cell:
            return i
    return -1

func _captures(i: int) -> Array:
    var result: Array = []
    if not pieces[i]["alive"]:
        return result
    var p: Dictionary = pieces[i]
    for direction in [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]:
        var middle: Vector2i = p["cell"] + direction
        var landing: Vector2i = p["cell"] + direction * 2
        if not _inside(landing):
            continue
        var victim := _piece_at(middle)
        if victim >= 0 and pieces[victim]["team"] != p["team"] and _piece_at(landing) == -1:
            result.append({"cell": landing, "victim": victim})
    return result

func _team_must_capture(team: int) -> bool:
    for i in pieces.size():
        if pieces[i]["alive"] and pieces[i]["team"] == team and not _captures(i).is_empty():
            return true
    return false

func _inside(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.x < ROWS and cell.y >= 0 and cell.y < COLS

# A football pass is exactly one cell diagonally in any direction.
# Normal piece movement rules remain unchanged.
func _can_pass(from_index: int, to_index: int) -> bool:
    if from_index < 0 or to_index < 0 or from_index >= pieces.size() or to_index >= pieces.size():
        return false
    if from_index == to_index or ball_holder != from_index:
        return false
    if not bool(pieces[from_index]["alive"]) or not bool(pieces[to_index]["alive"]):
        return false
    if int(pieces[from_index]["team"]) != turn or int(pieces[to_index]["team"]) != turn:
        return false
    var from_cell: Vector2i = pieces[from_index]["cell"]
    var to_cell: Vector2i = pieces[to_index]["cell"]
    return absi(to_cell.x - from_cell.x) == 1 and absi(to_cell.y - from_cell.y) == 1

func _pass_ball(to_index: int) -> void:
    if not _can_pass(ball_holder, to_index):
        return
    pass_fx_from = pieces[ball_holder]["cell"]
    pass_fx_to = pieces[to_index]["cell"]
    pass_fx_progress = 0.0
    _play_sfx("pass")
    ball_holder = to_index
    ball_cell = pass_fx_to
    var score_before: Array = scores.duplicate()
    _finish_turn()
    # Keep the goal message if the other team's lone carrier gets stuck.
    if not game_over and scores == score_before:
        message = "ПАС! " + ("Ход голубых" if turn == 1 else "Ход красных")
    queue_redraw()

func _carrier_has_move(index: int) -> bool:
    if index < 0 or index >= pieces.size() or not bool(pieces[index]["alive"]):
        return false
    if not _captures(index).is_empty():
        return true
    var forward: int = -1 if int(pieces[index]["team"]) == 1 else 1
    var from_cell: Vector2i = pieces[index]["cell"]
    for dc in [-1, 1]:
        var target: Vector2i = from_cell + Vector2i(forward, dc)
        if _inside(target) and _piece_at(target) == -1:
            return true
    return false

func _check_last_carrier_stuck(team_id: int) -> bool:
    # Only the last surviving ball carrier can concede a goal this way.
    if _living(team_id) != 1 or ball_holder < 0 or game_over:
        return false
    if not bool(pieces[ball_holder]["alive"]) or int(pieces[ball_holder]["team"]) != team_id:
        return false
    if _carrier_has_move(ball_holder):
        return false
    _award_point(3 - team_id, "МЯЧ ЗАБЛОКИРОВАН — ГОЛ СОПЕРНИКА!")
    return true

func _gui_input(event: InputEvent) -> void:
    if _drag_event(event):
        accept_event()
        return
    var point := Vector2(-1, -1)
    if event is InputEventScreenTouch and event.pressed:
        point = event.position
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        point = event.position
    else:
        return
    accept_event()
    if celebrating:
        return
    if customization_open:
        if pending_skin >= 0:
            _confirmation_tap(point)
            return
        _customization_tap(point)
        return
    if point.y > size.y - 82.0:
        if point.x >= size.x * 0.5:
            _go_to_main_menu()
            return
        scores = [0, 0]
        _reset_board()
        return
    if game_over or bot_pending or (game_mode == 0 and turn == 2):
        return
    var geometry := _geometry()
    var origin: Vector2 = geometry["offset"]
    var side: float = geometry["cell_size"]
    var col := int(floor((point.x - origin.x) / side))
    var row := int(floor((point.y - origin.y) / side))
    var cell := Vector2i(row, col)
    if _inside(cell):
        _tap(cell)

func _customization_tap(point: Vector2) -> void:
    if point.y < 130.0 or point.y > size.y - 65.0:
        customization_open = false
    elif point.y < 180.0:
        customization_team = 1 if point.x < size.x * 0.5 else 2
        customization_slot = 0
    elif point.y < 245.0:
        customization_slot = clampi(int(point.x / maxf(1.0, size.x / float(FOOTBALL_TEAM_SIZE))), 0, FOOTBALL_TEAM_SIZE - 1)
    elif point.y >= 255.0 and point.y <= 265.0 + size.x / 4.0:
        var skin: int = clampi(int(point.x / maxf(1.0, size.x / 4.0)), 0, 3)
        pending_skin = skin
    queue_redraw()

func _tap(cell: Vector2i) -> void:
    var clicked := _piece_at(cell)
    # Passing must be checked BEFORE teammate selection; otherwise a tap on
    # a teammate simply switches the selected player and no pass occurs.
    if clicked >= 0 and selected >= 0 and _can_pass(selected, clicked):
        if _team_must_capture(turn):
            message = "Сначала обязательное съедение"
            queue_redraw()
        else:
            _pass_ball(clicked)
        return
    if clicked >= 0 and pieces[clicked]["team"] == turn:
        if _team_must_capture(turn) and _captures(clicked).is_empty():
            message = "Нужно съесть фишку соперника"
        else:
            selected = clicked
            message = "Пас: выбери союзника по диагонали" if ball_holder == clicked else "Выбери соседнюю диагональную клетку"
        queue_redraw()
        return
    if selected < 0:
        message = "Сначала нажми свою фишку"
        queue_redraw()
        return
    for capture in _captures(selected):
        if capture["cell"] == cell:
            pieces[capture["victim"]]["alive"] = false
            _start_hit_fx(pieces[capture["victim"]]["cell"])
            if ball_holder == capture["victim"]:
                ball_holder = selected
            _move_selected(cell)
            if _check_elimination():
                return
            if _check_goal():
                return
            if not _captures(selected).is_empty():
                message = "Продолжай съедение той же фишкой"
                queue_redraw()
            else:
                _finish_turn()
            return
    if _team_must_capture(turn):
        message = "Съедение обязательно"
        queue_redraw()
        return
    var from: Vector2i = pieces[selected]["cell"]
    var dr := cell.x - from.x
    var dc: int = absi(cell.y - from.y)
    var forward := -1 if turn == 1 else 1
    if abs(dr) == 1 and dc == 1 and clicked == -1 and (ball_holder != selected or dr == forward):
        _move_selected(cell)
        if not _check_goal():
            _finish_turn()
    else:
        message = "Ходить можно на одну клетку по диагонали"
        queue_redraw()

func _move_selected(cell: Vector2i) -> void:
    var previous: Vector2i = pieces[selected]["cell"]
    _start_move_fx(selected, previous, cell)
    pieces[selected]["cell"] = cell
    if ball_holder == selected:
        ball_cell = cell
    elif ball_holder == -1 and ball_cell == cell:
        ball_holder = selected
    queue_redraw()

func _check_goal() -> bool:
    if ball_holder != selected:
        return false
    var cell: Vector2i = pieces[selected]["cell"]
    var goal_row := 0 if turn == 1 else 9
    if cell.x == goal_row and cell.y >= 2 and cell.y <= 5:
        _award_point(turn, "ГОЛ!")
        return true
    return false

func _finish_turn() -> void:
    selected = -1
    turn = 2 if turn == 1 else 1
    message = "Ход голубых" if turn == 1 else "Ход красных"
    # Check as soon as the blocked team would receive the turn.
    if _check_last_carrier_stuck(turn):
        return
    queue_redraw()
    if game_mode == 0 and turn == 2 and not game_over:
        _schedule_bot()

func _schedule_bot() -> void:
    if bot_pending or game_over or turn != 2:
        return
    bot_pending = true
    _bot_turn.call_deferred()

func _football_bot_score(index: int, target: Vector2i, victim: int) -> int:
    var value: int = 0
    if ball_holder == index:
        value += target.x * 9
        if target.x == 9 and target.y >= 2 and target.y <= 5:
            value += 500
    elif ball_holder == -1:
        value -= (absi(target.x - ball_cell.x) + absi(target.y - ball_cell.y)) * 8
        if target == ball_cell:
            value += 170
    else:
        var holder: int = ball_holder
        if holder >= 0 and pieces[holder]["alive"]:
            var enemy: Vector2i = pieces[holder]["cell"]
            value -= (absi(target.x - enemy.x) + absi(target.y - enemy.y)) * 5
    if victim >= 0:
        value += 65
    for j in pieces.size():
        if not pieces[j]["alive"] or pieces[j]["team"] != 1 or j == victim:
            continue
        var enemy_cell: Vector2i = pieces[j]["cell"]
        if absi(enemy_cell.x - target.x) == 1 and absi(enemy_cell.y - target.y) == 1:
            var escape: Vector2i = target + (target - enemy_cell)
            if _inside(escape) and _piece_at(escape) == -1:
                value -= 55
    return value

func _bot_turn() -> void:
    if not is_inside_tree():
        return
    await get_tree().create_timer(0.77).timeout
    bot_pending = false
    if game_mode != 0 or turn != 2 or game_over:
        return
    var candidates: Array[Dictionary] = []
    var must_capture := _team_must_capture(2)
    for i in pieces.size():
        if not pieces[i]["alive"] or pieces[i]["team"] != 2:
            continue
        var from: Vector2i = pieces[i]["cell"]
        for capture in _captures(i):
            var weight: int = 100 if bot_difficulty > 0 else randi_range(0, 60)
            if bot_difficulty == 2:
                weight += _football_bot_score(i, capture["cell"], capture["victim"])
            candidates.append({"piece": i, "to": capture["cell"], "victim": capture["victim"], "weight": weight})
        if must_capture:
            continue
        for dr in [-1, 1]:
            if ball_holder == i and dr != 1:
                continue
            for dc in [-1, 1]:
                var target := from + Vector2i(dr, dc)
                if not _inside(target) or _piece_at(target) != -1:
                    continue
                var weight := 5
                if ball_holder == i:
                    weight += 12 + target.x * 3
                elif ball_holder == -1:
                    weight += 20 - (abs(target.x - ball_cell.x) + abs(target.y - ball_cell.y)) * 3
                elif dr == 1:
                    weight += 3
                if bot_difficulty == 0:
                    weight = randi_range(0, 70)
                elif bot_difficulty == 1:
                    weight += randi_range(-10, 10)
                else:
                    weight += _football_bot_score(i, target, -1)
                candidates.append({"piece": i, "to": target, "victim": -1, "weight": weight})
        # The bot can also give a one-cell diagonal pass to its own teammate.
        if ball_holder == i:
            for j in pieces.size():
                if not _can_pass(i, j):
                    continue
                var receiver: Vector2i = pieces[j]["cell"]
                var pass_weight: int = 12 + (receiver.x - from.x) * 10 + receiver.x * 2
                if not _carrier_has_move(i):
                    pass_weight += 65
                if bot_difficulty == 0:
                    pass_weight = randi_range(0, 70)
                elif bot_difficulty == 1:
                    pass_weight += randi_range(-9, 9)
                candidates.append({"piece": i, "pass_to": j, "weight": pass_weight})
    if candidates.is_empty():
        message = "Бот не может сделать ход"
        turn = 1
        queue_redraw()
        return
    candidates.sort_custom(func(a, b): return a["weight"] > b["weight"])
    var best: Dictionary = candidates[0]
    selected = int(best["piece"])
    if best.has("pass_to"):
        _pass_ball(int(best["pass_to"]))
        return
    if best["victim"] >= 0:
        pieces[best["victim"]]["alive"] = false
        _start_hit_fx(pieces[best["victim"]]["cell"])
        if ball_holder == best["victim"]:
            ball_holder = selected
    _move_selected(best["to"])
    if _check_elimination():
        return
    if _check_goal():
        return
    # Keep capturing with the same piece while captures are available.
    if best["victim"] >= 0:
        while not _captures(selected).is_empty():
            var next_capture: Dictionary = _captures(selected)[0]
            pieces[next_capture["victim"]]["alive"] = false
            _start_hit_fx(pieces[next_capture["victim"]]["cell"])
            if ball_holder == next_capture["victim"]:
                ball_holder = selected
            _move_selected(next_capture["cell"])
            if _check_elimination():
                return
            if _check_goal():
                return
    _finish_turn()

func _draw() -> void:
    var geometry := _geometry()
    var side: float = geometry["cell_size"]
    var offset: Vector2 = geometry["offset"]
    _halloween_arena(offset, Vector2(COLS * side, ROWS * side))
    var font: Font = ThemeDB.fallback_font
    draw_string(font, Vector2(18, 27), "MONSTER BALL  /  HALLOWEEN", HORIZONTAL_ALIGNMENT_LEFT, size.x - 36.0, 18, Color("#ffc079"))
    draw_string(font, Vector2(18, 48), "%d : %d" % [scores[0], scores[1]], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#dffcff"))
    draw_string(font, Vector2(18, 68), message, HORIZONTAL_ALIGNMENT_LEFT, size.x - 36, 16, Color("#d9f6f9"))
    # Fantasy stone board. Geometry and input coordinates stay unchanged.
    var board_size := Vector2(COLS * side, ROWS * side)
    draw_rect(Rect2(offset - Vector2(6, 6), board_size + Vector2(12, 12)), Color("#0b1925"))
    draw_rect(Rect2(offset - Vector2(4, 4), board_size + Vector2(8, 8)), Color("#db8b49"), false, 3.0)
    for row in ROWS:
        for col in COLS:
            var pos := offset + Vector2(col, row) * side
            var rect := Rect2(pos, Vector2(side, side))
            var dark := (row + col) % 2 == 0
            var stone := Color("#152c3b") if dark else Color("#697786")
            var variation := float(((row * 17 + col * 29) % 9) - 4) * 0.012
            stone = stone.lightened(variation) if variation >= 0.0 else stone.darkened(-variation)
            draw_rect(rect, stone)
            _draw_asset("stone_dark" if dark else "stone_light", rect)
            draw_rect(rect, Color("#392036", 0.24))
            draw_line(pos + Vector2(2, 2), pos + Vector2(side - 3, 2), Color("#9fd6df", 0.14 if dark else 0.26), 1.5)
            draw_line(pos + Vector2(2, 2), pos + Vector2(2, side - 3), Color("#b6e4e6", 0.12 if dark else 0.24), 1.5)
            draw_line(pos + Vector2(2, side - 2), pos + Vector2(side - 2, side - 2), Color("#030e18", 0.45), 2.0)
            draw_line(pos + Vector2(side - 2, 2), pos + Vector2(side - 2, side - 2), Color("#030e18", 0.35), 2.0)
            # Fine cracks in the stone, deterministically placed.
            if (row * 7 + col * 11) % 4 == 0:
                var crack := Color("#091521", 0.24)
                draw_line(pos + Vector2(side * 0.18, side * 0.23), pos + Vector2(side * 0.39, side * 0.32), crack, 1.0)
                draw_line(pos + Vector2(side * 0.39, side * 0.32), pos + Vector2(side * 0.48, side * 0.51), crack, 1.0)
                draw_line(pos + Vector2(side * 0.48, side * 0.51), pos + Vector2(side * 0.70, side * 0.57), crack, 1.0)
            if (row + col) % 2 == 0:
                var rune := pos + Vector2.ONE * (side * 0.5)
                draw_arc(rune, side * 0.22, 0.0, TAU, 20, Color("#4be4ef", 0.075), 1.0)
                draw_line(rune + Vector2(-side * 0.12, 0), rune + Vector2(side * 0.12, 0), Color("#6fe5f1", 0.075), 1.0)
    for col in range(COLS + 1):
        var x := offset.x + col * side
        draw_line(Vector2(x, offset.y), Vector2(x, offset.y + board_size.y), Color("#07131f", 0.6), 1.0)
    for row in range(ROWS + 1):
        var y := offset.y + row * side
        draw_line(Vector2(offset.x, y), Vector2(offset.x + board_size.x, y), Color("#07131f", 0.6), 1.0)
    draw_rect(Rect2(offset, board_size), Color("#e5a65c", 0.75), false, 2.0)
    for col in COLS:
        var letter := char(65 + col)
        var x := offset.x + (col + 0.5) * side - 5.0
        draw_string(font, Vector2(x, offset.y - 10), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#b9e5e8"))
        draw_string(font, Vector2(x, offset.y + ROWS * side + 21), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#b9e5e8"))
    for row in ROWS:
        var label := str(ROWS - row)
        var y := offset.y + (row + 0.5) * side + 5.0
        draw_string(font, Vector2(offset.x - 23, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#b9e5e8"))
        draw_string(font, Vector2(offset.x + COLS * side + 7, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#b9e5e8"))
    # Glowing goal frames are BEHIND the pieces, outside the pitch.
    var goal_left := offset.x + 2.0 * side
    var goal_right := offset.x + 6.0 * side
    var goal_depth: float = minf(12.0, side * 0.15)
    for edge_y in [offset.y, offset.y + board_size.y]:
        var sign_dir := -1.0 if edge_y == offset.y else 1.0
        var a := Vector2(goal_left, edge_y)
        var b := Vector2(goal_left, edge_y + goal_depth * sign_dir)
        var c := Vector2(goal_right, edge_y + goal_depth * sign_dir)
        var d := Vector2(goal_right, edge_y)
        for thickness in [9.0, 5.0, 2.5]:
            var glow := Color("#40e3ff", 0.12) if thickness == 9.0 else (Color("#4af5ff", 0.38) if thickness == 5.0 else Color("#bafaff"))
            draw_line(a, b, glow, thickness)
            draw_line(b, c, glow, thickness)
            draw_line(c, d, glow, thickness)
    for i in pieces.size():
        if not pieces[i]["alive"]:
            continue
        var cell: Vector2i = pieces[i]["cell"]
        var center := offset + Vector2(cell.y + 0.5, cell.x + 0.5) * side
        if i == selected:
            _magic_ring(center, side * 0.44, Color("#5eeeff"), true)
        var team: int = pieces[i]["team"]
        var key: String = BLUE_SKINS[piece_skins[i]] if team == 1 else RED_SKINS[piece_skins[i]]
        var token_side := side * 0.93
        var token_center: Vector2 = center
        if fx_piece == i and fx_progress < 1.0 and not drag_active:
            var eased: float = fx_progress * fx_progress * (3.0 - 2.0 * fx_progress)
            token_center = _drag_cell_center(fx_from).lerp(_drag_cell_center(fx_to), eased)
            token_center.y -= sin(fx_progress * PI) * side * 0.035
        if drag_active and drag_moved and cell == drag_origin:
            continue
        if not _draw_asset(key, Rect2(token_center - Vector2.ONE * token_side * 0.5, Vector2.ONE * token_side)):
            _draw_fantasy_token(token_center, side * 0.37, team, i)
        if ball_holder == i and pass_fx_progress >= 1.0:
            var pumpkin_center := token_center + Vector2(side * 0.17, -side * 0.20)
            var pumpkin_size := side * 0.50
            if not _draw_asset("ghost_pumpkin", Rect2(pumpkin_center - Vector2.ONE * pumpkin_size * 0.5, Vector2.ONE * pumpkin_size)):
                _draw_ghost_pumpkin(pumpkin_center, side * 0.16)
    if ball_holder == -1:
        var pumpkin_center := offset + Vector2(ball_cell.y + 0.5, ball_cell.x + 0.5) * side
        var pumpkin_size := side * 0.90
        if not _draw_asset("ghost_pumpkin", Rect2(pumpkin_center - Vector2.ONE * pumpkin_size * 0.5, Vector2.ONE * pumpkin_size)):
            _draw_ghost_pumpkin(pumpkin_center, side * 0.23)
    _draw_drag_hints()
    _draw_game_fx()
    _draw_drag_piece_overlay(side)
    if celebrating:
        _draw_halloween_party(1.0 - celebration_time / maxf(0.01, celebration_duration), celebration_team, celebration_final)
    _draw_bottom_actions()
    if game_over and not celebrating:
        var panel := Rect2(Vector2(18, size.y * 0.38), Vector2(size.x - 36, 145))
        draw_rect(panel, Color("#15111eef"))
        draw_rect(panel, Color("#f6cf65"), false, 3.0)
        var heading := "ПОЗДРАВЛЯЕМ С ПОБЕДОЙ!" if (game_mode == 1 or winner == 1) else "ВЫ ПРОИГРАЛИ!"
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 52), heading, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 24, Color.WHITE)
        var detail := "Победили голубые" if winner == 1 else "Победили красные"
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 87), "%s · Счёт %d : %d" % [detail, scores[0], scores[1]], HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 17, Color("#f6cf65"))
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 117), "Нажми НОВАЯ ИГРА, чтобы сыграть ещё", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 14, Color.WHITE)


    if customization_open:
        _draw_customization_panel()
        _confirmation_ui()

func _draw_customization_panel() -> void:
    var font: Font = _ui_font()
    draw_rect(Rect2(Vector2.ZERO, size), Color("#080e1a", 0.97))
    draw_string(font, Vector2(14, 46), "ГЕРОИ И ОБЛИКИ", HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 22, Color("#f8d29a"))
    draw_string(font, Vector2(14, 101), "Нажми здесь, чтобы закрыть", HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 15, Color("#b6d9df"))
    var half: float = size.x / 2.0
    draw_rect(Rect2(0, 140, half, 39), Color("#236d83") if customization_team == 1 else Color("#343743"))
    draw_rect(Rect2(half, 140, half, 39), Color("#923d50") if customization_team == 2 else Color("#343743"))
    draw_string(font, Vector2(10, 166), "СИНИЕ", HORIZONTAL_ALIGNMENT_LEFT, half - 15, 16, Color.WHITE)
    draw_string(font, Vector2(half + 10, 166), "КРАСНЫЕ", HORIZONTAL_ALIGNMENT_LEFT, half - 15, 16, Color.WHITE)
    var skins: Array = BLUE_SKINS if customization_team == 1 else RED_SKINS
    for slot in FOOTBALL_TEAM_SIZE:
        var x: float = float(slot) * size.x / float(FOOTBALL_TEAM_SIZE)
        var w: float = size.x / float(FOOTBALL_TEAM_SIZE)
        draw_rect(Rect2(x + 2, 192, w - 4, 46), Color("#38687a") if slot == customization_slot else Color("#303441"))
        draw_string(font, Vector2(x + 5, 222), "Игрок %d" % (slot + 1), HORIZONTAL_ALIGNMENT_LEFT, w - 8, 12, Color.WHITE)
    for skin_idx in 4:
        var w: float = size.x / 4.0
        var x: float = float(skin_idx) * w
        var rect := Rect2(x + 7, 267, w - 14, w - 14)
        var chosen: bool = piece_skins[(customization_team - 1) * FOOTBALL_TEAM_SIZE + customization_slot] == skin_idx
        _flame_frame(rect.grow(2), chosen)
        _draw_asset(skins[skin_idx], rect)
        draw_string(font, Vector2(x + 10, 284 + w), "ОБЛИК %d" % (skin_idx + 1), HORIZONTAL_ALIGNMENT_LEFT, w - 14, 12, Color("#ffdab0"))
    var caption_y: float = 315.0 + size.x / 4.0
    draw_string(font, Vector2(14, caption_y), "5 игроков · выбери игрока и облик", HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 16, Color("#d4e6ed"))
    draw_string(font, Vector2(14, size.y - 26), "ЗАКРЫТЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#a5d4dc"))


# Beveled metal rim, glassy core and engraved fantasy insignia.
func _draw_fantasy_token(center: Vector2, radius: float, team: int, token_index: int) -> void:
    var metal := Color("#247aab") if team == 1 else Color("#a53e43")
    var light := Color("#68edff") if team == 1 else Color("#ff8c6a")
    var dark := Color("#09253c") if team == 1 else Color("#3b1724")
    draw_circle(center + Vector2(radius * 0.12, radius * 0.19), radius * 1.07, Color("#000712", 0.57))
    draw_circle(center, radius * 1.08, light.darkened(0.35))
    draw_circle(center, radius * 0.99, metal)
    draw_circle(center + Vector2(0, radius * 0.055), radius * 0.86, dark)
    draw_circle(center - Vector2(radius * 0.06, radius * 0.07), radius * 0.73, Color("#274f66") if team == 1 else Color("#63333c"))
    draw_arc(center, radius * 0.94, PI * 1.04, PI * 1.91, 32, light, max(1.5, radius * 0.13))
    draw_arc(center, radius * 0.94, PI * 0.03, PI * 0.89, 32, Color("#06121d"), max(1.5, radius * 0.12))
    draw_arc(center, radius * 0.78, 0.0, TAU, 48, Color("#d4f4e5", 0.38), 1.5)
    # Unique sigils: blue knights and red demonic masks.
    if team == 1:
        var hood := PackedVector2Array([center + Vector2(-radius * 0.50, radius * 0.38), center + Vector2(-radius * 0.31, -radius * 0.42), center + Vector2(0, -radius * 0.65), center + Vector2(radius * 0.32, -radius * 0.42), center + Vector2(radius * 0.49, radius * 0.39)])
        draw_colored_polygon(hood, Color("#95b6cc"))
        draw_circle(center + Vector2(0, -radius * 0.03), radius * 0.30, Color("#d5c6a8"))
        draw_line(center + Vector2(-radius * 0.21, -radius * 0.08), center + Vector2(radius * 0.21, -radius * 0.08), Color("#17334c"), max(1.5, radius * 0.14))
        draw_line(center + Vector2(-radius * 0.35, radius * 0.28), center + Vector2(radius * 0.35, radius * 0.28), Color("#e1faff"), max(1.5, radius * 0.14))
    else:
        var head := PackedVector2Array([center + Vector2(-radius * 0.46, -radius * 0.28), center + Vector2(-radius * 0.22, -radius * 0.54), center + Vector2(radius * 0.23, -radius * 0.54), center + Vector2(radius * 0.46, -radius * 0.25), center + Vector2(radius * 0.30, radius * 0.41), center + Vector2(0, radius * 0.55), center + Vector2(-radius * 0.30, radius * 0.41)])
        draw_colored_polygon(head, Color("#b3b8c1"))
        draw_colored_polygon(PackedVector2Array([center + Vector2(-radius * 0.48, -radius * 0.28), center + Vector2(-radius * 0.60, -radius * 0.70), center + Vector2(-radius * 0.15, -radius * 0.48)]), Color("#cbd5d9"))
        draw_colored_polygon(PackedVector2Array([center + Vector2(radius * 0.48, -radius * 0.28), center + Vector2(radius * 0.60, -radius * 0.70), center + Vector2(radius * 0.15, -radius * 0.48)]), Color("#cbd5d9"))
        draw_line(center + Vector2(-radius * 0.26, -radius * 0.04), center + Vector2(-radius * 0.08, radius * 0.02), Color("#ff3c2d"), max(2.0, radius * 0.13))
        draw_line(center + Vector2(radius * 0.26, -radius * 0.04), center + Vector2(radius * 0.08, radius * 0.02), Color("#ff3c2d"), max(2.0, radius * 0.13))
        draw_line(center + Vector2(-radius * 0.13, radius * 0.29), center + Vector2(radius * 0.13, radius * 0.29), Color("#301923"), max(1.5, radius * 0.10))
    # Four tiny rivets on the metal rim.
    for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
        draw_circle(center + Vector2(cos(angle), sin(angle)) * radius * 0.92, max(1.0, radius * 0.065), Color("#e3d7b4"))


func _draw_ghost_pumpkin(center: Vector2, radius: float) -> void:
    # Layered translucent halos create an eerie supernatural glow.
    for step in range(5, 0, -1):
        var halo_radius := radius * (1.0 + float(step) * 0.31)
        draw_circle(center, halo_radius, Color("#44f7cf", 0.025 + (6 - step) * 0.012))
    draw_circle(center + Vector2(radius * 0.08, radius * 0.14), radius * 1.05, Color("#071219", 0.4))
    draw_circle(center, radius, Color("#ed8a2d"))
    draw_circle(center + Vector2(-radius * 0.28, -radius * 0.08), radius * 0.62, Color("#ffa63a"))
    draw_circle(center + Vector2(radius * 0.30, -radius * 0.08), radius * 0.62, Color("#ce651f"))
    draw_circle(center + Vector2(0, -radius * 0.06), radius * 0.67, Color("#ffb449"))
    draw_line(center + Vector2(0, -radius * 0.86), center + Vector2(radius * 0.14, -radius * 1.18), Color("#73db88"), max(2.0, radius * 0.19))
    draw_colored_polygon(PackedVector2Array([center + Vector2(-radius * 0.63, -radius * 0.14), center + Vector2(-radius * 0.10, -radius * 0.14), center + Vector2(-radius * 0.31, radius * 0.23)]), Color("#102f28"))
    draw_colored_polygon(PackedVector2Array([center + Vector2(radius * 0.63, -radius * 0.14), center + Vector2(radius * 0.10, -radius * 0.14), center + Vector2(radius * 0.31, radius * 0.23)]), Color("#102f28"))
    draw_colored_polygon(PackedVector2Array([center + Vector2(-radius * 0.55, radius * 0.38), center + Vector2(0, radius * 0.67), center + Vector2(radius * 0.55, radius * 0.38), center + Vector2(radius * 0.25, radius * 0.30), center + Vector2(0, radius * 0.45), center + Vector2(-radius * 0.25, radius * 0.30)]), Color("#14372b"))
    draw_arc(center, radius * 1.02, 0.0, TAU, 32, Color("#a7ffe0", 0.8), max(1.0, radius * 0.08))

func _go_to_main_menu() -> void:
    get_tree().root.set_meta("mb_customize", false)
    get_tree().change_scene_to_file("res://main.tscn")

func _draw_bottom_actions() -> void:
    var font: Font = ThemeDB.fallback_font
    var y: float = size.y - 74.0
    var w: float = size.x * 0.5
    draw_rect(Rect2(4, y, w - 8, 61), Color("#273d51"))
    draw_rect(Rect2(w + 4, y, w - 8, 61), Color("#684026"))
    draw_rect(Rect2(4, y, w - 8, 61), Color("#83d5e4"), false, 2.0)
    draw_rect(Rect2(w + 4, y, w - 8, 61), Color("#ffc17a"), false, 2.0)
    draw_string(font, Vector2(13, y + 37), "НОВАЯ ИГРА", HORIZONTAL_ALIGNMENT_LEFT, w - 17, 15, Color.WHITE)
    draw_string(font, Vector2(w + 12, y + 37), "ГЛАВНОЕ МЕНЮ", HORIZONTAL_ALIGNMENT_LEFT, w - 18, 14, Color.WHITE)
