extends Node
## ゲーム内の時計。現実の時刻とはつながっていない（CONCEPT.md 8章の見直し）。
## 時間はカミサマが「眠る」ときだけ進む（Sim.sleep）。time は UNIX 秒の形で持つ（日付表示のため）。

var time: int = 0


func now() -> int:
	return time


func advance(seconds: int) -> void:
	time += seconds


## 新しい町：今日の日付の hour 時から始める
func start_today(hour: float) -> void:
	var bias := _bias()
	var real := int(Time.get_unix_time_from_system())
	var local_midnight := (real + bias) - (real + bias) % 86400
	time = local_midnight - bias + int(hour * 3600.0)


## UNIX秒 → ローカル時刻の辞書（year, month, day, hour, minute, second）
func local(unix: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(unix + _bias())


func hour(unix: int) -> int:
	return int(local(unix)["hour"])


## 次に「hour 時（小数可）」になるまでの秒数。ちょうどその時刻なら翌日
func seconds_until(hour_f: float) -> int:
	var d := local(time)
	var cur: int = int(d["hour"]) * 3600 + int(d["minute"]) * 60 + int(d["second"])
	var diff := int(hour_f * 3600.0) - cur
	if diff <= 0:
		diff += 86400
	return diff


func format_hm(unix: int) -> String:
	var d := local(unix)
	return "%02d:%02d" % [d["hour"], d["minute"]]


func format_mdhm(unix: int) -> String:
	var d := local(unix)
	return "%d/%d %02d:%02d" % [d["month"], d["day"], d["hour"], d["minute"]]


func _bias() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
