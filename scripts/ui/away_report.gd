extends Control
## 「留守中の出来事」ポップアップ。重要度の高いものから最大5件＋「ほか N 件」。

signal suggestion_chosen(kind: String, id: String)

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const MAX_LINES := 5
const W := 320

var _card: PanelContainer
var _title: Label
var _sub: Label
var _list: VBoxContainer
var _suggest_box: PanelContainer
var _suggest_label: Label
var _go: Button
var _suggestion: Dictionary = {}
var _hello: Label
var _moon  # icon.gd（時間帯で太陽／月）


func _ready() -> void:
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.06, 0.22, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)  # 背面のタップを止める

	_card = PanelContainer.new()
	var sb := UITheme.box(UITheme.CARD, 24, Color(0, 0, 0, 0), 0, 20, Color(0.1, 0.03, 0.25, 0.4))
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 0)
	_card.add_theme_stylebox_override("panel", sb)
	_card.custom_minimum_size = Vector2(W, 0)
	add_child(_card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	_card.add_child(vb)

	# 帯（夜空っぽいグラデーション風）
	var header := Control.new()
	header.custom_minimum_size = Vector2(W, 92)
	vb.add_child(header)
	var band := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = UITheme.PURPLE.darkened(0.15)
	bsb.corner_radius_top_left = 24
	bsb.corner_radius_top_right = 24
	band.add_theme_stylebox_override("panel", bsb)
	band.size = Vector2(W, 92)
	header.add_child(band)
	var glow := Panel.new()
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(UITheme.PINK, 0.45)
	gsb.corner_radius_top_right = 24
	gsb.corner_radius_bottom_left = 92
	glow.add_theme_stylebox_override("panel", gsb)
	glow.position = Vector2(W * 0.45, 0)
	glow.size = Vector2(W * 0.55, 92)
	header.add_child(glow)
	for s in [[Vector2(270, 10), 22, 0.7], [Vector2(246, 50), 14, 0.5], [Vector2(18, 58), 12, 0.4], [Vector2(292, 56), 10, 0.6]]:
		var st := Icon.make("sparkle", Color(1, 1, 1, s[2]), s[1])
		st.position = s[0]
		header.add_child(st)
	_moon = Icon.make("moon", Color("ffe28a"), 30)
	_moon.position = Vector2(18, 16)
	header.add_child(_moon)
	_hello = UITheme.label("おかえりなさい、カミサマ", 18, Color.WHITE, true)
	_hello.position = Vector2(56, 18)
	_hello.add_theme_constant_override("outline_size", 5)
	_hello.add_theme_color_override("font_outline_color", UITheme.PURPLE.darkened(0.45))
	header.add_child(_hello)
	_sub = UITheme.label("", 12, Color(1, 1, 1, 0.85), true)
	_sub.position = Vector2(58, 50)
	header.add_child(_sub)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 18)
	vb.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	_title = UITheme.label("", 14, UITheme.PURPLE, true)
	body.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	body.add_child(_list)
	# いま決められること（1つだけ）
	var ssb := UITheme.box(Color("f1ebfa"), 16)
	ssb.content_margin_left = 12
	ssb.content_margin_right = 12
	ssb.content_margin_top = 8
	ssb.content_margin_bottom = 10
	_suggest_box = PanelContainer.new()
	_suggest_box.add_theme_stylebox_override("panel", ssb)
	body.add_child(_suggest_box)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 2)
	_suggest_box.add_child(sv)
	sv.add_child(UITheme.label("いま決められること", 11, UITheme.PURPLE, true))
	_suggest_label = UITheme.label("", 13, UITheme.INK, true)
	_suggest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_suggest_label.custom_minimum_size = Vector2(W - 60, 0)
	sv.add_child(_suggest_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	var ok := Button.new()
	ok.text = "町を見る"
	ok.custom_minimum_size = Vector2(0, 50)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(ok, UITheme.GRAY, Color.WHITE, 18, 16)
	ok.pressed.connect(_close)
	row.add_child(ok)
	_go = Button.new()
	_go.text = "見に行く"
	_go.custom_minimum_size = Vector2(0, 50)
	_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(_go, UITheme.GOLD, Color.WHITE, 18, 16)
	_go.pressed.connect(func():
		_close()
		suggestion_chosen.emit(_suggestion["kind"], _suggestion["id"]))
	row.add_child(_go)


func show_report(seconds: int, events: Array) -> void:
	var hours := seconds / 3600.0
	_hello.text = "おかえりなさい、カミサマ"
	_moon.set_kind("moon", Color("ffe28a"))
	if hours < 1.0:
		_title.text = "カミサマが少し目を離した間に"
	elif hours < 12.0:
		_title.text = "カミサマが眠っている間に"
	elif hours < 48.0:
		_title.text = "カミサマが長く眠っている間に"
	else:
		_title.text = "カミサマがいない間に"
	_sub.text = "%s留守にしていた" % Sim.format_duration(seconds)
	_fill(events)


## 眠って目覚めた（時間帯が1つ進んだ）
func show_wake(from_seg: Dictionary, to_seg: Dictionary, events: Array) -> void:
	_hello.text = "%sになった" % to_seg["name"]
	var night: bool = to_seg["id"] in ["night", "midnight"]
	_moon.set_kind("moon" if night else "sun", Color("ffe28a"))
	_sub.text = "%d日目・%sから眠っていた" % [Sim.day, from_seg["name"]]
	_title.text = "カミサマが眠っている間に"
	_fill(events)


func _fill(events: Array) -> void:
	for c in _list.get_children():
		c.queue_free()
	# 重要度の高い順（同じなら古い順）
	var sorted := events.duplicate()
	sorted.sort_custom(func(a, b):
		if a["imp"] != b["imp"]:
			return a["imp"] > b["imp"]
		return a["t"] < b["t"])
	if sorted.is_empty():
		_add_line("町は静かだった。誰もカミサマの話をしなかった。", UITheme.LINE)
	for i in mini(MAX_LINES, sorted.size()):
		var e: Dictionary = sorted[i]
		var imp := int(e["imp"])
		_add_line(e["text"], UITheme.RED if imp >= 3 else (UITheme.GOLD if imp == 2 else UITheme.LINE))
	if sorted.size() > MAX_LINES:
		var more := UITheme.chip("ほか %d 件" % (sorted.size() - MAX_LINES), Color("f1ebfa"), UITheme.INK_SOFT, 11)
		more.size_flags_horizontal = Control.SIZE_SHRINK_END
		_list.add_child(more)
	_suggestion = Sim.suggestion()
	_suggest_label.text = _suggestion["text"]
	_go.visible = _suggestion["kind"] in ["prayer", "dream"]
	var praying: Array = Sim.praying_residents().map(func(r): return r["name"])
	if not praying.is_empty():
		var sb := UITheme.box(UITheme.CREAM, 14, UITheme.GOLD, 2)
		sb.content_margin_left = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		p.add_child(hb)
		hb.add_child(Icon.make("pray", UITheme.GOLD, 18))
		var l := UITheme.label("いま%sが、カミサマに祈っている。" % "と".join(praying), 12, Color("a06c00"), true)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(240, 0)
		hb.add_child(l)
		_list.add_child(p)
	visible = true
	_card.reset_size()
	_layout.call_deferred()


func _layout() -> void:
	_card.reset_size()
	_card.position = Vector2((360 - W) / 2.0, maxf(20.0, (640.0 - _card.size.y) / 2.0))
	UITheme.pop_in(_card, 0.85)


func _close() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		visible = false
		modulate.a = 1.0)


func _add_line(text: String, accent: Color) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var dot := Panel.new()
	dot.add_theme_stylebox_override("panel", UITheme.box(accent, 4))
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", 5)
	holder.add_child(dot)
	hb.add_child(holder)
	var l := UITheme.label(text, 13, UITheme.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(W - 36 - 16, 0)
	hb.add_child(l)
	_list.add_child(hb)
