extends Node2D
## 町の表示（SubViewport 内・360×400 のピクセルアート）。Sim の状態を読んで描くだけ。
## 背景は tools/gen_art.py が生成した画像。タイル 16px、22×25 マス。

const TILE := 16
const ORIGIN := Vector2(4, 0)
const AREA := Vector2(360, 400)
const ResidentScene := preload("res://scenes/Resident.tscn")
const BG_TEX := preload("res://assets/sprites/town_bg.png")
const GLOW_TEX := preload("res://assets/sprites/town_glow.png")
const GRAVE_TEX := preload("res://assets/sprites/grave.png")

var _bg: Sprite2D
var _glow: Sprite2D
var _graves: Node2D
var _people: Node2D
var _fx: Node2D
var _nodes: Dictionary = {}
var _shade := Color.WHITE
var _night := 0.0
var _t := 0.0
var _fireflies: Array = []
var _winds: Array = []   # 風の演出 {pos, t}


func _ready() -> void:
	_bg = Sprite2D.new()
	_bg.texture = BG_TEX
	_bg.centered = false
	add_child(_bg)
	_glow = Sprite2D.new()
	_glow.texture = GLOW_TEX
	_glow.centered = false
	_glow.modulate.a = 0.0
	add_child(_glow)
	_graves = Node2D.new()
	add_child(_graves)
	_people = Node2D.new()
	_people.y_sort_enabled = true
	add_child(_people)
	_fx = Node2D.new()
	add_child(_fx)
	_fx.draw.connect(_draw_fx)
	for i in 14:
		_fireflies.append(Vector3(randf() * AREA.x, randf() * AREA.y, randf() * TAU))
	Sim.state_changed.connect(refresh)
	Sim.resident_bubble.connect(func(id, text):
		if _nodes.has(id):
			_nodes[id].bubble(text))
	_apply_sky(true)


static func tile_to_px(v: Vector2i) -> Vector2:
	return ORIGIN + Vector2(v) * TILE + Vector2(TILE / 2.0, TILE / 2.0 + 4)


func refresh() -> void:
	for r in Sim.residents:
		var id: String = r["id"]
		if not _nodes.has(id):
			var n: Node2D = ResidentScene.instantiate()
			_people.add_child(n)
			n.setup(r, tile_to_px(r["pos"]))
			_nodes[id] = n
		_nodes[id].sync(r, tile_to_px(r["pos"]))
		_nodes[id].shade = _shade
	if _graves.get_child_count() != Sim.graves.size():
		for c in _graves.get_children():
			c.queue_free()
		for g in Sim.graves:
			var s := Sprite2D.new()
			s.texture = GRAVE_TEX
			s.position = tile_to_px(g["pos"]) + Vector2(0, -8)
			_graves.add_child(s)


## タップ位置にいちばん近い場所（風の行き先）
func nearest_place(p: Vector2) -> String:
	var best := "plaza"
	var best_d := INF
	for pid in Sim.PLACES:
		var d := tile_to_px(Sim.PLACES[pid]).distance_to(p)
		if d < best_d:
			best_d = d
			best = pid
	return best


func wind_fx(place: String) -> void:
	_winds.append({"pos": tile_to_px(Sim.PLACES[place]), "t": 0.0})


func select(id: String) -> void:
	for k in _nodes:
		_nodes[k].selected = k == id


func on_god_woke() -> void:
	for n in _nodes.values():
		n.bubble("!", 2.0)


## タップ位置（町のローカル座標）にある住民か墓を返す
func pick(p: Vector2) -> Dictionary:
	if p.y < 0 or p.y > AREA.y:
		return {}
	var best := ""
	var best_d := 14.0
	for id in _nodes:
		var n: Node2D = _nodes[id]
		if not n.visible:
			continue
		var d := (n.position + Vector2(0, -8)).distance_to(p)
		if n.praying:  # 祈りの吹き出しもタップ対象
			d = minf(d, (n.position + Vector2(0, -26)).distance_to(p))
		if d < best_d:
			best_d = d
			best = id
	if best != "":
		return {"type": "resident", "id": best}
	for i in Sim.graves.size():
		if (tile_to_px(Sim.graves[i]["pos"]) + Vector2(0, -8)).distance_to(p) < 10.0:
			return {"type": "grave", "index": i}
	return {}


func _process(delta: float) -> void:
	_t += delta
	for w in _winds:
		w["t"] += delta
	_winds = _winds.filter(func(w): return w["t"] < 2.2)
	_apply_sky(false)
	_fx.queue_redraw()


## 時間帯で町の色を変える（乗算）。夜は窓に明かりがつく
func _apply_sky(instant: bool) -> void:
	var h := GameClock.local(GameClock.now())
	var hour := float(h["hour"]) + float(h["minute"]) / 60.0
	var target := _sky_color(hour)
	var night := _night_amount(hour)
	if Sim.weather == "rain":
		target *= Color(0.82, 0.86, 0.95)
	var k := 1.0 if instant else 0.05
	_shade = _shade.lerp(target, k)
	_night = lerpf(_night, night, k)
	_bg.modulate = _shade
	_graves.modulate = _shade
	_glow.modulate.a = _night
	for n in _nodes.values():
		n.shade = _shade


static func _sky_color(h: float) -> Color:
	var keys := [
		[0.0, Color(0.38, 0.42, 0.68)], [4.5, Color(0.38, 0.42, 0.68)], [6.0, Color(1.0, 0.86, 0.8)],
		[7.5, Color(1, 1, 1)], [16.5, Color(1, 1, 1)], [18.0, Color(1.0, 0.8, 0.7)],
		[19.5, Color(0.55, 0.55, 0.8)], [22.0, Color(0.4, 0.44, 0.7)], [24.0, Color(0.38, 0.42, 0.68)],
	]
	for i in keys.size() - 1:
		if h >= keys[i][0] and h <= keys[i + 1][0]:
			var t: float = (h - keys[i][0]) / maxf(0.001, keys[i + 1][0] - keys[i][0])
			return (keys[i][1] as Color).lerp(keys[i + 1][1], t)
	return Color.WHITE


static func _night_amount(h: float) -> float:
	if h >= 19.0 or h < 5.0:
		return 1.0
	if h >= 17.5:
		return (h - 17.5) / 1.5
	if h < 6.5:
		return 1.0 - (h - 5.0) / 1.5
	return 0.0


func _draw_fx() -> void:
	# 風が運んだ花（咲いたものは町に残る）
	for b in Sim.blooms:
		if not b["bloomed"]:
			continue
		var c := tile_to_px(Sim.PLACES[b["place"]]) + Vector2(0, -2)
		var rs := RandomNumberGenerator.new()
		rs.seed = int(b["seed"])
		for i in 7:
			var fp := (c + Vector2(rs.randf_range(-22, 22), rs.randf_range(-10, 10))).round()
			var col: Color = [Color("ff8fc4"), Color("ffe066"), Color("b9a6ff"), Color.WHITE][rs.randi() % 4]
			_fx.draw_rect(Rect2(fp + Vector2(0, 1), Vector2(1, 2)), Color("4f9a4a") * _shade)
			_fx.draw_rect(Rect2(fp - Vector2(1, 0), Vector2(3, 1)), col * _shade)
			_fx.draw_rect(Rect2(fp - Vector2(0, 1), Vector2(1, 3)), col * _shade)
			_fx.draw_rect(Rect2(fp, Vector2(1, 1)), Color("f6a33b") * _shade)
	# 風の演出（白い筋と木の葉）
	for w in _winds:
		var k: float = w["t"] / 2.2
		var a := sin(k * PI)
		for i in 7:
			var y: float = w["pos"].y - 30 + i * 9 + sin(_t * 6.0 + i) * 2.0
			var x: float = w["pos"].x - 70 + fmod(k * 160.0 + i * 23.0, 140.0)
			_fx.draw_line(Vector2(x, y).round(), Vector2(x + 14, y).round(), Color(1, 1, 1, 0.8 * a), 1.0)
			_fx.draw_rect(Rect2(Vector2(x + 18, y - 2 + sin(_t * 9.0 + i) * 3.0).round(), Vector2(2, 1)), Color(0.5, 0.8, 0.35, a))
	# 蛍（夜だけ）
	if _night > 0.3 and Sim.weather != "rain":
		for f in _fireflies:
			var p := Vector2(fmod(f.x + sin(_t * 0.3 + f.z) * 20.0 + 400.0, AREA.x), fmod(f.y + cos(_t * 0.25 + f.z) * 14.0 + 400.0, AREA.y))
			var a := (0.5 + 0.5 * sin(_t * 2.0 + f.z * 3.0)) * _night
			_fx.draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(1.0, 0.95, 0.5, a))
			_fx.draw_rect(Rect2(p.round() - Vector2(1, 1), Vector2(3, 3)), Color(1.0, 0.9, 0.4, a * 0.25))
	# 雨
	if Sim.weather == "rain":
		var off := fmod(_t * 240.0, AREA.y)
		for i in 80:
			var x := fmod(i * 53.7 + _t * 30.0, AREA.x)
			var y := fmod(i * 97.3 + off, AREA.y)
			_fx.draw_line(Vector2(x, y).round(), Vector2(x - 2, y + 6).round(), Color(0.8, 0.88, 1.0, 0.7), 1.0)
		for i in 16:
			var sx := fmod(i * 131.1 + floor(_t * 6.0) * 17.0, AREA.x)
			var sy := fmod(i * 71.9 + floor(_t * 6.0) * 29.0, AREA.y)
			_fx.draw_rect(Rect2(Vector2(sx, sy).round(), Vector2(3, 1)), Color(0.85, 0.92, 1.0, 0.6))
