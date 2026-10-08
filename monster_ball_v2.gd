extends Control

const ROWS = 10
const COLS = 8

func _ready():
    queue_redraw()

func _draw():
    var cell_size = min(size.x / COLS, size.y / ROWS)
    var offset = (size - Vector2(COLS, ROWS) * cell_size) / 2.0

    for row in range(ROWS):
        for col in range(COLS):
            var rect = Rect2(
                offset + Vector2(col, row) * cell_size,
                Vector2.ONE * cell_size
            )
            var color = Color("#30243f") if (row + col) % 2 == 0 else Color("#665174")
            draw_rect(rect, color)

    for col in [0, 2, 4, 6]:
        draw_circle(offset + Vector2(col + 0.5, 9.5) * cell_size, cell_size * 0.32, Color("#4ac5e8"))

    for col in [1, 3, 5, 7]:
        draw_circle(offset + Vector2(col + 0.5, 0.5) * cell_size, cell_size * 0.32, Color("#e45a78"))

    draw_circle(offset + Vector2(3.5, 4.5) * cell_size, cell_size * 0.18, Color("#f6cf65"))
