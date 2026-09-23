extends Node
## 音の再生。BGM（昼／夜を時刻でクロスフェード）、雨の環境音、効果音。
## 素材は tools/gen_audio.py が生成した仮の音。assets/audio/ の同名ファイルを差し替えれば本番の音になる。

const DIR := "res://assets/audio/"
const SETTINGS_PATH := "user://settings.cfg"
const BGM_DB := -10.0
const AMB_DB := -8.0
const SFX_DB := -4.0
const FADE := 2.5

## Sim の吹き出し → 効果音
const BUBBLE_SFX := {
	"ぽわ": "heal", "!!": "scare", "!?": "revelation", "×": "disaster",
	"答えだ!": "yes", "…": "dream",
}

var muted := false

var _bgm: Array = []            # [AudioStreamPlayer, AudioStreamPlayer]（クロスフェード用）
var _bgm_cur := 0
var _bgm_name := ""
var _amb: AudioStreamPlayer
var _sfx: Array = []
var _sfx_i := 0
var _cache: Dictionary = {}
var _check := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		p.finished.connect(p.play)  # ループ情報が読めなかったときの保険
		add_child(p)
		_bgm.append(p)
	_amb = AudioStreamPlayer.new()
	_amb.volume_db = -80.0
	_amb.finished.connect(_amb.play)
	add_child(_amb)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = SFX_DB
		add_child(p)
		_sfx.append(p)
	Sim.resident_bubble.connect(func(_id, text): play_for_bubble(text))
	Sim.prayer_started.connect(func(_id): play("bell"))
	Doctrine.doctrine_event.connect(func(_k, _d): play("doctrine"))
	Sim.woke_up.connect(func(_a, _b, _e): play("wake"))
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		muted = bool(cfg.get_value("audio", "muted", false))
	_apply_mute()


func _stream(name: String) -> AudioStream:
	if not _cache.has(name):
		var path := DIR + name + ".wav"
		_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return _cache[name]


func play(name: String, pitch_jitter: float = 0.0) -> void:
	var s := _stream("sfx_" + name)
	if s == null:
		return
	var p: AudioStreamPlayer = _sfx[_sfx_i]
	_sfx_i = (_sfx_i + 1) % _sfx.size()
	p.stream = s
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play_for_bubble(text: String) -> void:
	if BUBBLE_SFX.has(text):
		play(BUBBLE_SFX[text], 0.05)


func toggle_mute() -> void:
	muted = not muted
	_apply_mute()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "muted", muted)
	cfg.save(SETTINGS_PATH)


func _apply_mute() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if not Sim.running:
		return
	# 時間帯でBGMを切り替え、雨なら環境音を重ねる
	var h := GameClock.hour(GameClock.now())
	_set_bgm("bgm_night" if h >= 19 or h < 6 else "bgm_day")
	_set_rain(Sim.weather == "rain")


func _set_bgm(name: String) -> void:
	if name == _bgm_name:
		return
	_bgm_name = name
	var old: AudioStreamPlayer = _bgm[_bgm_cur]
	_bgm_cur = 1 - _bgm_cur
	var cur: AudioStreamPlayer = _bgm[_bgm_cur]
	cur.stream = _stream(name)
	if cur.stream == null:
		return
	cur.volume_db = -40.0
	cur.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(cur, "volume_db", BGM_DB, FADE)
	if old.playing:
		tw.tween_property(old, "volume_db", -60.0, FADE)
		tw.chain().tween_callback(old.stop)


func _set_rain(on: bool) -> void:
	if on == _amb.playing:
		return
	if on:
		_amb.stream = _stream("amb_rain")
		if _amb.stream == null:
			return
		_amb.volume_db = -40.0
		_amb.play()
		create_tween().tween_property(_amb, "volume_db", AMB_DB, FADE)
	else:
		var tw := create_tween()
		tw.tween_property(_amb, "volume_db", -60.0, FADE)
		tw.tween_callback(_amb.stop)
