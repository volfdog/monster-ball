extends Control

const ROWS := 10
const COLS := 8
const START_1 := [Vector2i(9,0), Vector2i(9,2), Vector2i(9,4), Vector2i(9,6), Vector2i(8,3)]
const START_2 := [Vector2i(0,1), Vector2i(0,3), Vector2i(0,5), Vector2i(0,7), Vector2i(1,4)]

var pieces: Array = []
var ball := {"cell": Vector2i(4,3), "holder": -1}
var turn := 1
var selected := -1
var scores := [0, 0]
var cells: Array[Button] = []
var status: Label
var score_label: Label
var game_over := false

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_ui()
    _reset_rally()

func _build_ui() -> void:
    var bg := ColorRect.new()
    bg.color = Color("07110d")
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    var root := VBoxContainer.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.offset_left = 12
    root.offset_right = -12
    root.offset_top = 18
    root.offset_bottom = -18
    root.add_theme_constant_override("separation", 10)
    add_child(root)

    var title := Label.new()
    title.text = "MONSTER BALL 3.0"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 25)
    root.add_child(title)

    score_label = Label.new()
    score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    score_label.add_theme_font_size_override("font_size", 22)
    root.add_child(score_label)

    status = Label.new()
    status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    root.add_child(status)

    var frame := PanelContainer.new()
    frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(frame)

    var board := GridContainer.new()
    board.columns = COLS
    board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    board.size_flags_vertical = Control.SIZE_EXPAND_FILL
    board.add_theme_constant_override("h_separation", 2)
    board.add_theme_constant_override("v_separation", 2)
    frame.add_child(board)

    for r in range(ROWS):
        for c in range(COLS):
            var b := Button.new()
            b.custom_minimum_size = Vector2(36, 36)
            b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            b.size_flags_vertical = Control.SIZE_EXPAND_FILL
            b.focus_mode = Control.FOCUS_NONE
            b.pressed.connect(_cell_pressed.bind(r, c))
            board.add_child(b)
            cells.append(b)

    var hint := Label.new()
    hint.text = "Нажми свою фишку, затем соседнюю клетку по диагонали"
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    root.add_child(hint)

func _reset_rally() -> void:
    pieces.clear()
    for i in range(5):
        pieces.append({"team": 1, "cell": START_1[i], "alive": true, "hero": i == 0})
    for i in range(5):
        pieces.append({"team": 2, "cell": START_2[i], "alive": true, "hero": i == 0})
    ball = {"cell": Vector2i(4,3), "holder": -1}
    turn = 1
    selected = -1
    status.text = "Ход синих. Нажми синюю фишку"
    _render()

func _piece_at(cell: Vector2i) -> int:
    for i in range(pieces.size()):
        if pieces[i]["alive"] and pieces[i]["cell"] == cell:
            return i
    return -1

func _captures_for(i: int) -> Array:
    var out: Array = []
    var p: Dictionary = pieces[i]
    for d in [Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)]:
        var mid: Vector2i = p["cell"] + d
        var land: Vector2i = p["cell"] + d * 2
        if land.x < 0 or land.x >= ROWS or land.y < 0 or land.y >= COLS:
            continue
        var j := _piece_at(mid)
        if j >= 0 and pieces[j]["team"] != p["team"] and _piece_at(land) < 0:
            out.append({"to": land, "eat": j})
    return out

func _team_has_capture(team: int) -> bool:
    for i in range(pieces.size()):
        if pieces[i]["alive"] and pieces[i]["team"] == team and not _captures_for(i).is_empty():
            return true
    return false

func _cell_pressed(r: int, c: int) -> void:
    if game_over:
        return
    var cell := Vector2i(r, c)
    var at := _piece_at(cell)
    if at >= 0 and pieces[at]["team"] == turn:
        if _team_has_capture(turn) and _captures_for(at).is_empty():
            status.text = "Нужно съесть соперника другой фишкой"
            return
        selected = at
        status.text = "Фишка выбрана. Нажми клетку для хода"
        _render()
        return
    if selected < 0:
        status.text = "Сначала нажми свою фишку"
        return
    if at >= 0:
        status.text = "Клетка занята"
        return
    var p: Dictionary = pieces[selected]
    for cap in _captures_for(selected):
        if cap["to"] == cell:
            pieces[cap["eat"]]["alive"] = false
            if ball["holder"] == cap["eat"]:
                ball["holder"] = selected
            pieces[selected]["cell"] = cell
            if ball["holder"] == selected:
                ball["cell"] = cell
            elif ball["holder"] < 0 and ball["cell"] == cell:
                ball["holder"] = selected
            if _check_goal(selected):
                return
            if not _captures_for(selected).is_empty():
                status.text = "Продолжай серию съедений"
                _render()
                return
            _end_turn()
            return
    if _team_has_capture(turn):
        status.text = "Съедение обязательно"
        return
    var dr: int = cell.x - p["cell"].x
    var dc: int = abs(cell.y - p["cell"].y)
    var forward := -1 if turn == 1 else 1
    if dc == 1 and abs(dr) == 1 and (ball["holder"] != selected or dr == forward):
        pieces[selected]["cell"] = cell
        if ball["holder"] == selected:
            ball["cell"] = cell
        elif ball["holder"] < 0 and ball["cell"] == cell:
            ball["holder"] = selected
        if _check_goal(selected):
            return
        _end_turn()
    else:
        status.text = "Ходи на одну клетку по диагонали"

func _check_goal(i: int) -> bool:
    if ball["holder"] != i:
        return false
    var p: Dictionary = pieces[i]
    var goal_row := 0 if p["team"] == 1 else 9
    if p["cell"].x == goal_row and p["cell"].y >= 2 and p["cell"].y <= 5:
        scores[p["team"] - 1] += 1
        if scores[p["team"] - 1] >= 3:
            game_over = true
            status.text = "Команда %d победила матч!" % p["team"]
            _render()
        else:
            _reset_rally()
            status.text = "ГОЛ! Новый розыгрыш"
        return true
    return false

func _end_turn() -> void:
    selected = -1
    turn = 2 if turn == 1 else 1
    status.text = "Ход синих" if turn == 1 else "Ход красных"
    _render()

func _render() -> void:
    score_label.text = "%d : %d" % [scores[0], scores[1]]
    for r in range(ROWS):
        for c in range(COLS):
            var idx := r * COLS + c
            var b: Button = cells[idx]
            var cell := Vector2i(r, c)
            b.text = ""
            b.modulate = Color("566d60") if (r + c) % 2 == 0 else Color("253c30")
            if (r == 0 or r == 9) and c >= 2 and c <= 5:
                b.modulate = Color("547a98")
            var pi := _piece_at(cell)
            if pi >= 0:
                var p: Dictionary = pieces[pi]
                b.text = ("🔵" if p["team"] == 1 else "🔴") + ("★" if p["hero"] else "")
                if pi == selected:
                    b.modulate = Color("a3c76b")
            if ball["holder"] < 0 and ball["cell"] == cell:
                b.text += "⚽"
            elif pi >= 0 and ball["holder"] == pi:
                b.text += "⚽"
