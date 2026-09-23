extends Control
## 町の住民（ふつうはミミ）が、その場の状況に合わせて遊び方を一度ずつ教えてくれる。
## 読んだ案内は Sim.guide_seen に残る（セーブされる）。

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const SHEET_Y := 388
const SPEAKERS := ["mimi", "tome", "kaz", "sen", "nob"]

## [id, 本文]。上から順に、条件を満たしたものを1つずつ出す
const TIPS := [
	["intro", "カミサマ、起きてる？ {name}だよ。\nこの町のみんなは、カミサマのことを知ってるの。見てるだけでもいいし、ちょっかいを出してもいいんだって。"],
	["sleep", "ちょっかいは、1つの時間に2回まで。\n終わったら右下の「眠る」で次の時間へ進むよ。起きたら、その間に何があったか分かるの。"],
	["prayer", "頭に金色の「祈」が出てる人は、カミサマにお願いしてるの。タップすると、何をお願いしてるか分かるよ。"],
	["card", "祈ってる人に、つつく・夢・風・雨のどれかが届くと、その人は「答え」だと思うの。\nいい意味か悪い意味かは、その人が勝手に決めちゃうんだ。"],
	["answered", "あ、答えだと思ったみたい！\n何もしないと、そのうち祈るのをやめちゃう。それもカミサマの自由だけどね。"],
	["doctrine", "誰かが「教え」を言い出したよ！\n同じことが何回か続くと、みんなそこに意味を見つけちゃうの。右下の「聖典」に書いてあるよ。"],
	["question", "見て、「〜なら、○○をお送りください」って祈ってる！\nカミサマの答え方を、みんな覚えはじめたんだね。そのちょっかいを送ればイエス、何もしなければノーだよ。"],
	["dream", "深夜はみんな寝てるよ。寝てる人をタップすると、夢を見せられるの。\n朝になったら、その人が夢の意味を話すんだって。"],
	["wind", "下の「風」は、町のどこかをタップして吹かせるの。「雨」は町じゅうに降るよ。\nどっちも、みんなが勝手に意味を考えるんだ。"],
	["death", "お墓ができちゃった……。\nお墓をタップすると、その人の最後の言葉が読めるよ。町はずっと覚えてるんだって。"],
	["lonely", "カミサマがいない時間が長いと、みんな不安になるみたい。\n「カミサマは死んだ」って言う人も出てくるかも。"],
]

var hud: Control
var blockers: Array = []   # これらが開いている間は出さない
var _flags: Dictionary = {}
var _card: PanelContainer
var _portrait: TextureRect
var _frame: Panel
var _name: Label
var _text: Label
var _current := ""
var _cooldown := 2.0
var _check := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	var sb := UITheme.box(Color.WHITE, 20, UITheme.PINK, 2, 14, Color(0.2, 0.05, 0.3, 0.3))
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_card.add_theme_stylebox_override("panel", sb)
	_card.custom_minimum_size = Vector2(336, 0)
	_card.visible = false
	add_child(_card)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	_card.add_child(hb)
	_frame = Panel.new()
	_frame.custom_minimum_size = Vector2(52, 52)
	_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(_frame)
	_portrait = TextureRect.new()
	_portrait.position = Vector2(4, 4)
	_portrait.size = Vector2(44, 44)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame.add_child(_portrait)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	hb.add_child(vb)
	_name = UITheme.label("", 12, UITheme.PINK, true)
	vb.add_child(_name)
	_text = UITheme.label("", 13, UITheme.INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(248, 0)
	vb.add_child(_text)
	var ok := Button.new()
	ok.text = "わかった"
	ok.custom_minimum_size = Vector2(96, 34)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	UITheme.style_button(ok, UITheme.PINK, Color.WHITE, 12, 13)
	ok.pressed.connect(_dismiss)
	vb.add_child(ok)


## main.gd から：HUD と、開いている間は案内を出さない画面を渡す
func setup(h: Control, block: Array) -> void:
	hud = h
	blockers = block
	hud.card_opened.connect(func(): _flags["card"] = true)
	Sim.prayer_answered.connect(func(_id, _good): _flags["answered"] = true)


func _process(delta: float) -> void:
	if _card.visible or hud == null or not Sim.running:
		return
	_cooldown -= delta
	_check -= delta
	if _cooldown > 0.0 or _check > 0.0:
		return
	_check = 0.5
	if hud.is_popup_open() or hud.wind_mode or hud.is_busy():
		return
	for b in blockers:
		if b.visible:
			return
	for tip in TIPS:
		if not Sim.guide_seen.has(tip[0]) and _ready_for(tip[0]):
			_show(tip[0], tip[1])
			return


func _ready_for(id: String) -> bool:
	var hour := GameClock.hour(GameClock.now())
	var seen: Array = Sim.guide_seen
	match id:
		"intro":
			return true
		"sleep":
			return seen.has("intro")
		"prayer":
			return not Sim.praying_residents().is_empty()
		"card", "answered":
			return _flags.get(id, false)
		"doctrine":
			return not Doctrine.active().is_empty()
		"question":
			return Sim.praying_residents().any(func(r): return r["prayer"]["id"] == "question")
		"dream":
			return hour < 6 and Sim.dream_available() and seen.has("intro")
		"wind":
			return seen.has("card") and hour >= 7 and hour < 21
		"death":
			return not Sim.graves.is_empty()
		"lonely":
			return Sim.god_presence < 30.0
	return false


func _show(id: String, text: String) -> void:
	var speaker := _speaker()
	if speaker.is_empty():
		return
	_current = id
	var col: Color = UITheme.CHARA_COLORS.get(speaker["id"], UITheme.PINK)
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/sprites/chara_%s.png" % speaker["id"])
	at.region = Rect2(0, 0, 16, 16)
	_portrait.texture = at
	_frame.add_theme_stylebox_override("panel", UITheme.box(col.lightened(0.8), 14, col, 2))
	_name.text = speaker["name"]
	_name.add_theme_color_override("font_color", col.darkened(0.1))
	_text.text = text.format({"name": speaker["name"]})
	_card.visible = true
	_card.reset_size()
	_layout.call_deferred()
	Audio.play("guide")


func _layout() -> void:
	await get_tree().process_frame
	_card.reset_size()
	_card.position = Vector2((360 - _card.size.x) / 2.0, SHEET_Y - _card.size.y - 44)
	UITheme.pop_in(_card, 0.9)


## 案内を最初から（設定・リセットから）
func restart() -> void:
	_flags = {}
	_current = ""
	_card.visible = false
	_cooldown = 1.0


func _dismiss() -> void:
	if _current != "" and not Sim.guide_seen.has(_current):
		Sim.guide_seen.append(_current)
		SaveManager.save_game()
	_current = ""
	_cooldown = 1.5
	var tw := _card.create_tween()
	tw.tween_property(_card, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func(): _card.visible = false)


## 案内役：ミミ。いなければ町の誰か
func _speaker() -> Dictionary:
	for id in SPEAKERS:
		var r := Sim.find_resident(id)
		if not r.is_empty() and r["state"] != "dead":
			return r
	return {}
