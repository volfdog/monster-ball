extends Control

const N := 8
const DIRECTIONS := [Vector2i(-1,-1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(1,1)]
var board: Array = []
var turn: int = 1
var selected: Vector2i = Vector2i(-1,-1)
var forced: Vector2i = Vector2i(-1,-1)
var message: String = "Ход синих"
var finished: bool = false
var textures: Dictionary = {}
const BLUE_SKINS := ["blue_knight", "blue_wizard", "blue_rogue", "blue_dwarf"]
const RED_SKINS := ["red_orc", "red_skull", "red_goblin", "red_vampire"]
var pawn_skin: Array[int] = [0, 0]
var king_skin: Array[int] = [1, 1]
var game_mode: int = 0 # 0 bot, 1 two players
var bot_pending: bool = false
var customization_open: bool = false
var customization_team: int = 1
var customization_kind: int = 0 # 0 pawn, 1 king


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    for name in ["stone_dark", "stone_light", "blue_knight", "blue_wizard", "blue_rogue", "blue_dwarf", "red_orc", "red_skull", "red_goblin", "red_vampire"]:
        var path: String = "res://assets/%s.png" % name
        if ResourceLoader.exists(path):
            textures[name] = load(path)
    _new_game()
    game_mode = int(get_tree().root.get_meta("mb_mode", 0))
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
                message = "ПОБЕДИЛИ СИНИЕ!" if turn == 2 else "ПОБЕДИЛИ КРАСНЫЕ!"
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
    if customization_open:
        _customization_tap(pos)
        return
    if pos.y < 42.0:
        get_tree().change_scene_to_file("res://main.tscn")
        return
    if pos.y < 81.0:
        game_mode = 0 if pos.x < size.x * 0.5 else 1
        _new_game()
        return
    if pos.y < 143.0:
        customization_open = true
        customization_team = 1
        customization_kind = 0
        queue_redraw()
        return
    if pos.y > size.y - 65.0:
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
    draw_string(font,Vector2(18,30),"‹  MONSTER BALL / ШАШКИ",HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color.WHITE)
    var half: float = size.x / 2.0
    draw_rect(Rect2(0, 45, half, 35), Color("#347d80") if game_mode == 0 else Color("#34303c"))
    draw_rect(Rect2(half, 45, half, 35), Color("#347d80") if game_mode == 1 else Color("#34303c"))
    draw_string(font, Vector2(10, 69), "С БОТОМ", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
    draw_string(font, Vector2(half + 10, 69), "НА ДВОИХ", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
    draw_rect(Rect2(0, 88, size.x, 49), Color("#283f50"))
    draw_string(font, Vector2(18, 118), "КОСТЮМЫ ФИШЕК И ДАМОК", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#d9f6f9"))
    draw_string(font, Vector2(18, 158), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#d9f6f9"))
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
    draw_string(font,Vector2(18,size.y-25),"НОВАЯ ПАРТИЯ",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color.WHITE)
    if customization_open:
        _draw_customization(font)

func _customization_tap(pos: Vector2) -> void:
    if pos.y < 120.0 or pos.y > size.y - 65.0:
        customization_open = false
    elif pos.y < 180.0:
        customization_team = 1 if pos.x < size.x * 0.5 else 2
    elif pos.y < 235.0:
        customization_kind = 0 if pos.x < size.x * 0.5 else 1
    elif pos.y < 380.0:
        var index: int = clampi(int(pos.x / maxf(1.0, size.x / 4.0)), 0, 3)
        if customization_kind == 0:
            pawn_skin[customization_team - 1] = index
            get_tree().root.set_meta("mb_checkers_pawn", pawn_skin.duplicate())
        else:
            king_skin[customization_team - 1] = index
            get_tree().root.set_meta("mb_checkers_king", king_skin.duplicate())
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
        draw_rect(rect.grow(3.0), Color("#76ffe0") if chosen == i else Color("#536476"), false, 3.0)
        if textures.has(skins[i]):
            draw_texture_rect(textures[skins[i]], rect, false)
        draw_string(font, Vector2(i * w + 10.0, 284.0 + w), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
    draw_string(font, Vector2(14, 416), "Выбери вид для всей команды", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
    draw_string(font, Vector2(14, size.y - 25), "ЗАКРЫТЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

func _schedule_bot() -> void:
    if bot_pending or finished or game_mode != 0 or turn != 2:
        return
    bot_pending = true
    _bot_move.call_deferred()

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
                options.append({"from": from, "to": target, "taken": victim, "score": score})
    if options.is_empty():
        finished = true
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
    queue_redraw()
