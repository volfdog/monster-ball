extends Control

# Explicit dependency: the exported Godot Web build must include this recording.
const HD_STADIUM: AudioStream = preload("res://audio/stadium_crowd.mp3")

const ROWS := 10
const COLS := 8
const FOOTBALL_TEAM_SIZE := 5
const BLUE := Color("#4ac5e8")
const RED := Color("#e45a78")
const BALL := Color("#f6cf65")

var pieces: Array[Dictionary] = []
var ball_cell := Vector2i(4, 4)
# A free ball spawns in the center two rows, on reachable diagonal squares.
var ball_holder := -1
var turn := 1
var selected := -1
var scores := [0, 0]
var message := "Ход голубых"
var game_mode := 0 # 0 = bot, 1 = two players
var bot_difficulty: int = 1

# PRE-MATCH TACTICAL SETUP. Only 3 ranks nearest each team's own goal are
# available. Every new token MUST diagonally touch an existing friendly token.
# The finished formations are reused at every kickoff during the same match.
var setup_active: bool = false
var setup_team: int = 1
var setup_blue: Array[Vector2i] = []
var setup_red: Array[Vector2i] = []
var setup_tip: String = ""
const SETUP_TIME_LIMIT: float = 30.0
var setup_time_remaining: float = SETUP_TIME_LIMIT
var game_over := false
var bot_pending := false
var winner := 0

# Football 3.1: two REAL-TIME halves and a separate anti-stalling decision clock.
const HALF_SECONDS: int = 180
# The final 30 seconds are action-based: waiting cannot run out the match clock.
const FINAL_PHASE_SECONDS: float = 30.0
const FINAL_PHASE_ACTION_COST: float = 3.0
const FINAL_PHASE_ACTIONS: int = 10
const DECISION_SECONDS: float = 20.0
const HALF_BREAK_SECONDS: float = 7.0
const COIN_SECONDS: float = 2.8
var half_number: int = 1
var half_remaining: float = float(HALF_SECONDS)
var final_phase_active: bool = false
var final_actions_remaining: int = FINAL_PHASE_ACTIONS
# Monster Score: actual goals are worth 5; each eliminated rival is worth 1.
# Every capture is counted as it happens, including the final fifth player.
var match_goals := [0, 0]
var match_captures := [0, 0]
var match_blocks := [0, 0]
var boundary_resolved_half: int = 0
var first_kickoff_team: int = 1
var active_kickoff_team: int = 1
var decision_remaining: float = DECISION_SECONDS
var coin_remaining: float = 0.0
var halftime_remaining: float = 0.0
var opening_second_half: float = 0.0
var paused_match: bool = false
var phase_after_goal: bool = false
var consecutive_passes: int = 0
var last_pass_sender: int = -1
var pass_side: int = 0
var ball_wiggle: float = 0.0
var referee_warning: bool = false
var kickoff_whistle_pending: bool = false
var halftime_player: AudioStreamPlayer
var halftime_jingle_delay: float = 0.0

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
var crowd_ambience: AudioStreamPlayer
var game_audio_unlocked: bool = false
var background_audio_poll: float = 0.0

func _setup_game_audio() -> void:
    for sound_name in ["stone_move", "king_move", "capture", "pass", "goal", "crowd", "victory", "arena_ambience", "time_warning", "whistle_halftime", "whistle_fulltime"]:
        var audio_path: String = "res://audio/%s.wav" % sound_name
        if ResourceLoader.exists(audio_path):
            sound_library[sound_name] = load(audio_path)
    # Optional professionally-recorded guitar and sinister laughter (MP3/OGG/WAV).
    # Missing files must never prevent Godot from starting the game.
    for effect_name in ["king_laugh", "king_guitar", "match_guitar_final"]:
        for extension in ["mp3", "ogg", "wav"]:
            var effect_path: String = "res://audio/%s.%s" % [effect_name, extension]
            if ResourceLoader.exists(effect_path):
                sound_library[effect_name] = load(effect_path)
                break
    # Prefer real, long field recordings if available. Keep existing effects intact.
    for track_name in ["stadium_crowd", "arena_ambience", "goal_crowd"]:
        for extension in ["ogg", "mp3"]:
            var alternate: String = "res://audio/%s.%s" % [track_name, extension]
            if ResourceLoader.exists(alternate):
                sound_library[track_name] = load(alternate)
                break
    # Never use the short/synthetic background: force the long WAV stadium recording.
    sound_library["stadium_crowd"] = HD_STADIUM
    arena_music = AudioStreamPlayer.new()
    arena_music.name = "HalloweenAmbience"
    add_child(arena_music)
    # Old synthetic arena_ambience is deliberately silent in the HD mix;
    # the stadium player below provides the single continuous match background.

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
    halftime_player = AudioStreamPlayer.new()
    halftime_player.name = "HalftimeJingle"
    add_child(halftime_player)
    if ResourceLoader.exists("res://audio/halftime_jingle.mp3"):
        halftime_player.stream = load("res://audio/halftime_jingle.mp3")
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
    if halftime_player != null:
        halftime_player.volume_db = linear_to_db(maxf(0.001, music_volume * 0.78))
        if muted or music_volume <= 0.005:
            halftime_player.stop()
    if crowd_ambience != null:
        # The original crowd WAV is quiet; do not attenuate it again.
        var crowd_balance: float = 0.53 if sound_library.has("stadium_crowd") else 1.10
        crowd_ambience.volume_db = linear_to_db(maxf(0.001, crowd_volume * crowd_balance * (0.33 if halftime_remaining > 0.0 else 1.0)))
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
    if kickoff_whistle_pending:
        kickoff_whistle_pending = false
        _play_sfx("whistle_halftime")

func _start_kickoff_whistle() -> void:
    # A whistle for the start of each half; delay until touch if iOS audio is locked.
    if game_audio_unlocked:
        _play_sfx("whistle_halftime")
    else:
        kickoff_whistle_pending = true

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
    # A complete pause freezes all match, celebration, transition and animation timers.
    if paused_match:
        return
    # Each human team gets its own 30-second pre-match placement window.
    # Match time and the 20-second decision timer remain frozen during setup.
    if setup_active and not customization_open:
        setup_time_remaining = maxf(0.0, setup_time_remaining - delta)
        if setup_time_remaining <= 0.0:
            _setup_auto_complete()
        queue_redraw()
    # First 2:30: real-time clock. The final 0:30 FREEZES while thinking,
    # then each completed team action costs 3 seconds. A 20-second timeout
    # forces an action, so a leading team cannot wait out the final seconds.
    # Neither clock runs during intermissions, celebrations, customization or pause.
    if not paused_match and not game_over and not celebrating and coin_remaining <= 0.0 and halftime_remaining <= 0.0 and opening_second_half <= 0.0 and not customization_open and pending_skin < 0 and not setup_active and not _capture_motion_active():
        if not final_phase_active:
            half_remaining = maxf(FINAL_PHASE_SECONDS, half_remaining - delta)
            if half_remaining <= FINAL_PHASE_SECONDS:
                _begin_final_phase()
        # In final phase, the main clock never uses delta: only completed turns
        # count down, explicitly tracked by final_actions_remaining.
        queue_redraw()
    # Intermission and intro animations are real-time but do not spend match time.
    if coin_remaining > 0.0:
        coin_remaining = maxf(0.0, coin_remaining - delta)
        if coin_remaining <= 0.0:
            _start_kickoff_whistle()
            _schedule_bot()
        queue_redraw()
    elif halftime_remaining > 0.0:
        if halftime_jingle_delay > 0.0:
            halftime_jingle_delay = maxf(0.0, halftime_jingle_delay - delta)
            if halftime_jingle_delay <= 0.0 and halftime_player != null and halftime_player.stream != null:
                var muted: bool = bool(get_tree().root.get_meta("mb_muted", false))
                if not muted and float(get_tree().root.get_meta("mb_vol_music", 0.55)) > 0.005:
                    halftime_player.play()
        halftime_remaining = maxf(0.0, halftime_remaining - delta)
        if halftime_remaining <= 0.0:
            _begin_second_half()
        queue_redraw()
    elif opening_second_half > 0.0:
        opening_second_half = maxf(0.0, opening_second_half - delta)
        if opening_second_half <= 0.0:
            _start_kickoff_whistle()
            _schedule_bot()
        queue_redraw()
    if celebrating and not _capture_motion_active():
        celebration_time = maxf(0.0, celebration_time - delta)
        if celebration_time <= 0.0:
            celebrating = false
            if phase_after_goal:
                phase_after_goal = false
                _resolve_half_boundary()
            elif not game_over:
                var completed_reason: String = celebration_reason
                _reset_board(3 - celebration_team)
                message = "%s  %d : %d" % [completed_reason, scores[0], scores[1]]
                _schedule_bot()
        queue_redraw()
    if not paused_match and not game_over and not celebrating and coin_remaining <= 0.0 and halftime_remaining <= 0.0 and opening_second_half <= 0.0 and not customization_open and not setup_active and not bot_pending and not _capture_motion_active() and (game_mode == 1 or turn == 1):
        decision_remaining = maxf(0.0, decision_remaining - delta)
        referee_warning = decision_remaining <= 5.0
        if decision_remaining <= 0.0:
            _auto_human_action()
        queue_redraw()
    if ball_wiggle > 0.0:
        ball_wiggle = maxf(0.0, ball_wiggle - delta)
        queue_redraw()
    magic_clock += delta
    if fmod(magic_clock, 0.11) < delta: queue_redraw()
    if fx_progress < 1.0:
        fx_progress = minf(1.0, fx_progress + delta / fx_duration)
        queue_redraw()
    if fx_impact_time > 0.0:
        fx_impact_time = maxf(0.0, fx_impact_time - delta)
        if fx_impact_time <= 0.0:
            fx_victim_index = -1
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
        var mb_save: Dictionary = _mb_read_profile()
        mb_save["football_skins"] = piece_skins.duplicate()
        _mb_write_profile(mb_save)
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
                    if carried_piece >= 0 and fx_piece == carried_piece and fx_to == target and fx_progress < 1.0 and fx_victim_index < 0:
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
    return not setup_active and not paused_match and coin_remaining <= 0.0 and halftime_remaining <= 0.0 and opening_second_half <= 0.0 and not celebrating and not customization_open and pending_skin < 0 and not game_over and not bot_pending and (game_mode != 0 or turn == 1)

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
# A captured monster should still be visible while the attacker jumps over it.
var fx_victim_index: int = -1
var fx_victim_cell: Vector2i = Vector2i(-1, -1)
var capture_sequence_running: bool = false

func _capture_motion_active() -> bool:
    return capture_sequence_running or (fx_victim_index >= 0 and fx_progress < 0.99)

func _wait_for_current_jump() -> void:
    # Also waits for a PAUSED game; no new step replaces the previous frame.
    while is_inside_tree() and (paused_match or fx_progress < 0.99):
        await get_tree().process_frame

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

func _start_hit_fx(victim_index: int) -> void:
    # The rules may remove the victim immediately, but its last image remains
    # until the jumping monster reaches the captured square.
    if victim_index < 0 or victim_index >= pieces.size():
        return
    _play_sfx("capture")
    fx_victim_index = victim_index
    fx_victim_cell = pieces[victim_index]["cell"]
    fx_impact = fx_victim_cell
    fx_impact_time = 0.68

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
        var t: float = 1.0 - fx_impact_time / 0.68
        if fx_victim_index >= 0 and fx_victim_index < pieces.size():
            # Victim remains solid until the attack reaches its square, then
            # dissolves in a glow rather than popping off the board instantly.
            var alpha: float = 1.0 - smoothstep(0.38, 0.79, t)
            if alpha > 0.01:
                var victim_team: int = int(pieces[fx_victim_index]["team"])
                var victim_key: String = BLUE_SKINS[piece_skins[fx_victim_index]] if victim_team == 1 else RED_SKINS[piece_skins[fx_victim_index]]
                var victim_size: float = side * 0.93 * (1.0 - 0.23 * t)
                if fantasy_textures.has(victim_key):
                    draw_texture_rect(fantasy_textures[victim_key], Rect2(center - Vector2.ONE * victim_size * 0.5, Vector2.ONE * victim_size), false, Color(1, 1, 1, alpha))
                else:
                    draw_circle(center, victim_size * 0.38, Color(0.18, 0.7, 0.92, alpha) if victim_team == 1 else Color(0.91, 0.27, 0.29, alpha))
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

func _credit_capture(team_id: int) -> void:
    # Called ONLY on real moves, never from the AI's speculative search.
    if celebrating or game_over:
        return
    scores[team_id - 1] += 1
    match_captures[team_id - 1] += 1

func _end_round(team_id: int, reason: String, goal_scored: bool = false, spend_clock: bool = true) -> void:
    if celebrating or game_over:
        return
    # A goal scores +5, but eliminating all five earns precisely the five
    # capture points already awarded. There is NO bonus on round completion.
    if goal_scored:
        scores[team_id - 1] += 5
        match_goals[team_id - 1] += 1
    celebrating = true
    celebration_team = team_id
    celebration_reason = reason
    celebration_final = false
    celebration_duration = 3.2
    celebration_time = celebration_duration
    selected = -1
    bot_pending = false
    message = "%s  %d : %d" % [reason, scores[0], scores[1]]
    if spend_clock:
        _complete_action_clock()
    _play_sfx("goal" if goal_scored else "capture")
    _play_sfx("crowd", "crowd")
    queue_redraw()

func _check_elimination() -> bool:
    if _living(1) == 0:
        _end_round(2, "ВСЕ СИНИЕ ФИШКИ УНИЧТОЖЕНЫ!")
        return true
    if _living(2) == 0:
        _end_round(1, "ВСЕ КРАСНЫЕ ФИШКИ УНИЧТОЖЕНЫ!")
        return true
    return false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    _setup_game_audio()
    if ResourceLoader.exists("res://assets/game_font.ttf"):
        fancy_font = load("res://assets/game_font.ttf")
    _load_fantasy_assets()
    first_kickoff_team = randi_range(1, 2)
    half_number = 1
    half_remaining = float(HALF_SECONDS)
    final_phase_active = false
    final_actions_remaining = FINAL_PHASE_ACTIONS
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
    _start_setup()

func _setup_cells(team_id: int) -> Array[Vector2i]:
    return setup_blue if team_id == 1 else setup_red

func _setup_allowed(cell: Vector2i, team_id: int) -> bool:
    if not _inside(cell) or (cell.x + cell.y) % 2 != 0 or _piece_at(cell) >= 0:
        return false
    # At most 3 rows from our own back line; no jump toward midfield.
    if team_id == 1 and (cell.x < ROWS - 3 or cell.x >= ROWS):
        return false
    if team_id == 2 and (cell.x < 0 or cell.x > 2):
        return false
    var formation: Array[Vector2i] = _setup_cells(team_id)
    # The very first piece must anchor the formation on its back rank.
    if formation.is_empty():
        return cell.x == (ROWS - 1 if team_id == 1 else 0)
    # Every next piece touches another friendly piece on a playable diagonal.
    for existing in formation:
        if absi(cell.x - existing.x) == 1 and absi(cell.y - existing.y) == 1:
            return true
    return false

func _setup_add(cell: Vector2i) -> void:
    var formation: Array[Vector2i] = _setup_cells(setup_team)
    if formation.size() >= FOOTBALL_TEAM_SIZE or not _setup_allowed(cell, setup_team):
        setup_tip = "КЛЕТКА НЕДОСТУПНА: ставь вплотную по диагонали"
        queue_redraw()
        return
    formation.append(cell)
    pieces.append({"team": setup_team, "cell": cell, "alive": true})
    setup_tip = "ФИШКИ: %d/%d" % [formation.size(), FOOTBALL_TEAM_SIZE]
    _play_sfx("menu_click")
    queue_redraw()

func _setup_undo() -> void:
    var formation: Array[Vector2i] = _setup_cells(setup_team)
    if formation.is_empty():
        setup_tip = "ЕЩЁ НЕТ ПОСТАВЛЕННЫХ ФИШЕК"
        queue_redraw()
        return
    formation.pop_back()
    # Pieces are appended in the order the user places them.
    pieces.pop_back()
    setup_tip = "ПОСЛЕДНЯЯ ФИШКА УБРАНА"
    queue_redraw()

func _setup_bot() -> void:
    # Bot builds a valid tight cluster rather than using the old fixed 4+1.
    for candidate_round in 12:
        setup_red.clear()
        var candidate: Array[Vector2i] = []
        for column in range(0, COLS, 2):
            candidate.append(Vector2i(0, column))
        candidate.shuffle()
        if candidate.is_empty():
            break
        setup_red.append(candidate[0])
        while setup_red.size() < FOOTBALL_TEAM_SIZE:
            var allowed: Array[Vector2i] = []
            for row in 3:
                for col in COLS:
                    var cell := Vector2i(row, col)
                    if setup_red.has(cell) or (row + col) % 2 != 0:
                        continue
                    for other in setup_red:
                        if absi(cell.x - other.x) == 1 and absi(cell.y - other.y) == 1:
                            allowed.append(cell)
                            break
            if allowed.is_empty():
                break
            setup_red.append(allowed.pick_random())
        if setup_red.size() == FOOTBALL_TEAM_SIZE:
            break
    if setup_red.size() != FOOTBALL_TEAM_SIZE:
        # Safety net: connected staggered formation, all on playable squares.
        setup_red.clear()
        setup_red.append_array([Vector2i(0, 2), Vector2i(1, 3), Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 4)])
    for cell in setup_red:
        pieces.append({"team": 2, "cell": cell, "alive": true})

func _setup_auto_complete() -> void:
    # Time ran out: keep all already-placed pieces and legally add the missing ones.
    # Every placement is on an active square of the team's three home ranks,
    # diagonally adjacent to at least one existing friendly piece.
    while _setup_cells(setup_team).size() < FOOTBALL_TEAM_SIZE:
        var available: Array[Vector2i] = []
        var first_row: int = ROWS - 3 if setup_team == 1 else 0
        for row in range(first_row, first_row + 3):
            for col in COLS:
                var cell := Vector2i(row, col)
                if _setup_allowed(cell, setup_team):
                    available.append(cell)
        if available.is_empty():
            # Defensive stop rather than creating an illegal piece.
            setup_tip = "НЕТ ДОПУСТИМЫХ КЛЕТОК — ИСПРАВЬ РАССТАНОВКУ"
            queue_redraw()
            return
        var chosen: Vector2i = available.pick_random()
        _setup_cells(setup_team).append(chosen)
        pieces.append({"team": setup_team, "cell": chosen, "alive": true})
    setup_tip = "ВРЕМЯ ВЫШЛО: РАССТАНОВКА ЗАВЕРШЕНА"
    _setup_confirm()

func _setup_confirm() -> void:
    var formation: Array[Vector2i] = _setup_cells(setup_team)
    if formation.size() < FOOTBALL_TEAM_SIZE:
        setup_tip = "НУЖНО ПОСТАВИТЬ ВСЕ ПЯТЬ ФИШЕК"
        queue_redraw()
        return
    if setup_team == 1:
        setup_team = 2
        setup_time_remaining = SETUP_TIME_LIMIT  # Fresh 30 seconds for red friend.
        setup_tip = "КРАСНЫЕ: расставьте свою пятёрку"
        if game_mode == 0:
            _setup_bot()
            _setup_finalize()
        else:
            queue_redraw()
    else:
        _setup_finalize()

func _setup_finalize() -> void:
    # The coin toss follows both formations; the ball stays unclaimed.
    setup_active = false
    first_kickoff_team = randi_range(1, 2)
    _reset_board(first_kickoff_team)
    coin_remaining = COIN_SECONDS
    message = "ЖЕРЕБЬЁВКА — КТО ПЕРВЫМ ИДЁТ К МЯЧУ?"
    queue_redraw()

func _start_setup() -> void:
    # New match = new formation; goal and halftime = restore the same formation.
    setup_active = true
    setup_team = 1
    setup_time_remaining = SETUP_TIME_LIMIT
    setup_blue.clear()
    setup_red.clear()
    pieces.clear()
    ball_holder = -1
    ball_cell = Vector2i(4, 4)
    selected = -1
    paused_match = false
    coin_remaining = 0.0
    opening_second_half = 0.0
    halftime_remaining = 0.0
    celebrating = false
    drag_active = false
    bot_pending = false
    decision_remaining = DECISION_SECONDS
    setup_tip = "СИНИЕ: начни с заднего ряда"
    message = "РАССТАНОВКА ПЕРЕД МАТЧЕМ"
    queue_redraw()

func _setup_input(point: Vector2) -> void:
    if point.y > size.y - 82.0:
        if point.x < size.x * 0.5:
            _setup_undo()
        else:
            _setup_confirm()
        return
    var cell: Vector2i = _drag_point_to_cell(point)
    if _inside(cell):
        _setup_add(cell)

func _draw_setup_help(offset: Vector2, side: float, font: Font) -> void:
    # Highlight the three home ranks and the next admissible diagonal squares.
    var row_start: int = ROWS - 3 if setup_team == 1 else 0
    var stripe_color: Color = Color("#338cd1", 0.15) if setup_team == 1 else Color("#d4526c", 0.15)
    for row in range(row_start, row_start + 3):
        draw_rect(Rect2(offset + Vector2(0, row * side), Vector2(COLS * side, side)), stripe_color)
    for row in range(row_start, row_start + 3):
        for col in COLS:
            var cell: Vector2i = Vector2i(row, col)
            if _setup_allowed(cell, setup_team):
                var center: Vector2 = offset + Vector2(col + 0.5, row + 0.5) * side
                draw_circle(center, maxf(3.0, side * 0.11), Color("#b8ffb1", 0.92))
                draw_arc(center, side * 0.29, 0.0, TAU, 32, Color("#89f8bd", 0.6), 1.7)
    # Large countdown is visible for the active side only. Each friend gets 30s.
    var panel := Rect2(9.0, 35.0, size.x - 18.0, 137.0)
    draw_rect(panel, Color("#111426", 0.96))
    draw_rect(panel, Color("#55d5ff") if setup_team == 1 else Color("#ff7b8e"), false, 2.0)
    var heading: String = "СИНИЕ — РАССТАНОВКА" if setup_team == 1 else "КРАСНЫЕ — РАССТАНОВКА"
    draw_string(font, Vector2(panel.position.x + 8.0, 57.0), heading, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x - 16.0, 20, Color("#ffde9d"))
    var countdown_color: Color = Color("#ff6c69") if setup_time_remaining <= 5.0 else Color("#f8f6df")
    draw_string(font, Vector2(panel.position.x + 8.0, 100.0), "00:%02d" % maxi(0, ceili(setup_time_remaining)), HORIZONTAL_ALIGNMENT_CENTER, panel.size.x - 16.0, 36, countdown_color)
    draw_string(font, Vector2(panel.position.x + 8.0, 121.0), "ПОСТАВЛЕНО: %d/5" % _setup_cells(setup_team).size(), HORIZONTAL_ALIGNMENT_CENTER, panel.size.x - 16.0, 16, Color.WHITE)
    draw_string(font, Vector2(panel.position.x + 8.0, 140.0), "3 своих ряда · фишки вплотную по диагонали", HORIZONTAL_ALIGNMENT_CENTER, panel.size.x - 16.0, 12, Color("#cce3eb"))
    draw_string(font, Vector2(panel.position.x + 8.0, 161.0), setup_tip, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x - 16.0, 12, Color("#f7d293"))

func _reset_board(kickoff_team: int = 1) -> void:
    celebrating = false
    celebration_time = 0.0
    active_kickoff_team = kickoff_team
    consecutive_passes = 0
    last_pass_sender = -1
    pass_side = 0
    paused_match = false
    if halftime_player != null:
        halftime_player.stop()
    decision_remaining = DECISION_SECONDS
    referee_warning = false
    pieces.clear()
    fx_progress = 1.0
    capture_sequence_running = false
    fx_victim_index = -1
    fx_impact_time = 0.0
    fx_impact_time = 0.0
    pass_fx_progress = 1.0
    # Restore each side's chosen compact setup after every goal and at halftime.
    for cell in setup_blue:
        pieces.append({"team": 1, "cell": cell, "alive": true})
    for cell in setup_red:
        pieces.append({"team": 2, "cell": cell, "alive": true})
    # The coin awards the FIRST MOVE, never immediate possession.
    # Choose one of the 8 playable central squares (even row+column parity).
    # Both teams must travel to the unclaimed pumpkin to pick it up.
    _spawn_free_ball_center()
    selected = -1
    turn = kickoff_team
    bot_pending = false
    message = "СИНИЕ ПЕРВЫМИ ИДУТ К МЯЧУ!" if kickoff_team == 1 else "КРАСНЫЕ ПЕРВЫМИ ИДУТ К МЯЧУ!"
    queue_redraw()

func _spawn_free_ball_center() -> void:
    ball_holder = -1
    var candidates: Array[Vector2i] = []
    for center_row in [4, 5]:
        for column in COLS:
            var candidate := Vector2i(center_row, column)
            # All our players remain on even parity squares after diagonal moves.
            if (center_row + column) % 2 == 0 and _piece_at(candidate) < 0:
                candidates.append(candidate)
    if candidates.is_empty():
        # Should not occur with the normal starting formation.
        ball_cell = Vector2i(4, 4)
    else:
        ball_cell = candidates.pick_random()

# === Monster Ball 3.1 match director ===
func _new_match() -> void:
    halftime_jingle_delay = 0.0
    mb_profile_counted = false
    scores = [0, 0]
    winner = 0
    game_over = false
    phase_after_goal = false
    boundary_resolved_half = 0
    match_goals = [0, 0]
    match_captures = [0, 0]
    match_blocks = [0, 0]
    half_number = 1
    half_remaining = float(HALF_SECONDS)
    final_phase_active = false
    final_actions_remaining = FINAL_PHASE_ACTIONS
    _start_setup()

func _begin_final_phase() -> void:
    # One transition per half. IMPORTANT: arriving at 00:30 never ends a half.
    if final_phase_active or game_over or boundary_resolved_half == half_number:
        return
    final_phase_active = true
    final_actions_remaining = FINAL_PHASE_ACTIONS
    half_remaining = FINAL_PHASE_SECONDS
    message = "30 СЕКУНД! РЕШАЮЩАЯ ФАЗА — 10 ХОДОВ!"
    _play_sfx("time_warning")
    queue_redraw()

func _complete_action_clock() -> bool:
    # Count one COMPLETED turn/pass, not frames or jumps within a capture chain.
    # Only 10 real actions after 00:30 can finish the half.
    decision_remaining = DECISION_SECONDS
    referee_warning = false
    if game_over or boundary_resolved_half == half_number:
        return true
    if half_remaining <= FINAL_PHASE_SECONDS and not final_phase_active:
        _begin_final_phase()
    if not final_phase_active:
        return false
    if final_actions_remaining <= 0:
        return true
    final_actions_remaining -= 1
    half_remaining = float(final_actions_remaining) * FINAL_PHASE_ACTION_COST
    queue_redraw()
    if final_actions_remaining == 0:
        # Let goals/eliminations celebrate before halftime or match end.
        if celebrating:
            phase_after_goal = true
        else:
            _resolve_half_boundary()
        return true
    return false

func _resolve_half_boundary() -> void:
    # An explicit safety gate: 00:30 alone can NEVER cause a whistle.
    if boundary_resolved_half == half_number:
        return
    if not final_phase_active or final_actions_remaining > 0:
        return
    boundary_resolved_half = half_number

    # Avoid carrying a drag or a scheduled bot move across the whistle.
    selected = -1
    drag_active = false
    drag_moved = false
    drag_input_touch = false
    bot_pending = false
    if half_number == 1:
        halftime_remaining = HALF_BREAK_SECONDS
        halftime_jingle_delay = 1.20
        _play_sfx("whistle_halftime")
        selected = -1
        bot_pending = false
        message = "ПЕРЕРЫВ!  %d : %d" % [scores[0], scores[1]]
    else:
        _finish_match()
    queue_redraw()

func _begin_second_half() -> void:
    halftime_jingle_delay = 0.0
    half_number = 2
    half_remaining = float(HALF_SECONDS)
    final_phase_active = false
    final_actions_remaining = FINAL_PHASE_ACTIONS
    _reset_board(3 - first_kickoff_team)
    opening_second_half = 2.0
    message = "2-Й ТАЙМ! ПЕРВЫЙ ХОД СИНИХ" if turn == 1 else "2-Й ТАЙМ! ПЕРВЫЙ ХОД КРАСНЫХ"
    queue_redraw()

func _finish_match() -> void:
    _play_sfx("whistle_fulltime")
    # Longer recorded electric-guitar ending; keep existing victory cue as fallback.
    if sound_library.has("match_guitar_final"):
        _play_sfx("match_guitar_final")
    game_over = true
    bot_pending = false
    selected = -1
    winner = 1 if scores[0] > scores[1] else (2 if scores[1] > scores[0] else 0)
    _mb_record_finished("football", winner)
    message = "КОНЕЦ МАТЧА — НИЧЬЯ!" if winner == 0 else "ФИНАЛЬНЫЙ СВИСТОК!"
    if winner != 0:
        celebrating = true
        celebration_time = 3.6
        celebration_duration = 3.6
        celebration_final = true
        celebration_team = winner
        if not sound_library.has("match_guitar_final"):
            _play_sfx("victory")
        _play_sfx("crowd", "crowd")
    queue_redraw()

func _auto_human_action() -> void:
    if bot_pending or celebrating or game_over or paused_match:
        return
    drag_active = false
    drag_moved = false
    drag_input_touch = false
    drag_origin = Vector2i(-1, -1)
    var options: Array[Dictionary] = _fb_ai_choices(turn)
    if options.is_empty():
        _end_round(3 - turn, "СУДЬЯ: НЕТ ДОПУСТИМЫХ ХОДОВ!")
        return
    # Timeout never gives free ball possession; it selects a legal action.
    var action: Dictionary = options[0]
    for candidate in options:
        if not candidate.has("pass_to"):
            action = candidate
            break
    selected = int(action["piece"])
    capture_sequence_running = not action.has("pass_to") and int(action.get("victim", -1)) >= 0
    if action.has("pass_to"):
        _pass_ball(int(action["pass_to"]))
        return
    if int(action["victim"]) >= 0:
        var victim: int = int(action["victim"])
        pieces[victim]["alive"] = false
        _credit_capture(turn)
        _start_hit_fx(victim)
        if ball_holder == victim:
            ball_holder = selected
    _move_selected(action["to"])
    if capture_sequence_running:
        await _wait_for_current_jump()
    if not is_inside_tree():
        return
    if _check_elimination() or _check_goal():
        capture_sequence_running = false
        return
    if int(action["victim"]) >= 0:
        for n in FOOTBALL_TEAM_SIZE:
            var chain: Array = _captures(selected)
            if chain.is_empty():
                break
            var nxt: Dictionary = chain[0]
            var victim_index: int = int(nxt["victim"])
            pieces[victim_index]["alive"] = false
            _credit_capture(turn)
            _start_hit_fx(victim_index)
            if ball_holder == victim_index:
                ball_holder = selected
            _move_selected(nxt["cell"])
            await _wait_for_current_jump()
            if not is_inside_tree():
                return
            if _check_elimination() or _check_goal():
                capture_sequence_running = false
                return
    capture_sequence_running = false
    _finish_turn()

func _draw_referee(at: Vector2, sc: float) -> void:
    # On-pitch judge sprite drawn in the arena margin: never occupies a board square.
    var shadow: Color = Color("#16131e")
    draw_circle(at + Vector2(0, -18) * sc, 12.0 * sc, Color("#e9e4db"))
    draw_rect(Rect2(at + Vector2(-8,-15) * sc, Vector2(16,25) * sc), shadow)
    for stripe in 3:
        draw_rect(Rect2(at + Vector2((-6 + stripe * 5), -13) * sc, Vector2(2,22) * sc), Color("#f5f2dd"))
    draw_circle(at + Vector2(-4,-19) * sc, 2.4 * sc, Color("#ff9d40"))
    draw_circle(at + Vector2(4,-19) * sc, 2.4 * sc, Color("#ff9d40"))
    draw_line(at + Vector2(-8, -2) * sc, at + Vector2(-16, 11) * sc, Color("#e9e4db"), 3.0 * sc)
    draw_line(at + Vector2(8, -2) * sc, at + Vector2(15, 9) * sc, Color("#e9e4db"), 3.0 * sc)
    draw_line(at + Vector2(-4,10) * sc, at + Vector2(-7,21) * sc, Color("#e9e4db"), 3.0 * sc)
    draw_line(at + Vector2(4,10) * sc, at + Vector2(7,21) * sc, Color("#e9e4db"), 3.0 * sc)
    if referee_warning:
        draw_rect(Rect2(at + Vector2(-24,-48) * sc, Vector2(13,18) * sc), Color("#ffdd45"))
        draw_string(ThemeDB.fallback_font, at + Vector2(-155, -39), "СУДЬЯ: ХОДИ!", HORIZONTAL_ALIGNMENT_LEFT, 145, 13, Color("#ffdd63"))

func _draw_coin_toss() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0919", 0.80))
    var t: float = 1.0 - coin_remaining / COIN_SECONDS
    var cx: Vector2 = size * 0.5 + Vector2(0, -30 - sin(t * PI) * 50.0)
    var squash: float = maxf(0.16, absf(cos(t * PI * 6.0))) if t < 0.72 else 1.0
    var tone: Color = Color("#42d9ff") if first_kickoff_team == 1 else Color("#fa526c")
    draw_circle(cx, 78.0, Color(tone.r, tone.g, tone.b, 0.10 + 0.25 * t))
    draw_colored_polygon(PackedVector2Array([cx + Vector2(-48*squash,-48), cx + Vector2(48*squash,-48), cx + Vector2(48*squash,48), cx + Vector2(-48*squash,48)]), Color("#4b3421"))
    draw_ellipse_31(cx, Vector2(46.0 * squash, 46.0), Color("#d8a64e"))
    draw_ellipse_31(cx, Vector2(39.0 * squash, 39.0), Color("#88612e"))
    if t > 0.72:
        _magic_ring(cx, 58.0, tone, true)
    _draw_referee(cx + Vector2(0, 120), 1.25)
    var font: Font = ThemeDB.fallback_font
    draw_string(font, Vector2(16.0, size.y * 0.32), "ЖЕРЕБЬЁВКА MONSTER BALL", HORIZONTAL_ALIGNMENT_CENTER, size.x - 32.0, 24, Color("#ffe2a5"))
    draw_string(font, Vector2(16.0, size.y * 0.66), "СИНИЕ — ПЕРВЫЙ ХОД!" if first_kickoff_team == 1 else "КРАСНЫЕ — ПЕРВЫЙ ХОД!", HORIZONTAL_ALIGNMENT_CENTER, size.x - 32.0, 21, tone)
    draw_string(font, Vector2(16.0, size.y * 0.71), "МЯЧ СВОБОДЕН — В ЦЕНТРЕ ПОЛЯ", HORIZONTAL_ALIGNMENT_CENTER, size.x - 32.0, 14, Color("#fff2cb"))

func draw_ellipse_31(center: Vector2, axes: Vector2, fill_color: Color) -> void:
    var outline: PackedVector2Array = PackedVector2Array()
    for k in 32:
        var theta: float = float(k) * TAU / 32.0
        outline.append(center + Vector2(cos(theta) * axes.x, sin(theta) * axes.y))
    draw_colored_polygon(outline, fill_color)

func _draw_halftime_show() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0919", 0.88))
    var font: Font = ThemeDB.fallback_font
    draw_string(font, Vector2(10, size.y * 0.22), "ПЕРЕРЫВ — ШОУ МОНСТРОВ!", HORIZONTAL_ALIGNMENT_CENTER, size.x - 20, 25, Color("#ffe19b"))
    draw_string(font, Vector2(10, size.y * 0.31), "СЧЁТ  %d : %d" % [scores[0], scores[1]], HORIZONTAL_ALIGNMENT_CENTER, size.x - 20, 26, Color.WHITE)
    draw_string(font, Vector2(10, size.y * 0.36), "ГОЛЫ  %d:%d   •   ВЗЯТИЯ  %d:%d" % [match_goals[0], match_goals[1], match_captures[0], match_captures[1]], HORIZONTAL_ALIGNMENT_CENTER, size.x - 20, 16, Color("#cde7eb"))
    draw_string(font, Vector2(10, size.y * 0.41), "БЛОКИРОВКИ  %d:%d  •  БОНУСОВ НЕТ" % [match_blocks[0], match_blocks[1]], HORIZONTAL_ALIGNMENT_CENTER, size.x - 20, 15, Color("#ffe09b"))
    for i in 5:
        var xx: float = (float(i) + 0.65) * size.x / 5.5
        var yy: float = size.y * 0.54 + sin(magic_clock * (3.0 + i * 0.15) + i) * 19.0
        _draw_halloween_spectator(i, Vector2(xx, yy), 1.40, float(i))
    draw_string(font, Vector2(10, size.y * 0.78), "ВТОРОЙ ТАЙМ ЧЕРЕЗ %d" % ceili(halftime_remaining), HORIZONTAL_ALIGNMENT_CENTER, size.x - 20.0, 20, Color("#ffd487"))

func _draw_second_half_start() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0919", 0.75))
    draw_string(ThemeDB.fallback_font, Vector2(12, size.y * 0.48), "ВТОРОЙ ТАЙМ!", HORIZONTAL_ALIGNMENT_CENTER, size.x - 24, 33, Color("#ffe4a0"))
    draw_string(ThemeDB.fallback_font, Vector2(12, size.y * 0.55), "ПЕРВЫЙ ХОД СИНИХ" if turn == 1 else "ПЕРВЫЙ ХОД КРАСНЫХ", HORIZONTAL_ALIGNMENT_CENTER, size.x - 24, 19, Color("#4ac5e8") if turn == 1 else Color("#e45a78"))
    draw_string(ThemeDB.fallback_font, Vector2(12, size.y * 0.60), "МЯЧ — В ЦЕНТРЕ", HORIZONTAL_ALIGNMENT_CENTER, size.x - 24, 15, Color("#ffe2af"))

func _draw_pause_screen() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0919", 0.76))
    draw_string(ThemeDB.fallback_font, Vector2(12, size.y * 0.5), "ПАУЗА", HORIZONTAL_ALIGNMENT_CENTER, size.x - 24.0, 35, Color("#ffcc80"))
    draw_string(ThemeDB.fallback_font, Vector2(12, size.y * 0.58), "Нажми ПАУЗА сверху, чтобы продолжить", HORIZONTAL_ALIGNMENT_CENTER, size.x - 24.0, 16, Color.WHITE)
    draw_rect(Rect2(size.x - 106.0, 73.0, 96.0, 30.0), Color("#584166"))
    draw_string(ThemeDB.fallback_font, Vector2(size.x - 99.0, 93.0), "ПРОДОЛЖИТЬ", HORIZONTAL_ALIGNMENT_LEFT, 95.0, 12, Color.WHITE)

func _geometry() -> Dictionary:
    # Reserve space for the large match clock and a side-specific move clock.
    var top_margin := 196.0
    var bottom_margin := 144.0
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
    if consecutive_passes >= 2 and pass_side == turn:
        return false
    if last_pass_sender == to_index and pass_side == turn:
        return false
    return absi(to_cell.x - from_cell.x) == 1 and absi(to_cell.y - from_cell.y) == 1

func _pass_ball(to_index: int) -> void:
    if not _can_pass(ball_holder, to_index):
        return
    last_pass_sender = ball_holder
    pass_side = turn
    consecutive_passes += 1
    pass_fx_from = pieces[ball_holder]["cell"]
    pass_fx_to = pieces[to_index]["cell"]
    pass_fx_progress = 0.0
    _play_sfx("pass")
    ball_holder = to_index
    ball_cell = pass_fx_to
    # A pass can be an immediate goal: the RECEIVER already stands in the
    # opponent's goal (the last row, columns C-F). Do not switch turns or
    # reset the board before _award_point starts the goal celebration.
    if _check_goal():
        queue_redraw()
        return
    var score_before: Array = scores.duplicate()
    _finish_turn()
    # Keep the goal message if the other team's lone carrier gets stuck.
    if not game_over and halftime_remaining <= 0.0 and scores == score_before:
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
    # The blocked last carrier counts as ONE eliminated piece, not a goal.
    # With four prior captures the total is exactly five points.
    pieces[ball_holder]["alive"] = false
    ball_holder = -1
    var opponent: int = 3 - team_id
    scores[opponent - 1] += 1
    match_blocks[opponent - 1] += 1
    _end_round(opponent, "ПОСЛЕДНИЙ ИГРОК ЗАБЛОКИРОВАН! +1", false, false)
    return true

func _gui_input(event: InputEvent) -> void:
    if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
        _unlock_game_audio()
        var touch_point: Vector2 = event.position
        # Touching the pumpkin makes it wobble without changing possession.
        if not celebrating and not customization_open and not game_over:
            var ball_pos: Vector2 = _drag_cell_center(ball_cell)
            if touch_point.distance_to(ball_pos) <= float(_geometry()["cell_size"]) * 0.45:
                ball_wiggle = 0.65
        if touch_point.y < 115.0 and touch_point.x > size.x - 107.0 and not customization_open and not setup_active and not game_over:
            paused_match = not paused_match
            drag_active = false
            drag_moved = false
            drag_input_touch = false
            if crowd_ambience != null:
                crowd_ambience.stream_paused = paused_match
            if halftime_player != null:
                halftime_player.stream_paused = paused_match
            queue_redraw()
            accept_event()
            return
    if setup_active and not customization_open:
        if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
            _setup_input(event.position)
        accept_event()
        return
    if paused_match or coin_remaining > 0.0 or halftime_remaining > 0.0 or opening_second_half > 0.0 or _capture_motion_active():
        accept_event()
        return
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
        _new_match()
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
            _credit_capture(turn)
            _start_hit_fx(int(capture["victim"]))
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
    # Rival moves do NOT clear the other team's pass chain.
    # Only movement by the passing side, or a change of ball possession, does.
    if pass_side == int(pieces[selected]["team"]) or ball_holder == selected:
        consecutive_passes = 0
        last_pass_sender = -1
        pass_side = 0
    pieces[selected]["cell"] = cell
    if ball_holder == selected:
        ball_cell = cell
    elif ball_holder == -1 and ball_cell == cell:
        ball_holder = selected
    queue_redraw()

func _check_goal() -> bool:
    # Scoring is based on who NOW holds the ball, not on the last mover.
    # This covers both walking into goal and receiving a pass while in goal.
    if ball_holder < 0 or ball_holder >= pieces.size():
        return false
    if not bool(pieces[ball_holder]["alive"]):
        return false
    var scoring_team: int = int(pieces[ball_holder]["team"])
    var cell: Vector2i = pieces[ball_holder]["cell"]
    var goal_row: int = 0 if scoring_team == 1 else ROWS - 1
    if cell.x == goal_row and cell.y >= 2 and cell.y <= 5:
        _end_round(scoring_team, "ГОЛ! +5", true)
        return true
    return false

func _finish_turn() -> void:
    selected = -1
    # If the last move used the final three seconds, blow the whistle
    # before handing the turn over or scheduling the red bot.
    if _complete_action_clock():
        return
    turn = 2 if turn == 1 else 1
    decision_remaining = DECISION_SECONDS
    referee_warning = false
    message = "Ход голубых" if turn == 1 else "Ход красных"
    # Check as soon as the blocked team would receive the turn.
    if _check_last_carrier_stuck(turn):
        return
    queue_redraw()
    if game_mode == 0 and turn == 2 and not game_over:
        _schedule_bot()

func _schedule_bot() -> void:
    if bot_pending or game_over or celebrating or paused_match or setup_active or coin_remaining > 0.0 or halftime_remaining > 0.0 or opening_second_half > 0.0 or turn != 2:
        return
    bot_pending = true
    _bot_turn.call_deferred()

# AI 2.0: red attacks the bottom goal, blue attacks the top.
# The search uses the real 5v5 rules, including forced jumps and diagonal passes.
var _fb_ai_nodes: int = 0

func _fb_ai_choices(side: int) -> Array[Dictionary]:
    var forced_moves: Array[Dictionary] = []
    var free_moves: Array[Dictionary] = []
    for i in pieces.size():
        if not bool(pieces[i]["alive"]) or int(pieces[i]["team"]) != side:
            continue
        var src: Vector2i = pieces[i]["cell"]
        for capture in _captures(i):
            forced_moves.append({"piece":i, "to":capture["cell"], "victim":capture["victim"]})
        for dr in [-1, 1]:
            if ball_holder == i and dr != (1 if side == 2 else -1):
                continue
            for dc in [-1, 1]:
                var target: Vector2i = src + Vector2i(dr, dc)
                if _inside(target) and _piece_at(target) < 0:
                    free_moves.append({"piece":i, "to":target, "victim":-1})
        if ball_holder == i:
            for j in pieces.size():
                if j == i or not bool(pieces[j]["alive"]) or int(pieces[j]["team"]) != side:
                    continue
                var dest: Vector2i = pieces[j]["cell"]
                if absi(src.x - dest.x) == 1 and absi(src.y - dest.y) == 1:
                    if pass_side == side and (consecutive_passes >= 2 or last_pass_sender == j):
                        continue
                    free_moves.append({"piece":i, "pass_to":j})
    return forced_moves if not forced_moves.is_empty() else free_moves

func _fb_ai_apply(move: Dictionary) -> void:
    var mover: int = int(move["piece"])
    if move.has("pass_to"):
        last_pass_sender = mover
        pass_side = int(pieces[mover]["team"])
        consecutive_passes += 1
        ball_holder = int(move["pass_to"])
        ball_cell = pieces[ball_holder]["cell"]
        return
    var victim: int = int(move["victim"])
    if pass_side == int(pieces[mover]["team"]) or ball_holder == mover or (victim >= 0 and ball_holder == victim):
        consecutive_passes = 0
        last_pass_sender = -1
        pass_side = 0
    if victim >= 0:
        pieces[victim]["alive"] = false
        if ball_holder == victim:
            ball_holder = mover
    pieces[mover]["cell"] = move["to"]
    if ball_holder == mover:
        ball_cell = move["to"]
    elif ball_holder < 0 and ball_cell == move["to"]:
        ball_holder = mover
    # A capture chain is completed during the same turn.
    if victim >= 0:
        for unused in FOOTBALL_TEAM_SIZE:
            var next_captures: Array = _captures(mover)
            if next_captures.is_empty():
                break
            var chosen: Dictionary = next_captures[0]
            for candidate in next_captures:
                if int(candidate["victim"]) == ball_holder:
                    chosen = candidate
                    break
            var next_victim: int = int(chosen["victim"])
            pieces[next_victim]["alive"] = false
            if ball_holder == next_victim:
                ball_holder = mover
            pieces[mover]["cell"] = chosen["cell"]
            if ball_holder == mover:
                ball_cell = chosen["cell"]
            elif ball_holder < 0 and ball_cell == chosen["cell"]:
                ball_holder = mover

func _fb_ai_value() -> int:
    var red_count: int = 0
    var blue_count: int = 0
    var value: int = 0
    for i in pieces.size():
        if not bool(pieces[i]["alive"]):
            continue
        var team_id: int = int(pieces[i]["team"])
        var cell: Vector2i = pieces[i]["cell"]
        var sign: int = 1 if team_id == 2 else -1
        if team_id == 2:
            red_count += 1
        else:
            blue_count += 1
        # Value active pieces and space/position around the central lanes.
        value += sign * (220 + (cell.x if team_id == 2 else 9 - cell.x) * 4 + (3 - mini(absi(cell.y - 3), 3)) * 5)
        # A jump threat matters much more if the victim carries the ball.
        for cap in _captures(i):
            var opponent: int = int(cap["victim"])
            value += sign * (220 if opponent == ball_holder else 34)
    if red_count == 0:
        return -50000
    if blue_count == 0:
        return 50000
    if ball_holder >= 0 and bool(pieces[ball_holder]["alive"]):
        var holder_side: int = int(pieces[ball_holder]["team"])
        var pos: Vector2i = pieces[ball_holder]["cell"]
        if pos.x == (9 if holder_side == 2 else 0) and pos.y >= 2 and pos.y <= 5:
            return 50000 if holder_side == 2 else -50000
        var sign: int = 1 if holder_side == 2 else -1
        var progress: int = pos.x if holder_side == 2 else 9 - pos.x
        value += sign * (170 + progress * 42 + (3 - mini(absi(pos.y - 3), 3)) * 14)
        if (red_count == 1 and holder_side == 2) or (blue_count == 1 and holder_side == 1):
            if not _carrier_has_move(ball_holder):
                return -50000 if holder_side == 2 else 50000
    else:
        var red_nearest: int = 30
        var blue_nearest: int = 30
        for i in pieces.size():
            if not bool(pieces[i]["alive"]):
                continue
            var cell: Vector2i = pieces[i]["cell"]
            var distance: int = absi(cell.x - ball_cell.x) + absi(cell.y - ball_cell.y)
            if int(pieces[i]["team"]) == 2:
                red_nearest = mini(red_nearest, distance)
            else:
                blue_nearest = mini(blue_nearest, distance)
        value += (blue_nearest - red_nearest) * 30
    return value

func _fb_ai_search(side: int, depth: int, alpha: int, beta: int) -> int:
    _fb_ai_nodes += 1
    var static_score: int = _fb_ai_value()
    if depth <= 0 or absi(static_score) >= 49000 or _fb_ai_nodes > 1600:
        return static_score
    var moves: Array[Dictionary] = _fb_ai_choices(side)
    if moves.is_empty():
        return -28000 if side == 2 else 28000
    # Move ordering: look at promising tactical moves first, keep mobile fast.
    var ranked: Array[Dictionary] = []
    for move in moves:
        var old_pieces: Array[Dictionary] = pieces
        var old_holder: int = ball_holder
        var old_cell: Vector2i = ball_cell
        var old_chain: int = consecutive_passes
        var old_sender: int = last_pass_sender
        var old_side: int = pass_side
        pieces = old_pieces.duplicate(true)
        _fb_ai_apply(move)
        var merit: int = _fb_ai_value()
        pieces = old_pieces
        ball_holder = old_holder
        ball_cell = old_cell
        consecutive_passes = old_chain
        last_pass_sender = old_sender
        pass_side = old_side
        ranked.append({"action":move, "merit":merit})
    ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return int(a["merit"]) > int(b["merit"]) if side == 2 else int(a["merit"]) < int(b["merit"])
    )
    var best: int = -60000 if side == 2 else 60000
    for k in mini(ranked.size(), 8):
        var action: Dictionary = ranked[k]["action"]
        var snapshot: Array[Dictionary] = pieces
        var previous_holder: int = ball_holder
        var previous_cell: Vector2i = ball_cell
        var previous_chain: int = consecutive_passes
        var previous_sender: int = last_pass_sender
        var previous_side: int = pass_side
        pieces = snapshot.duplicate(true)
        _fb_ai_apply(action)
        var score: int = _fb_ai_search(3 - side, depth - 1, alpha, beta)
        pieces = snapshot
        ball_holder = previous_holder
        ball_cell = previous_cell
        consecutive_passes = previous_chain
        last_pass_sender = previous_sender
        pass_side = previous_side
        if side == 2:
            best = maxi(best, score)
            alpha = maxi(alpha, best)
        else:
            best = mini(best, score)
            beta = mini(beta, best)
        if alpha >= beta:
            break
    return best

func _fb_choose_action(moves: Array[Dictionary], depth: int) -> Dictionary:
    _fb_ai_nodes = 0
    var best: Dictionary = moves[0]
    var best_score: int = -999999
    for move in moves:
        var snapshot: Array[Dictionary] = pieces
        var previous_holder: int = ball_holder
        var previous_cell: Vector2i = ball_cell
        var previous_chain: int = consecutive_passes
        var previous_sender: int = last_pass_sender
        var previous_side: int = pass_side
        pieces = snapshot.duplicate(true)
        _fb_ai_apply(move)
        var score: int = _fb_ai_search(1, depth - 1, -60000, 60000)
        pieces = snapshot
        ball_holder = previous_holder
        ball_cell = previous_cell
        consecutive_passes = previous_chain
        last_pass_sender = previous_sender
        pass_side = previous_side
        if score > best_score:
            best_score = score
            best = move
    return best

func _bot_turn() -> void:
    if not is_inside_tree():
        return
    await get_tree().create_timer(0.77).timeout
    bot_pending = false
    if game_mode != 0 or turn != 2 or game_over or paused_match or celebrating or coin_remaining > 0.0 or halftime_remaining > 0.0:
        return
    var candidates: Array[Dictionary] = _fb_ai_choices(2)
    if candidates.is_empty():
        message = "У красных нет допустимых ходов"
        _end_round(1, "НЕТ ХОДОВ — НОВЫЙ РОЗЫГРЫШ!")
        return
    var best: Dictionary
    if bot_difficulty == 0:
        # Beginner makes occasional mistakes without breaking legal moves.
        best = candidates.pick_random()
    else:
        # Experienced sees one reply; Legend sees the reply and counterplay.
        best = _fb_choose_action(candidates, 2 if bot_difficulty == 1 else 3)
    selected = int(best["piece"])
    capture_sequence_running = not best.has("pass_to") and int(best.get("victim", -1)) >= 0
    if best.has("pass_to"):
        _pass_ball(int(best["pass_to"]))
        return
    if best["victim"] >= 0:
        pieces[best["victim"]]["alive"] = false
        _credit_capture(turn)
        _start_hit_fx(int(best["victim"]))
        if ball_holder == best["victim"]:
            ball_holder = selected
    _move_selected(best["to"])
    if capture_sequence_running:
        await _wait_for_current_jump()
    if not is_inside_tree():
        return
    if _check_elimination():
        capture_sequence_running = false
        return
    if _check_goal():
        capture_sequence_running = false
        return
    # Keep capturing with the same piece while captures are available.
    if best["victim"] >= 0:
        while not _captures(selected).is_empty():
            var all_captures: Array = _captures(selected)
            var next_capture: Dictionary = all_captures[0]
            if bot_difficulty > 0 and all_captures.size() > 1:
                var chain_candidates: Array[Dictionary] = []
                for cap in all_captures:
                    chain_candidates.append({"piece":selected, "to":cap["cell"], "victim":cap["victim"]})
                next_capture = all_captures[0]
                var chain_choice: Dictionary = _fb_choose_action(chain_candidates, 1 if bot_difficulty == 1 else 2)
                next_capture = {"cell":chain_choice["to"], "victim":chain_choice["victim"]}
            pieces[next_capture["victim"]]["alive"] = false
            _credit_capture(turn)
            _start_hit_fx(int(next_capture["victim"]))
            if ball_holder == next_capture["victim"]:
                ball_holder = selected
            _move_selected(next_capture["cell"])
            await _wait_for_current_jump()
            if not is_inside_tree():
                return
            if _check_elimination():
                capture_sequence_running = false
                return
            if _check_goal():
                capture_sequence_running = false
                return
    capture_sequence_running = false
    _finish_turn()

# Central match time and large 20-second decision clock on the side now moving.
func _draw_match_clocks(board_origin: Vector2, cell_side: float, font: Font) -> void:
    # Leave touch coordinates of the pause control unchanged (top-right, y<115).
    var banner_width: float = maxf(104.0, minf(182.0, size.x - 212.0))
    var center_x: float = size.x * 0.5
    var banner := Rect2(Vector2(center_x - banner_width * 0.5, 34.0), Vector2(banner_width, 69.0))
    draw_rect(banner, Color("#171528", 0.95))
    draw_rect(banner, Color("#e7a85f"), false, 2.0)
    var decisive_phase: bool = final_phase_active and final_actions_remaining > 0
    var half_label: String = "%d-Й ТАЙМ • ФИНИШ" % half_number if decisive_phase else "%d-Й ТАЙМ" % half_number
    draw_string(font, Vector2(banner.position.x + 4.0, 52.0), half_label, HORIZONTAL_ALIGNMENT_CENTER, banner.size.x - 8.0, 14, Color("#ffd89c"))
    # Round UP so 00:01 is shown until the final fraction of a second has passed.
    var seconds_display: int = maxi(0, ceili(half_remaining))
    var match_text: String = "%02d:%02d" % [seconds_display / 60, seconds_display % 60]
    draw_string(font, Vector2(banner.position.x + 5.0, 90.0), match_text, HORIZONTAL_ALIGNMENT_CENTER, banner.size.x - 10.0, 34, Color("#fff5dc"))
    # Score on the left and pause on the right, clear of the central clock.
    var score_width: float = maxf(62.0, (size.x - banner_width) * 0.5 - 23.0)
    draw_rect(Rect2(8.0, 50.0, score_width, 47.0), Color("#102638", 0.95))
    draw_string(font, Vector2(12.0, 62.0), "СЧЁТ", HORIZONTAL_ALIGNMENT_CENTER, score_width - 8.0, 11, Color("#9cdaee"))
    draw_string(font, Vector2(10.0, 87.0), "%d:%d" % [scores[0], scores[1]], HORIZONTAL_ALIGNMENT_CENTER, score_width - 4.0, 23, Color.WHITE)
    draw_rect(Rect2(size.x - 106.0, 73.0, 96.0, 29.0), Color("#30283c"))
    draw_string(font, Vector2(size.x - 102.0, 93.0), "ПРОДОЛЖИТЬ" if paused_match else "ПАУЗА", HORIZONTAL_ALIGNMENT_CENTER, 87.0, 12, Color("#fff2d8"))
    draw_string(font, Vector2(12.0, 22.0), "MONSTER BALL · HALLOWEEN", HORIZONTAL_ALIGNMENT_LEFT, size.x - 20.0, 16, Color("#ffc079"))
    draw_string(font, Vector2(10.0, 123.0), message, HORIZONTAL_ALIGNMENT_CENTER, size.x - 20.0, 13, Color("#d9f6f9"))
    if decisive_phase:
        draw_string(font, Vector2(10.0, 140.0), "ФИНИШ: ОСТАЛОСЬ ХОДОВ — %d" % final_actions_remaining, HORIZONTAL_ALIGNMENT_CENTER, size.x - 20.0, 12, Color("#ffca83"))
    elif consecutive_passes > 0:
        draw_string(font, Vector2(10.0, 140.0), "ПАСОВ ПОДРЯД: %d/2" % consecutive_passes, HORIZONTAL_ALIGNMENT_CENTER, size.x - 20.0, 12, Color("#ffca83"))
    # The RED team defends the top, BLUE the bottom. Show ONLY the active team.
    var red_to_move: bool = turn == 2
    var team_color: Color = Color("#f3617a") if red_to_move else Color("#51d9ff")
    var clock_width: float = minf(202.0, size.x * 0.57)
    var board_end: float = board_origin.y + float(ROWS) * cell_side
    var clock_y: float = board_origin.y - 52.0 if red_to_move else board_end + 8.0
    clock_y = clampf(clock_y, 145.0, size.y - 135.0)
    var clock_rect := Rect2(Vector2(center_x - clock_width * 0.5, clock_y), Vector2(clock_width, 44.0))
    draw_rect(clock_rect, Color("#151323", 0.96))
    draw_rect(clock_rect, team_color, false, 2.5)
    draw_string(font, Vector2(clock_rect.position.x + 7.0, clock_y + 13.0), "ХОД КРАСНЫХ" if red_to_move else "ХОД СИНИХ", HORIZONTAL_ALIGNMENT_LEFT, clock_width - 58.0, 12, team_color)
    var decision_color: Color = Color("#ffdb77") if decision_remaining <= 5.0 else Color.WHITE
    draw_string(font, Vector2(clock_rect.position.x + 6.0, clock_y + 36.0), "%02d" % ceili(decision_remaining), HORIZONTAL_ALIGNMENT_RIGHT, clock_width - 12.0, 30, decision_color)

func _draw() -> void:
    var geometry := _geometry()
    var side: float = geometry["cell_size"]
    var offset: Vector2 = geometry["offset"]
    _halloween_arena(offset, Vector2(COLS * side, ROWS * side))
    var font: Font = ThemeDB.fallback_font
    if not setup_active:
        _draw_match_clocks(offset, side, font)
    _draw_referee(Vector2(size.x - 24.0, 168.0), 0.76)
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
    if setup_active and not customization_open:
        _draw_setup_help(offset, side, font)
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
            token_center.y -= sin(fx_progress * PI) * side * (0.28 if fx_victim_index >= 0 else 0.035)
        if drag_active and drag_moved and cell == drag_origin:
            continue
        if not _draw_asset(key, Rect2(token_center - Vector2.ONE * token_side * 0.5, Vector2.ONE * token_side)):
            _draw_fantasy_token(token_center, side * 0.37, team, i)
        if ball_holder == i and pass_fx_progress >= 1.0:
            var pumpkin_center := token_center + Vector2(side * 0.17, -side * 0.20)
            if ball_wiggle > 0.0:
                pumpkin_center += Vector2(sin(magic_clock * 26.0) * side * 0.10, cos(magic_clock * 22.0) * side * 0.06) * (ball_wiggle / 0.65)
            var pumpkin_size := side * 0.50
            if not _draw_asset("ghost_pumpkin", Rect2(pumpkin_center - Vector2.ONE * pumpkin_size * 0.5, Vector2.ONE * pumpkin_size)):
                _draw_ghost_pumpkin(pumpkin_center, side * 0.16)
    if ball_holder == -1:
        var pumpkin_center := offset + Vector2(ball_cell.y + 0.5, ball_cell.x + 0.5) * side
        if ball_wiggle > 0.0:
            pumpkin_center += Vector2(sin(magic_clock * 26.0) * side * 0.10, cos(magic_clock * 22.0) * side * 0.06) * (ball_wiggle / 0.65)
        var pumpkin_size := side * 0.90
        if not _draw_asset("ghost_pumpkin", Rect2(pumpkin_center - Vector2.ONE * pumpkin_size * 0.5, Vector2.ONE * pumpkin_size)):
            _draw_ghost_pumpkin(pumpkin_center, side * 0.23)
    _draw_drag_hints()
    _draw_game_fx()
    _draw_drag_piece_overlay(side)
    if celebrating and not _capture_motion_active():
        _draw_halloween_party(1.0 - celebration_time / maxf(0.01, celebration_duration), celebration_team, celebration_final)
    _draw_bottom_actions()
    if paused_match:
        _draw_pause_screen()
    elif coin_remaining > 0.0:
        _draw_coin_toss()
    elif halftime_remaining > 0.0:
        _draw_halftime_show()
    elif opening_second_half > 0.0:
        _draw_second_half_start()
    if game_over and not celebrating:
        var panel := Rect2(Vector2(18, size.y * 0.34), Vector2(size.x - 36, 204))
        draw_rect(panel, Color("#15111eef"))
        draw_rect(panel, Color("#f6cf65"), false, 3.0)
        var heading := ("НИЧЬЯ!" if winner == 0 else ("ПОЗДРАВЛЯЕМ С ПОБЕДОЙ!" if (game_mode == 1 or winner == 1) else "ВЫ ПРОИГРАЛИ!"))
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 52), heading, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 24, Color.WHITE)
        var detail := "Равный счёт" if winner == 0 else ("Победили голубые" if winner == 1 else "Победили красные")
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 87), "%s · Счёт %d : %d" % [detail, scores[0], scores[1]], HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 17, Color("#f6cf65"))
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 116), "ГОЛЫ (5)        %d : %d" % [match_goals[0], match_goals[1]], HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 15, Color("#ffd68e"))
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 140), "ВЗЯТИЯ (1)    %d : %d" % [match_captures[0], match_captures[1]], HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 15, Color("#c8e9f2"))
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 164), "БЛОКИРОВКИ (1) %d : %d" % [match_blocks[0], match_blocks[1]], HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 14, Color("#d4c4ff"))
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 191), "НОВАЯ ИГРА — сыграть ещё", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 13, Color.WHITE)


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
    var left_label: String = "УБРАТЬ ПОСЛЕДНЮЮ" if setup_active else "НОВАЯ ИГРА"
    var ready: bool = _setup_cells(setup_team).size() == FOOTBALL_TEAM_SIZE
    var right_label: String = ("ГОТОВО ✓" if ready else "ПОСТАВЬ ВСЕ 5") if setup_active else "ГЛАВНОЕ МЕНЮ"
    draw_string(font, Vector2(13, y + 37), left_label, HORIZONTAL_ALIGNMENT_LEFT, w - 17, 14, Color.WHITE)
    draw_string(font, Vector2(w + 12, y + 37), right_label, HORIZONTAL_ALIGNMENT_LEFT, w - 18, 14, Color.WHITE)

# Local save data is separate for each browser/PWA installation.
# There is no online account or server sync in this version.
const MB_PROFILE_FILE: String = "user://monster_ball_profile_v1.json"
var mb_profile_counted: bool = false

func _mb_read_profile() -> Dictionary:
    var profile: Dictionary = {"version": 1, "played": 0, "wins": 0, "losses": 0, "draws": 0, "friend_games": 0, "football_games": 0, "checkers_games": 0}
    if FileAccess.file_exists(MB_PROFILE_FILE):
        var file: FileAccess = FileAccess.open(MB_PROFILE_FILE, FileAccess.READ)
        if file != null:
            var parsed: Variant = JSON.parse_string(file.get_as_text())
            if parsed is Dictionary and int(parsed.get("version", 0)) == 1:
                profile.merge(parsed, true)
    return profile

func _mb_write_profile(profile: Dictionary) -> void:
    var file: FileAccess = FileAccess.open(MB_PROFILE_FILE, FileAccess.WRITE)
    if file == null:
        push_warning("Monster Ball: cannot write local profile save")
        return
    file.store_string(JSON.stringify(profile, "  "))
    file.flush()

func _mb_record_finished(kind: String, victor: int) -> void:
    # Record once per finished game; abandoned/restarted games do not count.
    if mb_profile_counted:
        return
    mb_profile_counted = true
    var data: Dictionary = _mb_read_profile()
    data["played"] = int(data.get("played", 0)) + 1
    var stat: String = "football_games" if kind == "football" else "checkers_games"
    data[stat] = int(data.get(stat, 0)) + 1
    if game_mode == 1:
        # Local friend mode: ONE game, never a win or loss for the profile.
        data["friend_games"] = int(data.get("friend_games", 0)) + 1
    elif victor == 1:
        data["wins"] = int(data.get("wins", 0)) + 1
    elif victor == 2:
        data["losses"] = int(data.get("losses", 0)) + 1
    else:
        data["draws"] = int(data.get("draws", 0)) + 1
    _mb_write_profile(data)
