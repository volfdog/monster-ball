extends Control

var section: String = ""
var choose_difficulty: bool = false
var backdrop: Texture2D
var panel: VBoxContainer


# Original Halloween melody, controlled from the title screen.
var menu_music: AudioStreamPlayer
var menu_click_stream: AudioStream
const AUDIO_KEYS := ["mb_vol_music", "mb_vol_effects", "mb_vol_crowd", "mb_muted"]

func _read_audio_settings() -> void:
    var cfg: ConfigFile = ConfigFile.new()
    cfg.load("user://monster_ball_audio.cfg")
    var defaults: Array = [0.55, 0.78, 0.65, false]
    for index in AUDIO_KEYS.size():
        get_tree().root.set_meta(AUDIO_KEYS[index], cfg.get_value("audio", AUDIO_KEYS[index], defaults[index]))

func _save_audio_settings() -> void:
    var cfg: ConfigFile = ConfigFile.new()
    for key in AUDIO_KEYS:
        cfg.set_value("audio", key, get_tree().root.get_meta(key))
    cfg.save("user://monster_ball_audio.cfg")

func _init_menu_audio() -> void:
    menu_music = AudioStreamPlayer.new()
    menu_music.name = "HalloweenTitleTheme"
    add_child(menu_music)
    var theme_path: String = "res://audio/halloween_theme.wav"
    if ResourceLoader.exists(theme_path):
        var melody: AudioStream = load(theme_path)
        var wav_melody: AudioStreamWAV = melody as AudioStreamWAV
        if wav_melody != null:
            wav_melody.loop_mode = AudioStreamWAV.LOOP_FORWARD
        menu_music.stream = melody
    if ResourceLoader.exists("res://audio/menu_click.wav"):
        menu_click_stream = load("res://audio/menu_click.wav")
    _update_menu_audio()

func _update_menu_audio() -> void:
    if menu_music == null or menu_music.stream == null:
        return
    var muted: bool = bool(get_tree().root.get_meta("mb_muted", false))
    var volume: float = float(get_tree().root.get_meta("mb_vol_music", 0.55))
    menu_music.volume_db = linear_to_db(maxf(0.001, volume * 0.60))
    if muted or volume < 0.005:
        menu_music.stop()
    elif not menu_music.playing:
        menu_music.play()

func _play_menu_click() -> void:
    _update_menu_audio() # iOS browsers often unlock sound on the first tap.
    if menu_click_stream == null or bool(get_tree().root.get_meta("mb_muted", false)):
        return
    var volume: float = float(get_tree().root.get_meta("mb_vol_effects", 0.78))
    if volume <= 0.005:
        return
    var fx: AudioStreamPlayer = AudioStreamPlayer.new()
    add_child(fx)
    fx.stream = menu_click_stream
    fx.volume_db = linear_to_db(maxf(0.001, volume * 0.7))
    fx.finished.connect(func(): fx.queue_free())
    fx.play()

func _sound_slider(title: String, key: String, fallback: float) -> void:
    var label: Label = Label.new()
    label.text = title
    label.add_theme_font_size_override("font_size", 17)
    label.add_theme_color_override("font_color", Color("#ffe5ad"))
    panel.add_child(label)
    var slider: HSlider = HSlider.new()
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.step = 5.0
    slider.value = float(get_tree().root.get_meta(key, fallback)) * 100.0
    slider.value_changed.connect(func(value: float):
        get_tree().root.set_meta(key, value / 100.0)
        _save_audio_settings()
        _update_menu_audio()
    )
    panel.add_child(slider)

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    backdrop = load("res://assets/menu_heroes.png")
    _read_audio_settings()
    _init_menu_audio()
    _build()

func _build() -> void:
    for child in get_children():
        if child != menu_music and not (child is AudioStreamPlayer):
            child.queue_free()
    var background := TextureRect.new()
    background.texture = backdrop
    background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    var veil := ColorRect.new()
    veil.color = Color(0.025, 0.035, 0.075, 0.55)
    veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(veil)
    panel = VBoxContainer.new()
    panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    panel.anchor_left = 0.07
    panel.anchor_right = 0.93
    panel.anchor_top = 0.39 if section == "sound" else 0.55
    panel.anchor_bottom = 0.98
    panel.offset_left = 0
    panel.offset_right = 0
    panel.offset_top = 0
    panel.offset_bottom = 0
    panel.add_theme_constant_override("separation", 12)
    add_child(panel)
    var heading := Label.new()
    heading.text = "НАСТРОЙКИ ЗВУКА" if section == "sound" else ("ВЫБЕРИ СЛОЖНОСТЬ" if choose_difficulty else ("ДОБРО ПОЖАЛОВАТЬ!" if section == "" else ("ШАШКИ" if section == "checkers" else "ФУТБОЛ")))
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    heading.add_theme_font_size_override("font_size", 27)
    heading.add_theme_color_override("font_color", Color("#f5dca6"))
    panel.add_child(heading)
    if choose_difficulty:
        _button("НОВИЧОК", func(): _launch(0, false, 0))
        _button("ОПЫТНЫЙ", func(): _launch(0, false, 1))
        _button("ЛЕГЕНДА", func(): _launch(0, false, 2))
        _button("← НАЗАД", func(): choose_difficulty = false; _build())
    elif section == "":
        _button("♟  ШАШКИ", func(): section = "checkers"; _build())
        _button("⚽  ФУТБОЛ", func(): section = "football"; _build())
        _button("♫  ЗВУК И МУЗЫКА", func(): section = "sound"; _build())
    elif section == "sound":
        _button("🔊 ВЫКЛЮЧИТЬ ЗВУК" if not bool(get_tree().root.get_meta("mb_muted", false)) else "🔇 ВКЛЮЧИТЬ ЗВУК", func():
            get_tree().root.set_meta("mb_muted", not bool(get_tree().root.get_meta("mb_muted", false)))
            _save_audio_settings()
            _update_menu_audio()
            _build()
        )
        _sound_slider("МУЗЫКА", "mb_vol_music", 0.55)
        _sound_slider("ЭФФЕКТЫ", "mb_vol_effects", 0.78)
        _sound_slider("ЗРИТЕЛИ", "mb_vol_crowd", 0.65)
        _button("← НАЗАД", func(): section = ""; _build())
    else:
        _button("ИГРА С БОТОМ", func(): choose_difficulty = true; _build())
        _button("ИГРА С ДРУГОМ", func(): _launch(1, false))
        _button("КОСТЮМИЗАЦИЯ", func(): _launch(0, true))
        _button("← НАЗАД", func(): section = ""; _build())

func _button(label_text: String, action: Callable) -> void:
    var b := Button.new()
    b.text = label_text
    b.custom_minimum_size = Vector2(0, 55)
    b.add_theme_font_size_override("font_size", 19)
    b.add_theme_color_override("font_color", Color("#f6e6c4"))
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#14243a")
    style.border_color = Color("#68b9d4")
    style.set_border_width_all(2)
    style.set_corner_radius_all(10)
    b.add_theme_stylebox_override("normal", style)
    b.pressed.connect(func():
        _play_menu_click()
        action.call()
    )
    panel.add_child(b)

func _launch(mode: int, customize: bool, difficulty: int = 1) -> void:
    get_tree().root.set_meta("mb_bot_difficulty", difficulty)
    get_tree().root.set_meta("mb_mode", mode)
    get_tree().root.set_meta("mb_customize", customize)
    var path := "res://checkers.tscn" if section == "checkers" else "res://football.tscn"
    get_tree().change_scene_to_file(path)
