extends Control
## 画面のUI。上：日付・時刻・天気・存在感のピル / 下：町のようす（最新ログ）と、ちょっかいのボタン
## 住民・墓のキャラカード、夢の象徴えらび、風の場所えらび、デバッグUI（折りたたみ）もここで出す。

signal open_log_requested
signal open_scripture_requested
signal selection_changed(id: String)
signal card_opened

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const Gauge := preload("res://scripts/ui/gauge.gd")
const DreamPicker := preload("res://scripts/ui/dream_picker.gd")
const SHEET_Y := 388
const CARD_W := 320
const INNER_W := 284

const STATE_NAMES := {
	"sleeping": "睡眠中", "working": "仕事中", "wandering": "おさんぽ",
	"praying": "お祈り中", "dead": "故人",
}
const RESULT_NAMES := {
	"heal": "癒やし", "scare": "驚かす", "revelation": "啓示", "disaster": "災い",
}

## デバッグUIは debug ビルドのみ。書き出し時に feature tag "no_debug_ui" を付けると出なくなる
var show_debug := OS.is_debug_build() and not OS.has_feature("no_debug_ui")
## 風の場所えらび中（町をタップすると風が吹く）
var wind_mode := false

# 上部
var _day_label: Label
var _time_label: Label
var _weather_icon  # icon.gd
var _presence_gauge  # gauge.gd
var _presence_label: Label
var _speed_chip: PanelContainer
var _wind_banner: PanelContainer
var _toast: PanelContainer
var _toast_label: Label
var _mute_btn: Button
var _mute_icon  # icon.gd
var _banner: PanelContainer
var _banner_title: Label
var _banner_text: Label
var _banner_sub: Label
var _banner_queue: Array = []
# シート
var _feed_rows: Array = []
var _btns: Dictionary = {}  # "wind"/"rain"/"pray"/"book" → {btn, sub}
var _debug_panel: Panel
# キャラカード
var _dim: ColorRect
var _card: PanelContainer
var _band: Panel
var _portrait: TextureRect
var _portrait_frame: Panel
var _name_label: Label
var _chips: HBoxContainer
var _stats: VBoxContainer
var _gauges: Dictionary = {}
var _traits: HFlowContainer
var _motto: Label
var _beliefs: VBoxContainer
var _wish_box: PanelContainer
var _wish_label: Label
var _wish_timer: Label
var _wish_hint: Label
var _result_box: PanelContainer
var _result_head: Label
var _result_text: Label
var _actions: HBoxContainer
var _poke_btn: Button
var _dream_btn: Button
var _dream_sub: Label
var _grave_box: PanelContainer
var _grave_label: Label
var _popup_rid := ""
var _dream_picker: Control

var _refresh_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top()
	_build_sheet()
	if show_debug:
		_build_debug()
	_build_card()
	_dream_picker = DreamPicker.new()
	add_child(_dream_picker)
	_dream_picker.chosen.connect(_on_dream_chosen)
	_build_banner()
	Doctrine.doctrine_event.connect(func(kind, d):
		_banner_queue.append([kind, d])
		if not _banner.visible:
			_next_banner())
	LogManager.log_added.connect(func(_e): _refresh_feed())
	Sim.state_changed.connect(_on_state_changed)
	GameClock.speed_changed.connect(func(_s): _refresh_top())
	_refresh_feed()


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.25
		_refresh_top()
		if _card.visible and _popup_rid != "":
			_refresh_card()  # 祈りの残り時間を進める


# ------------------------------------------------------------
# 上部のピル
# ------------------------------------------------------------

func _build_top() -> void:
	var pill := UITheme.box(Color(1, 1, 1, 0.92), 17, Color(0, 0, 0, 0), 0, 8)
	var left := _panel(self, Rect2(10, 10, 186, 34), pill)
	var day := _panel(left, Rect2(5, 5, 52, 24), UITheme.box(UITheme.PINK, 12))
	_day_label = _place(day, UITheme.label("", 12, Color.WHITE, true), Vector2(0, 2))
	_day_label.size = Vector2(52, 20)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label = _place(left, UITheme.label("", 15, UITheme.INK, true), Vector2(64, 6))
	_weather_icon = _place(left, Icon.make("sun", UITheme.GOLD, 22), Vector2(158, 6))

	var right := _panel(self, Rect2(204, 10, 146, 34), pill)
	_place(right, Icon.make("halo", UITheme.GOLD, 22), Vector2(8, 6))
	_place(right, UITheme.label("存在感", 10, UITheme.INK_SOFT, true), Vector2(34, 2))
	_presence_gauge = _place(right, Gauge.new(), Vector2(34, 19))
	_presence_gauge.size = Vector2(76, 8)
	_presence_gauge.color = UITheme.GOLD
	_presence_label = _place(right, UITheme.label("", 13, UITheme.INK, true), Vector2(116, 7))

	_mute_btn = Button.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		_mute_btn.add_theme_stylebox_override(st, UITheme.box(Color(1, 1, 1, 0.92), 15, Color(0, 0, 0, 0), 0, 6))
	_mute_btn.position = Vector2(318, 50)
	_mute_btn.size = Vector2(30, 30)
	add_child(_mute_btn)
	_mute_icon = _place(_mute_btn, Icon.make("sound", UITheme.PURPLE, 18), Vector2(6, 6))
	_mute_btn.pressed.connect(func():
		Audio.toggle_mute()
		_refresh_mute())
	_refresh_mute.call_deferred()

	_speed_chip = UITheme.chip("", UITheme.RED, Color.WHITE, 11)
	_place(self, _speed_chip, Vector2(12, 50))
	_speed_chip.visible = false

	# 風の場所えらびの案内
	_wind_banner = PanelContainer.new()
	var wsb := UITheme.box(UITheme.MINT, 18, Color.WHITE, 2, 8)
	wsb.content_margin_left = 14
	wsb.content_margin_right = 6
	_wind_banner.add_theme_stylebox_override("panel", wsb)
	var whb := HBoxContainer.new()
	whb.add_theme_constant_override("separation", 8)
	_wind_banner.add_child(whb)
	whb.add_child(Icon.make("wind", Color.WHITE, 20))
	var wl := UITheme.label("風を吹かせる場所をタップ", 13, Color.WHITE, true)
	wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	whb.add_child(wl)
	var cancel := Button.new()
	cancel.text = "やめる"
	UITheme.style_button(cancel, UITheme.MINT.darkened(0.2), Color.WHITE, 12, 11)
	cancel.custom_minimum_size = Vector2(60, 28)
	cancel.pressed.connect(func(): set_wind_mode(false))
	whb.add_child(cancel)
	_wind_banner.position = Vector2(40, 56)
	_wind_banner.visible = false
	add_child(_wind_banner)

	# ちょっかいの結果（数秒で消える）
	_toast = PanelContainer.new()
	var tsb := UITheme.box(Color(0.16, 0.11, 0.28, 0.9), 16, Color(0, 0, 0, 0), 0, 10)
	tsb.content_margin_left = 14
	tsb.content_margin_right = 14
	tsb.content_margin_top = 10
	tsb.content_margin_bottom = 10
	_toast.add_theme_stylebox_override("panel", tsb)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = UITheme.label("", 12, Color.WHITE)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.custom_minimum_size = Vector2(300, 0)
	_toast.add_child(_toast_label)
	_toast.position = Vector2(16, 90)
	_toast.visible = false
	add_child(_toast)


func _refresh_mute() -> void:
	_mute_icon.set_kind("mute" if Audio.muted else "sound", UITheme.INK_SOFT if Audio.muted else UITheme.PURPLE)


func toast(lines: Array) -> void:
	if lines.is_empty():
		return
	Audio.play("toast")
	_toast_label.text = "\n".join(lines.slice(0, 5))
	_toast.visible = true
	_toast.reset_size()
	_toast.modulate.a = 1.0
	UITheme.pop_in(_toast, 0.95)
	var tw := _toast.create_tween()
	tw.tween_interval(3.5 + lines.size() * 0.8)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): _toast.visible = false)


# ------------------------------------------------------------
# 下部のシート（町のようす＋ちょっかい）
# ------------------------------------------------------------

func _build_sheet() -> void:
	var sb := UITheme.box(UITheme.CARD, 0, Color(0, 0, 0, 0), 0, 14, Color(0.2, 0.1, 0.35, 0.22))
	sb.corner_radius_top_left = 24
	sb.corner_radius_top_right = 24
	sb.shadow_offset = Vector2(0, -3)
	var sheet := _panel(self, Rect2(0, SHEET_Y, 360, 640 - SHEET_Y), sb)
	_panel(sheet, Rect2(160, 8, 40, 4), UITheme.box(UITheme.LINE, 2))
	_place(sheet, Icon.make("scroll", UITheme.PURPLE, 18), Vector2(18, 20))
	_place(sheet, UITheme.label("町のようす", 15, UITheme.INK, true), Vector2(42, 17))
	var more := Button.new()
	more.text = "すべて見る ›"
	UITheme.style_flat(more, UITheme.PINK, 12)
	more.position = Vector2(254, 16)
	more.size = Vector2(96, 24)
	more.pressed.connect(func(): open_log_requested.emit())
	sheet.add_child(more)

	# 最新ログ3件（タップで全件）
	var feed := Button.new()
	UITheme.style_flat(feed, UITheme.INK)
	feed.position = Vector2(12, 46)
	feed.size = Vector2(336, 124)
	feed.clip_contents = true
	feed.pressed.connect(func(): open_log_requested.emit())
	sheet.add_child(feed)
	var vb := VBoxContainer.new()
	vb.position = Vector2(4, 0)
	vb.size = Vector2(328, 124)
	vb.add_theme_constant_override("separation", 7)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_child(vb)
	for i in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var chip := UITheme.chip("--:--", Color("f1ebfa"), UITheme.INK_SOFT, 10)
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(chip)
		var text := UITheme.label("", 12, UITheme.INK)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(270, 0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		vb.add_child(row)
		_feed_rows.append({"row": row, "chip": chip.get_node("Text"), "text": text})

	# ちょっかい（町全体・場所）と、祈り・聖典
	var by := 640 - SHEET_Y - 70
	var x := 12.0
	for b in [["wind", "風", UITheme.MINT, "wind"], ["rain", "雨", UITheme.SKY, "rain"],
			["pray", "祈り", UITheme.GOLD, "pray"], ["book", "聖典", UITheme.PURPLE, "book"]]:
		_btns[b[0]] = _action_button(sheet, Rect2(x, by, 78, 60), b[2], b[3], b[1])
		x += 84
	_btns["wind"]["btn"].pressed.connect(func(): set_wind_mode(not wind_mode))
	_btns["rain"]["btn"].pressed.connect(_on_rain)
	_btns["pray"]["btn"].pressed.connect(_on_pray_button)
	_btns["book"]["btn"].pressed.connect(func(): open_scripture_requested.emit())


func _action_button(parent: Control, rect: Rect2, col: Color, icon: String, title: String) -> Dictionary:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	UITheme.style_button(b, col, Color.WHITE, 16)
	parent.add_child(b)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_bottom = -4
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", -1)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var ic := Icon.make(icon, Color.WHITE, 22)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(ic)
	var t := UITheme.label(title, 14, Color.WHITE, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 4)
	t.add_theme_color_override("font_outline_color", col.darkened(0.3))
	vb.add_child(t)
	var s := UITheme.label("", 9, Color(1, 1, 1, 0.92), true)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(s)
	return {"btn": b, "sub": s}


## デバッグUI。普段は閉じておき、町の右下の「DEBUG」で開く
func _build_debug() -> void:
	var toggle := Button.new()
	toggle.text = "DEBUG"
	for st in ["normal", "hover", "pressed", "focus"]:
		toggle.add_theme_stylebox_override(st, UITheme.box(Color(0.1, 0.07, 0.2, 0.55), 11))
	toggle.add_theme_font_override("font", UITheme.font(true))
	toggle.add_theme_font_size_override("font_size", 10)
	toggle.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	toggle.position = Vector2(296, SHEET_Y - 32)
	toggle.size = Vector2(54, 22)
	add_child(toggle)

	var sb := UITheme.box(Color(0.12, 0.09, 0.2, 0.94), 16, Color(1, 1, 1, 0.15), 1, 10)
	_debug_panel = _panel(self, Rect2(10, SHEET_Y - 158, 340, 120), sb)
	_debug_panel.visible = false
	toggle.pressed.connect(func():
		_debug_panel.visible = not _debug_panel.visible
		if _debug_panel.visible:
			UITheme.pop_in(_debug_panel, 0.95))
	var note: Label = _place(_debug_panel, UITheme.label("テスト用（製品版には出ない）。速度＝時間の早送り：×60で10秒ごと、×600で1秒ごとに町が10分進む", 10, Color(1, 1, 1, 0.75)), Vector2(12, 8))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size = Vector2(316, 0)
	var y := 46.0
	_place(_debug_panel, UITheme.label("速度", 10, Color(1, 1, 1, 0.6), true), Vector2(12, y + 6))
	var x := 42.0
	for s in [1, 60, 600]:
		_small_button(_debug_panel, "×%d" % s, Rect2(x, y, 40, 26), func(): GameClock.set_speed(s))
		x += 42
	x += 6
	for j in [["朝", 6], ["昼", 9], ["夕", 17], ["夜", 22]]:
		var h: int = j[1]
		_small_button(_debug_panel, j[0] + "へ", Rect2(x, y, 38, 26), func(): Sim.fast_forward(GameClock.seconds_until_hour(h)))
		x += 40
	y += 34
	_place(_debug_panel, UITheme.label("放置", 10, Color(1, 1, 1, 0.6), true), Vector2(12, y + 6))
	x = 42.0
	for hrs in [3, 12, 24, 72]:
		_small_button(_debug_panel, "%dh" % hrs, Rect2(x, y, 40, 26), func(): Sim.debug_absence(hrs * 3600))
		x += 42
	x += 6
	_small_button(_debug_panel, "CD解除", Rect2(x, y, 52, 26), _on_clear_cooldowns, UITheme.MINT)
	x += 56
	_small_button(_debug_panel, "初期化", Rect2(x, y, 52, 26), _on_reset, UITheme.RED)


func _small_button(parent: Control, text: String, rect: Rect2, cb: Callable, col: Color = UITheme.PURPLE) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	UITheme.style_button(b, col, Color.WHITE, 8, 11)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ------------------------------------------------------------
# キャラカード
# ------------------------------------------------------------

func _build_card() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.12, 0.06, 0.22, 0.35)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	_dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close_popup())
	add_child(_dim)

	_card = PanelContainer.new()
	var sb := UITheme.box(UITheme.CARD, 24, Color(0, 0, 0, 0), 0, 18, Color(0.15, 0.05, 0.3, 0.3))
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	_card.add_theme_stylebox_override("panel", sb)
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	_card.position = Vector2(20, 60)
	_card.visible = false
	add_child(_card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	_card.add_child(vb)

	# ヘッダー（色帯＋ポートレート＋名前）
	var header := Control.new()
	header.custom_minimum_size = Vector2(CARD_W, 100)
	vb.add_child(header)
	_band = _panel(header, Rect2(0, 0, CARD_W, 66), StyleBoxFlat.new())
	var gloss := _panel(_band, Rect2(0, 0, CARD_W, 30), StyleBoxFlat.new())
	var gsb: StyleBoxFlat = gloss.get_theme_stylebox("panel")
	gsb.bg_color = Color(1, 1, 1, 0.16)
	gsb.corner_radius_top_left = 24
	gsb.corner_radius_top_right = 24
	_place(_band, Icon.make("sparkle", Color(1, 1, 1, 0.35), 26), Vector2(240, 6))
	_place(_band, Icon.make("sparkle", Color(1, 1, 1, 0.25), 16), Vector2(222, 38))
	_portrait_frame = _panel(header, Rect2(18, 24, 72, 72), StyleBoxFlat.new())
	_portrait = TextureRect.new()
	_portrait.position = Vector2(4, 4)
	_portrait.size = Vector2(64, 64)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait_frame.add_child(_portrait)
	_name_label = _place(header, UITheme.label("", 22, Color.WHITE, true), Vector2(102, 16))
	_name_label.add_theme_constant_override("outline_size", 6)
	_chips = HBoxContainer.new()
	_chips.position = Vector2(102, 72)
	_chips.add_theme_constant_override("separation", 6)
	header.add_child(_chips)
	var close := Button.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		close.add_theme_stylebox_override(st, UITheme.box(Color(1, 1, 1, 0.28), 14))
	close.position = Vector2(CARD_W - 40, 12)
	close.size = Vector2(28, 28)
	close.pressed.connect(close_popup)
	header.add_child(close)
	_place(close, Icon.make("close", Color.WHITE, 14), Vector2(7, 7))

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 18)
	vb.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)

	# ステータス
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 6)
	body.add_child(_stats)
	for s in [["faith", "信仰"], ["health", "体力"], ["mood", "気分"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_stats.add_child(row)
		var l := UITheme.label(s[1], 11, UITheme.INK_SOFT, true)
		l.custom_minimum_size = Vector2(30, 0)
		row.add_child(l)
		var g = Gauge.new()
		g.custom_minimum_size = Vector2(0, 10)
		g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		match s[0]:
			"faith":
				g.center = true
				g.lo = -100.0
				g.color = UITheme.GOLD
				g.neg_color = UITheme.PURPLE
			"health":
				g.color = UITheme.MINT
			"mood":
				g.color = UITheme.PINK
		row.add_child(g)
		var v := UITheme.label("", 12, UITheme.INK, true)
		v.custom_minimum_size = Vector2(78, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(v)
		_gauges[s[0]] = {"g": g, "v": v}

	_traits = HFlowContainer.new()
	_traits.add_theme_constant_override("h_separation", 6)
	_traits.add_theme_constant_override("v_separation", 4)
	body.add_child(_traits)
	_motto = UITheme.label("", 11, UITheme.INK_SOFT)
	_motto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_motto.custom_minimum_size = Vector2(INNER_W, 0)
	body.add_child(_motto)

	# 信じている教え
	_beliefs = VBoxContainer.new()
	_beliefs.add_theme_constant_override("separation", 4)
	body.add_child(_beliefs)

	# 祈り
	_wish_box = _box_container(body, UITheme.box(UITheme.CREAM, 16, UITheme.GOLD, 2))
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 4)
	_wish_box.add_child(wv)
	var wh := HBoxContainer.new()
	wh.add_theme_constant_override("separation", 6)
	wv.add_child(wh)
	wh.add_child(Icon.make("pray", UITheme.GOLD, 18))
	wh.add_child(UITheme.label("祈っている", 12, Color("c08400"), true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wh.add_child(spacer)
	var timer_chip := UITheme.chip("", UITheme.GOLD, Color.WHITE, 11)
	wh.add_child(timer_chip)
	_wish_timer = timer_chip.get_node("Text")
	_wish_label = UITheme.label("", 16, UITheme.INK, true)
	_wish_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wish_label.custom_minimum_size = Vector2(INNER_W - 28, 0)
	wv.add_child(_wish_label)
	_wish_hint = UITheme.label("", 10, Color("a07a2a"))
	_wish_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wish_hint.custom_minimum_size = Vector2(INNER_W - 28, 0)
	wv.add_child(_wish_hint)

	# 結果
	_result_box = _box_container(body, UITheme.box(Color("f3efff"), 16))
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	_result_box.add_child(rv)
	_result_head = UITheme.label("", 12, UITheme.PURPLE, true)
	rv.add_child(_result_head)
	_result_text = UITheme.label("", 12, UITheme.INK)
	_result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_text.custom_minimum_size = Vector2(INNER_W - 24, 0)
	rv.add_child(_result_text)

	# 墓
	_grave_box = _box_container(body, UITheme.box(Color("f2f0f6"), 16))
	_grave_label = UITheme.label("", 13, UITheme.INK)
	_grave_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_grave_label.custom_minimum_size = Vector2(INNER_W - 24, 0)
	_grave_box.add_child(_grave_label)

	# この住民へのちょっかい（つつく・夢を見せる）
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	body.add_child(_actions)
	_poke_btn = _icon_button("つつく", "tap", UITheme.PINK, Vector2(138, 60))
	_poke_btn.pressed.connect(_on_poke)
	_actions.add_child(_poke_btn)
	_dream_btn = _icon_button("夢を見せる", "moon", UITheme.PURPLE, Vector2(138, 60))
	_dream_btn.pressed.connect(_on_dream)
	_actions.add_child(_dream_btn)
	_dream_sub = UITheme.label("", 9, Color(1, 1, 1, 0.9), true)
	_dream_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dream_btn.get_child(1).add_child(_dream_sub)


func _icon_button(text: String, icon: String, col: Color, min_size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	UITheme.style_button(b, col, Color.WHITE, 16)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_bottom = -4
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var ic := Icon.make(icon, Color.WHITE, 20)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ic)
	var l := UITheme.label(text, 14, Color.WHITE, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", col.darkened(0.3))
	box.add_child(l)
	return b


func show_resident(id: String) -> void:
	var r := Sim.find_resident(id)
	if r.is_empty():
		return
	set_wind_mode(false)
	_popup_rid = id
	var col: Color = UITheme.CHARA_COLORS.get(id, UITheme.PURPLE)
	_set_band(col)
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/sprites/chara_%s.png" % id)
	at.region = Rect2(0, 0, 16, 16)
	_portrait.texture = at
	_name_label.text = r["name"]
	_traits.get_children().map(func(c): c.queue_free())
	for tr in r["traits"]:
		_traits.add_child(UITheme.chip("#" + str(tr), Color("f1ebfa"), UITheme.PURPLE, 11))
	_motto.text = r.get("motto", "")
	_result_box.visible = false
	_grave_box.visible = false
	for c in [_stats, _traits, _motto, _actions]:
		c.visible = true
	_refresh_card()
	_open_card()
	selection_changed.emit(id)
	card_opened.emit()


func show_grave(index: int) -> void:
	_popup_rid = ""
	var g: Dictionary = Sim.graves[index]
	_set_band(Color("7a8194"))
	_portrait.texture = load("res://assets/sprites/grave.png")
	_name_label.text = "%sの墓" % g["name"]
	_set_chips([[g["role"], Color("eceaf2"), UITheme.INK_SOFT], ["%d日目に没" % g["day_of_death"], Color("eceaf2"), UITheme.INK_SOFT]])
	_grave_label.text = "死因：%s\n\n遺言\n「%s」" % [g["cause"], g["epitaph"]]
	for c in [_stats, _traits, _motto, _beliefs, _wish_box, _result_box, _actions]:
		c.visible = false
	_grave_box.visible = true
	_open_card()
	selection_changed.emit("")


func close_popup() -> void:
	if not _card.visible:
		return
	_popup_rid = ""
	_dim.visible = false
	Audio.play("close")
	var tw := _card.create_tween()
	tw.tween_property(_card, "modulate:a", 0.0, 0.1)
	tw.tween_callback(func(): _card.visible = false)
	selection_changed.emit("")


## トーストやバナーが出ている（ミミの案内はその間待つ）
func is_busy() -> bool:
	return _toast.visible or _banner.visible


func is_popup_open() -> bool:
	return _card.visible or _dream_picker.visible


func _open_card() -> void:
	Audio.play("open")
	_dim.visible = true
	_card.visible = true
	_card.modulate.a = 1.0
	_card.reset_size()
	_layout_card.call_deferred(true)


func _layout_card(animate: bool = false) -> void:
	_card.reset_size()
	_card.position = Vector2(20, clampf((SHEET_Y - _card.size.y) / 2.0 + 20.0, 12.0, 640.0 - _card.size.y - 12.0))
	if animate:
		UITheme.pop_in(_card)


func _set_band(col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = 24
	sb.corner_radius_top_right = 24
	_band.add_theme_stylebox_override("panel", sb)
	_portrait_frame.add_theme_stylebox_override("panel", UITheme.box(Color.WHITE, 20, col, 3, 6))
	_name_label.add_theme_color_override("font_outline_color", col.darkened(0.35))


func _set_chips(list: Array) -> void:
	for c in _chips.get_children():
		c.queue_free()
	for c in list:
		_chips.add_child(UITheme.chip(c[0], c[1], c[2], 11))


func _refresh_card() -> void:
	if _popup_rid == "":
		return
	var r := Sim.find_resident(_popup_rid)
	if r.is_empty():
		return
	var col: Color = UITheme.CHARA_COLORS.get(_popup_rid, UITheme.PURPLE)
	var state_col := UITheme.GOLD if r["state"] == "praying" else col
	var chip_list := [[r["role"], col.lightened(0.78), col.darkened(0.2)]]
	chip_list.append([STATE_NAMES.get(r["state"], r["state"]), state_col, Color.WHITE])
	if _chips.get_child_count() != chip_list.size() or _chip_text(0) != chip_list[0][0] or _chip_text(1) != chip_list[1][0]:
		_set_chips(chip_list)
	_gauges["faith"]["g"].set_value(r["faith"])
	_gauges["faith"]["v"].text = "%+d %s" % [roundi(r["faith"]), _faith_word(r["faith"])]
	_gauges["health"]["g"].set_value(r["health"])
	_gauges["health"]["v"].text = "%d" % roundi(r["health"])
	_gauges["mood"]["g"].set_value(r["mood"])
	_gauges["mood"]["v"].text = "%d" % roundi(r["mood"])
	var changed := _refresh_beliefs(r)
	var wish := Sim.prayer_wish(r)
	var was := _wish_box.visible
	_wish_box.visible = wish != ""
	if wish != "":
		_wish_label.text = "「%s」" % wish
		var left := Sim.prayer_seconds_left(r)
		_wish_timer.text = "あと %d:%02d" % [left / 3600, (left % 3600) / 60]
		var pr: Dictionary = r["prayer"]
		if pr["id"] == "question":
			_wish_hint.text = "%sを送ればイエス。何もしなければノーと受け取る。" % Doctrine.INTERVENTIONS[pr["intervention"]]
		else:
			_wish_hint.text = "つつく・夢・風・雨のどれかが届くと、%sなりに「答え」と受け取る。何もしなければ無視になる。" % r["name"]
		if not was:
			_result_box.visible = false  # 新しい祈りが来たら前の結果は消す
	_poke_btn.disabled = r["state"] == "dead"
	_actions.visible = r["state"] != "dead"  # 亡くなった住民にはもう何もできない
	var reason := Sim.dream_block_reason(r)
	_dream_btn.disabled = reason != ""
	_dream_sub.text = reason if reason != "" else "今夜の1回"
	if was != _wish_box.visible or changed:
		_layout_card.call_deferred()


## 信じている教えの一覧。変わったら true
func _refresh_beliefs(r: Dictionary) -> bool:
	var docs := Doctrine.believed_by(r)
	var key := ",".join(docs.map(func(d): return str(d["id"])))
	if _beliefs.get_meta("key", "") == key and _beliefs.visible == not docs.is_empty():
		return false
	_beliefs.set_meta("key", key)
	for c in _beliefs.get_children():
		c.queue_free()
	_beliefs.visible = not docs.is_empty()
	if docs.is_empty():
		return true
	_beliefs.add_child(UITheme.label("信じている教え", 11, UITheme.INK_SOFT, true))
	for d in docs:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.add_child(Icon.make("book", UITheme.PURPLE, 14))
		var l := UITheme.label("「%s」" % Doctrine.text(d), 12, UITheme.PURPLE.darkened(0.2), true)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(INNER_W - 22, 0)
		hb.add_child(l)
		_beliefs.add_child(hb)
	return true


func _chip_text(i: int) -> String:
	if i >= _chips.get_child_count():
		return ""
	var c := _chips.get_child(i)
	return c.get_node("Text").text if c.has_node("Text") else ""


func _faith_word(f: float) -> String:
	if f >= 60:
		return "狂信"
	if f >= 20:
		return "崇拝"
	if f > -20:
		return "半信半疑"
	if f > -60:
		return "懐疑"
	return "憎悪"


func _on_poke() -> void:
	Audio.play("poke", 0.1)
	var res := Sim.poke(_popup_rid)
	if res.is_empty():
		return
	_show_result("つつく → %s" % RESULT_NAMES.get(res["result"], ""), res["lines"])


func _on_dream() -> void:
	var r := Sim.find_resident(_popup_rid)
	if r.is_empty() or Sim.dream_block_reason(r) != "":
		return
	_dream_picker.open(r)


func _on_dream_chosen(id: String, symbols: Array) -> void:
	var res := Sim.send_dream(id, symbols)
	if res.is_empty():
		return
	Audio.play("dream")
	if _card.visible and _popup_rid == id:
		_show_result("夢を見せた（%s）" % "・".join(symbols), res["lines"] + ["朝になれば、何を見たか語るだろう。"])
	else:
		toast(res["lines"])


func _show_result(head: String, lines: Array) -> void:
	_result_head.text = head
	_result_text.text = "\n".join(lines)
	_result_box.visible = true
	_refresh_card()
	_layout_card.call_deferred()
	_result_box.modulate.a = 0.0
	_result_box.create_tween().tween_property(_result_box, "modulate:a", 1.0, 0.25)


func _on_pray_button() -> void:
	var praying := Sim.praying_residents()
	if praying.is_empty():
		return
	var idx := 0
	for i in praying.size():
		if praying[i]["id"] == _popup_rid:
			idx = (i + 1) % praying.size()
	show_resident(praying[idx]["id"])


# ------------------------------------------------------------
# 風（場所えらび）と雨
# ------------------------------------------------------------

func set_wind_mode(on: bool) -> void:
	if on and not Sim.can_wind():
		return
	wind_mode = on
	_wind_banner.visible = on
	if on:
		close_popup()
		_wind_banner.reset_size()
		_wind_banner.position.x = (360 - _wind_banner.size.x) / 2.0
		UITheme.pop_in(_wind_banner, 0.9)


## main.gd から：町の場所がタップされた
func blow_wind_at(place: String) -> void:
	set_wind_mode(false)
	var res := Sim.blow_wind(place)
	if not res.is_empty():
		Audio.play("wind")
		toast(res["lines"])


func _on_rain() -> void:
	set_wind_mode(false)
	var res := Sim.make_rain()
	if not res.is_empty():
		Audio.play("rain")
		toast(res["lines"])
	_refresh_top()


# ------------------------------------------------------------
# 更新
# ------------------------------------------------------------

func _on_state_changed() -> void:
	_refresh_top()
	if _card.visible and _popup_rid != "":
		_refresh_card()


func _refresh_top() -> void:
	var now := GameClock.now()
	var d := GameClock.local(now)
	var hour: int = d["hour"]
	_day_label.text = "%d日目" % Sim.day
	_time_label.text = "%d/%d %02d:%02d" % [d["month"], d["day"], hour, d["minute"]]
	if Sim.weather == "rain":
		_weather_icon.set_kind("rain", UITheme.SKY)
	elif hour >= 19 or hour < 5:
		_weather_icon.set_kind("moon", Color("f5c542"))
	else:
		_weather_icon.set_kind("sun", UITheme.GOLD)
	_presence_gauge.set_value(Sim.god_presence)
	_presence_gauge.color = UITheme.RED if Sim.god_presence < 20.0 else UITheme.GOLD
	_presence_label.text = "%d" % roundi(Sim.god_presence)
	_speed_chip.visible = GameClock.speed != 1.0
	if _speed_chip.visible:
		_speed_chip.get_node("Text").text = "早送り中 ×%d" % GameClock.speed
	_set_btn("wind", Sim.can_wind(), "場所をえらぶ" if Sim.can_wind() else "あと%d分" % ceili(Sim.wind_cooldown_left() / 60.0))
	_set_btn("rain", Sim.can_rain(), "町じゅうに" if Sim.can_rain() else "あと%d分" % ceili(Sim.rain_cooldown_left() / 60.0))
	var n := Sim.praying_residents().size()
	_set_btn("pray", n > 0, "%d人" % n if n > 0 else "いまは静か")
	var active := Doctrine.active().size()
	_set_btn("book", true, "教え %d" % active if active > 0 else "まだ白紙")


func _set_btn(key: String, enabled: bool, sub: String) -> void:
	_btns[key]["btn"].disabled = not enabled
	_btns[key]["sub"].text = sub


func _refresh_feed() -> void:
	var latest := LogManager.latest(_feed_rows.size())
	latest.reverse()
	for i in _feed_rows.size():
		var row: Dictionary = _feed_rows[i]
		row["row"].visible = i < latest.size()
		if i < latest.size():
			var e: Dictionary = latest[i]
			row["chip"].text = GameClock.format_hm(int(e["t"]))
			row["text"].text = e["text"]
			var imp := int(e.get("imp", 1))
			var col := UITheme.RED if imp >= 3 else UITheme.INK
			row["text"].add_theme_color_override("font_color", col if i == 0 else col.lerp(UITheme.INK_SOFT, 0.6))


func _on_clear_cooldowns() -> void:
	Sim.rain_cooldown_until = 0
	Sim.wind_cooldown_until = 0
	Sim.dream_night = -1
	_refresh_top()


func _on_reset() -> void:
	close_popup()
	SaveManager.delete_save()
	GameClock.offset = 0.0
	GameClock.set_speed(1.0)
	Sim.new_game()
	SaveManager.save_game()
	Sim.state_changed.emit()
	_refresh_feed()


# ------------------------------------------------------------
# 部品
# ------------------------------------------------------------

func _panel(parent: Control, rect: Rect2, sb: StyleBox) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE if parent == self and rect.size.y < 60 else Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	return p


func _place(parent: Control, c: Control, pos: Vector2):
	c.position = pos
	parent.add_child(c)
	return c


func _box_container(parent: Control, sb: StyleBoxFlat) -> PanelContainer:
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


# ------------------------------------------------------------
# 教えが生まれた瞬間のバナー（タップで聖典）
# ------------------------------------------------------------

func _build_banner() -> void:
	_banner = PanelContainer.new()
	var sb := UITheme.box(Color("3b2a78"), 20, Color("ffe28a"), 2, 16, Color(0.2, 0.05, 0.4, 0.45))
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	_banner.add_theme_stylebox_override("panel", sb)
	_banner.custom_minimum_size = Vector2(320, 0)
	_banner.visible = false
	_banner.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_hide_banner()
			open_scripture_requested.emit())
	add_child(_banner)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hb)
	hb.add_child(Icon.make("sparkle", Color("ffe28a"), 18))
	_banner_title = UITheme.label("", 13, Color("ffe28a"), true)
	hb.add_child(_banner_title)
	_banner_text = UITheme.label("", 17, Color.WHITE, true)
	_banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_text.custom_minimum_size = Vector2(288, 0)
	_banner_text.add_theme_constant_override("outline_size", 4)
	_banner_text.add_theme_color_override("font_outline_color", Color("2a1c5a"))
	vb.add_child(_banner_text)
	_banner_sub = UITheme.label("", 11, Color(1, 1, 1, 0.75))
	_banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_sub.custom_minimum_size = Vector2(288, 0)
	vb.add_child(_banner_sub)


func _next_banner() -> void:
	if _banner_queue.is_empty():
		return
	var item: Array = _banner_queue.pop_front()
	var kind: String = item[0]
	var d: Dictionary = item[1]
	var titles := {"new": "新しい教えが生まれた", "rival": "町が二つに割れた", "established": "町の教えになった"}
	_banner_title.text = titles.get(kind, "教え")
	_banner_text.text = "「%s」" % Doctrine.text(d)
	if kind == "established":
		_banner_sub.text = "信じる者が町の半分を超えた。タップで聖典を読む"
	else:
		_banner_sub.text = "%sが唱えた。タップで聖典を読む" % d["founder_name"]
	_toast.visible = false  # バナーのほうが大事。結果はログにも残っている
	_banner.visible = true
	_banner.modulate.a = 1.0
	_banner.reset_size()
	_banner.position = Vector2(20, 96)
	UITheme.pop_in(_banner, 0.8)
	var tw := _banner.create_tween()
	tw.tween_interval(6.0)
	tw.tween_callback(_hide_banner)


func _hide_banner() -> void:
	if not _banner.visible:
		return
	var tw := _banner.create_tween()
	tw.tween_property(_banner, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		_banner.visible = false
		_next_banner())
