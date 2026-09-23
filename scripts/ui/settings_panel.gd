extends Control
## 設定：音量、案内をもう一度、データを消して最初から、クレジット。

signal reset_requested
signal guide_reset_requested

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const W := 320

var _card: PanelContainer
var _music: HSlider
var _sfx: HSlider
var _confirm: PanelContainer
var _dim: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.12, 0.06, 0.22, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(_dim)

	_card = PanelContainer.new()
	var sb := UITheme.box(UITheme.CARD, 24, Color(0, 0, 0, 0), 0, 18, Color(0.15, 0.05, 0.3, 0.3))
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 20
	_card.add_theme_stylebox_override("panel", sb)
	_card.custom_minimum_size = Vector2(W, 0)
	add_child(_card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_card.add_child(vb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	head.add_child(Icon.make("gear", UITheme.PURPLE, 22))
	var title := UITheme.label("設定", 18, UITheme.INK, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "とじる"
	close_btn.custom_minimum_size = Vector2(74, 32)
	UITheme.style_button(close_btn, UITheme.PURPLE, Color.WHITE, 14, 12)
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	# 音
	vb.add_child(_section("サウンド"))
	_music = _slider_row(vb, "BGM", Audio.music_volume)
	_sfx = _slider_row(vb, "効果音", Audio.sfx_volume)
	_music.value_changed.connect(func(_v): Audio.set_volumes(_music.value, _sfx.value))
	_sfx.value_changed.connect(func(_v):
		Audio.set_volumes(_music.value, _sfx.value)
		Audio.play("tap"))

	# あそび
	vb.add_child(_section("あそび"))
	var guide := Button.new()
	guide.text = "ミミの案内をもう一度見る"
	guide.custom_minimum_size = Vector2(0, 44)
	UITheme.style_button(guide, UITheme.PINK, Color.WHITE, 14, 14)
	guide.pressed.connect(func():
		guide_reset_requested.emit()
		close())
	vb.add_child(guide)
	var reset := Button.new()
	reset.text = "データを消して最初から"
	reset.custom_minimum_size = Vector2(0, 44)
	UITheme.style_button(reset, UITheme.RED, Color.WHITE, 14, 14)
	reset.pressed.connect(func(): _confirm.visible = true)
	vb.add_child(reset)

	# 確認（リセット）
	_confirm = PanelContainer.new()
	var csb := UITheme.box(Color("fff0f1"), 16, UITheme.RED, 2)
	csb.content_margin_left = 14
	csb.content_margin_right = 14
	csb.content_margin_top = 10
	csb.content_margin_bottom = 12
	_confirm.add_theme_stylebox_override("panel", csb)
	_confirm.visible = false
	vb.add_child(_confirm)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	_confirm.add_child(cv)
	var warn := UITheme.label("本当に最初からやり直しますか？\n町も、住民も、墓も、聖典も、すべて消えます。元には戻せません。", 12, UITheme.RED.darkened(0.25), true)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(W - 70, 0)
	cv.add_child(warn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	cv.add_child(row)
	var no := Button.new()
	no.text = "やめる"
	no.custom_minimum_size = Vector2(0, 40)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(no, UITheme.GRAY, Color.WHITE, 12, 13)
	no.pressed.connect(func(): _confirm.visible = false)
	row.add_child(no)
	var yes := Button.new()
	yes.text = "消して最初から"
	yes.custom_minimum_size = Vector2(0, 40)
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(yes, UITheme.RED, Color.WHITE, 12, 13)
	yes.pressed.connect(func():
		reset_requested.emit()
		close())
	row.add_child(yes)

	# クレジット
	vb.add_child(_section("クレジット"))
	var credit := UITheme.label("カミサマ、いま起きてる？（プロトタイプ）\n絵・音：仮素材（tools/ で生成）\nフォント：DotGothic16 / M PLUS Rounded 1c（SIL Open Font License 1.1）", 10, UITheme.INK_SOFT)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.custom_minimum_size = Vector2(W - 40, 0)
	vb.add_child(credit)


func open() -> void:
	_music.set_value_no_signal(Audio.music_volume)
	_sfx.set_value_no_signal(Audio.sfx_volume)
	_confirm.visible = false
	visible = true
	_layout.call_deferred()


func close() -> void:
	visible = false


func _layout() -> void:
	await get_tree().process_frame
	_card.reset_size()
	_card.position = Vector2((360 - _card.size.x) / 2.0, maxf(20.0, (640 - _card.size.y) / 2.0))
	UITheme.pop_in(_card)


func _section(text: String) -> Label:
	return UITheme.label(text, 11, UITheme.PURPLE, true)


func _slider_row(parent: Control, text: String, value: float) -> HSlider:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	parent.add_child(hb)
	var l := UITheme.label(text, 13, UITheme.INK, true)
	l.custom_minimum_size = Vector2(56, 0)
	hb.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 28)
	var track := UITheme.box(UITheme.LINE, 4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := UITheme.box(UITheme.PURPLE, 4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", _knob(UITheme.PURPLE))
	s.add_theme_icon_override("grabber_highlight", _knob(UITheme.PURPLE.lightened(0.2)))
	hb.add_child(s)
	return s


## スライダーのつまみ（白い丸に色のふち）
static func _knob(col: Color) -> Texture2D:
	var n := 22
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n / 2.0 - 0.5, n / 2.0 - 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(c)
			if d <= 10.5:
				img.set_pixel(x, y, col if d > 7.5 else Color.WHITE)
			elif d <= 11.0:
				img.set_pixel(x, y, Color(col, 11.0 - d))
	return ImageTexture.create_from_image(img)
