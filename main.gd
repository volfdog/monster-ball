extends Control

const ROWS := 10
const COLS := 8
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
var game_over := false
var bot_pending := false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    _reset_board()

func _reset_board() -> void:
    pieces.clear()
    for c in [0, 2, 4, 6]:
        pieces.append({"team": 1, "cell": Vector2i(9, c + 1), "alive": true})
    for c in [1, 3, 5, 7]:
        pieces.append({"team": 2, "cell": Vector2i(0, c - 1), "alive": true})
    ball_cell = Vector2i(4, 4)
    ball_holder = -1
    selected = -1
    turn = 1
    game_over = false
    bot_pending = false
    message = "Ход голубых"
    queue_redraw()

func _geometry() -> Dictionary:
    var top_margin := 108.0
    var bottom_margin := 65.0
    var usable := Vector2(size.x, max(1.0, size.y - top_margin - bottom_margin))
    var cell_size: float = min(usable.x / COLS, usable.y / ROWS)
    var offset := Vector2((size.x - COLS * cell_size) / 2.0, top_margin + (usable.y - ROWS * cell_size) / 2.0)
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

func _gui_input(event: InputEvent) -> void:
    var point := Vector2(-1, -1)
    if event is InputEventScreenTouch and event.pressed:
        point = event.position
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        point = event.position
    else:
        return
    accept_event()
    # Tap the mode tabs at the top, or the restart button at the bottom.
    if point.y < 70.0:
        if point.x < size.x * 0.5:
            game_mode = 0
        else:
            game_mode = 1
        scores = [0, 0]
        _reset_board()
        queue_redraw()
        return
    if point.y > size.y - 57.0:
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

func _tap(cell: Vector2i) -> void:
    var clicked := _piece_at(cell)
    if clicked >= 0 and pieces[clicked]["team"] == turn:
        if _team_must_capture(turn) and _captures(clicked).is_empty():
            message = "Нужно съесть фишку соперника"
        else:
            selected = clicked
            message = "Выбери соседнюю диагональную клетку"
        queue_redraw()
        return
    if selected < 0:
        message = "Сначала нажми свою фишку"
        queue_redraw()
        return
    for capture in _captures(selected):
        if capture["cell"] == cell:
            pieces[capture["victim"]]["alive"] = false
            if ball_holder == capture["victim"]:
                ball_holder = selected
            _move_selected(cell)
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
    var dc := abs(cell.y - from.y)
    var forward := -1 if turn == 1 else 1
    if abs(dr) == 1 and dc == 1 and clicked == -1 and (ball_holder != selected or dr == forward):
        _move_selected(cell)
        if not _check_goal():
            _finish_turn()
    else:
        message = "Ходить можно на одну клетку по диагонали"
        queue_redraw()

func _move_selected(cell: Vector2i) -> void:
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
        scores[turn - 1] += 1
        if scores[turn - 1] >= 3:
            message = "Победа голубых!" if turn == 1 else "Победа красных!"
            selected = -1
            game_over = true
            queue_redraw()
        else:
            _reset_board()
            message = "ГОЛ! %d : %d — ход голубых" % [scores[0], scores[1]]
            queue_redraw()
        return true
    return false

func _finish_turn() -> void:
    selected = -1
    turn = 2 if turn == 1 else 1
    message = "Ход голубых" if turn == 1 else "Ход красных"
    queue_redraw()
    if game_mode == 0 and turn == 2 and not game_over:
        _schedule_bot()

func _schedule_bot() -> void:
    if bot_pending or game_over or turn != 2:
        return
    bot_pending = true
    _bot_turn.call_deferred()

func _bot_turn() -> void:
    if not is_inside_tree():
        return
    await get_tree().create_timer(0.4).timeout
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
            candidates.append({"piece": i, "to": capture["cell"], "victim": capture["victim"], "weight": 100})
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
                candidates.append({"piece": i, "to": target, "victim": -1, "weight": weight})
    if candidates.is_empty():
        message = "Бот не может сделать ход"
        turn = 1
        queue_redraw()
        return
    candidates.sort_custom(func(a, b): return a["weight"] > b["weight"])
    var best: Dictionary = candidates[0]
    selected = best["piece"]
    if best["victim"] >= 0:
        pieces[best["victim"]]["alive"] = false
        if ball_holder == best["victim"]:
            ball_holder = selected
    _move_selected(best["to"])
    if _check_goal():
        return
    # Keep capturing with the same piece while captures are available.
    if best["victim"] >= 0:
        while not _captures(selected).is_empty():
            var next_capture: Dictionary = _captures(selected)[0]
            pieces[next_capture["victim"]]["alive"] = false
            if ball_holder == next_capture["victim"]:
                ball_holder = selected
            _move_selected(next_capture["cell"])
            if _check_goal():
                return
    _finish_turn()

func _draw() -> void:
    var geometry := _geometry()
    var side: float = geometry["cell_size"]
    var offset: Vector2 = geometry["offset"]
    draw_rect(Rect2(Vector2.ZERO, size), Color("#14111b"))
    var font: Font = ThemeDB.fallback_font
    draw_string(font, Vector2(18, 27), "MONSTER BALL    %d : %d" % [scores[0], scores[1]], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color.WHITE)
    var tab_width := size.x / 2.0
    draw_rect(Rect2(0, 38, tab_width, 32), Color("#347d80") if game_mode == 0 else Color("#37303d"))
    draw_rect(Rect2(tab_width, 38, tab_width, 32), Color("#347d80") if game_mode == 1 else Color("#37303d"))
    draw_string(font, Vector2(12, 61), "С БОТОМ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
    draw_string(font, Vector2(tab_width + 12, 61), "НА ДВОИХ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
    draw_string(font, Vector2(18, 95), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
    for row in ROWS:
        for col in COLS:
            var rect := Rect2(offset + Vector2(col, row) * side, Vector2.ONE * side)
            draw_rect(rect, Color("#30243f") if (row + col) % 2 == 0 else Color("#665174"))
    for i in pieces.size():
        if not pieces[i]["alive"]:
            continue
        var cell: Vector2i = pieces[i]["cell"]
        var center := offset + Vector2(cell.y + 0.5, cell.x + 0.5) * side
        if i == selected:
            draw_rect(Rect2(offset + Vector2(cell.y, cell.x) * side, Vector2.ONE * side), Color("#a4c886"), false, 4.0)
        draw_circle(center, side * 0.32, BLUE if pieces[i]["team"] == 1 else RED)
        if ball_holder == i:
            draw_circle(center, side * 0.13, BALL)
    if ball_holder == -1:
        draw_circle(offset + Vector2(ball_cell.y + 0.5, ball_cell.x + 0.5) * side, side * 0.18, BALL)
    draw_string(font, Vector2(18, size.y - 24), "СБРОС / НОВАЯ ИГРА", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#dddddd"))
