extends Control
## 聖典：住民が書き継ぐ、カミサマについての本（CONCEPT.md 6.6）。
## 載るのは誰かが唱えた教えだけ。内部の数値は見せない。忘れられた教えも灰色で残す。

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const TOP := 56.0
const W := 326

var _sheet: Panel
var _list: VBoxContainer
var _scroll: ScrollContainer
var _dim: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.12, 0.06, 0.22, 0.4)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(_dim)
	_sheet = Panel.new()
	var sb := UITheme.box(Color("fbf6ea"), 0, Color(0, 0, 0, 0), 0, 16, Color(0.15, 0.05, 0.3, 0.3))
	sb.corner_radius_top_left = 24
	sb.corner_radius_top_right = 24
	_sheet.add_theme_stylebox_override("panel", sb)
	_sheet.position = Vector2(0, TOP)
	_sheet.size = Vector2(360, 640 - TOP)
	add_child(_sheet)
	var handle := Panel.new()
	handle.add_theme_stylebox_override("panel", UITheme.box(Color("e6dcc6"), 2))
	handle.position = Vector2(160, 8)
	handle.size = Vector2(40, 4)
	_sheet.add_child(handle)
	var ic := Icon.make("book", UITheme.PURPLE, 24)
	ic.position = Vector2(16, 18)
	_sheet.add_child(ic)
	var title := UITheme.label("聖典", 18, UITheme.INK, true)
	title.position = Vector2(46, 14)
	_sheet.add_child(title)
	var sub := UITheme.label("町の人々が書き継ぐ、カミサマについての本", 10, UITheme.INK_SOFT)
	sub.position = Vector2(46, 38)
	_sheet.add_child(sub)
	var close_btn := Button.new()
	close_btn.text = "とじる"
	UITheme.style_button(close_btn, UITheme.PURPLE, Color.WHITE, 14, 12)
	close_btn.position = Vector2(272, 16)
	close_btn.size = Vector2(74, 32)
	close_btn.pressed.connect(close)
	_sheet.add_child(close_btn)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(12, 62)
	_scroll.size = Vector2(336, 640 - TOP - 72)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 6
	_sheet.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(W, 0)
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)


func open() -> void:
	for c in _list.get_children():
		c.queue_free()
	var established: Array = Doctrine.active().filter(func(d): return d["established"])
	var proposed: Array = Doctrine.active().filter(func(d): return not d["established"])
	var hints := Doctrine.hints()
	var forgotten := Doctrine.forgotten()
	_list.add_child(_howto())
	if established.is_empty() and proposed.is_empty() and hints.is_empty() and forgotten.is_empty():
		var empty := UITheme.label("まだ白紙。\nカミサマの行いに、誰も法則を見出していない。\n\n同じ状況で同じちょっかいを繰り返すと、誰かが気づくかもしれない。夢で教えることもできる。", 13, UITheme.INK_SOFT)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(W, 0)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(_spacer(40))
		_list.add_child(empty)
	if not established.is_empty():
		_section("町の教え")
		for d in established:
			_list.add_child(_page(d))
	if not proposed.is_empty():
		_section("唱えられている教え")
		for d in proposed:
			_list.add_child(_page(d))
	if not hints.is_empty():
		_section("生まれかけ")
		for h in hints:
			var l := UITheme.label("%sが、%sについて何か言いかけている。" % [h["name"], h["int"]], 12, UITheme.INK_SOFT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(W, 0)
			_list.add_child(l)
	if not forgotten.is_empty():
		_section("忘れられた教え")
		for d in forgotten:
			var p := _page(d)
			p.modulate = Color(1, 1, 1, 0.5)
			_list.add_child(p)
	_scroll.scroll_vertical = 0
	visible = true
	_dim.modulate.a = 0.0
	_sheet.position.y = 640
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.2)
	tw.tween_property(_sheet, "position:y", TOP, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dim, "modulate:a", 0.0, 0.18)
	tw.tween_property(_sheet, "position:y", 640.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func(): visible = false)


## この本の読み方（いつも先頭に）
func _howto() -> Control:
	var sb := UITheme.box(Color("f4ecd8"), 16)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	vb.add_child(UITheme.label("この本の読み方", 12, Color("a0782a"), true))
	var l := UITheme.label(
		"・住民は、カミサマのちょっかいと、その直前の出来事を結びつけて「教え」を作る。\n" +
		"・同じ状況で同じちょっかいを繰り返すと、誰かが気づく。夢で教えることもできる。\n" +
		"・教えを信じる人は、ちょっかいをその意味で受け取る。半分を超えると「町の教え」になる。\n" +
		"・「返事」の教えが根づくと、住民がイエス・ノーで問いかけてくる。", 11, UITheme.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(W - 28, 0)
	vb.add_child(l)
	return p


func _section(text: String) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(Icon.make("sparkle", Color("c9a44a"), 14))
	hb.add_child(UITheme.label(text, 13, Color("a0782a"), true))
	_list.add_child(hb)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## 教え1つ＝聖典の1ページ
func _page(d: Dictionary) -> Control:
	var v: int = Doctrine.VALENCE[d["meaning"]]
	var accent := UITheme.GOLD if v > 0 else (UITheme.RED if v < 0 else UITheme.PURPLE)
	var sb := UITheme.box(Color.WHITE, 16, Color(0, 0, 0, 0), 0, 4, Color(0.3, 0.2, 0.1, 0.1))
	sb.border_color = accent
	sb.border_width_left = 5
	sb.content_margin_left = 14
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	vb.add_child(chips)
	if d["status"] == "forgotten":
		chips.add_child(UITheme.chip("忘れられた", Color("eceaf2"), UITheme.INK_SOFT, 10))
	elif d["established"]:
		chips.add_child(UITheme.chip("町の教え", UITheme.GOLD, Color.WHITE, 10))
	else:
		chips.add_child(UITheme.chip("唱えられている", Color("f1ebfa"), UITheme.PURPLE, 10))
	if int(d["rival"]) >= 0 and d["status"] == "active":
		chips.add_child(UITheme.chip("分派", Color("ffe3e6"), UITheme.RED, 10))
	chips.add_child(UITheme.chip("%d日目・%s" % [d["born_day"], d["founder_name"]], Color("f4efe4"), Color("a0782a"), 10))

	var t := UITheme.label("「%s」" % Doctrine.text(d), 15, UITheme.INK, true)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(W - 30, 0)
	vb.add_child(t)
	var voice := UITheme.label("%s「%s」" % [d["founder_name"], Doctrine.voice(d)], 11, UITheme.INK_SOFT)
	voice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voice.custom_minimum_size = Vector2(W - 30, 0)
	vb.add_child(voice)

	if d["status"] == "active":
		vb.add_child(_people_row("信じる者", d["believers"], true))
		if not d["deniers"].is_empty():
			vb.add_child(_people_row("否定する者", d["deniers"], false))
		if d["deniers"].has("nob"):
			var note := UITheme.label("※ノブ注：相関は因果ではない。", 10, Color("7a8fb8"))
			vb.add_child(note)
		var rival := Doctrine.find(int(d["rival"]))
		if not rival.is_empty() and rival["status"] == "active":
			var rl := UITheme.label("対立する教え：「%s」" % Doctrine.text(rival), 11, UITheme.RED.darkened(0.1))
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rl.custom_minimum_size = Vector2(W - 30, 0)
			vb.add_child(rl)
	return p


func _people_row(label: String, ids: Array, believe: bool) -> Control:
	var hb := HFlowContainer.new()
	hb.add_theme_constant_override("h_separation", 4)
	hb.add_theme_constant_override("v_separation", 4)
	var l := UITheme.label(label, 10, UITheme.INK_SOFT, true)
	l.custom_minimum_size = Vector2(58, 0)
	hb.add_child(l)
	for id in ids:
		var r := Sim.find_resident(id)
		if r.is_empty():
			continue
		var col: Color = UITheme.CHARA_COLORS.get(id, UITheme.PURPLE)
		if believe:
			hb.add_child(UITheme.chip(r["name"], col.lightened(0.75), col.darkened(0.25), 10))
		else:
			hb.add_child(UITheme.chip(r["name"], Color("eceaf2"), UITheme.INK_SOFT, 10))
	return hb
