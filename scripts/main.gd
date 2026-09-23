extends Control
## ルート。町（ピクセルアートの SubViewport）とUIをつなぎ、タップを振り分ける。

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const ScripturePanel := preload("res://scripts/ui/scripture_panel.gd")
const Guide := preload("res://scripts/ui/guide.gd")

@onready var town_view: SubViewportContainer = $TownView
@onready var town_vp: SubViewport = $TownView/SubViewport
@onready var town: Node2D = $TownView/SubViewport/Town
@onready var hud: Control = $HUD
@onready var log_panel: Control = $LogPanel
@onready var away_report: Control = $AwayReport
var scripture: Control
var guide: Control


func _ready() -> void:
	theme = UITheme.make()
	RenderingServer.set_default_clear_color(Color("2a2140"))
	# 町はピクセルのまま拡大する（UIは高解像度）
	town_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	town_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	town_vp.snap_2d_transforms_to_pixel = true
	town_vp.snap_2d_vertices_to_pixel = true
	scripture = ScripturePanel.new()
	add_child(scripture)
	move_child(scripture, away_report.get_index())
	hud.open_scripture_requested.connect(scripture.open)
	guide = Guide.new()
	add_child(guide)
	move_child(guide, scripture.get_index())
	guide.setup(hud, [log_panel, scripture, away_report])
	away_report.suggestion_chosen.connect(_on_suggestion)
	hud.open_log_requested.connect(log_panel.open)
	hud.selection_changed.connect(town.select)
	Sim.away_report.connect(away_report.show_report)
	Sim.god_woke.connect(town.on_god_woke)
	Sim.boot()
	town.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if log_panel.visible or away_report.visible or scripture.visible or hud.is_popup_open():
		return
	var p: Vector2 = event.position - town_view.position
	if hud.wind_mode:
		if p.y < hud.SHEET_Y:
			var place: String = town.nearest_place(p)
			town.wind_fx(place)
			hud.blow_wind_at(place)
		return
	var hit: Dictionary = town.pick(p)
	match hit.get("type", ""):
		"resident":
			hud.show_resident(hit["id"])
		"grave":
			hud.show_grave(hit["index"])


## 「おかえりなさい」の「見に行く」
func _on_suggestion(kind: String, id: String) -> void:
	if kind in ["prayer", "dream"] and id != "":
		hud.show_resident(id)
