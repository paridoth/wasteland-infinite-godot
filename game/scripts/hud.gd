extends CanvasLayer
## Message log, HP / action-point bar, end-turn button and cursor tooltip.

const LOG_LINES := 7

var main: Node3D  # main.gd; untyped to avoid a preload cycle.
var log_label := Label.new()
var hp_label := Label.new()
var status := Label.new()
var pips := HBoxContainer.new()
var end_turn := Button.new()
var tooltip := Label.new()
var banner := Label.new()
var lines: Array[String] = []


func _ready() -> void:
	var log_panel := PanelContainer.new()
	log_panel.position = Vector2(16, 16)
	log_panel.custom_minimum_size = Vector2(460, 0)
	log_panel.add_theme_stylebox_override("panel", _box())
	log_label.add_theme_font_size_override("font_size", 15)
	log_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	log_panel.add_child(log_label)
	add_child(log_panel)

	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _box())
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -300
	bar.offset_right = 300
	bar.offset_top = -64
	bar.offset_bottom = -16
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 20)
	row.add_child(hp_label)
	pips.add_theme_constant_override("separation", 4)
	row.add_child(pips)
	status.add_theme_font_size_override("font_size", 18)
	row.add_child(status)
	end_turn.text = "End turn [Space]"
	end_turn.focus_mode = Control.FOCUS_NONE
	end_turn.pressed.connect(func() -> void: main.combat.end_player_turn())
	row.add_child(end_turn)
	bar.add_child(row)
	add_child(bar)

	tooltip.add_theme_font_size_override("font_size", 16)
	tooltip.add_theme_constant_override("outline_size", 6)
	tooltip.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(tooltip)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.add_theme_font_size_override("font_size", 40)
	banner.add_theme_color_override("font_color", Color(1, 0.3, 0.2))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(banner)
	refresh()


func log_line(text: String) -> void:
	lines.append(text)
	if lines.size() > LOG_LINES:
		lines.pop_front()
	log_label.text = "\n".join(lines)


func show_tooltip(text: String, at: Vector2) -> void:
	tooltip.text = text
	tooltip.position = at + Vector2(18, 12)


func refresh() -> void:
	var player = main.player
	var combat = main.combat
	hp_label.text = "HP %d/%d" % [player.hp, player.max_hp]
	for pip in pips.get_children():
		pip.queue_free()
	for i in player.max_ap:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 14)
		var lit: bool = combat.active and i < player.ap
		pip.color = Color(0.3, 1, 0.3) if lit else Color(0.15, 0.25, 0.15)
		pips.add_child(pip)
	status.text = "YOUR TURN" if combat.player_turn else ("ENEMY TURN" if combat.active else "")
	status.add_theme_color_override("font_color", Color(1, 0.35, 0.25) if combat.active else Color.WHITE)
	end_turn.disabled = not combat.player_turn
	banner.text = "" if player.alive() else "You have died.\nPress R to restart."


func _box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.05, 0.8)
	box.border_color = Color(0.3, 0.45, 0.3)
	box.set_border_width_all(1)
	box.set_content_margin_all(10)
	return box
