extends Node
## 教義システム（CONCEPT.md 6章）。
## 住民は「ちょっかい × 状況」の一致を数え、法則に気づくと教義を唱える。
## 教義は集会や布教で広まり、矛盾が続くと揺らぎ、信じる者がいなくなると忘れられる（消さずに残す）。

## 教えが生まれた・割れた・町の教えになった（起動中のみ。演出用）
signal doctrine_event(kind: String, d: Dictionary)

const INTERVENTIONS := {"poke": "つつき", "dream": "夢", "wind": "風", "rain": "雨"}
const SITUATIONS := {
	"quarrel": "争いへの", "sick": "病への", "prayer": "祈りへの",
	"death": "死への", "assembly": "集会への", "morning": "朝の",
}
const MEANINGS := {
	"rebuke": "叱責", "grace": "恵み", "trial": "試練",
	"yes": "返事", "wrath": "怒り", "blessing": "祝福",
}
const VALENCE := {"rebuke": -1, "grace": 1, "trial": 0, "yes": 1, "wrath": -1, "blessing": 1}
## 状況ごとの意味の候補 [良い意味, 悪い意味]
const MEANING_BY_SITUATION := {
	"quarrel": ["trial", "rebuke"], "sick": ["grace", "trial"], "prayer": ["yes", "wrath"],
	"death": ["blessing", "wrath"], "assembly": ["blessing", "rebuke"], "morning": ["grace", "trial"],
}
const NONE := 99             # interpret() で「信じている教義なし」
const MAX_ACTIVE := 5        # 同時に存在できる教義の数
const RECENT_SECONDS := 3 * 3600
const CONTRADICTION_LIMIT := 3

## d = {id, intervention, situation, meaning, founder, founder_name, believers, deniers,
##      born_day, status("active"/"forgotten"), established, rival, contradictions}
var doctrines: Array = []
var next_id := 1
var recent: Array = []       # 最近の出来事 {kind, t}（状況の判定に使う）

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func reset() -> void:
	doctrines = []
	next_id = 1
	recent = []


# ------------------------------------------------------------
# 表示用
# ------------------------------------------------------------

static func text_of(i: String, s: String, m: String) -> String:
	return "%sは%s%sである" % [INTERVENTIONS[i], SITUATIONS[s], MEANINGS[m]]


func text(d: Dictionary) -> String:
	return text_of(d["intervention"], d["situation"], d["meaning"])


## 唱えた人の口調で言い直した一文
func voice(d: Dictionary) -> String:
	var key := "voice_" + str(d["founder"])
	if not LogManager.has_template(key):
		key = "voice"
	return LogManager.render(key, {
		"text": text(d), "int": INTERVENTIONS[d["intervention"]], "meaning": MEANINGS[d["meaning"]],
	})


func active() -> Array:
	return doctrines.filter(func(d): return d["status"] == "active")


func forgotten() -> Array:
	return doctrines.filter(func(d): return d["status"] == "forgotten")


func find(id: int) -> Dictionary:
	for d in doctrines:
		if d["id"] == id:
			return d
	return {}


func believed_by(r: Dictionary) -> Array:
	return active().filter(func(d): return d["believers"].has(r["id"]))


## あと1回で何か言い出しそうな住民（聖典の「生まれかけ」）
func hints() -> Array:
	var out: Array = []
	for r in Sim.alive():
		var th := threshold(r)
		if th >= 99:
			continue
		for key in r["obs"]:
			if th > 1 and int(r["obs"][key]) == th - 1:
				out.append({"name": r["name"], "int": INTERVENTIONS[str(key).split("|")[0]]})
	return out


## 町に定着した「返事」の教義（イエス・ノーの祈りの前提）
func yes_doctrine() -> Dictionary:
	for d in active():
		if d["meaning"] == "yes" and d["established"]:
			return d
	return {}


# ------------------------------------------------------------
# 状況の判定
# ------------------------------------------------------------

func note_event(kind: String, t: int) -> void:
	recent.append({"kind": kind, "t": t})
	_prune(t)


func _prune(t: int) -> void:
	recent = recent.filter(func(e): return t - int(e["t"]) <= RECENT_SECONDS)


## ある住民にとって、いまのちょっかいは「どんな状況で」起きたか。該当なしなら ""
func situation_for(r: Dictionary, t: int) -> String:
	_prune(t)
	for kind in ["death", "quarrel", "sick"]:
		for e in recent:
			if e["kind"] == kind:
				return kind
	if not r["prayer"].is_empty():
		return "prayer"
	var hour := GameClock.hour(t)
	if hour >= 17 and hour < 21 and r["pos"] == Sim.PLACES["plaza"]:
		return "assembly"
	if hour >= 6 and hour < 9:
		return "morning"
	return ""


# ------------------------------------------------------------
# 観察 → 提唱
# ------------------------------------------------------------

## 何回の一致で「法則」に気づくか（性格しだい）
func threshold(r: Dictionary) -> int:
	var traits: Array = r["traits"]
	if traits.has("懐疑派"):
		return 99  # 自分からは唱えない
	if traits.has("狂信的"):
		return 1
	if traits.has("信心深い") or traits.has("無邪気"):
		return 2
	if traits.has("無関心"):
		return 4
	return 3


## ちょっかいを見た住民たちが一致を数える。valence はそのちょっかいの見た目の良し悪し
func observe(intervention: String, observers: Array, valence: int, t: int) -> void:
	var seen_situations: Array = []
	for r in observers:
		if r["state"] == "dead":
			continue
		var s := situation_for(r, t)
		if s == "":
			continue
		seen_situations.append(s)
		var key := intervention + "|" + s
		r["obs"][key] = int(r["obs"].get(key, 0)) + 1
		_maybe_propose(r, intervention, s, valence)
	_react(intervention, valence)
	# 教えと違う状況でちょっかいが起きた → 矛盾
	if not seen_situations.is_empty():
		for d in active():
			if d["intervention"] != intervention:
				continue
			if seen_situations.has(d["situation"]):
				d["contradictions"] = 0
			else:
				d["contradictions"] = int(d["contradictions"]) + 1
				if d["contradictions"] >= CONTRADICTION_LIMIT:
					d["contradictions"] = 0
					_shake(d)


func _maybe_propose(r: Dictionary, i: String, s: String, valence: int) -> void:
	var th := threshold(r)
	if th >= 99:
		return
	var key := i + "|" + s
	var cnt := int(r["obs"][key])
	if cnt == th - 1 and not r["hinted"].has(key):
		r["hinted"][key] = true
		Sim.log_key("doctrine_hint", {"name": r["name"], "int": INTERVENTIONS[i]})
	if cnt < th:
		return
	r["obs"][key] = 0
	r["hinted"].erase(key)
	_teach(r, i, s, _choose_meaning(r, s, valence))


## 夢で直接教わる（CONCEPT.md 6.5）。boost ぶん数えを進める
func dream_teach(r: Dictionary, i: String, s: String, m: String, boost: int = 2) -> void:
	var th := threshold(r)
	if th >= 99:
		return
	var key := i + "|" + s
	r["obs"][key] = int(r["obs"].get(key, 0)) + boost
	if int(r["obs"][key]) >= th:
		r["obs"][key] = 0
		r["hinted"].erase(key)
		_teach(r, i, s, m)


func _choose_meaning(r: Dictionary, s: String, valence: int) -> String:
	var pair: Array = MEANING_BY_SITUATION[s]
	var traits: Array = r["traits"]
	var good := valence > 0
	if valence == 0:
		good = traits.has("信心深い") or traits.has("狂信的") or traits.has("無邪気")
	if traits.has("無邪気"):
		good = true  # ミミはなんでも良いほうに取る
	var m: String = pair[0] if good else pair[1]
	if not good and traits.has("狂信的") and m != "wrath":
		m = "wrath" if s in ["quarrel", "death", "prayer"] else m  # カズは大げさに
	return m


## 住民 r が (i, s, m) の教義を唱える／信じる
func _teach(r: Dictionary, i: String, s: String, m: String) -> void:
	var same: Array = active().filter(func(d): return d["intervention"] == i and d["situation"] == s)
	for d in same:
		if d["meaning"] == m:
			if not d["believers"].has(r["id"]):
				adopt(d, r)
			return
	if not same.is_empty():
		# 同じ現象に別の意味 → 分派。すでに別説を信じているなら黙っている
		for d in same:
			if d["believers"].has(r["id"]):
				return
		_create(r, i, s, m, same[0])
	else:
		_create(r, i, s, m, {})


func _create(r: Dictionary, i: String, s: String, m: String, rival: Dictionary) -> void:
	if active().size() >= MAX_ACTIVE:
		# いちばん信者の少ない、定着していない教義が忘れられる
		var weakest: Dictionary = {}
		for d in active():
			if not d["established"] and (weakest.is_empty() or d["believers"].size() < weakest["believers"].size()):
				weakest = d
		if weakest.is_empty():
			return
		_forget(weakest)
	var deniers: Array = []
	for o in Sim.alive():
		if o["traits"].has("懐疑派") and o != r:
			deniers.append(o["id"])
	var d := {
		"id": next_id, "intervention": i, "situation": s, "meaning": m,
		"founder": r["id"], "founder_name": r["name"], "believers": [r["id"]], "deniers": deniers,
		"born_day": Sim.day, "status": "active", "established": false,
		"rival": rival.get("id", -1), "contradictions": 0,
	}
	next_id += 1
	doctrines.append(d)
	if rival.is_empty():
		Sim.log_key("doctrine_new", {"name": r["name"], "text": text(d)}, 2)
	else:
		rival["rival"] = d["id"]
		Sim.log_key("doctrine_rival", {"name": r["name"], "old": text(rival), "text": text(d)}, 3)
	if not Sim.is_silent():
		doctrine_event.emit("rival" if not rival.is_empty() else "new", d)
	Sim.bubble_for(r, "!")
	_check_established(d)


func adopt(d: Dictionary, r: Dictionary) -> void:
	if d["believers"].has(r["id"]) or r["traits"].has("懐疑派"):
		return
	# 分派の相手側を信じていたら乗り換える
	var rival := find(int(d["rival"]))
	if not rival.is_empty() and rival["believers"].has(r["id"]):
		rival["believers"].erase(r["id"])
		if rival["believers"].is_empty():
			_forget(rival)
	d["believers"].append(r["id"])
	d["deniers"].erase(r["id"])
	Sim.log_key("doctrine_adopt", {"name": r["name"], "text": text(d)})
	_check_established(d)


func drop(d: Dictionary, r: Dictionary) -> void:
	if not d["believers"].has(r["id"]):
		return
	d["believers"].erase(r["id"])
	Sim.log_key("doctrine_doubt", {"name": r["name"], "text": text(d)})
	if d["believers"].is_empty():
		_forget(d)
	elif d["established"] and d["believers"].size() * 2 < Sim.alive().size():
		d["established"] = false


func _check_established(d: Dictionary) -> void:
	if d["established"] or d["status"] != "active":
		return
	# 唱えられた翌日以降、信じる者が半分を超えたら町の教えになる
	if Sim.day <= int(d["born_day"]):
		return
	if d["believers"].size() * 2 >= Sim.alive().size() and d["believers"].size() >= 2:
		d["established"] = true
		if d.get("ritual", false):
			return  # 一度定着して揺らぎ、また戻ってきた
		d["ritual"] = true
		Sim.log_key("doctrine_established", {"text": text(d)}, 3)
		Sim.log_key("ritual_" + str(d["meaning"]), {"int": INTERVENTIONS[d["intervention"]]}, 2)
		if not Sim.is_silent():
			doctrine_event.emit("established", d)


func _forget(d: Dictionary) -> void:
	d["status"] = "forgotten"
	d["established"] = false
	d["believers"] = []
	Sim.log_key("doctrine_forgotten", {"text": text(d)}, 2)


## 矛盾が続いて揺らぐ。唱えた本人はなかなか折れない
func _shake(d: Dictionary) -> void:
	for id in d["believers"].duplicate():
		var r := Sim.find_resident(id)
		if r.is_empty():
			continue
		var p := 0.1 if id == d["founder"] else 0.35
		if r["traits"].has("狂信的"):
			p = 0.0
		if _rng.randf() < p:
			drop(d, r)
			if d["status"] != "active":
				return


## 教えを信じる住民は、ちょっかいを教えどおりに受け取る
func _react(intervention: String, _valence: int) -> void:
	var reacted: Array = []  # 1人1回（定着した教えを優先）
	var docs := active().filter(func(d): return d["intervention"] == intervention)
	docs.sort_custom(func(a, b): return a["established"] and not b["established"])
	for d in docs:
		var names: Array = []
		for id in d["believers"]:
			var r := Sim.find_resident(id)
			if r.is_empty() or r["state"] == "sleeping" or r["state"] == "dead" or reacted.has(id):
				continue
			reacted.append(id)
			Sim.bubble_for(r, MEANINGS[d["meaning"]])  # 町の上に「試練」「恵み」…と出す
			var v: int = VALENCE[d["meaning"]]
			Sim.add_stat(r, "mood", 6.0 * v)
			Sim.add_stat(r, "faith", 2.0)
			names.append(r["name"])
		if not names.is_empty():
			Sim.log_key("doctrine_react", {"names": "と".join(names), "int": INTERVENTIONS[intervention], "meaning": MEANINGS[d["meaning"]]})


## 住民がこのちょっかいをどう受け取るか（信じている教義の意味の良し悪し）。なければ NONE
func interpret(r: Dictionary, intervention: String) -> int:
	var best := NONE
	for d in believed_by(r):
		if d["intervention"] == intervention:
			best = VALENCE[d["meaning"]]
			if d["established"]:
				break
	return best


# ------------------------------------------------------------
# 広まる・忘れられる（毎ティック）
# ------------------------------------------------------------

func spread_tick(awake: Array, hour: int) -> void:
	for d in active():
		var believers_here: Array = []
		for r in awake:
			if d["believers"].has(r["id"]):
				believers_here.append(r["pos"])
		if believers_here.is_empty():
			continue
		for r in awake:
			if d["believers"].has(r["id"]) or r["traits"].has("懐疑派") or not believers_here.has(r["pos"]):
				continue
			var p := 0.004
			if r["faith"] > 30:
				p += 0.006
			if hour >= 17 and hour < 21 and r["pos"] == Sim.PLACES["plaza"]:
				p += 0.012  # 集会で広まる
			if _rng.randf() < p:
				adopt(d, r)
	for d in active():
		_check_established(d)
	# 信仰を失った者は教えも手放していく
	for r in awake:
		if r["faith"] < -40:
			for d in believed_by(r):
				if _rng.randf() < 0.03:
					drop(d, r)


## カズの布教：自分の信じる教えを広める
func preach(src: Dictionary, targets: Array) -> void:
	for d in believed_by(src):
		for r in targets:
			if _rng.randf() < 0.15:
				adopt(d, r)


## ノブの反論：聞いた者が教えを1つ疑う
func refute(src: Dictionary, targets: Array) -> void:
	for r in targets:
		var mine := believed_by(r)
		if mine.is_empty() or _rng.randf() >= 0.25:
			continue
		var d: Dictionary = mine[_rng.randi() % mine.size()]
		if not d["deniers"].has(src["id"]):
			d["deniers"].append(src["id"])
		drop(d, r)


func on_death(r: Dictionary) -> void:
	for d in active():
		d["deniers"].erase(r["id"])
		if d["believers"].has(r["id"]):
			d["believers"].erase(r["id"])
			if d["believers"].is_empty():
				_forget(d)


# ------------------------------------------------------------
# セーブ用
# ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"doctrines": doctrines, "next_id": next_id, "recent": recent}


func from_dict(d: Dictionary) -> void:
	doctrines = []
	for x in d.get("doctrines", []):
		var doc: Dictionary = x
		for k in ["id", "born_day", "rival", "contradictions"]:
			doc[k] = int(doc[k])
		doctrines.append(doc)
	next_id = int(d.get("next_id", 1))
	recent = d.get("recent", [])
