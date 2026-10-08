extends Control

const ROWS := 10
const COLS := 8
const START_1 := [Vector2i(9,0),Vector2i(9,2),Vector2i(9,4),Vector2i(9,6),Vector2i(8,3)]
const START_2 := [Vector2i(0,1),Vector2i(0,3),Vector2i(0,5),Vector2i(0,7),Vector2i(1,4)]

var pieces := []
var ball := {"cell": Vector2i(4,3), "holder": -1}
var turn := 1
var selected := -1
var scores := [0,0]
var board: GridContainer
var status: Label
var score_label: Label
var cells := []

func _ready():
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_ui()
    _reset_rally()

func _build_ui():
    var bg=ColorRect.new(); bg.color=Color("07110d"); bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
    var root=VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_theme_constant_override("separation",14); root.offset_left=18;root.offset_right=-18;root.offset_top=28;root.offset_bottom=-24; add_child(root)
    var title=Label.new(); title.text="MONSTER BALL 3.0 · GODOT"; title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size",28); root.add_child(title)
    score_label=Label.new(); score_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; score_label.add_theme_font_size_override("font_size",22); root.add_child(score_label)
    status=Label.new(); status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; root.add_child(status)
    var frame=PanelContainer.new(); frame.size_flags_vertical=Control.SIZE_EXPAND_FILL; root.add_child(frame)
    board=GridContainer.new(); board.columns=COLS; board.size_flags_horizontal=Control.SIZE_EXPAND_FILL; board.size_flags_vertical=Control.SIZE_EXPAND_FILL; board.add_theme_constant_override("h_separation",3); board.add_theme_constant_override("v_separation",3); frame.add_child(board)
    for r in ROWS:
        for c in COLS:
            var b=Button.new(); b.custom_minimum_size=Vector2(56,56); b.size_flags_horizontal=Control.SIZE_EXPAND_FILL; b.size_flags_vertical=Control.SIZE_EXPAND_FILL; b.pressed.connect(_cell_pressed.bind(r,c)); board.add_child(b); cells.append(b)
    var hint=Label.new(); hint.text="Первая Godot-сборка: базовое поле, ходы, обязательное съедение, мяч и голевая зона. HTML v2.2.7 остаётся резервной версией."; hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; root.add_child(hint)

func _reset_rally():
    pieces.clear()
    for i in 5: pieces.append({"team":1,"cell":START_1[i],"alive":true,"hero": i==0})
    for i in 5: pieces.append({"team":2,"cell":START_2[i],"alive":true,"hero": i==0})
    ball={"cell":Vector2i(4,3),"holder":-1}; turn=1; selected=-1; _render()

func _piece_at(cell:Vector2i)->int:
    for i in pieces.size():
        if pieces[i].alive and pieces[i].cell==cell: return i
    return -1

func _captures_for(i:int)->Array:
    var out=[]; var p=pieces[i]
    for d in [Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]:
        var mid=p.cell+d; var land=p.cell+d*2; var j=_piece_at(mid)
        if land.x>=0 and land.x<ROWS and land.y>=0 and land.y<COLS and j>=0 and pieces[j].team!=p.team and _piece_at(land)<0: out.append({"to":land,"eat":j})
    return out

func _team_has_capture(team:int)->bool:
    for i in pieces.size():
        if pieces[i].alive and pieces[i].team==team and not _captures_for(i).is_empty(): return true
    return false

func _cell_pressed(r:int,c:int):
    var cell=Vector2i(r,c); var at=_piece_at(cell)
    if at>=0 and pieces[at].team==turn:
        if _team_has_capture(turn) and _captures_for(at).is_empty(): status.text="Есть обязательное съедение другой фишкой"; return
        selected=at; _render(); return
    if selected<0: return
    var p=pieces[selected]; var caps=_captures_for(selected)
    for cap in caps:
        if cap.to==cell:
            pieces[cap.eat].alive=false
            if ball.holder==cap.eat: ball.holder=selected
            pieces[selected].cell=cell
            if ball.holder==selected: ball.cell=cell
            if not _captures_for(selected).is_empty(): status.text="Продолжай серию съедений"; _render(); return
            _end_turn(); return
    if _team_has_capture(turn): status.text="Съедение обязательно"; return
    var dr=cell.x-p.cell.x; var dc=abs(cell.y-p.cell.y)
    var forward = -1 if turn==1 else 1
    if dc==1 and abs(dr)==1 and _piece_at(cell)<0 and (ball.holder!=selected or dr==forward):
        pieces[selected].cell=cell
        if ball.holder==selected: ball.cell=cell
        elif ball.holder<0 and ball.cell==cell: ball.holder=selected
        _check_goal(selected)
        if scores[0]>=3 or scores[1]>=3: return
        _end_turn()

func _check_goal(i:int):
    if ball.holder!=i: return
    var p=pieces[i]; var goal_row=0 if p.team==1 else 9
    if p.cell.x==goal_row and p.cell.y>=2 and p.cell.y<=5:
        scores[p.team-1]+=1
        if scores[p.team-1]>=3:
            status.text="Команда %d победила матч!" % p.team; _render(); return
        status.text="ГОЛ! Новый розыгрыш"; _reset_rally()

func _end_turn():
    selected=-1; turn=2 if turn==1 else 1; status.text="Ход команды %d"%turn; _render()

func _render():
    score_label.text="%d  :  %d" % [scores[0],scores[1]]
    if status.text=="": status.text="Ход команды %d"%turn
    for r in ROWS:
        for c in COLS:
            var idx=r*COLS+c; var b:Button=cells[idx]; var cell=Vector2i(r,c)
            b.text=""; b.modulate=Color("31463e") if (r+c)%2==0 else Color("13231e")
            if (r==0 or r==9) and c>=2 and c<=5: b.modulate=Color("34556a")
            var pi=_piece_at(cell)
            if pi>=0:
                var p=pieces[pi]; b.text=("🔵" if p.team==1 else "🔴") + ("★" if p.hero else "")
                if pi==selected: b.modulate=Color("6f8f72")
            if ball.holder<0 and ball.cell==cell: b.text += "⚽"
