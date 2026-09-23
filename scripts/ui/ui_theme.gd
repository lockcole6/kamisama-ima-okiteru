extends RefCounted
## UIの見た目（色・フォント・ボタン）。ソシャゲ風：白いカード、丸ゴシック、ツヤのある立体ボタン。
## UIは高解像度で描き、町（ピクセルアート）は SubViewport で拡大表示する。

const FONT_BOLD := "res://assets/fonts/MPLUSRounded1c-Bold.ttf"
const FONT_MED := "res://assets/fonts/MPLUSRounded1c-Medium.ttf"
const FONT_PIXEL := "res://assets/fonts/DotGothic16-Regular.ttf"

const INK := Color("3a2e4f")
const INK_SOFT := Color("8a7fa0")
const CARD := Color("fffdf8")
const LINE := Color("ece4f2")
const PINK := Color("ff6fae")
const GOLD := Color("ffb92e")
const SKY := Color("3fb5ff")
const PURPLE := Color("8b6cff")
const MINT := Color("3ecf8e")
const RED := Color("ff5d6c")
const GRAY := Color("b3aec0")
const CREAM := Color("fff4d6")

## キャラごとのテーマ色（カードの帯など）
const CHARA_COLORS := {
	"tome": Color("f08a4b"), "kaz": Color("8b5ad6"), "nob": Color("4a78d8"),
	"sen": Color("7a8194"), "mimi": Color("ff78b4"),
}

static var _fonts := {}


static func font(bold: bool = true) -> Font:
	return _load(FONT_BOLD if bold else FONT_MED)


static func pixel_font() -> Font:
	return _load(FONT_PIXEL)


static func _load(path: String) -> Font:
	if not _fonts.has(path):
		_fonts[path] = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _fonts[path]


static func box(bg: Color, radius: int = 12, border: Color = Color(0, 0, 0, 0), border_w: int = 0,
		shadow: int = 0, shadow_col: Color = Color(0.2, 0.1, 0.3, 0.18)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if shadow > 0:
		sb.shadow_color = shadow_col
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, shadow * 0.4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func make() -> Theme:
	var t := Theme.new()
	t.default_font = font(false)
	t.default_font_size = 13
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "Panel", box(CARD, 16))
	t.set_stylebox("panel", "PanelContainer", box(CARD, 16))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.45, 0.7, 0.35)
	sb.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return t


## 立体でツヤのあるボタンにする（下辺が濃い色で厚みを出し、押すと沈む）
static func style_button(b: Button, base: Color, text_col: Color = Color.WHITE, radius: int = 14, font_size: int = 15) -> void:
	var depth := 4
	var normal := box(base, radius, base.darkened(0.28), 0)
	normal.border_width_bottom = depth
	normal.border_color = base.darkened(0.28)
	var hover := normal.duplicate()
	hover.bg_color = base.lightened(0.08)
	var pressed := normal.duplicate()
	pressed.border_width_bottom = 1
	pressed.content_margin_top = normal.content_margin_top + depth - 1
	pressed.bg_color = base.darkened(0.05)
	var disabled := box(Color("d9d4e2"), radius)
	disabled.border_width_bottom = depth
	disabled.border_color = Color("bdb6c9")
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", font(true))
	b.add_theme_font_size_override("font_size", font_size)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, text_col)
	b.add_theme_color_override("font_disabled_color", Color("a39db0"))
	# ツヤ（上半分に白を薄く重ねる）
	var gloss := Panel.new()
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(1, 1, 1, 0.22)
	gsb.corner_radius_top_left = radius
	gsb.corner_radius_top_right = radius
	gsb.corner_radius_bottom_left = radius / 2
	gsb.corner_radius_bottom_right = radius / 2
	gloss.add_theme_stylebox_override("panel", gsb)
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gloss.set_anchors_preset(Control.PRESET_TOP_WIDE)
	gloss.offset_left = 3
	gloss.offset_right = -3
	gloss.offset_top = 2
	gloss.offset_bottom = 0
	gloss.name = "Gloss"
	b.add_child(gloss)
	b.resized.connect(func():
		gloss.offset_bottom = (b.size.y - depth) * 0.45
		b.pivot_offset = b.size / 2.0)
	# 押したときにぷにっと縮む
	b.button_down.connect(func():
		b.create_tween().tween_property(b, "scale", Vector2(0.96, 0.96), 0.06))
	b.button_up.connect(func():
		b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(b, "scale", Vector2.ONE, 0.18))
	b.draw.connect(func(): gloss.visible = not b.disabled)
	b.pressed.connect(func(): Audio.play("tap"))


## 透明で文字だけのボタン
static func style_flat(b: Button, col: Color, font_size: int = 12) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.add_theme_font_override("font", font(true))
	b.add_theme_font_size_override("font_size", font_size)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, col)


static func label(text: String, size: int = 13, col: Color = INK, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", font(true))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 小さな丸いラベル（タグ）
static func chip(text: String, bg: Color, fg: Color, size: int = 11) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(bg, 10)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, size, fg, true)
	l.name = "Text"
	p.add_child(l)
	return p


## ポップアップが出るときのアニメーション
static func pop_in(c: Control, from_scale: float = 0.9) -> void:
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2(from_scale, from_scale)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.14)
