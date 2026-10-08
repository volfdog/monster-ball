extends Control

var section: String = ""
var backdrop: Texture2D
var panel: VBoxContainer

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    backdrop = load("res://assets/menu_heroes.png")
    _build()

func _build() -> void:
    for child in get_children():
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
    panel.anchor_top = 0.55
    panel.anchor_bottom = 0.98
    panel.offset_left = 0
    panel.offset_right = 0
    panel.offset_top = 0
    panel.offset_bottom = 0
    panel.add_theme_constant_override("separation", 12)
    add_child(panel)
    var heading := Label.new()
    heading.text = "ДОБРО ПОЖАЛОВАТЬ!" if section == "" else ("ШАШКИ" if section == "checkers" else "ФУТБОЛ")
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    heading.add_theme_font_size_override("font_size", 27)
    heading.add_theme_color_override("font_color", Color("#f5dca6"))
    panel.add_child(heading)
    if section == "":
        _button("♟  ШАШКИ", func(): section = "checkers"; _build())
        _button("⚽  ФУТБОЛ", func(): section = "football"; _build())
    else:
        _button("ИГРА С БОТОМ", func(): _launch(0, false))
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
    b.pressed.connect(action)
    panel.add_child(b)

func _launch(mode: int, customize: bool) -> void:
    get_tree().root.set_meta("mb_mode", mode)
    get_tree().root.set_meta("mb_customize", customize)
    var path := "res://checkers.tscn" if section == "checkers" else "res://football.tscn"
    get_tree().change_scene_to_file(path)
