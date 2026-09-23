extends Node
## 住民ログの生成・保持。文面は data/log_templates.json のテンプレートから作る。
## entry = { "t": UNIX秒, "text": 本文, "imp": 重要度 }
## 重要度: 4=死亡 3=神は死んだ説 2=口論など 1=その他

signal log_added(entry: Dictionary)

const MAX_ENTRIES := 200
const TEMPLATE_PATH := "res://data/log_templates.json"

var entries: Array = []

var _templates: Dictionary = {}
var _capturing := false
var _captured: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var f := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if f == null:
		push_error("log_templates.json を開けません")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_templates = parsed


func has_template(key: String) -> bool:
	return _templates.has(key)


## テンプレートから1文を作る。バリエーションがあればランダムに選ぶ
func render(key: String, params: Dictionary = {}) -> String:
	var v = _templates.get(key, key)
	if v is Array:
		v = v[_rng.randi() % v.size()]
	return str(v).format(params)


func add(key: String, params: Dictionary = {}, importance: int = 1, t: int = -1) -> Dictionary:
	return add_text(render(key, params), importance, t)


## テンプレートを通さず、できあがった文をそのままログにする
func add_text(text: String, importance: int = 1, t: int = -1) -> Dictionary:
	var entry := {
		"t": t if t >= 0 else GameClock.now(),
		"text": text,
		"imp": importance,
	}
	entries.append(entry)
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES)
	if _capturing:
		_captured.append(entry)
	log_added.emit(entry)
	return entry


## 性格タグから遺言を1行作る
func epitaph(traits: Array) -> String:
	var keys: Array = []
	for tr in traits:
		if has_template("epitaph_" + str(tr)):
			keys.append("epitaph_" + str(tr))
	if keys.is_empty():
		return render("epitaph")
	return render(keys[_rng.randi() % keys.size()])


func latest(n: int) -> Array:
	return entries.slice(maxi(0, entries.size() - n))


func clear() -> void:
	entries.clear()


## オフライン進行中のログを集める（留守中の出来事用）
func begin_capture() -> void:
	_capturing = true
	_captured = []


func end_capture() -> Array:
	_capturing = false
	var out := _captured
	_captured = []
	return out
