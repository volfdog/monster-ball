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

func _process(delta: float) -> void:
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

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
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
    var pos := Vector2(-1,-1)
    if event is InputEventScreenTouch and event.pressed: pos = event.position
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: pos = event.position
    if pos.x < 0: return
    accept_event()
    if finished:
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
    draw_rect(Rect2(Vector2.ZERO,size),Color("#14111b"))
    var font: Font = ThemeDB.fallback_font
    draw_string(font, Vector2(18, 35), "MONSTER BALL  /  ШАШКИ", HORIZONTAL_ALIGNMENT_LEFT, size.x - 36, 22, Color("#f3d59b"))
    draw_string(font, Vector2(18, 72), message, HORIZONTAL_ALIGNMENT_LEFT, size.x - 36, 17, Color("#d9f6f9"))
    var g: Dictionary = _geometry()
    var s: float = g["side"]
    var o: Vector2 = g["origin"]
    draw_rect(Rect2(o-Vector2(5,5),Vector2(s*8+10,s*8+10)),Color("#8acbdf"),false,3.0)
    for r in N:
        for c in N:
            var p := Vector2i(r,c)
            var at: Vector2 = o+Vector2(c,r)*s
            var rect := Rect2(at,Vector2(s,s))
            var dark: bool = (r+c)%2 == 0
            draw_rect(rect,Color("#182c3a") if dark else Color("#6b7a8a"))
            var texname := "stone_dark" if dark else "stone_light"
            if textures.has(texname): draw_texture_rect(textures[texname],rect,false)
            draw_rect(rect,Color("#0b1926",0.45),false,1.0)
            if p == selected:
                draw_rect(rect,Color("#73ffcf"),false,3.0)
            var data: Dictionary = _piece(p)
            if data["team"] == 0: continue
            var center := at+Vector2.ONE*s*0.5
            var team_idx: int = int(data["team"]) - 1
            var skin_idx: int = king_skin[team_idx] if data["king"] else pawn_skin[team_idx]
            var texname2: String = BLUE_SKINS[skin_idx] if team_idx == 0 else RED_SKINS[skin_idx]
            var inset: float = s*0.06
            if textures.has(texname2):
                draw_texture_rect(textures[texname2],rect.grow(-inset),false)
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
    _draw_bottom_actions()
    if customization_open:
        _draw_customization(font)
        _confirmation_ui()
    elif finished:
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

func _evaluate_bot_checkers(source: Vector2i, target: Vector2i, victim: Vector2i, level: int) -> int:
    var original_from: Dictionary = _piece(source).duplicate()
    var original_to: Dictionary = _piece(target).duplicate()
    var original_victim: Dictionary = {}
    if victim.x >= 0:
        original_victim = _piece(victim).duplicate()
    board[source.x][source.y] = {"team": 0, "king": false}
    board[target.x][target.y] = original_from.duplicate()
    if victim.x >= 0:
        board[victim.x][victim.y] = {"team": 0, "king": false}
    var danger: int = 0
    var enemy_captures: int = 0
    for r in N:
        for c in N:
            var at := Vector2i(r, c)
            if _piece(at)["team"] != 1:
                continue
            for move in _captures(at):
                enemy_captures += 1
                if move["taken"] == target:
                    danger += 1
    var score: int = -danger * (130 if level == 2 else 65)
    score -= mini(enemy_captures, 4) * (9 if level == 2 else 3)
    if original_from["king"]:
        score += 12
    elif target.x == 7:
        score += 100
    if level == 2:
        score += 10 - absi(target.y - 3) * 3
        if victim.x >= 0:
            score += 45
    board[source.x][source.y] = original_from
    board[target.x][target.y] = original_to
    if victim.x >= 0:
        board[victim.x][victim.y] = original_victim
    return score

func _bot_move() -> void:
    if not is_inside_tree():
        return
    await get_tree().create_timer(0.35).timeout
    if not is_inside_tree():
        return
    bot_pending = false
    if game_mode != 0 or turn != 2 or finished:
        return
    var options: Array[Dictionary] = []
    var must: bool = _must_capture(2)
    for r in N:
        for c in N:
            var from := Vector2i(r, c)
            if _piece(from)["team"] != 2:
                continue
            var candidates: Array = _captures(from)
            if not must:
                candidates.append_array(_moves(from))
            for move in candidates:
                var target: Vector2i = move["to"]
                var victim: Vector2i = move["taken"]
                var score: int = (100 if victim.x >= 0 else 0) + target.x * 3
                if target.x == 7:
                    score += 20
                if bot_difficulty == 0:
                    score = randi_range(0, 120)
                else:
                    score += _evaluate_bot_checkers(from, target, victim, bot_difficulty)
                    if bot_difficulty == 1:
                        score += randi_range(-12, 12)
                options.append({"from": from, "to": target, "taken": victim, "score": score})
    if options.is_empty():
        finished = true
        winning_team = 1
        message = "ПОБЕДИЛИ СИНИЕ!"
        queue_redraw()
        return
    options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
    var best: Dictionary = options[0]
    var source: Vector2i = best["from"]
    var dest: Vector2i = best["to"]
    var captured: Vector2i = best["taken"]
    var piece_data: Dictionary = _piece(source).duplicate()
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
    await get_tree().create_timer(0.25).timeout
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
    var dest: Vector2i = move["to"]
    var victim: Vector2i = move["taken"]
    var data: Dictionary = _piece(forced).duplicate()
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
