extends Control

# Long soundtrack files already imported in the project.
# Both MP3 resources are verified in the GitHub Actions export log.
const HD_TITLE_THEME: AudioStream = preload("res://audio/halloween_theme.mp3")
const HD_STADIUM: AudioStream = preload("res://audio/stadium_crowd.mp3")

var section: String = ""
var choose_difficulty: bool = false
var backdrop: Texture2D
var panel: VBoxContainer


# Original Halloween melody, controlled from the title screen.
var menu_music: AudioStreamPlayer
var menu_click_stream: AudioStream
var menu_music_unlocked: bool = false
var background_test_status: Label
var profile_notice: Label
var import_callback_ref: JavaScriptObject
var pending_profile_import: Dictionary = {}
const MB_PROFILE_FILE: String = "user://monster_ball_profile_v1.json"
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
    # Audio values are included in the portable backup too.
    var profile: Dictionary = _profile_load()
    var audio: Dictionary = {}
    for key in AUDIO_KEYS:
        audio[key] = get_tree().root.get_meta(key)
    profile["audio"] = audio
    _profile_write(profile)

func _init_menu_audio() -> void:
    menu_music = AudioStreamPlayer.new()
    menu_music.name = "HalloweenTitleTheme"
    add_child(menu_music)
    # Use the verified long recording directly; never fall back to the old tune.
    var melody: AudioStream = HD_TITLE_THEME
    var wav_melody: AudioStreamWAV = melody as AudioStreamWAV
    if wav_melody != null:
        wav_melody.loop_mode = AudioStreamWAV.LOOP_DISABLED
    menu_music.stream = melody
    menu_music.finished.connect(_restart_menu_music)
    if ResourceLoader.exists("res://audio/menu_click.wav"):
        menu_click_stream = load("res://audio/menu_click.wav")
    _update_menu_audio()

func _update_menu_audio() -> void:
    if menu_music == null or menu_music.stream == null:
        return
    var muted: bool = bool(get_tree().root.get_meta("mb_muted", false))
    var volume: float = float(get_tree().root.get_meta("mb_vol_music", 0.55))
    menu_music.volume_db = linear_to_db(maxf(0.001, volume * 0.95))
    if muted or volume < 0.005:
        menu_music.stop()
    elif menu_music_unlocked and not menu_music.playing:
        menu_music.play()

# Player.finished is more reliable here than WAV loop points on exported Web builds.
func _restart_menu_music() -> void:
    if not is_inside_tree() or not menu_music_unlocked:
        return
    _update_menu_audio()

# A user gesture is needed to release web audio on iPhone/Safari.
func _unlock_menu_music() -> void:
    if menu_music_unlocked:
        return
    menu_music_unlocked = true
    _update_menu_audio()
    if menu_music != null and menu_music.stream != null and not bool(get_tree().root.get_meta("mb_muted", false)) and float(get_tree().root.get_meta("mb_vol_music", 0.55)) > 0.005:
        menu_music.stop()
        menu_music.play()

func _input(event: InputEvent) -> void:
    if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
        _unlock_menu_music()

func _play_menu_click() -> void:
    _unlock_menu_music()
    _update_menu_audio()
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

# A single diagnostic button confirms actual playback after a real user tap.
func _test_background_audio() -> void:
    _unlock_menu_music()
    var melody_ready: bool = menu_music != null and menu_music.stream != null
    if melody_ready:
        menu_music.stop()
        menu_music.play()
    var crowd_ready: bool = HD_STADIUM != null
    if crowd_ready:
        var test_player: AudioStreamPlayer = AudioStreamPlayer.new()
        test_player.name = "CrowdSoundTestHD"
        add_child(test_player)
        test_player.stream = HD_STADIUM
        test_player.volume_db = -4.0
        test_player.finished.connect(func(): test_player.queue_free())
        test_player.play()
    if background_test_status != null and is_instance_valid(background_test_status):
        background_test_status.text = "Музыка: %s  |  Зрители: %s" % ["запущена" if melody_ready else "файл не найден", "запущены" if crowd_ready else "файл не найден"]

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
    _apply_saved_preferences()
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
    background_test_status = null
    panel = VBoxContainer.new()
    panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    panel.anchor_left = 0.07
    panel.anchor_right = 0.93
    panel.anchor_top = 0.23 if section == "profile" else (0.34 if section == "about" else (0.39 if section == "sound" else 0.55))
    panel.anchor_bottom = 0.98
    panel.offset_left = 0
    panel.offset_right = 0
    panel.offset_top = 0
    panel.offset_bottom = 0
    panel.add_theme_constant_override("separation", 12)
    add_child(panel)
    var heading := Label.new()
    heading.text = "МОЙ ПРОФИЛЬ" if section == "profile" else ("ОБ ИГРЕ" if section == "about" else ("ЗВУК • HD AUDIO" if section == "sound" else ("ВЫБЕРИ СЛОЖНОСТЬ" if choose_difficulty else ("ДОБРО ПОЖАЛОВАТЬ!" if section == "" else ("ШАШКИ" if section == "checkers" else "ФУТБОЛ")))))
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
        _button("◉  МОЙ ПРОФИЛЬ", func(): section = "profile"; _build())
        _button("ⓘ  ОБ ИГРЕ", func(): section = "about"; _build())
    elif section == "profile":
        _build_profile_panel()
    elif section == "about":
        var credits_scroll: ScrollContainer = ScrollContainer.new()
        credits_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        credits_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        panel.add_child(credits_scroll)
        var credits: Label = Label.new()
        credits.text = "MONSTER BALL — HALLOWEEN\n\nРазработчик проекта: Volfdog\n© 2026 Volfdog\nОригинальные материалы защищены авторским правом в соответствии с применимым законодательством.\n\nМУЗЫКА ГЛАВНОГО МЕНЮ\nVampire's Piano — TAD\nИсточник: OpenGameArt\nЛицензия: CC0 1.0\n\nЗВУК ЗРИТЕЛЕЙ\nAmbient Sports Crowd Sound — Mixkit\nУсловия: Mixkit Sound Effects Free License\n\nБлагодарим авторов сторонних материалов!\nОтдельные права на них принадлежат соответствующим правообладателям.\nПодробнее: COPYRIGHT.txt в GitHub."
        credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        credits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        credits.add_theme_font_size_override("font_size", 16)
        credits.add_theme_color_override("font_color", Color("#f6e6c4"))
        credits_scroll.add_child(credits)
        _button("← НАЗАД", func(): section = ""; _build())
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
        _button("▶ ПРОВЕРИТЬ ФОН", func(): _test_background_audio())
        background_test_status = Label.new()
        background_test_status.add_theme_font_size_override("font_size", 12)
        background_test_status.add_theme_color_override("font_color", Color("#b7e9c5"))
        background_test_status.text = "Нажми «Проверить фон»"
        panel.add_child(background_test_status)
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
    if mode == 0:
        var profile: Dictionary = _profile_load()
        profile["bot_difficulty"] = difficulty
        _profile_write(profile)
    get_tree().root.set_meta("mb_mode", mode)
    get_tree().root.set_meta("mb_customize", customize)
    var path := "res://checkers.tscn" if section == "checkers" else "res://football.tscn"
    get_tree().change_scene_to_file(path)

# Monster Ball local profile. A player ID/login does not exist yet.
func _profile_load() -> Dictionary:
    var data: Dictionary = {"version": 1, "played": 0, "wins": 0, "losses": 0, "draws": 0, "friend_games": 0, "football_games": 0, "checkers_games": 0}
    if FileAccess.file_exists(MB_PROFILE_FILE):
        var file: FileAccess = FileAccess.open(MB_PROFILE_FILE, FileAccess.READ)
        if file != null:
            var parsed: Variant = JSON.parse_string(file.get_as_text())
            if parsed is Dictionary and int(parsed.get("version", 0)) == 1:
                data.merge(parsed, true)
    return data

func _profile_write(data: Dictionary) -> void:
    var file: FileAccess = FileAccess.open(MB_PROFILE_FILE, FileAccess.WRITE)
    if file == null:
        return
    file.store_string(JSON.stringify(data, "  "))
    file.flush()

func _apply_saved_preferences() -> void:
    var data: Dictionary = _profile_load()
    get_tree().root.set_meta("mb_bot_difficulty", clampi(int(data.get("bot_difficulty", 1)), 0, 2))
    for key in ["football_skins", "checkers_pawn", "checkers_king"]:
        if data.get(key, null) is Array:
            get_tree().root.set_meta("mb_" + key, data[key])

func _profile_message(text_value: String) -> void:
    if profile_notice != null and is_instance_valid(profile_notice):
        profile_notice.text = text_value

func _build_profile_panel() -> void:
    var data: Dictionary = _profile_load()
    var statistics: Label = Label.new()
    statistics.text = "ПРОФИЛЬ ЭТОГО УСТРОЙСТВА\n\nСыграно партий: %d\nПобед над ботом: %d\nПоражений от бота: %d\nНичьих с ботом: %d\nМатчей с другом: %d\n\nФутбол: %d  •  Шашки: %d" % [int(data.get("played", 0)), int(data.get("wins", 0)), int(data.get("losses", 0)), int(data.get("draws", 0)), int(data.get("friend_games", 0)), int(data.get("football_games", 0)), int(data.get("checkers_games", 0))]
    statistics.add_theme_font_size_override("font_size", 19)
    statistics.add_theme_color_override("font_color", Color("#f9e6bc"))
    panel.add_child(statistics)
    var info_scroll: ScrollContainer = ScrollContainer.new()
    info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_child(info_scroll)
    var help: Label = Label.new()
    help.text = "КАК СОХРАНЯЕТСЯ ПРОГРЕСС\n\nАвтоматически в памяти браузера или установленной PWA на этом устройстве (Godot user://, IndexedDB). На сервер и в GitHub прогресс не отправляется.\n\nМатчи с другом увеличивают только число сыгранных партий. Победы и поражения учитываются только против бота. Прерванные матчи не считаются.\n\nПЕРЕНОС НА ДРУГОЙ ТЕЛЕФОН\n1. Нажми «СКАЧАТЬ СОХРАНЕНИЕ» и сохрани JSON в «Файлы» / облако.\n2. Открой Monster Ball на новом устройстве.\n3. Нажми «ВОССТАНОВИТЬ СОХРАНЕНИЕ» и выбери этот JSON.\n4. Подтверди замену прогресса.\n\nВосстановление ЗАМЕНИТ текущую статистику и настройки. Перед ним скачай резервную копию текущего прогресса.\n\nПотерять прогресс можно при удалении данных сайта, приложения или использовании частного режима. Удаление только ярлыка PWA тоже может затронуть его данные — не рассчитывай на их сохранность."
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    help.add_theme_font_size_override("font_size", 15)
    help.add_theme_color_override("font_color", Color("#ebdfd1"))
    help.custom_minimum_size.x = maxf(250.0, size.x * 0.77)
    info_scroll.add_child(help)
    _button("⬇ СКАЧАТЬ СОХРАНЕНИЕ", func(): _download_profile_backup())
    _button("⬆ ВОССТАНОВИТЬ СОХРАНЕНИЕ", func(): _choose_profile_backup())
    profile_notice = Label.new()
    profile_notice.text = "Совет: скачивай копию после важных достижений."
    profile_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    profile_notice.add_theme_font_size_override("font_size", 13)
    profile_notice.add_theme_color_override("font_color", Color("#b7e9c5"))
    panel.add_child(profile_notice)
    _button("← НАЗАД", func(): section = ""; _build())

func _backup_payload() -> Dictionary:
    var profile: Dictionary = _profile_load()
    # Include the current audio settings, which have their own Godot config.
    var audio: Dictionary = {}
    for key in AUDIO_KEYS:
        audio[key] = get_tree().root.get_meta(key)
    profile["audio"] = audio
    return {"format": "monster_ball_save", "version": 1, "profile": profile}

func _download_profile_backup() -> void:
    var json_text: String = JSON.stringify(_backup_payload(), "  ")
    if OS.has_feature("web"):
        # Must run directly from the button gesture: iOS can block delayed downloads.
        JavaScriptBridge.download_buffer(json_text.to_utf8_buffer(), "monster_ball_save.json", "application/json")
        _profile_message("Файл подготовлен. Сохрани его в «Файлы» или облако.")
    else:
        _profile_message("Экспорт файла доступен в веб-версии Monster Ball.")

func _choose_profile_backup() -> void:
    if not OS.has_feature("web"):
        _profile_message("Импорт файла доступен в веб-версии Monster Ball.")
        return
    import_callback_ref = JavaScriptBridge.create_callback(_on_import_selected)
    # Create a real browser file picker; Godot FileDialog cannot read iPhone files in Web.
    var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
    window.mb_import_save = import_callback_ref
    JavaScriptBridge.eval("""
        (() => {
          const input = document.createElement('input');
          input.type = 'file'; input.accept = '.json,application/json';
          input.style.display = 'none'; document.body.appendChild(input);
          input.addEventListener('change', () => {
            const selected = input.files && input.files[0];
            if (selected && selected.size <= 262144) {
              selected.text().then(t => window.mb_import_save(t))
                .catch(() => window.mb_import_save(''));
            } else if (selected) { window.mb_import_save(''); }
            input.remove();
          }, {once:true});
          input.click();
        })()
    """, true)
    _profile_message("Выбери файл monster_ball_save.json из «Файлов».")

func _on_import_selected(args: Array) -> void:
    if args.is_empty() or not (args[0] is String):
        _profile_message("Не удалось прочитать файл сохранения.")
        return
    var parsed: Variant = JSON.parse_string(args[0])
    if not (parsed is Dictionary):
        _profile_message("Неверный формат файла. Нужен JSON из Monster Ball.")
        return
    var backup: Dictionary = parsed
    if backup.get("format", "") != "monster_ball_save" or backup.get("version", -1) != 1:
        _profile_message("Неверная версия файла Monster Ball.")
        return
    var raw_profile: Variant = backup.get("profile", null)
    if not (raw_profile is Dictionary):
        _profile_message("В файле отсутствует профиль.")
        return
    var data: Dictionary = raw_profile
    if data.get("version", -1) != 1:
        _profile_message("В файле отсутствует совместимый профиль.")
        return
    var validated: Dictionary = {}
    for key in ["played", "wins", "losses", "draws", "friend_games", "football_games", "checkers_games"]:
        var value: Variant = data.get(key, 0)
        if not (value is int or value is float) or value < 0 or value > 100000000:
            _profile_message("Файл повреждён: неверная статистика.")
            return
        validated[key] = int(value)
    if validated["played"] != validated["wins"] + validated["losses"] + validated["draws"] + validated["friend_games"]:
        _profile_message("Файл повреждён: сумма партий не совпадает.")
        return
    validated["version"] = 1
    var raw_difficulty: Variant = data.get("bot_difficulty", 1)
    validated["bot_difficulty"] = clampi(int(raw_difficulty), 0, 2) if (raw_difficulty is int or raw_difficulty is float) else 1
    for key in ["football_skins", "checkers_pawn", "checkers_king"]:
        if data.get(key, null) is Array:
            var items: Array = data[key]
            var accepted: Array = []
            if items.size() <= 12:
                for skin in items:
                    if skin is int or skin is float:
                        accepted.append(clampi(int(skin), 0, 3))
                if accepted.size() == items.size():
                    validated[key] = accepted
    var audio: Dictionary = {}
    if data.get("audio", null) is Dictionary:
        var saved: Dictionary = data["audio"]
        for key in ["mb_vol_music", "mb_vol_effects", "mb_vol_crowd"]:
            var raw_volume: Variant = saved.get(key, 0.6)
            audio[key] = clampf(float(raw_volume), 0.0, 1.0) if (raw_volume is int or raw_volume is float) else 0.6
        var raw_muted: Variant = saved.get("mb_muted", false)
        audio["mb_muted"] = raw_muted if raw_muted is bool else false
    validated["audio"] = audio
    pending_profile_import = validated
    var confirm: ConfirmationDialog = ConfirmationDialog.new()
    confirm.title = "Восстановить Monster Ball?"
    confirm.dialog_text = "Текущий прогресс на этом устройстве будет ЗАМЕНЁН сохранением из файла. Продолжить?"
    add_child(confirm)
    confirm.confirmed.connect(func(): _apply_imported_profile())
    confirm.popup_centered()
    confirm.close_requested.connect(func(): confirm.queue_free())
    confirm.confirmed.connect(func(): confirm.queue_free())

func _apply_imported_profile() -> void:
    if pending_profile_import.is_empty():
        return
    _profile_write(pending_profile_import)
    if pending_profile_import.get("audio", null) is Dictionary:
        var cfg: ConfigFile = ConfigFile.new()
        for key in AUDIO_KEYS:
            if pending_profile_import["audio"].has(key):
                cfg.set_value("audio", key, pending_profile_import["audio"][key])
        cfg.save("user://monster_ball_audio.cfg")
    pending_profile_import = {}
    _read_audio_settings()
    _apply_saved_preferences()
    _update_menu_audio()
    _build()
    _profile_message("Прогресс восстановлен. Теперь можно играть!")
