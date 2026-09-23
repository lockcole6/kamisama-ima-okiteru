extends Control
## 夢を見せる：象徴を3つまで選ぶ（CONCEPT.md 5章）。どう解釈するかは見た住民しだい。

signal chosen(id: String, symbols: Array)

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const MAX_SYMBOLS := 3

var _rid := ""
var _card: PanelContainer
var _title: Label
var _sub: Label
var _flow: HFlowContainer
var _picked_label: Label
var _ok: Button
var _picked: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.2, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			visible = false)
	add_child(dim)

	_card = PanelContainer.new()
	var sb := UITheme.box(Color("2b2350"), 24, Color("8b6cff"), 2, 20, Color(0.05, 0, 0.2, 0.5))
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_card.add_theme_stylebox_override("panel", sb)
	_card.custom_minimum_size = Vector2(320, 0)
	add_child(_card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_card.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	hb.add_child(Icon.make("moon", Color("ffe28a"), 26))
	_title = UITheme.label("", 17, Color.WHITE, true)
	hb.add_child(_title)
	_sub = UITheme.label("", 11, Color(1, 1, 1, 0.7))
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(284, 0)
	vb.add_child(_sub)
	_flow = HFlowContainer.new()
	_flow.custom_minimum_size = Vector2(284, 0)
	_flow.add_theme_constant_override("h_separation", 8)
	_flow.add_theme_constant_override("v_separation", 8)
	vb.add_child(_flow)
	_picked_label = UITheme.label("", 14, Color("ffe28a"), true)
	_picked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_picked_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var cancel := Button.new()
	cancel.text = "やめる"
	cancel.custom_minimum_size = Vector2(100, 44)
	UITheme.style_button(cancel, Color("5a4f7a"), Color.WHITE, 14, 14)
	cancel.pressed.connect(func(): visible = false)
	row.add_child(cancel)
	_ok = Button.new()
	_ok.text = "この夢を見せる"
	_ok.custom_minimum_size = Vector2(176, 44)
	UITheme.style_button(_ok, UITheme.PURPLE, Color.WHITE, 14, 15)
	_ok.pressed.connect(_on_ok)
	row.add_child(_ok)


func open(r: Dictionary) -> void:
	_rid = r["id"]
	_picked = []
	_title.text = "%sに夢を見せる" % r["name"]
	_sub.text = "象徴を%dつまで選ぶ。どう解釈するかは%sしだい。雨・風・手と、パン・鐘などを組み合わせると、教えになりやすい。" % [MAX_SYMBOLS, r["name"]]
	for c in _flow.get_children():
		c.queue_free()
	for s in Sim.dream_symbols():
		if s == r["name"]:
			continue
		var b := Button.new()
		b.text = s
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(56, 36)
		var person: bool = not Sim.DREAM_SYMBOLS.has(s)
		var base := Color("3d3470") if not person else Color("463a5e")
		b.add_theme_stylebox_override("normal", UITheme.box(base, 14, Color(1, 1, 1, 0.15), 1))
		b.add_theme_stylebox_override("hover", UITheme.box(base.lightened(0.08), 14, Color(1, 1, 1, 0.25), 1))
		b.add_theme_stylebox_override("pressed", UITheme.box(UITheme.PURPLE, 14, Color("ffe28a"), 2))
		b.add_theme_stylebox_override("hover_pressed", UITheme.box(UITheme.PURPLE, 14, Color("ffe28a"), 2))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_font_override("font", UITheme.font(true))
		b.add_theme_font_size_override("font_size", 14)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, Color.WHITE)
		b.toggled.connect(func(on): _on_toggle(b, s, on))
		_flow.add_child(b)
	_refresh()
	visible = true
	_card.reset_size()
	_layout.call_deferred()


func _layout() -> void:
	await get_tree().process_frame  # 並べ終わってから高さを確定する
	_card.reset_size()
	_card.position = Vector2((360 - _card.size.x) / 2.0, maxf(20.0, (640 - _card.size.y) / 2.0))
	UITheme.pop_in(_card)


func _on_toggle(b: Button, s: String, on: bool) -> void:
	if on:
		if _picked.size() >= MAX_SYMBOLS:
			b.set_pressed_no_signal(false)
			return
		_picked.append(s)
	else:
		_picked.erase(s)
	_refresh()


func _refresh() -> void:
	_picked_label.text = "・".join(_picked) if not _picked.is_empty() else "（まだ何も選んでいない）"
	_ok.disabled = _picked.is_empty()


func _on_ok() -> void:
	visible = false
	chosen.emit(_rid, _picked.duplicate())
