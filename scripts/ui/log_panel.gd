extends Control
## 住民ログの一覧（最大200件・新しい順）。下からせり上がるシート。

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const TOP := 56.0

var _sheet: Panel
var _title: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _dim: ColorRect


func _ready() -> void:
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.12, 0.06, 0.22, 0.4)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(_dim)
	_sheet = Panel.new()
	var sb := UITheme.box(Color("f7f3fb"), 0, Color(0, 0, 0, 0), 0, 16, Color(0.15, 0.05, 0.3, 0.3))
	sb.corner_radius_top_left = 24
	sb.corner_radius_top_right = 24
	_sheet.add_theme_stylebox_override("panel", sb)
	_sheet.position = Vector2(0, TOP)
	_sheet.size = Vector2(360, 640 - TOP)
	add_child(_sheet)
	var handle := Panel.new()
	handle.add_theme_stylebox_override("panel", UITheme.box(UITheme.LINE, 2))
	handle.position = Vector2(160, 8)
	handle.size = Vector2(40, 4)
	_sheet.add_child(handle)
	var ic := Icon.make("scroll", UITheme.PURPLE, 20)
	ic.position = Vector2(18, 22)
	_sheet.add_child(ic)
	_title = UITheme.label("", 16, UITheme.INK, true)
	_title.position = Vector2(44, 19)
	_sheet.add_child(_title)
	var close_btn := Button.new()
	close_btn.text = "とじる"
	UITheme.style_button(close_btn, UITheme.PURPLE, Color.WHITE, 14, 12)
	close_btn.position = Vector2(272, 16)
	close_btn.size = Vector2(74, 32)
	close_btn.pressed.connect(close)
	_sheet.add_child(close_btn)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(12, 60)
	_scroll.size = Vector2(336, 640 - TOP - 70)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(326, 0)
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)


func open() -> void:
	for c in _list.get_children():
		c.queue_free()
	var entries: Array = LogManager.entries.duplicate()
	entries.reverse()
	_title.text = "町のようす（%d件）" % entries.size()
	for e in entries:
		_list.add_child(_entry(e))
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


func _entry(e: Dictionary) -> Control:
	var imp := int(e.get("imp", 1))
	var accent := UITheme.RED if imp >= 3 else (UITheme.GOLD if imp == 2 else UITheme.LINE)
	var sb := UITheme.box(Color.WHITE, 14, Color(0, 0, 0, 0), 0, 4, Color(0.2, 0.1, 0.35, 0.08))
	sb.border_color = accent
	sb.border_width_left = 5
	sb.content_margin_left = 14
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)
	vb.add_child(UITheme.label(GameClock.format_mdhm(int(e["t"])), 10, UITheme.INK_SOFT, true))
	var l := UITheme.label(e["text"], 13, UITheme.RED.darkened(0.2) if imp >= 3 else UITheme.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(296, 0)
	vb.add_child(l)
	return p
