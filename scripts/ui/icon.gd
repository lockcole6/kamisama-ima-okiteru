extends Control
## ベクター描画の簡易アイコン（24x24 を基準に拡大縮小）。画像素材を使わずに済ませるための仮実装。

var kind := "sun"
var color := Color.WHITE


static func make(k: String, col: Color, px: float = 22.0) -> Control:
	var ic: Control = load("res://scripts/ui/icon.gd").new()
	ic.kind = k
	ic.color = col
	ic.custom_minimum_size = Vector2(px, px)
	ic.size = Vector2(px, px)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


func set_kind(k: String, col: Color) -> void:
	kind = k
	color = col
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y) / 24.0
	draw_set_transform((size - Vector2(24, 24) * s) / 2.0, 0.0, Vector2(s, s))
	var c := color
	match kind:
		"sun":
			draw_circle(Vector2(12, 12), 5.0, c)
			for i in 8:
				var a := i * PI / 4.0
				var d := Vector2(cos(a), sin(a))
				draw_line(Vector2(12, 12) + d * 7.5, Vector2(12, 12) + d * 10.5, c, 2.2, true)
		"moon":
			# 三日月 = 外円のうち内円の外側 ＋ 内円のうち外円の内側（逆回り）
			var c1 := Vector2(11, 13)
			var c2 := Vector2(15.5, 9.5)
			var r1 := 9.0
			var r2 := 7.5
			var base := (c1 - c2).angle()
			var pts := PackedVector2Array()
			for i in 49:
				var a := base + lerpf(-PI, PI, i / 48.0)
				var p := c1 + Vector2(cos(a), sin(a)) * r1
				if p.distance_to(c2) > r2:
					pts.append(p)
			for i in 49:
				var a := base + lerpf(PI, -PI, i / 48.0)
				var p := c2 + Vector2(cos(a), sin(a)) * r2
				if p.distance_to(c1) < r1:
					pts.append(p)
			if pts.size() >= 3:
				draw_colored_polygon(pts, c)
		"cloud", "rain":
			var y := 10.0 if kind == "rain" else 12.0
			draw_circle(Vector2(8, y + 2), 4.5, c)
			draw_circle(Vector2(13, y - 1), 6.0, c)
			draw_circle(Vector2(17.5, y + 2.5), 4.0, c)
			draw_rect(Rect2(6, y + 2, 13, 4.5), c)
			if kind == "rain":
				for x in [8.0, 12.5, 17.0]:
					draw_line(Vector2(x, 19), Vector2(x - 1.5, 22.5), c, 2.0, true)
		"scroll":
			draw_rect(Rect2(5, 4, 14, 16), c, false, 2.0)
			for yy in [9.0, 12.5, 16.0]:
				draw_line(Vector2(8, yy), Vector2(16, yy), c, 1.8, true)
		"halo":
			_ellipse(Vector2(12, 8), Vector2(9, 3.5), c, 2.4)
			_star(Vector2(12, 16), 5.5, c)
		"sparkle":
			_star(Vector2(12, 12), 10.0, c)
			_star(Vector2(19, 5), 3.5, c)
		"pray":
			var pts := PackedVector2Array([Vector2(12, 2), Vector2(16.5, 9), Vector2(17, 19), Vector2(15, 22),
				Vector2(9, 22), Vector2(7, 19), Vector2(7.5, 9)])
			draw_colored_polygon(pts, c)
			draw_line(Vector2(12, 5), Vector2(12, 21), Color(0, 0, 0, 0.25), 1.2, true)
			_star(Vector2(20, 4), 3.0, c)
			_star(Vector2(4, 7), 2.4, c)
		"heart":
			draw_circle(Vector2(8.5, 9.5), 4.8, c)
			draw_circle(Vector2(15.5, 9.5), 4.8, c)
			draw_colored_polygon(PackedVector2Array([Vector2(4, 11), Vector2(20, 11), Vector2(12, 20.5)]), c)
		"bolt":
			draw_colored_polygon(PackedVector2Array([Vector2(14, 2), Vector2(5, 13.5), Vector2(11, 13.5),
				Vector2(9, 22), Vector2(19, 9.5), Vector2(13, 9.5)]), c)
		"dots":
			for x in [6.0, 12.0, 18.0]:
				draw_circle(Vector2(x, 12), 2.4, c)
		"tap":
			draw_circle(Vector2(12, 13), 3.5, c)
			draw_arc(Vector2(12, 13), 7.5, 0, TAU, 32, c, 2.0, true)
			draw_line(Vector2(12, 1.5), Vector2(12, 3.5), c, 2.0, true)
			draw_line(Vector2(3.5, 5), Vector2(5, 6.5), c, 2.0, true)
			draw_line(Vector2(20.5, 5), Vector2(19, 6.5), c, 2.0, true)
		"close":
			draw_line(Vector2(6, 6), Vector2(18, 18), c, 3.0, true)
			draw_line(Vector2(18, 6), Vector2(6, 18), c, 3.0, true)
		"wind":
			draw_polyline(PackedVector2Array([Vector2(3, 8), Vector2(14, 8), Vector2(17, 6.5), Vector2(17.5, 4), Vector2(15.5, 2.5), Vector2(13.5, 3.5)]), c, 2.2, true)
			draw_polyline(PackedVector2Array([Vector2(3, 13), Vector2(19, 13), Vector2(21.5, 11), Vector2(21, 8.5), Vector2(19, 8)]), c, 2.2, true)
			draw_polyline(PackedVector2Array([Vector2(5, 18), Vector2(13, 18), Vector2(15.5, 19.5), Vector2(15, 22), Vector2(13, 22.5)]), c, 2.2, true)
		"book":
			draw_colored_polygon(PackedVector2Array([Vector2(12, 6), Vector2(4, 4), Vector2(4, 19), Vector2(12, 21)]), c)
			draw_colored_polygon(PackedVector2Array([Vector2(12, 6), Vector2(20, 4), Vector2(20, 19), Vector2(12, 21)]), Color(c, c.a * 0.75))
			draw_line(Vector2(12, 6), Vector2(12, 21), Color(0, 0, 0, 0.25), 1.2, true)
			_star(Vector2(16, 11), 2.6, Color(1, 1, 1, 0.8 * c.a))
		"sound", "mute":
			draw_colored_polygon(PackedVector2Array([Vector2(3, 9), Vector2(8, 9), Vector2(13, 4), Vector2(13, 20), Vector2(8, 15), Vector2(3, 15)]), c)
			if kind == "sound":
				draw_arc(Vector2(13, 12), 4.5, -0.9, 0.9, 12, c, 2.0, true)
				draw_arc(Vector2(13, 12), 8.0, -0.9, 0.9, 16, c, 2.0, true)
			else:
				draw_line(Vector2(16, 8), Vector2(22, 16), c, 2.2, true)
				draw_line(Vector2(22, 8), Vector2(16, 16), c, 2.2, true)
		"gear":
			for i in 8:
				var a := i * PI / 4.0
				var d := Vector2(cos(a), sin(a))
				draw_line(Vector2(12, 12) + d * 6.5, Vector2(12, 12) + d * 10.0, c, 3.6, true)
			draw_circle(Vector2(12, 12), 7.2, c)
			draw_circle(Vector2(12, 12), 3.0, Color(1, 1, 1, 1))
		"clock":
			draw_arc(Vector2(12, 12), 8.5, 0, TAU, 32, c, 2.2, true)
			draw_line(Vector2(12, 12), Vector2(12, 7), c, 2.2, true)
			draw_line(Vector2(12, 12), Vector2(15.5, 13.5), c, 2.2, true)
		"grave":
			draw_colored_polygon(PackedVector2Array([Vector2(6, 21), Vector2(6, 9), Vector2(8, 5), Vector2(12, 3.5),
				Vector2(16, 5), Vector2(18, 9), Vector2(18, 21)]), c)
			draw_line(Vector2(12, 8), Vector2(12, 16), Color(0, 0, 0, 0.3), 1.8)
			draw_line(Vector2(9, 11), Vector2(15, 11), Color(0, 0, 0, 0.3), 1.8)


func _star(p: Vector2, r: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := i * PI / 4.0 - PI / 2.0
		var rr := r if i % 2 == 0 else r * 0.32
		pts.append(p + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, c)


func _ellipse(p: Vector2, r: Vector2, c: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(p + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_polyline(pts, c, w, true)
