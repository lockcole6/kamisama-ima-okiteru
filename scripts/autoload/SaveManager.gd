extends Node
## セーブ／ロード。user://save.json に町の状態全体とログを保存する。

const PATH := "user://save.json"
const VERSION := 4  # 2: 祈り / 3: 教義・夢・風 / 4: 時間帯制（現実時間から切り離し）


func save_game() -> void:
	Sim.last_seen = GameClock.now()
	var data := {
		"version": VERSION,
		"clock_time": GameClock.time,
		"sim": Sim.to_dict(),
		"doctrine": Doctrine.to_dict(),
		"logs": LogManager.entries,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("セーブに失敗: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(data))


func load_game() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		return false
	# 形式が変わったらここで移行処理を書く。今は非対応バージョンなら新規扱い
	if int(data.get("version", 0)) != VERSION:
		return false
	GameClock.time = int(data.get("clock_time", 0))
	Sim.from_dict(data["sim"])
	Doctrine.from_dict(data.get("doctrine", {}))
	LogManager.entries = data.get("logs", [])
	return true


func delete_save() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED:
			if Sim.running:
				save_game()
