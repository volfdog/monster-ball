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
var winner := 0


# High-detail fantasy assets are loaded from the local assets folder.
var fantasy_textures: Dictionary = {}

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

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    _load_fantasy_assets()
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
    winner = 0
    bot_pending = false
    message = "Ход голубых"
    queue_redraw()

func _geometry() -> Dictionary:
    var top_margin := 120.0
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
            winner = turn
            message = "ПОБЕДА!" if (game_mode == 1 or turn == 1) else "ВЫ ПРОИГРАЛИ"
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
    # Fantasy stone board. Geometry and input coordinates stay unchanged.
    var board_size := Vector2(COLS * side, ROWS * side)
    draw_rect(Rect2(offset - Vector2(6, 6), board_size + Vector2(12, 12)), Color("#0b1925"))
    draw_rect(Rect2(offset - Vector2(4, 4), board_size + Vector2(8, 8)), Color("#61869c"), false, 3.0)
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
    draw_rect(Rect2(offset, board_size), Color("#82cadc", 0.75), false, 2.0)
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
            draw_rect(Rect2(offset + Vector2(cell.y, cell.x) * side, Vector2.ONE * side), Color("#7ff9e2"), false, 3.0)
        var team: int = pieces[i]["team"]
        var key: String = ["blue_wizard", "blue_rogue", "blue_knight", "blue_dwarf"][i % 4] if team == 1 else ["red_skull", "red_orc", "red_goblin", "red_vampire"][i % 4]
        var token_side := side * 0.93
        if not _draw_asset(key, Rect2(center - Vector2.ONE * token_side * 0.5, Vector2.ONE * token_side)):
            _draw_fantasy_token(center, side * 0.37, team, i)
        if ball_holder == i:
            var pumpkin_center := center + Vector2(side * 0.17, -side * 0.20)
            var pumpkin_size := side * 0.50
            if not _draw_asset("ghost_pumpkin", Rect2(pumpkin_center - Vector2.ONE * pumpkin_size * 0.5, Vector2.ONE * pumpkin_size)):
                _draw_ghost_pumpkin(pumpkin_center, side * 0.16)
    if ball_holder == -1:
        var pumpkin_center := offset + Vector2(ball_cell.y + 0.5, ball_cell.x + 0.5) * side
        var pumpkin_size := side * 0.90
        if not _draw_asset("ghost_pumpkin", Rect2(pumpkin_center - Vector2.ONE * pumpkin_size * 0.5, Vector2.ONE * pumpkin_size)):
            _draw_ghost_pumpkin(pumpkin_center, side * 0.23)
    draw_string(font, Vector2(18, size.y - 24), "СБРОС / НОВАЯ ИГРА", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#dddddd"))
    if game_over:
        var panel := Rect2(Vector2(18, size.y * 0.38), Vector2(size.x - 36, 145))
        draw_rect(panel, Color("#15111eef"))
        draw_rect(panel, Color("#f6cf65"), false, 3.0)
        var heading := "ПОЗДРАВЛЯЕМ С ПОБЕДОЙ!" if (game_mode == 1 or winner == 1) else "ВЫ ПРОИГРАЛИ!"
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 52), heading, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 24, Color.WHITE)
        var detail := "Победили голубые" if winner == 1 else "Победили красные"
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 87), "%s · Счёт %d : %d" % [detail, scores[0], scores[1]], HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 17, Color("#f6cf65"))
        draw_string(font, Vector2(panel.position.x + 18, panel.position.y + 117), "Нажми НОВАЯ ИГРА, чтобы сыграть ещё", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36, 14, Color.WHITE)


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
