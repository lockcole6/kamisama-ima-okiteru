extends Node
## 現実時刻の取得と、デバッグ用の時間操作（加速・時刻ずらし）。
## ゲーム内時刻 = 端末の現実時刻 + offset。

signal speed_changed(speed: float)

var offset: float = 0.0  # デバッグ用の時刻ずらし（秒）。セーブに含める
var speed: float = 1.0   # デバッグ用の時間加速倍率


func _process(delta: float) -> void:
	if speed != 1.0:
		offset += delta * (speed - 1.0)


## ゲーム内の現在時刻（UNIX秒）
func now() -> int:
	return int(Time.get_unix_time_from_system() + offset)


## UNIX秒 → 端末のローカル時刻の辞書（year, month, day, hour, minute, second）
func local(unix: int) -> Dictionary:
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_dict_from_unix_time(unix + bias * 60)


func hour(unix: int) -> int:
	return int(local(unix)["hour"])


func set_speed(s: float) -> void:
	speed = s
	speed_changed.emit(s)


func advance(seconds: int) -> void:
	offset += seconds


## 次に「h時00分」になるまでの秒数（今がちょうどh時00分以降なら翌日のh時）
func seconds_until_hour(h: int) -> int:
	var d := local(now())
	var cur: int = int(d["hour"]) * 3600 + int(d["minute"]) * 60 + int(d["second"])
	var diff := h * 3600 - cur
	if diff <= 0:
		diff += 86400
	return diff


func format_hm(unix: int) -> String:
	var d := local(unix)
	return "%02d:%02d" % [d["hour"], d["minute"]]


func format_mdhm(unix: int) -> String:
	var d := local(unix)
	return "%d/%d %02d:%02d" % [d["month"], d["day"], d["hour"], d["minute"]]
