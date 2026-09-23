extends Node
## 町の状態とシミュレーション本体。表示には一切依存しない。
## 1ティック = 現実10分。オフライン中は表示なしでティックを一括実行する。
## 教義のロジックは Doctrine.gd（CONCEPT.md 6章）。

signal state_changed
signal resident_bubble(id: String, text: String)
signal away_report(seconds: int, events: Array)
signal god_woke
signal prayer_started(id: String)
signal prayer_answered(id: String, good: bool)

const TICK := 600
const MAX_OFFLINE_TICKS := 72 * 6        # オフライン進行の上限 72時間
const ABSENCE_THRESHOLD := 3600          # これ以上の空白はオフライン一括進行
const REPORT_THRESHOLD := 600            # これ以上あけて開いたら「おかえりなさい」を出す
const RAIN_TICKS := 18                   # 雨の長さ 3時間
const RAIN_COOLDOWN := 3600              # 雨のクールダウン 現実1時間
const WIND_COOLDOWN := 1800              # 風のクールダウン 現実30分
const POKE_SPAM_WINDOW_MS := 60000       # この間に同じ住民を連打すると災い率アップ
const PRAYER_SECONDS := 12 * 3600        # 祈りは半日待つ（通知なしでも気づけるように）

## 場所ID → タイル座標（住民が立つ位置）。Town.gd の建物配置と対応
const PLACES := {
	"shrine": Vector2i(11, 3),
	"bakery": Vector2i(3, 8),
	"study": Vector2i(19, 8),
	"plaza": Vector2i(11, 13),
	"cemetery": Vector2i(14, 20),
	"house_tome": Vector2i(2, 14),
	"house_nob": Vector2i(20, 14),
	"house_kaz": Vector2i(6, 21),
	"house_mimi": Vector2i(2, 21),
	"house_sen": Vector2i(12, 22),
}
const PLACE_NAMES := {
	"shrine": "祠", "bakery": "パン屋", "study": "学舎", "plaza": "広場", "cemetery": "墓地",
}

## 夢の象徴。ちょっかいを表すもの／意味（状況と意味）を表すもの
const DREAM_SYMBOLS := ["雨", "風", "手", "パン", "花", "星", "墓", "火", "鐘"]
const SYMBOL_INTERVENTION := {"雨": "rain", "風": "wind", "手": "poke"}
const SYMBOL_MEANING := {
	"パン": ["morning", "grace"], "花": ["morning", "blessing"], "星": ["assembly", "blessing"],
	"墓": ["death", "wrath"], "火": ["quarrel", "rebuke"], "鐘": ["prayer", "yes"],
}
const QUESTIONS := [
	"ノブの説が間違っている", "今年もパンがうまく焼ける", "カミサマがまだ見ていてくださる",
	"あの口論を許してもよい", "明日もみんな元気でいられる", "わたしの祈りが届いている",
]

var day: int = 1
var god_presence: float = 60.0
var weather: String = "sunny"
var rain_ticks_left: int = 0
var rain_cooldown_until: int = 0
var wind_cooldown_until: int = 0
var dream_night: int = -1                # 夢を見せた夜（1晩に1回）
var blooms: Array = []                   # 風が運んだ花 {place, day, bloomed, seed}
var residents: Array = []
var graves: Array = []
var last_tick: int = 0
var last_seen: int = 0
var god_dead_declared: bool = false
var god_dead_last_day: int = -1
var guide_seen: Array = []              # ミミの案内を読んだ id

var running := false
var _offline := false   # オフライン一括進行中
var _quiet := false     # 吹き出しを出さない
var _t: int = 0         # 処理中の時刻（ログのタイムスタンプ用）
var _poke_history: Dictionary = {}
var _prayers: Dictionary = {}  # data/prayers.json
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var f := FileAccess.open("res://data/prayers.json", FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_prayers = parsed


# ------------------------------------------------------------
# 起動・進行
# ------------------------------------------------------------

func boot() -> void:
	if not SaveManager.load_game():
		new_game()
	running = true
	check_absence()


func new_game() -> void:
	var f := FileAccess.open("res://data/residents.json", FileAccess.READ)
	var arr: Array = JSON.parse_string(f.get_as_text())
	var now := GameClock.now()
	residents = []
	for d in arr:
		residents.append({
			"id": d["id"], "name": d["name"], "role": d["role"], "motto": d.get("motto", ""),
			"faith": float(d["faith"]), "health": 100.0, "mood": 60.0,
			"state": "sleeping", "traits": d["traits"],
			"home": d["home"], "work": d["work"], "color": d["color"],
			"pos": PLACES[d["home"]],
			"prayed_day": -1, "prayer": {}, "quarrel_day": -1,
			"dream": {}, "obs": {}, "hinted": {},
		})
	graves = []
	blooms = []
	day = 1
	god_presence = 60.0
	weather = "sunny"
	rain_ticks_left = 0
	rain_cooldown_until = 0
	wind_cooldown_until = 0
	dream_night = -1
	god_dead_declared = false
	god_dead_last_day = -1
	guide_seen = []
	last_tick = now - now % TICK
	last_seen = now
	_poke_history = {}
	_t = now
	Doctrine.reset()
	var hour := GameClock.hour(now)
	for r in residents:
		_apply_schedule(r, hour)
	LogManager.clear()
	_log("welcome")


func _process(_delta: float) -> void:
	if not running:
		return
	var now := GameClock.now()
	# PCのスリープ復帰などで大きく空いたら留守扱い
	if now - last_tick >= ABSENCE_THRESHOLD + TICK:
		check_absence()
		return
	var n := 0
	while now - last_tick >= TICK and n < 30:
		_tick(last_tick + TICK)
		n += 1
	if n > 0:
		state_changed.emit()
		SaveManager.save_game()


## 起動・復帰時に呼ぶ。空白時間ぶんを表示なしで進め、留守中の出来事を通知する
func check_absence() -> void:
	var now := GameClock.now()
	var away := now - last_seen
	var events: Array = []
	if away >= ABSENCE_THRESHOLD or now - last_tick >= ABSENCE_THRESHOLD:
		events = _run_offline(now)
	if away >= ABSENCE_THRESHOLD:
		_t = now
		god_presence = clampf(god_presence + 5.0, 0.0, 100.0)
		_log("god_wake", {"duration": format_duration(away)})
	if away >= REPORT_THRESHOLD:
		away_report.emit(away, events)
	state_changed.emit()
	god_woke.emit()
	SaveManager.save_game()


func _run_offline(now: int) -> Array:
	var ticks := (now - last_tick) / TICK
	if ticks > MAX_OFFLINE_TICKS:
		last_tick = (now - now % TICK) - MAX_OFFLINE_TICKS * TICK
		ticks = MAX_OFFLINE_TICKS
	_offline = true
	LogManager.begin_capture()
	for i in ticks:
		_tick(last_tick + TICK)
	var events := LogManager.end_capture()
	_offline = false
	return events


## デバッグ：時刻を進めて、その間を「起動中」としてティックを回す
func fast_forward(seconds: int) -> void:
	GameClock.advance(seconds)
	var now := GameClock.now()
	_quiet = true
	while now - last_tick >= TICK:
		_tick(last_tick + TICK)
	_quiet = false
	state_changed.emit()
	SaveManager.save_game()


## デバッグ：N秒放置したことにする
func debug_absence(seconds: int) -> void:
	SaveManager.save_game()
	GameClock.advance(seconds)
	check_absence()


func _tick(t: int) -> void:
	last_tick = t
	_t = t
	var d := GameClock.local(t)
	var hour: int = d["hour"]
	if hour == 0 and int(d["minute"]) < 10:
		day += 1

	# カミサマ不在：開いていない間は存在感が大きく下がる。開いていても放置で少しずつ下がる
	god_presence = clampf(god_presence - (0.35 if _offline else 0.1), 0.0, 100.0)

	if rain_ticks_left > 0:
		rain_ticks_left -= 1
		if rain_ticks_left == 0:
			weather = "sunny"
			_log("rain_end")

	for r in _alive():
		var was_sleeping: bool = r["state"] == "sleeping"
		_apply_schedule(r, hour)
		# 夢は目覚めたときに語られる
		if was_sleeping and r["state"] != "sleeping" and not r["dream"].is_empty():
			_wake_dream(r)
		# 寝ると回復、気分は平常へ戻っていく
		if r["state"] == "sleeping":
			r["health"] = minf(100.0, r["health"] + 0.5)
		r["mood"] = r["mood"] + (60.0 - r["mood"]) * 0.02
		# 祈りの期限
		var pr: Dictionary = r["prayer"]
		if not pr.is_empty() and t >= int(pr["until"]):
			r["prayer"] = {}
			if pr["id"] == "question":
				_add(r, "mood", -5)
				_log("question_no", {"name": r["name"]})
			else:
				_add(r, "faith", -5)
				_log("prayer_unanswered", {"name": r["name"]})

	# 風が運んだ種が咲く
	for b in blooms:
		if not b["bloomed"] and day >= int(b["day"]) and hour >= 6:
			b["bloomed"] = true
			_log("bloom", {"place": place_name(b["place"])}, 2)
			for r in _alive():
				if r["pos"] == PLACES[b["place"]]:
					_add(r, "mood", 10)

	_auto_events(hour)
	Doctrine.spread_tick(_awake(), hour)


## 現実の時刻で行動と居場所が決まる
func _apply_schedule(r: Dictionary, hour: int) -> void:
	var state := "wandering"
	var place: String = r["home"]
	if hour < 6:
		state = "sleeping"
	elif hour < 9:
		if r["faith"] > 30:
			state = "praying"
			place = "shrine"
	elif hour < 17:
		state = "working"
		place = r["work"]
	elif hour < 21:
		if weather != "rain":
			place = "plaza"  # 集会
	elif hour >= 22:
		state = "sleeping"
	r["state"] = state
	r["pos"] = PLACES[place]


# ------------------------------------------------------------
# 自動イベント
# ------------------------------------------------------------

func _auto_events(hour: int) -> void:
	var awake := _awake()

	# 朝の祈り（1日1回）
	if hour >= 6 and hour < 9:
		for r in awake:
			if r["prayed_day"] == day or not r["prayer"].is_empty():
				continue
			var pid := ""
			match r["id"]:
				"tome": pid = "bread" if r["faith"] > 0 else ""
				"kaz": pid = "oracle" if r["faith"] > 0 else ""
				"mimi": pid = "wave" if r["faith"] > -30 else ""
				_: pid = "safe" if r["faith"] > 30 else ""
			if pid != "" and _rng.randf() < 0.3:
				r["prayed_day"] = day
				if r["id"] == "tome":
					_log("prayer_tome")
				# 「返事」の教えが定着していたら、イエス・ノーで問いかけることがある
				if not Doctrine.yes_doctrine().is_empty() and r["faith"] > 20 and _rng.randf() < 0.5:
					_start_question(r)
				else:
					_start_prayer(r, pid)

	# 仕事中のふとした祈り（ノブの挑戦、センの願い）
	for r in awake:
		if r["state"] != "working" or not r["prayer"].is_empty():
			continue
		if r["id"] == "nob" and r["faith"] < 30 and _rng.randf() < 0.01:
			_start_prayer(r, "proof")
		elif r["id"] == "sen" and _rng.randf() < 0.008:
			_start_prayer(r, "quiet")

	# 病気
	for r in _alive():
		if _rng.randf() < 0.002:
			Doctrine.note_event("sick", _t)
			_log("sick", {"name": r["name"]})
			_bubble(r, "熱")
			_damage(r, 20.0, "病")
			if r["state"] != "dead" and r["faith"] > -40:
				r["prayer"] = {}
				_start_prayer(r, "sick")

	awake = _awake()

	# 口論：faithの差が大きい2人が同じ場所
	for i in awake.size():
		for j in range(i + 1, awake.size()):
			var a: Dictionary = awake[i]
			var b: Dictionary = awake[j]
			if a["pos"] != b["pos"] or absf(a["faith"] - b["faith"]) < 60.0:
				continue
			if a["quarrel_day"] == day or b["quarrel_day"] == day:
				continue
			if _rng.randf() < 0.05:
				a["quarrel_day"] = day
				b["quarrel_day"] = day
				_add(a, "mood", -10)
				_add(b, "mood", -10)
				Doctrine.note_event("quarrel", _t)
				_log("quarrel", {"name": a["name"], "target": b["name"]}, 2)
				_bubble(a, "怒")
				_bubble(b, "怒")
				# 信心深いほうがカミサマに言いつける
				var zealot: Dictionary = a if a["faith"] >= b["faith"] else b
				var other: Dictionary = b if zealot == a else a
				if zealot["faith"] > 20 and zealot["prayer"].is_empty():
					_start_prayer(zealot, "curse", other["id"])

	# 布教（カズ）と反論（ノブ）
	_influence("kaz", 5.0, "preach", "説", awake)
	_influence("nob", -5.0, "refute", "理", awake)

	# 神は死んだ説
	if god_presence < 20.0 and god_dead_last_day != day and not awake.is_empty() and _rng.randf() < 0.05:
		var speaker: Dictionary = awake[0]
		for r in awake:
			if r["faith"] < speaker["faith"]:
				speaker = r
		god_dead_declared = true
		god_dead_last_day = day
		for r in _alive():
			_add(r, "faith", -10)
		_log("god_dead", {"name": speaker["name"]}, 3)
		_bubble(speaker, "死")

	# 復活説（存在感が戻ったら）
	if god_dead_declared and god_presence >= 40.0:
		god_dead_declared = false
		for r in _alive():
			_add(r, "faith", 5)
		var kaz := _find("kaz")
		_log("god_back" if not kaz.is_empty() and kaz["state"] != "dead" else "god_back_generic", {}, 2)


func _influence(id: String, amount: float, key: String, mark: String, awake: Array) -> void:
	var src := _find(id)
	if src.is_empty() or not awake.has(src):
		return
	var targets: Array = []
	for r in awake:
		if r != src and r["pos"] == src["pos"]:
			targets.append(r)
	if targets.is_empty() or _rng.randf() >= 0.08:
		return
	for r in targets:
		_add(r, "faith", amount)
	_log(key, {"targets": _names(targets)})
	_bubble(src, mark)
	if key == "preach":
		Doctrine.preach(src, targets)
	else:
		Doctrine.refute(src, targets)


# ------------------------------------------------------------
# 祈り（願いごと）
# ------------------------------------------------------------

func _start_prayer(r: Dictionary, pid: String, target_id: String = "") -> void:
	if not _prayers.has(pid) or r["state"] == "dead":
		return
	r["prayer"] = {"id": pid, "until": _t + PRAYER_SECONDS, "target": target_id}
	_log("prayer", {"name": r["name"], "wish": prayer_wish(r)})
	if not is_silent():
		prayer_started.emit(r["id"])


## イエス・ノーの祈り。「〜なら、○○をお送りください」
func _start_question(r: Dictionary) -> void:
	var d := Doctrine.yes_doctrine()
	r["prayer"] = {
		"id": "question", "until": _t + PRAYER_SECONDS, "target": "",
		"intervention": d["intervention"], "question": QUESTIONS[_rng.randi() % QUESTIONS.size()],
	}
	_log("prayer", {"name": r["name"], "wish": prayer_wish(r)}, 2)
	if not is_silent():
		prayer_started.emit(r["id"])


## 祈りの本文（「」の中身）。祈っていなければ空文字
func prayer_wish(r: Dictionary) -> String:
	var pr: Dictionary = r["prayer"]
	if pr.is_empty() or not _prayers.has(pr["id"]):
		return ""
	return str(_prayers[pr["id"]]["wish"]).format(_prayer_params(r))


## 祈りが諦められるまでの残り秒数
func prayer_seconds_left(r: Dictionary) -> int:
	var pr: Dictionary = r["prayer"]
	if pr.is_empty():
		return 0
	return maxi(0, int(pr["until"]) - GameClock.now())


func _prayer_params(r: Dictionary) -> Dictionary:
	var pr: Dictionary = r["prayer"]
	var params := {"name": r["name"], "target": "誰か"}
	var t := _find(str(pr.get("target", "")))
	if not t.is_empty():
		params["target"] = t["name"]
	if pr.has("question"):
		params["question"] = pr["question"]
		params["int"] = Doctrine.INTERVENTIONS[pr["intervention"]]
	return params


## ちょっかいが祈っている住民に届いた。受け取り方は信じている教義と性格しだい
## hint = そのちょっかい自体の良し悪し（+1 / 0 / -1）
func _receive(r: Dictionary, intervention: String, hint: int) -> void:
	var pr: Dictionary = r["prayer"]
	if pr.is_empty() or r["state"] == "dead":
		return
	if pr["id"] == "question":
		if pr["intervention"] == intervention:
			_answer_yes(r)
		return  # 指定と違うちょっかいは答えとみなさない
	r["prayer"] = {}
	var v := Doctrine.interpret(r, intervention)
	var by_doctrine := v != Doctrine.NONE
	if not by_doctrine:
		v = hint
	if v == 0:
		var traits: Array = r["traits"]
		v = 1 if traits.has("信心深い") or traits.has("狂信的") or traits.has("無邪気") else -1
	var good := v > 0
	var params := {"name": r["name"], "int": Doctrine.INTERVENTIONS[intervention]}
	_log("took_good" if good else "took_bad", params)
	var target := _find(str(pr.get("target", "")))
	var outcome := _pick_weighted(_prayers[pr["id"]]["grant" if good else "twist"])
	_log_text(str(outcome["log"]).format(_prayer_params_with(r, pr)), 2)
	_apply_fx(r, outcome.get("fx", {}))
	var others: Dictionary = outcome.get("others", {})
	for key in others:
		var fx: Dictionary = others[key]
		if key == "@target":
			if not target.is_empty():
				_apply_fx(target, fx)
		elif key == "@all":
			for o in _alive():
				if o != r:
					_apply_fx(o, fx)
		else:
			var o := _find(key)
			if not o.is_empty():
				_apply_fx(o, fx)
	god_presence = clampf(god_presence + 3.0, 0.0, 100.0)
	_bubble(r, "答えだ!" if good else "答え…?")
	if not is_silent():
		prayer_answered.emit(r["id"], good)


func _prayer_params_with(r: Dictionary, pr: Dictionary) -> Dictionary:
	var saved: Dictionary = r["prayer"]
	r["prayer"] = pr
	var p := _prayer_params(r)
	r["prayer"] = saved
	return p


func _answer_yes(r: Dictionary) -> void:
	var pr: Dictionary = r["prayer"]
	r["prayer"] = {}
	_add(r, "faith", 10)
	_add(r, "mood", 10)
	_log("question_yes", {"name": r["name"], "question": pr["question"]}, 2)
	_bubble(r, "答えだ!")
	if not is_silent():
		prayer_answered.emit(r["id"], true)
	# ノブ派はたまに「ただの偶然」と言い張る
	var nob := _find("nob")
	if not nob.is_empty() and nob["state"] != "dead" and nob["state"] != "sleeping" and _rng.randf() < 0.3:
		_log("question_misread", {"name": r["name"]})


func _pick_weighted(options: Array) -> Dictionary:
	var total := 0.0
	for o in options:
		total += float(o.get("w", 1))
	var roll := _rng.randf() * total
	for o in options:
		roll -= float(o.get("w", 1))
		if roll <= 0.0:
			return o
	return options.back()


func _apply_fx(r: Dictionary, fx: Dictionary) -> void:
	if r["state"] == "dead":
		return
	for k in ["faith", "mood"]:
		if fx.has(k):
			_add(r, k, float(fx[k]))
	if fx.has("health"):
		var h := float(fx["health"])
		if h >= 0.0:
			_add(r, "health", h)
		else:
			_damage(r, -h, str(fx.get("cause", "カミサマの気まぐれ")))


# ------------------------------------------------------------
# ちょっかい① つつく（1人）
# ------------------------------------------------------------

## 戻り値 { "result": 結果キー, "lines": 出たログ文 }
func poke(id: String) -> Dictionary:
	var r := _find(id)
	if r.is_empty() or r["state"] == "dead":
		return {}
	_t = GameClock.now()
	LogManager.begin_capture()

	# 短時間の連打ほど災いが起きやすい
	var now_ms := Time.get_ticks_msec()
	var hist: Array = _poke_history.get(id, [])
	hist = hist.filter(func(x): return now_ms - x < POKE_SPAM_WINDOW_MS)
	var disaster_p := minf(0.15 + 0.10 * hist.size(), 0.9)
	hist.append(now_ms)
	_poke_history[id] = hist
	god_presence = clampf(god_presence + 2.0, 0.0, 100.0)

	var result := ""
	var roll := _rng.randf()
	if roll < disaster_p:
		result = "disaster"
	else:
		var rest := (roll - disaster_p) / (1.0 - disaster_p) * 85.0  # 癒やし35:驚かす30:啓示20
		if rest < 35.0:
			result = "heal"
		elif rest < 65.0:
			result = "scare"
		else:
			result = "revelation"
	var hint: int = {"heal": 1, "revelation": 1, "scare": 0, "disaster": -1}[result]

	# 見ていた住民が一致を数える（祈りへの応えより先に。祈り中なら状況は「祈り」）
	var observers: Array = [r]
	if r["state"] != "sleeping":
		observers += _awake().filter(func(o): return o != r and o["pos"] == r["pos"])
	Doctrine.observe("poke", observers, hint, _t)

	match result:
		"heal":
			_add(r, "health", 30)
			_add(r, "faith", 10)
			_log("poke_heal", {"name": r["name"]})
			_bubble(r, "ぽわ")
		"scare":
			_add(r, "mood", -20)
			var delta := _scare_faith(r)
			_add(r, "faith", delta)
			var key := "poke_scare_mimi" if r["id"] == "mimi" else ("poke_scare_up" if delta > 0 else "poke_scare_down")
			_log(key, {"name": r["name"]})
			_bubble(r, "!!")
		"revelation":
			_add(r, "faith", 20)
			var others: Array = _alive().filter(func(o): return o != r)
			var target_name: String = others[_rng.randi() % others.size()]["name"] if not others.is_empty() else "誰か"
			var key := "poke_revelation"
			if r["id"] == "kaz":
				key = "poke_revelation_kaz"
			elif r["id"] == "nob":
				key = "poke_revelation_nob"
			_log(key, {"name": r["name"], "target": target_name})
			_bubble(r, "!?")
			if r["state"] != "sleeping":
				var near: Array = _awake().filter(func(o): return o != r and o["pos"] == r["pos"])
				if not near.is_empty():
					for o in near:
						_add(o, "faith", 5)
					_log("revelation_spread", {"name": r["name"], "targets": _names(near)})
		"disaster":
			_log("poke_disaster_nob" if r["id"] == "nob" else "poke_disaster", {"name": r["name"]}, 2)
			_bubble(r, "×")
			_damage(r, 40.0, "カミサマにつつかれた")

	_receive(r, "poke", hint)
	return _finish_action({"result": result})


func _scare_faith(r: Dictionary) -> float:
	var traits: Array = r["traits"]
	if traits.has("狂信的") or traits.has("信心深い") or traits.has("無邪気"):
		return 10.0
	if traits.has("懐疑派"):
		return -10.0
	return 10.0 if _rng.randf() < 0.5 else -10.0


# ------------------------------------------------------------
# ちょっかい② 夢を見せる（寝ている1人・1晩に1回）
# ------------------------------------------------------------

## 夜の通し番号（正午で切り替わる）。同じ夜には1回しか夢を見せられない
func night_key(t: int) -> int:
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return int(floor(float(t + bias - 12 * 3600) / 86400.0))


func dream_available() -> bool:
	return dream_night != night_key(GameClock.now())


## 夢を見せられない理由。見せられるなら ""
func dream_block_reason(r: Dictionary) -> String:
	if r["state"] == "dead":
		return "もういない"
	if r["state"] != "sleeping":
		return "眠っているときだけ"
	if not dream_available():
		return "今夜はもう見せた"
	return ""


func dream_symbols() -> Array:
	var out: Array = DREAM_SYMBOLS.duplicate()
	for r in _alive():
		out.append(r["name"])
	return out


func send_dream(id: String, symbols: Array) -> Dictionary:
	var r := _find(id)
	if r.is_empty() or dream_block_reason(r) != "" or symbols.is_empty():
		return {}
	_t = GameClock.now()
	LogManager.begin_capture()
	r["dream"] = {"symbols": symbols.slice(0, 3)}
	dream_night = night_key(_t)
	god_presence = clampf(god_presence + 2.0, 0.0, 100.0)
	_log("dream_sent", {"name": r["name"]})
	_bubble(r, "…")
	return _finish_action({})


## 目覚めた住民が夢を語る（朝に解釈を聞く）
func _wake_dream(r: Dictionary) -> void:
	var syms: Array = r["dream"]["symbols"]
	r["dream"] = {}
	var joined := "・".join(syms)
	var nightmare := (syms.has("墓") or syms.has("火")) and not (syms.has("花") or syms.has("星"))
	if nightmare:
		_add(r, "mood", -15)
		_add(r, "health", -5)
		_log("dream_nightmare", {"name": r["name"], "symbols": joined})
	else:
		_add(r, "mood", 10)
	var ints: Array = syms.filter(func(s): return SYMBOL_INTERVENTION.has(s))
	var means: Array = syms.filter(func(s): return SYMBOL_MEANING.has(s))
	var people: Array = []
	for s in syms:
		var p := _find_by_name(s)
		if not p.is_empty() and p != r and p["state"] != "dead":
			people.append(p)
	var traits: Array = r["traits"]
	if traits.has("懐疑派"):
		_log("dream_skeptic", {"name": r["name"], "symbols": joined})
	elif not ints.is_empty() and not means.is_empty():
		var i: String = SYMBOL_INTERVENTION[ints[0]]
		var sm: Array = SYMBOL_MEANING[means[0]]
		var s: String = sm[0]
		var m: String = sm[1]
		# 解釈はときどきずれる
		if _rng.randf() < 0.25:
			var pair: Array = Doctrine.MEANING_BY_SITUATION[s]
			m = pair[1] if m == pair[0] else pair[0]
		_log("dream_oracle", {"name": r["name"], "text": Doctrine.text_of(i, s, m)}, 2)
		Doctrine.dream_teach(r, i, s, m)
	elif not people.is_empty():
		var p: Dictionary = people[0]
		var bad := syms.has("墓") or syms.has("火")
		_add(p, "mood", -10 if bad else 10)
		_log("dream_person_bad" if bad else "dream_person_good", {"name": r["name"], "target": p["name"], "symbols": joined})
	else:
		_log("dream_vague", {"name": r["name"], "symbols": joined})
	_bubble(r, "!")
	_receive(r, "dream", -1 if nightmare else 1)


# ------------------------------------------------------------
# ちょっかい③ 風を吹かせる（1か所）
# ------------------------------------------------------------

func place_name(pid: String) -> String:
	if PLACE_NAMES.has(pid):
		return PLACE_NAMES[pid]
	for r in residents:
		if r["home"] == pid:
			return "%sの家" % r["name"]
	return "町のどこか"


func can_wind() -> bool:
	return GameClock.now() >= wind_cooldown_until


func wind_cooldown_left() -> int:
	return maxi(0, wind_cooldown_until - GameClock.now())


func blow_wind(place: String) -> Dictionary:
	if not can_wind() or not PLACES.has(place):
		return {}
	_t = GameClock.now()
	LogManager.begin_capture()
	wind_cooldown_until = _t + WIND_COOLDOWN
	god_presence = clampf(god_presence + 2.0, 0.0, 100.0)
	var here: Array = _alive().filter(func(r): return r["pos"] == PLACES[place])
	var awake_here: Array = here.filter(func(r): return r["state"] != "sleeping")
	var good := _rng.randf() < 0.5
	var pname := place_name(place)
	Doctrine.observe("wind", awake_here, 1 if good else -1, _t)
	if good:
		_log("wind_good", {"place": pname})
		for r in awake_here:
			_add(r, "mood", 5)
			_bubble(r, "♪")
		if _rng.randf() < 0.4 and blooms.filter(func(b): return b["place"] == place).is_empty():
			blooms.append({"place": place, "day": day + 1, "bloomed": false, "seed": _rng.randi() % 1000})
	else:
		match place:
			"bakery":
				_log("wind_bakery")
				var tome := _find("tome")
				if not tome.is_empty():
					_add(tome, "mood", -15)
			"cemetery":
				_log("wind_cemetery")
				var sen := _find("sen")
				if not sen.is_empty():
					_add(sen, "mood", 5)
			_:
				if awake_here.is_empty():
					_log("wind_bad_empty", {"place": pname})
				else:
					_log("wind_bad", {"place": pname, "names": _names(awake_here)})
		for r in awake_here:
			_add(r, "mood", -10)
			_bubble(r, "!!")
	for r in here:
		_receive(r, "wind", 1 if good else -1)
	_receive_question_all("wind")
	return _finish_action({"good": good, "place": place})


# ------------------------------------------------------------
# ちょっかい④ 雨を降らせる（町全体）
# ------------------------------------------------------------

func can_rain() -> bool:
	return GameClock.now() >= rain_cooldown_until


func rain_cooldown_left() -> int:
	return maxi(0, rain_cooldown_until - GameClock.now())


func make_rain() -> Dictionary:
	if not can_rain():
		return {}
	_t = GameClock.now()
	LogManager.begin_capture()
	var hour := GameClock.hour(_t)
	var assembly := hour >= 17 and hour < 21
	weather = "rain"
	rain_ticks_left = RAIN_TICKS
	rain_cooldown_until = _t + RAIN_COOLDOWN
	god_presence = clampf(god_presence + 2.0, 0.0, 100.0)
	Doctrine.observe("rain", _awake(), 0, _t)
	_log("rain_start")
	if assembly:
		_log("rain_assembly", {}, 2)
	for r in _alive():
		match r["id"]:
			"tome":
				_add(r, "mood", -10)
				_log("rain_tome")
			"nob":
				_log("rain_nob")
				_bubble(r, "ほら")
			"kaz":
				_log("rain_kaz")
				_bubble(r, "!")
		if assembly:
			if r["id"] != "nob":  # ノブにとってはただの気象
				_add(r, "faith", -5)
		elif r["id"] != "tome":
			_add(r, "mood", -5)
		_apply_schedule(r, hour)
	for r in _alive():
		_receive(r, "rain", 0)
	return _finish_action({})


## 風や雨は町じゅうから見えるので、イエス・ノーの祈りにはどこにいても届く
func _receive_question_all(intervention: String) -> void:
	for r in _alive():
		var pr: Dictionary = r["prayer"]
		if not pr.is_empty() and pr["id"] == "question" and pr["intervention"] == intervention:
			_answer_yes(r)


func _finish_action(res: Dictionary) -> Dictionary:
	res["lines"] = LogManager.end_capture().map(func(e): return e["text"])
	state_changed.emit()
	SaveManager.save_game()
	return res


# ------------------------------------------------------------
# 起動時の「いま決められること」（CONCEPT.md 8.1）
# ------------------------------------------------------------

## { kind: "prayer"/"dream"/"hint"/"none", id: 住民ID, text: 説明 }
func suggestion() -> Dictionary:
	var praying := praying_residents()
	for r in praying:
		if r["prayer"]["id"] == "question":
			return {"kind": "prayer", "id": r["id"],
				"text": "%sが、%sで答えてほしいと祈っている。" % [r["name"], Doctrine.INTERVENTIONS[r["prayer"]["intervention"]]]}
	if not praying.is_empty():
		var soon: Dictionary = praying[0]
		for r in praying:
			if int(r["prayer"]["until"]) < int(soon["prayer"]["until"]):
				soon = r
		var left := prayer_seconds_left(soon)
		return {"kind": "prayer", "id": soon["id"],
			"text": "%sが祈っている。あと%d時間で諦める。" % [soon["name"], ceili(left / 3600.0)]}
	if dream_available():
		var sleepers: Array = _alive().filter(func(r): return r["state"] == "sleeping")
		if not sleepers.is_empty():
			var s: Dictionary = sleepers[_rng.randi() % sleepers.size()]
			return {"kind": "dream", "id": s["id"], "text": "今夜はまだ、誰にも夢を見せていない。"}
	var hints := Doctrine.hints()
	if not hints.is_empty():
		return {"kind": "hint", "id": "", "text": "%sが、%sについて何か言いかけている。" % [hints[0]["name"], hints[0]["int"]]}
	return {"kind": "none", "id": "", "text": "いまは、何もしなくてもいい。"}


# ------------------------------------------------------------
# 死亡と墓
# ------------------------------------------------------------

func _damage(r: Dictionary, amount: float, cause: String) -> void:
	if r["state"] == "dead":
		return
	r["health"] = maxf(0.0, r["health"] - amount)
	if r["health"] <= 0.0:
		_kill(r, cause)


func _kill(r: Dictionary, cause: String) -> void:
	r["state"] = "dead"
	r["prayer"] = {}
	r["dream"] = {}
	var slot := graves.size()
	graves.append({
		"resident_id": r["id"], "name": r["name"], "role": r["role"],
		"day_of_death": day, "cause": cause,
		"epitaph": LogManager.epitaph(r["traits"]),
		"pos": Vector2i(16 + (slot % 3) * 2, 19 + (slot / 3) * 2),
	})
	Doctrine.note_event("death", _t)
	Doctrine.on_death(r)
	_log("death", {"name": r["name"], "cause": cause}, 4)
	var sen := _find("sen")
	if not sen.is_empty() and sen != r and sen["state"] != "dead":
		_add(sen, "mood", 10)
		_log("sen_dig")
		_bubble(sen, "♪")


# ------------------------------------------------------------
# ヘルパー（Doctrine.gd からも使う）
# ------------------------------------------------------------

func _find(id: String) -> Dictionary:
	for r in residents:
		if r["id"] == id:
			return r
	return {}


func _find_by_name(n: String) -> Dictionary:
	for r in residents:
		if r["name"] == n:
			return r
	return {}


func find_resident(id: String) -> Dictionary:
	return _find(id)


func alive() -> Array:
	return _alive()


func _alive() -> Array:
	return residents.filter(func(r): return r["state"] != "dead")


func _awake() -> Array:
	return residents.filter(func(r): return r["state"] != "dead" and r["state"] != "sleeping")


func add_stat(r: Dictionary, key: String, delta: float) -> void:
	_add(r, key, delta)


func _add(r: Dictionary, key: String, delta: float) -> void:
	var lo := -100.0 if key == "faith" else 0.0
	r[key] = clampf(r[key] + delta, lo, 100.0)


func _names(rs: Array) -> String:
	return "と".join(rs.map(func(r): return r["name"]))


func log_key(key: String, params: Dictionary = {}, imp: int = 1) -> void:
	_log(key, params, imp)


func _log(key: String, params: Dictionary = {}, imp: int = 1) -> void:
	LogManager.add(key, params, imp, _t)


func _log_text(text: String, imp: int = 1) -> void:
	LogManager.add_text(text, imp, _t)


## オフライン一括進行中・デバッグ早送り中（演出を出さない）
func is_silent() -> bool:
	return _offline or _quiet


func bubble_for(r: Dictionary, text: String) -> void:
	_bubble(r, text)


func _bubble(r: Dictionary, text: String) -> void:
	if not _offline and not _quiet:
		resident_bubble.emit(r["id"], text)


## いま祈っている住民
func praying_residents() -> Array:
	return residents.filter(func(r): return r["state"] != "dead" and not r["prayer"].is_empty())


static func format_duration(seconds: int) -> String:
	var h := seconds / 3600
	if h >= 24:
		return "%d日" % (h / 24)
	if h >= 1:
		return "%d時間" % h
	return "%d分" % maxi(1, seconds / 60)


# ------------------------------------------------------------
# セーブ用
# ------------------------------------------------------------

func to_dict() -> Dictionary:
	var rs: Array = []
	for r in residents:
		var c: Dictionary = r.duplicate(true)
		c["pos"] = [r["pos"].x, r["pos"].y]
		rs.append(c)
	var gs: Array = []
	for g in graves:
		var c: Dictionary = g.duplicate()
		c["pos"] = [g["pos"].x, g["pos"].y]
		gs.append(c)
	return {
		"day": day, "god_presence": god_presence, "weather": weather,
		"rain_ticks_left": rain_ticks_left, "rain_cooldown_until": rain_cooldown_until,
		"wind_cooldown_until": wind_cooldown_until, "dream_night": dream_night, "blooms": blooms,
		"residents": rs, "graves": gs,
		"last_tick": last_tick, "last_seen": last_seen,
		"god_dead_declared": god_dead_declared, "god_dead_last_day": god_dead_last_day,
		"guide_seen": guide_seen,
	}


func from_dict(d: Dictionary) -> void:
	day = int(d["day"])
	god_presence = float(d["god_presence"])
	weather = str(d["weather"])
	rain_ticks_left = int(d["rain_ticks_left"])
	rain_cooldown_until = int(d["rain_cooldown_until"])
	wind_cooldown_until = int(d.get("wind_cooldown_until", 0))
	dream_night = int(d.get("dream_night", -1))
	blooms = d.get("blooms", [])
	last_tick = int(d["last_tick"])
	last_seen = int(d["last_seen"])
	god_dead_declared = bool(d["god_dead_declared"])
	god_dead_last_day = int(d["god_dead_last_day"])
	guide_seen = d.get("guide_seen", [])
	residents = []
	for c in d["residents"]:
		var r: Dictionary = c
		r["pos"] = Vector2i(int(c["pos"][0]), int(c["pos"][1]))
		for k in ["prayed_day", "quarrel_day"]:
			r[k] = int(r[k])
		for k in ["faith", "health", "mood"]:
			r[k] = float(r[k])
		for k in ["prayer", "dream", "obs", "hinted"]:
			if not r.get(k) is Dictionary:
				r[k] = {}
		residents.append(r)
	graves = []
	for c in d["graves"]:
		var g: Dictionary = c
		g["pos"] = Vector2i(int(c["pos"][0]), int(c["pos"][1]))
		g["day_of_death"] = int(g["day_of_death"])
		graves.append(g)
