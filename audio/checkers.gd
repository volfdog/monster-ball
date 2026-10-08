extends Control

const N := 8
const DIRECTIONS := [Vector2i(-1,-1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(1,1)]
var board: Array = []
var turn: int = 1
var selected: Vector2i = Vector2i(-1,-1)
var forced: Vector2i = Vector2i(-1,-1)
var message: String = "Ход синих"
var finished: bool = false
var winning_team: int = 0
var win_celebration_time: float = 0.0
var win_celebration_seen: bool = false
const WIN_CELEBRATION_DURATION := 3.3
var textures: Dictionary = {}
const BLUE_SKINS := ["blue_knight", "blue_wizard", "blue_rogue", "blue_dwarf"]
const RED_SKINS := ["red_orc", "red_skull", "red_goblin", "red_vampire"]
var pawn_skin: Array[int] = [0, 0]
var king_skin: Array[int] = [1, 1]
var game_mode: int = 0 # 0 bot, 1 two players
var bot_difficulty: int = 1
var bot_pending: bool = false
var customization_open: bool = false
var customization_team: int = 1
var customization_kind: int = 0 # 0 pawn, 1 king


var pending_skin: int = -1
var flame_time: float = 0.0
var fancy_font: Font


# Halloween Sound Edition: shared per-scene sound system. No autoload required.
var sound_library: Dictionary = {}
var arena_music: AudioStreamPlayer
var crowd_ambience: AudioStreamPlayer
var game_audio_unlocked: bool = false
var background_audio_poll: float = 0.0

func _setup_game_audio() -> void:
    for sound_name in ["stone_move", "king_move", "capture", "pass", "goal", "crowd", "victory", "arena_ambience"]:
        var audio_path: String = "res://audio/%s.wav" % sound_name
        if ResourceLoader.exists(audio_path):
            sound_library[sound_name] = load(audio_path)
    # Prefer real, long field recordings if available. Keep existing effects intact.
    for track_name in ["stadium_crowd", "arena_ambience", "goal_crowd"]:
        for extension in ["ogg", "mp3"]:
            var alternate: String = "res://audio/%s.%s" % [track_name, extension]
            if ResourceLoader.exists(alternate):
                sound_library[track_name] = load(alternate)
                break
    arena_music = AudioStreamPlayer.new()
    arena_music.name = "HalloweenAmbience"
    add_child(arena_music)
    if sound_library.has("arena_ambience"):
        var ambience: AudioStream = sound_library["arena_ambience"]
        var wav_ambience: AudioStreamWAV = ambience as AudioStreamWAV
        if wav_ambience != null:
            # Do not use native WAV looping with an unset end point.
            wav_ambience.loop_mode = AudioStreamWAV.LOOP_DISABLED
        arena_music.stream = ambience
        arena_music.finished.connect(_restart_arena_ambience)

    crowd_ambience = AudioStreamPlayer.new()
    crowd_ambience.name = "HalloweenCrowdBackground"
    add_child(crowd_ambience)
    var crowd_key: String = "stadium_crowd" if sound_library.has("stadium_crowd") else "crowd"
    if sound_library.has(crowd_key):
        # Real stadium recordings are long ambient loops; WAV is a fallback.
        var original_crowd: AudioStreamWAV = sound_library[crowd_key] as AudioStreamWAV
        if original_crowd != null:
            var crowd_copy: AudioStreamWAV = original_crowd.duplicate() as AudioStreamWAV
            crowd_copy.loop_mode = AudioStreamWAV.LOOP_DISABLED
            crowd_ambience.stream = crowd_copy
        else:
            crowd_ambience.stream = sound_library[crowd_key]
        crowd_ambience.finished.connect(_restart_crowd_ambience)
    _refresh_background_volumes()

func _refresh_background_volumes() -> void:
    if not is_inside_tree():
        return
    var muted: bool = bool(get_tree().root.get_meta("mb_muted", false))
    var music_volume: float = float(get_tree().root.get_meta("mb_vol_music", 0.55))
    var crowd_volume: float = float(get_tree().root.get_meta("mb_vol_crowd", 0.65))
    if arena_music != null:
        arena_music.volume_db = linear_to_db(maxf(0.001, music_volume * 0.60))
        if muted or music_volume <= 0.005:
            arena_music.stop()
    if crowd_ambience != null:
        # The original crowd WAV is quiet; do not attenuate it again.
        var crowd_balance: float = 0.53 if sound_library.has("stadium_crowd") else 1.10
        crowd_ambience.volume_db = linear_to_db(maxf(0.001, crowd_volume * crowd_balance))
        if muted or crowd_volume <= 0.005:
            crowd_ambience.stop()

func _restart_arena_ambience() -> void:
    _resume_background_audio()

func _restart_crowd_ambience() -> void:
    _resume_background_audio()

func _resume_background_audio() -> void:
    if not game_audio_unlocked or not is_inside_tree():
        return
    var muted: bool = bool(get_tree().root.get_meta("mb_muted", false))
    _refresh_background_volumes()
    if muted:
        return
    if arena_music != null and arena_music.stream != null and not arena_music.playing:
        if float(get_tree().root.get_meta("mb_vol_music", 0.55)) > 0.005:
            arena_music.play()
    if crowd_ambience != null and crowd_ambience.stream != null and not crowd_ambience.playing:
        if float(get_tree().root.get_meta("mb_vol_crowd", 0.65)) > 0.005:
            crowd_ambience.play()

# Start only after a real iPhone gesture, just like the working one-shot sounds.
func _unlock_game_audio() -> void:
    if game_audio_unlocked:
        return
    game_audio_unlocked = true
    _resume_background_audio()

func _play_sfx(sound_name: String, channel: String = "effects") -> void:
    if not sound_library.has(sound_name) or bool(get_tree().root.get_meta("mb_muted", false)):
        return
    var volume_key: String = "mb_vol_crowd" if channel == "crowd" else "mb_vol_effects"
    var v: float = float(get_tree().root.get_meta(volume_key, 0.78))
    if v <= 0.005:
        return
    var player: AudioStreamPlayer = AudioStreamPlayer.new()
    add_child(player)
    player.stream = sound_library["goal_crowd"] if sound_name == "crowd" and sound_library.has("goal_crowd") else sound_library[sound_name]
    player.volume_db = linear_to_db(maxf(0.001, v * (0.68 if channel == "crowd" else 0.85)))
    player.finished.connect(func(): player.queue_free())
    player.play()

func _process(delta: float) -> void:
    # Retry occasionally if Safari suspended a background player.
    if game_audio_unlocked:
        background_audio_poll += delta
        if background_audio_poll > 2.0:
            background_audio_poll = 0.0
            _resume_background_audio()
    if finished and not win_celebration_seen:
        win_celebration_seen = true
        win_celebration_time = WIN_CELEBRATION_DURATION
        _play_sfx("victory")
        _play_sfx("crowd", "crowd")
    if win_celebration_time > 0.0:
        win_celebration_time = maxf(0.0, win_celebration_time - delta)
        queue_redraw()
    magic_clock += delta
    if fmod(magic_clock, 0.11) < delta: queue_redraw()
    if fx_progress < 1.0:
        fx_progress = minf(1.0, fx_progress + delta / fx_duration)
        queue_redraw()
    if fx_capture_time > 0.0:
        fx_capture_time = maxf(0.0, fx_capture_time - delta)
        queue_redraw()
    if fx_bounce_time > 0.0:
        fx_bounce_time = maxf(0.0, fx_bounce_time - delta)
        queue_redraw()
    if selected.x >= 0 or drag_active: queue_redraw()
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
        if customization_kind == 0:
            pawn_skin[customization_team - 1] = pending_skin
            get_tree().root.set_meta("mb_checkers_pawn", pawn_skin.duplicate())
        else:
            king_skin[customization_team - 1] = pending_skin
            get_tree().root.set_meta("mb_checkers_king", king_skin.duplicate())
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
                    _tap(target)
                    # The piece was physically carried to its destination.
                    # Never replay the travel from the old square after release.
                    if fx_progress < 1.0 and fx_target == target:
                        fx_source = target
                        fx_duration = 0.14 if bool(fx_piece_data.get("king", false)) else 0.24
                        fx_progress = 0.0
                else:
                    fx_bounce_cell = old
                    fx_bounce_start = point
                    fx_bounce_data = _piece(old).duplicate()
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
    if selected.x < 0 or not _inside(cell):
        return false
    var moves: Array = _captures(selected)
    if forced.x < 0 and not _must_capture(turn):
        moves.append_array(_moves(selected))
    for move in moves:
        if move["to"] == cell:
            return true
    return false

func _drag_point_to_cell(point: Vector2) -> Vector2i:
    var g: Dictionary = _geometry()
    var side: float = g["side"]
    var origin: Vector2 = g["origin"]
    return Vector2i(int(floor((point.y - origin.y) / side)), int(floor((point.x - origin.x) / side)))

func _drag_cell_center(cell: Vector2i) -> Vector2:
    var g: Dictionary = _geometry()
    var side: float = g["side"]
    var origin: Vector2 = g["origin"]
    return origin + Vector2(cell.y + 0.5, cell.x + 0.5) * side

func _drag_cell_valid(cell: Vector2i) -> bool:
    return _inside(cell)

func _drag_is_own_piece(cell: Vector2i) -> bool:
    return not finished and not bot_pending and (game_mode != 0 or turn == 1) and int(_piece(cell)["team"]) == turn and (forced.x < 0 or cell == forced)

func _drag_can_start(point: Vector2) -> bool:
    return not customization_open and pending_skin < 0 and not finished and not bot_pending and fx_progress >= 0.99 and (game_mode != 0 or turn == 1)

func _draw_drag_piece_overlay(side: float) -> void:
    if not drag_active or not drag_moved or not _inside(drag_origin):
        return
    var data: Dictionary = _piece(drag_origin)
    if int(data["team"]) == 0:
        return
    var center: Vector2 = drag_pointer
    draw_circle(center + Vector2(0, side * 0.17), side * 0.42, Color("#05040d", 0.57))
    draw_arc(center, side * 0.45, 0, TAU, 40, Color("#ffa74e", 0.82), 2.6)
    var team_idx: int = int(data["team"]) - 1
    var skin_idx: int = king_skin[team_idx] if bool(data["king"]) else pawn_skin[team_idx]
    var key: String = BLUE_SKINS[skin_idx] if team_idx == 0 else RED_SKINS[skin_idx]
    if textures.has(key):
        draw_texture_rect(textures[key], Rect2(center - Vector2.ONE * side * 0.44, Vector2.ONE * side * 0.88), false)
    else:
        draw_circle(center, side * 0.39, Color("#2aaedc") if team_idx == 0 else Color("#b83f43"))
        draw_arc(center, side * 0.37, 0, TAU, 40, Color("#c2efff"), 3.0)
    if bool(data["king"]):
        draw_circle(center + Vector2(0, side * 0.24), side * 0.13, Color("#e5ba4d"))
        draw_string(_ui_font(), center + Vector2(-side * 0.11, side * 0.29), "Д", HORIZONTAL_ALIGNMENT_LEFT, -1, int(side * 0.20), Color("#22150a"))

func _draw_drag_hints() -> void:
    if selected.x < 0 or not _inside(selected): return
    var options: Array = _captures(selected)
    if forced.x < 0 and not _must_capture(turn): options.append_array(_moves(selected))
    var g: Dictionary = _geometry()
    var side: float = g["side"]
    var origin: Vector2 = g["origin"]
    for option in options:
        var cell: Vector2i = option["to"]
        var center: Vector2 = origin + Vector2(cell.y + 0.5, cell.x + 0.5) * side
        var capture: bool = option["taken"].x >= 0
        _magic_ring(center, side * 0.28, Color("#ff6b30") if capture else Color("#71f9b0"))


var fx_source: Vector2i = Vector2i(-1, -1)
var fx_target: Vector2i = Vector2i(-1, -1)
var fx_progress: float = 1.0
var fx_duration: float = 0.72
var fx_capture: Vector2i = Vector2i(-1, -1)
var fx_capture_time: float = 0.0
var fx_piece_data: Dictionary = {}
var fx_bounce_time: float = 0.0
var fx_bounce_cell: Vector2i = Vector2i(-1, -1)
var fx_bounce_start: Vector2 = Vector2.ZERO
var fx_bounce_data: Dictionary = {}

func _start_move_fx(source: Vector2i, target: Vector2i, captured: Vector2i, data: Dictionary) -> void:
    _play_sfx("king_move" if bool(data["king"]) else "stone_move")
    if captured.x >= 0:
        _play_sfx("capture")
    fx_source = source
    fx_target = target
    fx_progress = 0.0
    fx_duration = 0.19 if bool(data["king"]) else 0.72
    fx_piece_data = data.duplicate()
    if captured.x >= 0:
        fx_capture = captured
        fx_capture_time = 0.55

func _draw_game_fx() -> void:
    var g: Dictionary = _geometry()
    var side: float = g["side"]
    var origin: Vector2 = g["origin"]
    if fx_capture_time > 0.0:
        var t: float = 1.0 - fx_capture_time / 0.55
        var c: Vector2 = origin + Vector2(fx_capture.y + 0.5, fx_capture.x + 0.5) * side
        draw_arc(c, side * (0.17 + 0.43 * t), 0.0, TAU, 40, Color(1.0, 0.4, 0.12, 1.0-t), 3.0)
        for i in 8:
            var a: float = TAU * float(i) / 8.0
            var d: Vector2 = Vector2(cos(a), sin(a))
            draw_line(c + d * side * 0.1, c + d * side * (0.2 + t * 0.4), Color(1.0, 0.73, 0.2, 1.0-t), 2.0)
    if fx_bounce_time > 0.0 and fx_bounce_cell.x >= 0:
        var t: float = 1.0 - fx_bounce_time / 0.22
        var dest: Vector2 = origin + Vector2(fx_bounce_cell.y + 0.5, fx_bounce_cell.x + 0.5) * side
        var c: Vector2 = fx_bounce_start.lerp(dest, t)
        if fx_bounce_data.size() > 0:
            var team_idx: int = int(fx_bounce_data["team"]) - 1
            var skin_idx: int = king_skin[team_idx] if bool(fx_bounce_data["king"]) else pawn_skin[team_idx]
            var key: String = BLUE_SKINS[skin_idx] if team_idx == 0 else RED_SKINS[skin_idx]
            if textures.has(key):
                draw_texture_rect(textures[key], Rect2(c - Vector2.ONE * side * 0.44, Vector2.ONE * side * 0.88), false)
        draw_arc(c, side * (0.25 + t * 0.2), 0.0, TAU, 36, Color(0.45, 0.96, 1.0, 0.8*(1.0-t)), 2.5)
    if fx_progress < 1.0 and fx_piece_data.size() > 0:
        var eased: float = fx_progress * fx_progress * (3.0 - 2.0 * fx_progress)
        var c1: Vector2 = origin + Vector2(fx_source.y + 0.5, fx_source.x + 0.5) * side
        var c2: Vector2 = origin + Vector2(fx_target.y + 0.5, fx_target.x + 0.5) * side
        var height: float = side * (0.115 if bool(fx_piece_data["king"]) else 0.021)
        var center: Vector2 = c1.lerp(c2, eased) - Vector2(0, sin(fx_progress * PI) * height)
        draw_circle(center + Vector2(0, side * 0.19), side * 0.36, Color("#07060e", 0.38))
        if not bool(fx_piece_data["king"]) and fx_progress > 0.84:
            var landing: float = (fx_progress - 0.84) / 0.16
            draw_arc(c2, side * (0.28 + landing * 0.14), 0, TAU, 32, Color("#efac74", 0.24 * (1.0 - landing)), 2.0)
        var team_idx: int = int(fx_piece_data["team"]) - 1
        var skin_idx: int = king_skin[team_idx] if bool(fx_piece_data["king"]) else pawn_skin[team_idx]
        var key: String = BLUE_SKINS[skin_idx] if team_idx == 0 else RED_SKINS[skin_idx]
        if textures.has(key):
            var width: float = side * 0.88
            draw_texture_rect(textures[key], Rect2(center - Vector2.ONE * width * 0.5, Vector2.ONE * width), false)
        else:
            draw_circle(center, side * 0.38, Color("#2aaedc") if team_idx == 0 else Color("#b83f43"))
        if bool(fx_piece_data["king"]):
            draw_circle(center + Vector2(0, side * 0.23), side * 0.12, Color("#e5ba4d"))
            draw_string(ThemeDB.fallback_font, center + Vector2(-side * 0.1, side * 0.28), "Д", HORIZONTAL_ALIGNMENT_LEFT, -1, int(side * 0.19), Color("#22150a"))

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    _setup_game_audio()
    if ResourceLoader.exists("res://assets/game_font.ttf"):
        fancy_font = load("res://assets/game_font.ttf")
    for name in ["stone_dark", "stone_light", "blue_knight", "blue_wizard", "blue_rogue", "blue_dwarf", "red_orc", "red_skull", "red_goblin", "red_vampire"]:
        var path: String = "res://assets/%s.png" % name
        if ResourceLoader.exists(path):
            textures[name] = load(path)
    _new_game()
    game_mode = int(get_tree().root.get_meta("mb_mode", 0))
    bot_difficulty = clampi(int(get_tree().root.get_meta("mb_bot_difficulty", 1)), 0, 2)
    customization_open = bool(get_tree().root.get_meta("mb_customize", false))
    if get_tree().root.has_meta("mb_checkers_pawn"):
        var saved_pawn: Array = get_tree().root.get_meta("mb_checkers_pawn")
        for j in mini(saved_pawn.size(), 2): pawn_skin[j] = int(saved_pawn[j])
    if get_tree().root.has_meta("mb_checkers_king"):
        var saved_king: Array = get_tree().root.get_meta("mb_checkers_king")
        for j in mini(saved_king.size(), 2): king_skin[j] = int(saved_king[j])

func _new_game() -> void:
    win_celebration_time = 0.0
    win_celebration_seen = false
    fx_progress = 1.0
    fx_capture_time = 0.0
    board.clear()
    for r in N:
        var line: Array = []
        for c in N:
            var side: int = 0
            if (r+c)%2 == 0:
                if r < 3: side = 2
                elif r > 4: side = 1
            line.append({"team":side, "king":false})
        board.append(line)
    turn = 1
    selected = Vector2i(-1,-1)
    forced = Vector2i(-1,-1)
    finished = false
    winning_team = 0
    bot_pending = false
    message = "Ход синих"
    queue_redraw()

func _inside(p: Vector2i) -> bool:
    return p.x >= 0 and p.x < N and p.y >= 0 and p.y < N

func _piece(p: Vector2i) -> Dictionary:
    return board[p.x][p.y]

func _geometry() -> Dictionary:
    var side: float = floor(minf((size.x-58.0)/8.0, (size.y-265.0)/8.0))
    side = maxf(8.0,side)
    var origin := Vector2(floor((size.x-side*8.0)/2.0), maxf(177.0, floor((size.y-side*8.0)/2.0)+26.0))
    return {"side":side,"origin":origin}

func _captures(p: Vector2i) -> Array:
    var result: Array = []
    var data: Dictionary = _piece(p)
    if data["team"] == 0: return result
    for d in DIRECTIONS:
        var mid: Vector2i = p+d
        if not _inside(mid) or _piece(mid)["team"] == 0 or _piece(mid)["team"] == data["team"]:
            continue
        if data["king"]:
            var dest: Vector2i = mid+d
            while _inside(dest) and _piece(dest)["team"] == 0:
                result.append({"to":dest,"taken":mid})
                dest += d
        else:
            var dest: Vector2i = mid+d
            if _inside(dest) and _piece(dest)["team"] == 0:
                result.append({"to":dest,"taken":mid})
    if data["king"]:
        for d in DIRECTIONS:
            var mid: Vector2i = p+d
            while _inside(mid) and _piece(mid)["team"] == 0:
                mid += d
            if not _inside(mid) or _piece(mid)["team"] == data["team"]: continue
            var dest: Vector2i = mid+d
            while _inside(dest) and _piece(dest)["team"] == 0:
                var entry: Dictionary = {"to":dest,"taken":mid}
                if not result.has(entry): result.append(entry)
                dest += d
    return result

func _moves(p: Vector2i) -> Array:
    var result: Array = []
    var data: Dictionary = _piece(p)
    if data["team"] == 0: return result
    for d in DIRECTIONS:
        if not data["king"] and d.x != (-1 if data["team"] == 1 else 1): continue
        var dest: Vector2i = p+d
        while _inside(dest) and _piece(dest)["team"] == 0:
            result.append({"to":dest,"taken":Vector2i(-1,-1)})
            if not data["king"]: break
            dest += d
    return result

func _must_capture(side: int) -> bool:
    for r in N:
        for c in N:
            var p := Vector2i(r,c)
            if _piece(p)["team"] == side and not _captures(p).is_empty(): return true
    return false

func _has_move(side: int) -> bool:
    for r in N:
        for c in N:
            var p := Vector2i(r,c)
            if _piece(p)["team"] == side and (not _captures(p).is_empty() or not _moves(p).is_empty()): return true
    return false

func _tap(p: Vector2i) -> void:
    if fx_progress < 0.99: return
    if finished or bot_pending or (game_mode == 0 and turn == 2): return
    if forced.x >= 0 and p == forced:
        selected = p
        return
    if _piece(p)["team"] == turn and forced.x < 0:
        selected = p
        message = "Выбери клетку для хода"
        queue_redraw()
        return
    if selected.x < 0:
        message = "Выбери свою фишку"
        queue_redraw()
        return
    var available: Array = _captures(selected)
    if forced.x < 0 and not _must_capture(turn):
        available.append_array(_moves(selected))
    for move in available:
        if move["to"] != p: continue
        var data: Dictionary = _piece(selected).duplicate()
        _start_move_fx(selected, p, move["taken"], data)
        board[selected.x][selected.y] = {"team":0,"king":false}
        board[p.x][p.y] = data
        var taken: Vector2i = move["taken"]
        if taken.x >= 0:
            board[taken.x][taken.y] = {"team":0,"king":false}
        var became_king: bool = false
        if not data["king"] and (p.x == 0 and turn == 1 or p.x == 7 and turn == 2):
            data["king"] = true
            became_king = true
        selected = p
        if taken.x >= 0 and not became_king and not _captures(p).is_empty():
            forced = p
            message = "Продолжай взятие этой фишкой"
        else:
            forced = Vector2i(-1,-1)
            selected = Vector2i(-1,-1)
            turn = 3-turn
            if not _has_move(turn):
                finished = true
                winning_team = 3 - turn
                message = "ПОБЕДИЛИ СИНИЕ!" if winning_team == 1 else "ПОБЕДИЛИ КРАСНЫЕ!"
            else:
                message = "Ход синих" if turn == 1 else "Ход красных"
        queue_redraw()
        if not finished and game_mode == 0 and turn == 2 and forced.x < 0:
            _schedule_bot()
        return
    message = "Взятие обязательно" if _must_capture(turn) else "Недопустимый ход"
    queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
        _unlock_game_audio()
    if _drag_event(event):
        accept_event()
        return
    var pos := Vector2(-1,-1)
    if event is InputEventScreenTouch and event.pressed: pos = event.position
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: pos = event.position
    if pos.x < 0: return
    accept_event()
    if finished:
        if win_celebration_time > 0.0:
            return
        if pos.y > size.y - 82.0:
            if pos.x >= size.x * 0.5: _go_to_main_menu()
            else: _new_game()
        else:
            _victory_tap(pos)
        return
    if customization_open:
        if pending_skin >= 0:
            _confirmation_tap(pos)
            return
        _customization_tap(pos)
        return
    if pos.y > size.y - 82.0:
        if pos.x >= size.x * 0.5:
            _go_to_main_menu()
            return
        _new_game()
        return
    var g: Dictionary = _geometry()
    var s: float = g["side"]
    var o: Vector2 = g["origin"]
    var p := Vector2i(int(floor((pos.y-o.y)/s)),int(floor((pos.x-o.x)/s)))
    if _inside(p): _tap(p)

func _draw() -> void:
    var g: Dictionary = _geometry()
    var s: float = g["side"]
    var o: Vector2 = g["origin"]
    _halloween_arena(o, Vector2(s * 8.0, s * 8.0))
    var font: Font = ThemeDB.fallback_font
    draw_string(font, Vector2(18, 35), "MONSTER BALL / HALLOWEEN", HORIZONTAL_ALIGNMENT_LEFT, size.x - 36, 19, Color("#ffbb74"))
    draw_string(font, Vector2(18, 72), message, HORIZONTAL_ALIGNMENT_LEFT, size.x - 36, 17, Color("#d9f6f9"))
    draw_rect(Rect2(o-Vector2(5,5),Vector2(s*8+10,s*8+10)),Color("#efad62"),false,3.0)
    for r in N:
        for c in N:
            var p := Vector2i(r,c)
            var at: Vector2 = o+Vector2(c,r)*s
            var rect := Rect2(at,Vector2(s,s))
            var dark: bool = (r+c)%2 == 0
            draw_rect(rect,Color("#182c3a") if dark else Color("#6b7a8a"))
            var texname := "stone_dark" if dark else "stone_light"
            if textures.has(texname): draw_texture_rect(textures[texname],rect,false)
            draw_rect(rect, Color("#3e2238", 0.25))
            draw_rect(rect,Color("#0b1926",0.45),false,1.0)
            if p == selected:
                _magic_ring(at + Vector2.ONE * s * 0.5, s * 0.45, Color("#5eeeff"), true)
            var data: Dictionary = _piece(p)
            if data["team"] == 0: continue
            if fx_progress < 1.0 and p == fx_target: continue
            var center := at+Vector2.ONE*s*0.5
            var team_idx: int = int(data["team"]) - 1
            var skin_idx: int = king_skin[team_idx] if data["king"] else pawn_skin[team_idx]
            var texname2: String = BLUE_SKINS[skin_idx] if team_idx == 0 else RED_SKINS[skin_idx]
            var inset: float = s*0.06
            var display_rect: Rect2 = rect.grow(-inset)
            if drag_active and drag_moved and p == drag_origin:
                continue
            if textures.has(texname2):
                draw_texture_rect(textures[texname2],display_rect,false)
            else:
                draw_circle(center,s*0.39,Color("#2aaedc") if data["team"] == 1 else Color("#b83f43"))
                draw_arc(center,s*0.37,0,TAU,40,Color("#c2efff"),3.0)
            if data["king"]:
                draw_circle(center+Vector2(0,s*0.24),s*0.13,Color("#e5ba4d"))
                draw_string(font,center+Vector2(-s*0.11,s*0.29),"Д",HORIZONTAL_ALIGNMENT_LEFT,-1,int(s*0.20),Color("#22150a"))
    for c in N:
        var letter: String = char(65+c)
        draw_string(font,o+Vector2((c+0.43)*s,-12),letter,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#b9e5e8"))
        draw_string(font,o+Vector2((c+0.43)*s,8*s+20),letter,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#b9e5e8"))
    for r in N:
        var label: String = str(8-r)
        draw_string(font,o+Vector2(-19,(r+0.58)*s),label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#b9e5e8"))
        draw_string(font,o+Vector2(8*s+7,(r+0.58)*s),label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#b9e5e8"))
    _draw_drag_hints()
    _draw_game_fx()
    _draw_drag_piece_overlay(s)
    if win_celebration_time > 0.0:
        _draw_halloween_party(1.0 - win_celebration_time / WIN_CELEBRATION_DURATION, winning_team, true)
    _draw_bottom_actions()
    if customization_open:
        _draw_customization(font)
        _confirmation_ui()
    elif finished and win_celebration_time <= 0.0:
        _draw_victory_panel()

func _customization_tap(pos: Vector2) -> void:
    if pos.y < 120.0 or pos.y > size.y - 65.0:
        customization_open = false
    elif pos.y < 180.0:
        customization_team = 1 if pos.x < size.x * 0.5 else 2
    elif pos.y < 235.0:
        customization_kind = 0 if pos.x < size.x * 0.5 else 1
    elif pos.y < 380.0:
        var index: int = clampi(int(pos.x / maxf(1.0, size.x / 4.0)), 0, 3)
        pending_skin = index
    queue_redraw()

func _draw_customization(font: Font) -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#07111b", 0.96))
    draw_string(font, Vector2(14, 49), "ШАШКИ — КОСТЮМЫ", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color.WHITE)
    draw_string(font, Vector2(14, 98), "Нажми здесь, чтобы закрыть", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#c5e7f2"))
    var half: float = size.x / 2.0
    draw_rect(Rect2(0, 140, half, 40), Color("#287d99") if customization_team == 1 else Color("#303945"))
    draw_rect(Rect2(half, 140, half, 40), Color("#99465d") if customization_team == 2 else Color("#303945"))
    draw_string(font, Vector2(10, 167), "СИНИЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
    draw_string(font, Vector2(half + 10, 167), "КРАСНЫЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
    draw_rect(Rect2(0, 191, half, 43), Color("#376a78") if customization_kind == 0 else Color("#303945"))
    draw_rect(Rect2(half, 191, half, 43), Color("#376a78") if customization_kind == 1 else Color("#303945"))
    draw_string(font, Vector2(10, 220), "ПЕШКИ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
    draw_string(font, Vector2(half + 10, 220), "ДАМКИ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
    var skins: Array = BLUE_SKINS if customization_team == 1 else RED_SKINS
    var chosen: int = pawn_skin[customization_team - 1] if customization_kind == 0 else king_skin[customization_team - 1]
    for i in 4:
        var w: float = size.x / 4.0
        var rect := Rect2(i * w + 4.0, 267, w - 8.0, w - 8.0)
        _flame_frame(rect.grow(3.0), chosen == i)
        if textures.has(skins[i]):
            draw_texture_rect(textures[skins[i]], rect, false)
        draw_string(font, Vector2(i * w + 7.0, 284.0 + w), "ОБЛИК %d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
    draw_string(font, Vector2(14, 325.0 + size.x / 4.0), "Выбери вид для всей команды", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
    draw_string(font, Vector2(14, size.y - 25), "ЗАКРЫТЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

func _schedule_bot() -> void:
    if bot_pending or finished or game_mode != 0 or turn != 2:
        return
    bot_pending = true
    _bot_move.call_deferred()

# AI 2.0: real look-ahead on the current board, including forced captures.
# Scores are always from the red bot's point of view.
var _ai_checkers_nodes: int = 0

func _ai_checkers_value() -> int:
    var value: int = 0
    var reds: int = 0
    var blues: int = 0
    for r in N:
        for c in N:
            var d: Dictionary = board[r][c]
            var team_id: int = int(d["team"])
            if team_id == 0:
                continue
            var sign: int = 1 if team_id == 2 else -1
            if team_id == 2:
                reds += 1
            else:
                blues += 1
            var rank: int = r if team_id == 2 else 7 - r
            var center: int = 3 - mini(absi(c - 3), 3)
            value += sign * (280 if bool(d["king"]) else 100 + rank * 5 + center * 3)
    if blues == 0:
        return 50000
    if reds == 0:
        return -50000
    return value

func _ai_checkers_options(team_id: int, only_piece: Vector2i = Vector2i(-1, -1)) -> Array[Dictionary]:
    var capture_list: Array[Dictionary] = []
    var quiet_list: Array[Dictionary] = []
    for r in N:
        for c in N:
            var from := Vector2i(r, c)
            if only_piece.x >= 0 and from != only_piece:
                continue
            if int(_piece(from)["team"]) != team_id:
                continue
            for move in _captures(from):
                capture_list.append({"from":from, "to":move["to"], "taken":move["taken"]})
            if only_piece.x < 0:
                for move in _moves(from):
                    quiet_list.append({"from":from, "to":move["to"], "taken":Vector2i(-1,-1)})
    if not capture_list.is_empty():
        return capture_list
    if only_piece.x >= 0:
        return []
    return quiet_list

func _ai_checkers_quick(action: Dictionary, side: int) -> int:
    var from: Vector2i = action["from"]
    var dest: Vector2i = action["to"]
    var captured: Vector2i = action["taken"]
    var bonus: int = 0
    if captured.x >= 0:
        bonus += 175 if bool(_piece(captured)["king"]) else 95
    if not bool(_piece(from)["king"]):
        if (side == 2 and dest.x == 7) or (side == 1 and dest.x == 0):
            bonus += 220
    bonus += 8 - absi(dest.y - 3) * 2
    return bonus

func _ai_checkers_search(side: int, plies: int, forced_piece: Vector2i, alpha: int, beta: int) -> int:
    _ai_checkers_nodes += 1
    # A hard limit keeps Legend responsive even with many flying kings.
    if _ai_checkers_nodes > 2400:
        return _ai_checkers_value()
    if plies <= 0 and forced_piece.x < 0:
        return _ai_checkers_value()
    var options: Array[Dictionary] = _ai_checkers_options(side, forced_piece)
    if options.is_empty():
        if forced_piece.x >= 0:
            return _ai_checkers_search(3 - side, plies - 1, Vector2i(-1,-1), alpha, beta)
        return -40000 - plies if side == 2 else 40000 + plies
    options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return _ai_checkers_quick(a, side) > _ai_checkers_quick(b, side)
    )
    var best: int = -60000 if side == 2 else 60000
    var limit: int = mini(options.size(), 12)
    for k in limit:
        var action: Dictionary = options[k]
        var src: Vector2i = action["from"]
        var dst: Vector2i = action["to"]
        var hit: Vector2i = action["taken"]
        var saved_from: Dictionary = _piece(src).duplicate()
        var saved_to: Dictionary = _piece(dst).duplicate()
        var saved_hit: Dictionary = {}
        if hit.x >= 0:
            saved_hit = _piece(hit).duplicate()
            board[hit.x][hit.y] = {"team":0, "king":false}
        board[src.x][src.y] = {"team":0, "king":false}
        board[dst.x][dst.y] = saved_from.duplicate()
        var promoted: bool = not bool(saved_from["king"]) and ((side == 2 and dst.x == 7) or (side == 1 and dst.x == 0))
        if promoted:
            board[dst.x][dst.y]["king"] = true
        var next_forced := Vector2i(-1,-1)
        var next_side: int = 3 - side
        var next_depth: int = plies - 1
        if hit.x >= 0 and not promoted and not _captures(dst).is_empty():
            next_forced = dst
            next_side = side
            next_depth = plies
        var result: int = _ai_checkers_search(next_side, next_depth, next_forced, alpha, beta)
        board[src.x][src.y] = saved_from
        board[dst.x][dst.y] = saved_to
        if hit.x >= 0:
            board[hit.x][hit.y] = saved_hit
        if side == 2:
            best = maxi(best, result)
            alpha = maxi(alpha, best)
        else:
            best = mini(best, result)
            beta = mini(beta, best)
        if beta <= alpha:
            break
    return best

func _ai_choose_checkers_action(options: Array[Dictionary], depth: int) -> Dictionary:
    _ai_checkers_nodes = 0
    var best_action: Dictionary = options[0]
    var best_score: int = -999999
    options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return _ai_checkers_quick(a, 2) > _ai_checkers_quick(b, 2)
    )
    for action in options:
        var src: Vector2i = action["from"]
        var dst: Vector2i = action["to"]
        var hit: Vector2i = action["taken"]
        var saved_from: Dictionary = _piece(src).duplicate()
        var saved_to: Dictionary = _piece(dst).duplicate()
        var saved_hit: Dictionary = {}
        if hit.x >= 0:
            saved_hit = _piece(hit).duplicate()
            board[hit.x][hit.y] = {"team":0, "king":false}
        board[src.x][src.y] = {"team":0, "king":false}
        board[dst.x][dst.y] = saved_from.duplicate()
        var promoted: bool = not bool(saved_from["king"]) and dst.x == 7
        if promoted:
            board[dst.x][dst.y]["king"] = true
        var chain: bool = hit.x >= 0 and not promoted and not _captures(dst).is_empty()
        var score: int = _ai_checkers_search(2 if chain else 1, depth if chain else depth - 1, dst if chain else Vector2i(-1,-1), -60000, 60000)
        board[src.x][src.y] = saved_from
        board[dst.x][dst.y] = saved_to
        if hit.x >= 0:
            board[hit.x][hit.y] = saved_hit
        if score > best_score:
            best_score = score
            best_action = action
    return best_action

func _bot_move() -> void:
    if not is_inside_tree():
        return
    await get_tree().create_timer(0.88).timeout
    if not is_inside_tree():
        return
    bot_pending = false
    if game_mode != 0 or turn != 2 or finished:
        return
    var options: Array[Dictionary] = _ai_checkers_options(2)
    if options.is_empty():
        finished = true
        winning_team = 1
        message = "ПОБЕДИЛИ СИНИЕ!"
        queue_redraw()
        return
    var best: Dictionary
    if bot_difficulty == 0:
        best = options.pick_random()
    else:
        # Experienced: 2-ply; Legend: 4-ply with alpha-beta and capture chains.
        best = _ai_choose_checkers_action(options, 2 if bot_difficulty == 1 else 4)
    var source: Vector2i = best["from"]
    var dest: Vector2i = best["to"]
    var captured: Vector2i = best["taken"]
    var piece_data: Dictionary = _piece(source).duplicate()
    _start_move_fx(source, dest, captured, piece_data)
    board[source.x][source.y] = {"team": 0, "king": false}
    board[dest.x][dest.y] = piece_data
    if captured.x >= 0:
        board[captured.x][captured.y] = {"team": 0, "king": false}
    var promoted: bool = not piece_data["king"] and dest.x == 7
    if promoted:
        piece_data["king"] = true
    if captured.x >= 0 and not promoted and not _captures(dest).is_empty():
        forced = dest
        selected = dest
        _bot_continue.call_deferred()
        queue_redraw()
        return
    turn = 1
    if not _has_move(1):
        finished = true
        winning_team = 2
        message = "ВЫ ПРОИГРАЛИ!"
    else:
        message = "Ход синих"
    queue_redraw()

func _bot_continue() -> void:
    if not is_inside_tree():
        return
    await get_tree().create_timer(0.80).timeout
    if not is_inside_tree() or game_mode != 0 or finished or turn != 2:
        return
    var moves: Array = _captures(forced)
    if moves.is_empty():
        forced = Vector2i(-1, -1)
        selected = Vector2i(-1, -1)
        turn = 1
        message = "Ход синих"
        queue_redraw()
        return
    var move: Dictionary = moves[0]
    if bot_difficulty > 0 and moves.size() > 1:
        var chain_choices: Array[Dictionary] = []
        for item in moves:
            chain_choices.append({"from":forced, "to":item["to"], "taken":item["taken"]})
        var chosen: Dictionary = _ai_choose_checkers_action(chain_choices, 2 if bot_difficulty == 1 else 4)
        move = {"to":chosen["to"], "taken":chosen["taken"]}
    var dest: Vector2i = move["to"]
    var victim: Vector2i = move["taken"]
    var data: Dictionary = _piece(forced).duplicate()
    _start_move_fx(forced, dest, victim, data)
    board[forced.x][forced.y] = {"team": 0, "king": false}
    board[dest.x][dest.y] = data
    board[victim.x][victim.y] = {"team": 0, "king": false}
    var promoted: bool = not data["king"] and dest.x == 7
    if promoted:
        data["king"] = true
    forced = dest
    selected = dest
    if not promoted and not _captures(dest).is_empty():
        _bot_continue.call_deferred()
    else:
        forced = Vector2i(-1, -1)
        selected = Vector2i(-1, -1)
        turn = 1
        message = "Ход синих" if _has_move(1) else "ВЫ ПРОИГРАЛИ!"
        if not _has_move(1):
            finished = true
            winning_team = 2
    queue_redraw()

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

func _draw_victory_panel() -> void:
    var font: Font = ThemeDB.fallback_font
    var panel_width: float = minf(size.x - 26.0, 460.0)
    var panel_height: float = 260.0
    var rect := Rect2(Vector2((size.x - panel_width) * 0.5, (size.y - panel_height) * 0.5), Vector2(panel_width, panel_height))
    draw_rect(Rect2(Vector2.ZERO, size), Color("#03060b", 0.82))
    draw_rect(rect, Color("#181522"))
    draw_rect(rect, Color("#ffcb72"), false, 3.0)
    var blue_won: bool = winning_team == 1
    var heading: String = "ПОЗДРАВЛЯЕМ С ПОБЕДОЙ!" if (game_mode == 1 or blue_won) else "ВЫ ПРОИГРАЛИ!"
    var detail: String = "ПОБЕДИЛИ СИНИЕ" if blue_won else "ПОБЕДИЛИ КРАСНЫЕ"
    draw_string(font, rect.position + Vector2(16, 62), heading, HORIZONTAL_ALIGNMENT_LEFT, panel_width - 32, 22, Color("#ffdc9e"))
    draw_string(font, rect.position + Vector2(16, 104), detail, HORIZONTAL_ALIGNMENT_LEFT, panel_width - 32, 19, Color.WHITE)
    draw_string(font, rect.position + Vector2(16, 145), "Выбери, что делать дальше:", HORIZONTAL_ALIGNMENT_LEFT, panel_width - 32, 15, Color("#d1c5b7"))
    var button_y: float = rect.end.y - 69.0
    var button_w: float = (panel_width - 40.0) * 0.5
    draw_rect(Rect2(rect.position.x + 12.0, button_y, button_w, 49), Color("#235369"))
    draw_rect(Rect2(rect.position.x + 28.0 + button_w, button_y, button_w, 49), Color("#885027"))
    draw_string(font, Vector2(rect.position.x + 19.0, button_y + 31.0), "ИГРАТЬ ЕЩЁ", HORIZONTAL_ALIGNMENT_LEFT, button_w - 12, 14, Color.WHITE)
    draw_string(font, Vector2(rect.position.x + 35.0 + button_w, button_y + 31.0), "ГЛАВНОЕ МЕНЮ", HORIZONTAL_ALIGNMENT_LEFT, button_w - 12, 13, Color.WHITE)

func _victory_tap(pos: Vector2) -> void:
    var panel_width: float = minf(size.x - 26.0, 460.0)
    var panel_height: float = 260.0
    var rect := Rect2(Vector2((size.x - panel_width) * 0.5, (size.y - panel_height) * 0.5), Vector2(panel_width, panel_height))
    if pos.y >= rect.end.y - 69.0 and pos.y <= rect.end.y - 20.0:
        if pos.x >= size.x * 0.5:
            _go_to_main_menu()
        else:
            _new_game()
