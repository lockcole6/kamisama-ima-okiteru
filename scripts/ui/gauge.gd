extends Control
## 横長のゲージ。center=true なら中央ゼロの両方向ゲージ（信仰：崇拝⇔憎悪）。

var value := 0.0
var lo := 0.0
var hi := 100.0
var color := Color("3ecf8e")
var neg_color := Color("ff5d6c")
var bg_color := Color("efe8f5")
var center := false


func set_value(v: float) -> void:
	value = v
	queue_redraw()


func _draw() -> void:
	var h := size.y
	var r := int(h / 2.0)
	draw_style_box(_sb(bg_color, r), Rect2(Vector2.ZERO, size))
	var from := 0.0
	var to := 0.0
	var col := color
	if center:
		var mid := size.x / 2.0
		var t := clampf(value / hi, -1.0, 1.0)
		if t >= 0.0:
			from = mid
			to = mid + t * mid
		else:
			from = mid + t * mid
			to = mid
			col = neg_color
	else:
		to = size.x * clampf((value - lo) / (hi - lo), 0.0, 1.0)
	var w := to - from
	if w > 0.5:
		var fill := Rect2(from, 0, maxf(w, h), h)
		if center and value >= 0.0:
			fill.position.x = from
		elif center:
			fill.position.x = to - maxf(w, h)
		draw_style_box(_sb(col, r), fill)
		draw_rect(Rect2(fill.position.x + r * 0.6, 1.5, maxf(0.0, fill.size.x - r * 1.2), h * 0.3), Color(1, 1, 1, 0.35))
	if center:
		draw_rect(Rect2(size.x / 2.0 - 1, -2, 2, h + 4), Color(0.23, 0.18, 0.31, 0.5))


func _sb(c: Color, r: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	return sb
