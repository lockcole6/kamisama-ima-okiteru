extends Node2D
## 住民1人分の表示（ピクセルアートのスプライト＋影＋吹き出し＋エフェクト）。
## 居場所（anchor）は Sim が決め、その周りをうろうろ歩くのは表示だけの演出。
## ノードの原点 = 足元。

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const OUTLINE := Color("2a1e36")
const PRAY_COL := Color("ffcf3f")

## [アニメ名, シートの行, フレーム数, fps, ループ]（tools/gen_art.py の ANIMS と同じ並び）
const ANIMS := [
	["idle", 0, 2, 2.0, true], ["walk_down", 1, 4, 8.0, true], ["walk_up", 2, 4, 8.0, true],
	["walk_side", 3, 4, 8.0, true], ["pray", 4, 2, 1.5, true], ["sleep", 5, 2, 1.0, true],
	["work", 6, 2, 3.0, true], ["surprise", 7, 2, 8.0, true],
]

var rid := ""
var display_name := ""
var state := "sleeping"
var praying := false
var dreaming := false
var anchor := Vector2.ZERO
var selected := false
var shade := Color.WHITE:
	set(v):
		shade = v
		if _sprite:
			_sprite.modulate = v

var _sprite: AnimatedSprite2D
var _over: Node2D  # スプライトより手前に描くもの（吹き出し・名前・粒）
var _target := Vector2.ZERO
var _wait := 0.0
var _moving := false
var _bubble_text := ""
var _bubble_time := 0.0
var _react := 0.0
var _shake := 0.0
var _particles: Array = []
var _t := 0.0
var _font: Font


func setup(r: Dictionary, anchor_px: Vector2) -> void:
	rid = r["id"]
	display_name = r["name"]
	_font = UITheme.pixel_font()
	anchor = anchor_px
	position = anchor_px
	_target = anchor_px
	_t = randf() * 10.0
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _build_frames(load("res://assets/sprites/chara_%s.png" % rid))
	_sprite.position = Vector2(0, -8)
	_sprite.play("idle")
	_sprite.frame = randi() % 2
	add_child(_sprite)
	_over = Node2D.new()
	_over.z_index = 5
	add_child(_over)
	_over.draw.connect(_draw_over)


static func _build_frames(tex: Texture2D) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for a in ANIMS:
		sf.add_animation(a[0])
		sf.set_animation_speed(a[0], a[3])
		sf.set_animation_loop(a[0], a[4])
		for i in a[2]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * 16, a[1] * 16, 16, 16)
			sf.add_frame(a[0], at)
	return sf


func sync(r: Dictionary, anchor_px: Vector2) -> void:
	state = r["state"]
	praying = not r["prayer"].is_empty() and state != "dead"
	dreaming = not r["dream"].is_empty()
	visible = state != "dead"
	if anchor_px != anchor:
		anchor = anchor_px
		_target = anchor_px
		_wait = 0.0


func bubble(text: String, secs: float = 2.5) -> void:
	_bubble_text = text
	_bubble_time = secs
	match text:
		"ぽわ":
			_burst(10, [Color("7dffa0"), Color("fff27a"), Color.WHITE], Vector2(0, -14), 1.1, -18.0)
		"!?":
			_react = 0.7
			_burst(12, [Color("ffd84d"), Color("fff6b8")], Vector2(0, -12), 0.9, 0.0, 26.0)
		"!!":
			_react = 0.6
			_burst(3, [Color("8fd4ff")], Vector2(6, -16), 0.7, 10.0)
		"×":
			_shake = 0.45
			_burst(10, [Color("9a93a8"), Color("c9c3d4")], Vector2(0, -6), 0.9, -8.0, 14.0)
		"!":
			_react = 0.4
			_burst(6, [PRAY_COL, Color.WHITE], Vector2(0, -16), 0.8, -10.0, 16.0)


## 粒を飛ばす（rise は上昇速度、spread は放射速度）
func _burst(n: int, cols: Array, at: Vector2, life: float, rise: float, spread: float = 10.0) -> void:
	for i in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * randf_range(spread * 0.3, spread) + Vector2(0, rise)
		_particles.append({"p": at + Vector2(randf_range(-4, 4), randf_range(-3, 3)), "v": v,
			"life": life * randf_range(0.6, 1.0), "c": cols[randi() % cols.size()]})


func _process(delta: float) -> void:
	_t += delta
	_bubble_time = maxf(0.0, _bubble_time - delta)
	_react = maxf(0.0, _react - delta)
	_shake = maxf(0.0, _shake - delta)
	_move(delta)
	_animate()
	for p in _particles:
		p["p"] += p["v"] * delta
		p["v"] *= 0.94
		p["life"] -= delta
	_particles = _particles.filter(func(p): return p["life"] > 0.0)
	_sprite.position = Vector2(roundf(sin(_t * 60.0) * 1.5) if _shake > 0.0 else 0.0, -8)
	queue_redraw()
	_over.queue_redraw()


func _move(delta: float) -> void:
	_moving = false
	if state == "sleeping" or _react > 0.0:
		if state == "sleeping":
			position = position.move_toward(anchor, 30.0 * delta)
		return
	var far := position.distance_to(anchor) > 30.0
	var spd := 38.0 if far else 14.0
	if position.distance_to(_target) < 0.5:
		_wait -= delta
		if _wait <= 0.0:
			var still := praying or state == "praying" or state == "working"
			var radius := 3.0 if still else 12.0
			_target = anchor + Vector2(randf_range(-radius, radius), randf_range(-radius * 0.5, radius * 0.5))
			_target = _target.clamp(Vector2(8, 16), Vector2(352, 392))
			_wait = randf_range(2.5, 6.0) if still else randf_range(0.8, 3.0)
	else:
		var before := position
		position = position.move_toward(_target, spd * delta)
		_moving = true
		var v := position - before
		if absf(v.x) > absf(v.y):
			_play("walk_side")
			_sprite.flip_h = v.x < 0.0
		else:
			_play("walk_down" if v.y > 0.0 else "walk_up")


func _animate() -> void:
	if _moving:
		return
	_sprite.flip_h = false
	if _react > 0.0:
		_play("surprise")
	elif state == "sleeping":
		_play("sleep")
	elif praying or state == "praying":
		_play("pray")
	elif state == "working":
		_play("work")
	else:
		_play("idle")


func _play(anim: String) -> void:
	if _sprite.animation != anim:
		_sprite.play(anim)


func _draw() -> void:
	# 影（スプライトより奥）
	_ellipse(Vector2(0, -1), Vector2(6, 2), Color(0.1, 0.05, 0.2, 0.28))
	if selected:
		var a := 0.6 + 0.4 * sin(_t * 6.0)
		_ellipse_line(Vector2(0, -1), Vector2(9, 3.5), Color(1.0, 0.85, 0.3, a))


func _draw_over() -> void:
	var d := _over
	# 名前
	var nw := _font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var np := Vector2(roundf(-nw / 2.0), 10)
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		d.draw_string(_font, np + o, display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(OUTLINE, 0.85))
	d.draw_string(_font, np, display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	# 粒
	for p in _particles:
		var c: Color = p["c"]
		c.a = clampf(p["life"] * 2.0, 0.0, 1.0)
		d.draw_rect(Rect2((p["p"] as Vector2).round(), Vector2(2, 2) if p["life"] > 0.4 else Vector2(1, 1)), c)
	# 吹き出し：一時的なものが優先。祈りは金色で上下にふわふわ
	var top := -18.0
	if _bubble_time > 0.0:
		_draw_bubble(_bubble_text, Vector2(0, top), Color.WHITE, OUTLINE)
	elif praying:
		var bob := roundf(sin(_t * 3.0) * 1.5)
		_draw_bubble("祈", Vector2(0, top - 1 + bob), PRAY_COL, Color("5a3a00"))
		var tw := 0.5 + 0.5 * sin(_t * 5.0)
		d.draw_rect(Rect2(Vector2(8, top - 14 + bob), Vector2(1, 1)), Color(1, 1, 1, tw))
		d.draw_rect(Rect2(Vector2(-9, top - 8 + bob), Vector2(1, 1)), Color(1, 1, 1, 1.0 - tw))
	elif dreaming:
		var bob := roundf(sin(_t * 2.0) * 1.0)
		_draw_bubble("夢", Vector2(0, top - 1 + bob), Color("c9b8ff"), Color("3a2a7a"))
	elif state == "sleeping":
		var zt := fmod(_t * 0.8, 1.0)
		d.draw_string(_font, Vector2(4 + zt * 4, top + 2 - zt * 6).round(), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 1.0 - zt))
		d.draw_string(_font, Vector2(8 + zt * 3, top - 4 - zt * 5).round(), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, (1.0 - zt) * 0.7))


## ピクセル風の吹き出し（角を欠いた四角＋しっぽ）
func _draw_bubble(text: String, bottom: Vector2, bg: Color, fg: Color) -> void:
	var d := _over
	var fs := 10
	var tw := ceilf(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var w := tw + 6.0
	var h := 12.0
	var r := Rect2(roundf(-w / 2.0), bottom.y - h - 3, w, h)
	d.draw_rect(Rect2(r.position + Vector2(1, -1), Vector2(r.size.x - 2, r.size.y + 2)), OUTLINE)
	d.draw_rect(Rect2(r.position + Vector2(-1, 1), Vector2(r.size.x + 2, r.size.y - 2)), OUTLINE)
	d.draw_rect(Rect2(r.position + Vector2(1, 0), Vector2(r.size.x - 2, r.size.y)), bg)
	d.draw_rect(Rect2(r.position + Vector2(0, 1), Vector2(r.size.x, r.size.y - 2)), bg)
	# しっぽ
	d.draw_rect(Rect2(Vector2(-3, r.end.y), Vector2(6, 1)), OUTLINE)
	d.draw_rect(Rect2(Vector2(-2, r.end.y), Vector2(4, 1)), bg)
	d.draw_rect(Rect2(Vector2(-2, r.end.y + 1), Vector2(4, 1)), OUTLINE)
	d.draw_rect(Rect2(Vector2(-1, r.end.y + 1), Vector2(2, 1)), bg)
	d.draw_rect(Rect2(Vector2(-1, r.end.y + 2), Vector2(2, 1)), OUTLINE)
	d.draw_string(_font, Vector2(r.position.x + 3, r.end.y - 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)


func _ellipse_line(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 21:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_polyline(pts, col, 1.0)
