## 主菜单界面
extends Control

const SETTINGS_FILE_NAME := "game_settings.cfg"

var _title_label: Label = null
var _subtitle_label: Label = null
var _menu_container: VBoxContainer = null
var _single_player_btn: Button = null
var _multiplayer_btn: Button = null
var _replay_btn: Button = null
var _settings_btn: Button = null
var _quit_btn: Button = null
var _replay_panel: PanelContainer = null
var _replay_list: VBoxContainer = null
var _game_setup_panel: PanelContainer = null
var _selected_fog_mode: int = GameConstants.FogMode.NONE
var _selected_game_speed_index: int = 4
var _selected_starting_minerals: int = GameConstants.STARTING_MINERALS
var _selected_starting_energy: int = GameConstants.STARTING_ENERGY
var _game_setup_language_option: OptionButton = null

const _FOG_OPTION_KEYS := [
	"settings.fog_none",
	"settings.fog_full_black",
	"settings.fog_terrain_only",
	"settings.fog_explored_visible",
]

const _FOG_OPTION_VALUES := [
	GameConstants.FogMode.NONE,
	GameConstants.FogMode.FULL_BLACK,
	GameConstants.FogMode.TERRAIN_ONLY,
	GameConstants.FogMode.EXPLORED_VISIBLE,
]

func _ready() -> void:
	_load_settings()
	LocalizationManager.language_changed.connect(_on_language_changed)
	# 全屏背景
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# 星空粒子装饰背景
	var stars_bg := StarField.new()
	stars_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stars_bg)
	
	# 居中容器
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(500, 0)
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
	
	# 标题
	_title_label = Label.new()
	_title_label.text = "FIRST RTS"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 64)
	_title_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	vbox.add_child(_title_label)
	
	# 副标题
	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	vbox.add_child(_subtitle_label)
	
	# 间距
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(spacer)
	
	# 菜单容器
	_menu_container = VBoxContainer.new()
	_menu_container.add_theme_constant_override("separation", 12)
	_menu_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_menu_container)
	
	_single_player_btn = _add_menu_button("", _on_single_player)
	_multiplayer_btn = _add_menu_button("", _on_multiplayer)
	_replay_btn = _add_menu_button("", _on_replay)
	_settings_btn = _add_menu_button("", _on_settings)
	_quit_btn = _add_menu_button("", _on_quit)
	
	# 版本号
	var version := Label.new()
	version.text = "v0.1.0 Alpha"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	vbox.add_child(version)
	
	# 标题动画
	_title_label.modulate.a = 0
	var tween := create_tween()
	tween.tween_property(_title_label, "modulate:a", 1.0, 1.0)
	_refresh_localized_texts()

func _on_language_changed(_lang_code: String) -> void:
	_refresh_localized_texts()
	if _game_setup_panel and is_instance_valid(_game_setup_panel):
		_build_game_setup_panel()
	if _replay_panel and is_instance_valid(_replay_panel):
		_build_replay_panel()

func _refresh_localized_texts() -> void:
	if _subtitle_label:
		_subtitle_label.text = LocalizationManager.t("menu.subtitle")
	if _single_player_btn:
		_single_player_btn.text = LocalizationManager.t("menu.single_player")
	if _multiplayer_btn:
		_multiplayer_btn.text = LocalizationManager.t("menu.multiplayer")
	if _replay_btn:
		_replay_btn.text = LocalizationManager.t("menu.replay")
	if _settings_btn:
		_settings_btn.text = LocalizationManager.t("menu.settings")
	if _quit_btn:
		_quit_btn.text = LocalizationManager.t("menu.quit")

func _get_game_speed_texts() -> Array[String]:
	return ["0.5x", "1.0x", "1.5x", "2.0x", LocalizationManager.t("settings.speed_unlimited")]

func _add_menu_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320, 50)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	# 样式
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.18, 0.3)
	normal_style.border_color = Color(0.3, 0.5, 0.8)
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(6)
	normal_style.set_content_margin_all(12)
	btn.add_theme_stylebox_override("normal", normal_style)
	
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.18, 0.28, 0.45)
	hover_style.border_color = Color(0.4, 0.7, 1.0)
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(6)
	hover_style.set_content_margin_all(12)
	btn.add_theme_stylebox_override("hover", hover_style)
	
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.1, 0.15, 0.25)
	pressed_style.border_color = Color(0.2, 0.4, 0.7)
	pressed_style.set_border_width_all(2)
	pressed_style.set_corner_radius_all(6)
	pressed_style.set_content_margin_all(12)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	
	btn.pressed.connect(func():
		AudioManager.play_ui_click()
		callback.call()
	)
	_menu_container.add_child(btn)
	return btn

## ====== 回调 ======

func _on_single_player() -> void:
	_build_game_setup_panel()

## 游戏设置面板（迷雾模式等开局选项）
func _build_game_setup_panel() -> void:
	if _game_setup_panel and is_instance_valid(_game_setup_panel):
		_game_setup_panel.queue_free()
	
	_game_setup_panel = PanelContainer.new()
	_game_setup_panel.set_anchors_preset(Control.PRESET_CENTER)
	_game_setup_panel.offset_left = -240
	_game_setup_panel.offset_right = 240
	_game_setup_panel.offset_top = -480
	_game_setup_panel.offset_bottom = -70
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.16, 0.97)
	style.border_color = Color(0.3, 0.5, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	_game_setup_panel.add_theme_stylebox_override("panel", style)
	add_child(_game_setup_panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_game_setup_panel.add_child(vbox)
	
	# 标题
	var title := Label.new()
	title.text = LocalizationManager.t("settings.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	vbox.add_child(title)
	
	var sep := HSeparator.new()
	vbox.add_child(sep)
	
	# 战争迷雾标签
	var fog_label := Label.new()
	fog_label.text = LocalizationManager.t("settings.fog_of_war")
	fog_label.add_theme_font_size_override("font_size", 16)
	fog_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(fog_label)
	
	# 四个迷雾模式按钮（单选组）
	var fog_btns: Array[Button] = []
	for i in range(_FOG_OPTION_KEYS.size()):
		var btn := Button.new()
		btn.text = LocalizationManager.t(_FOG_OPTION_KEYS[i])
		btn.toggle_mode = true
		btn.button_pressed = (_FOG_OPTION_VALUES[i] == _selected_fog_mode)
		btn.add_theme_font_size_override("font_size", 15)
		btn.custom_minimum_size = Vector2(0, 38)
		var fog_val: int = _FOG_OPTION_VALUES[i]
		btn.pressed.connect(func():
			_selected_fog_mode = fog_val
			for b in fog_btns:
				b.button_pressed = false
			btn.button_pressed = true
		)
		vbox.add_child(btn)
		fog_btns.append(btn)

	var speed_sep := HSeparator.new()
	vbox.add_child(speed_sep)

	var speed_label := Label.new()
	speed_label.text = LocalizationManager.t("settings.game_speed")
	speed_label.add_theme_font_size_override("font_size", 16)
	speed_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(speed_label)

	var speed_texts := _get_game_speed_texts()
	var speed_btns: Array[Button] = []
	for i in range(speed_texts.size()):
		var speed_btn := Button.new()
		speed_btn.text = speed_texts[i]
		speed_btn.toggle_mode = true
		speed_btn.button_pressed = (i == _selected_game_speed_index)
		speed_btn.add_theme_font_size_override("font_size", 15)
		speed_btn.custom_minimum_size = Vector2(0, 38)
		var speed_idx := i
		speed_btn.pressed.connect(func():
			_selected_game_speed_index = speed_idx
			for b in speed_btns:
				b.button_pressed = false
			speed_btn.button_pressed = true
		)
		vbox.add_child(speed_btn)
		speed_btns.append(speed_btn)

	var res_sep := HSeparator.new()
	vbox.add_child(res_sep)

	var lang_label := Label.new()
	lang_label.text = LocalizationManager.t("settings.language")
	lang_label.add_theme_font_size_override("font_size", 16)
	lang_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(lang_label)

	_game_setup_language_option = OptionButton.new()
	_game_setup_language_option.custom_minimum_size = Vector2(0, 38)
	_game_setup_language_option.add_theme_font_size_override("font_size", 15)
	for name in LocalizationManager.get_language_names():
		_game_setup_language_option.add_item(name)
	var current_lang_index := LocalizationManager.get_current_lang_index()
	if current_lang_index >= 0:
		_game_setup_language_option.select(current_lang_index)
	_game_setup_language_option.item_selected.connect(func(index: int):
		LocalizationManager.set_language_by_index(index)
	)
	vbox.add_child(_game_setup_language_option)

	var lang_sep := HSeparator.new()
	vbox.add_child(lang_sep)

	var starting_res_label := Label.new()
	starting_res_label.text = LocalizationManager.t("settings.starting_resources")
	starting_res_label.add_theme_font_size_override("font_size", 16)
	starting_res_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(starting_res_label)

	var mineral_row := HBoxContainer.new()
	mineral_row.add_theme_constant_override("separation", 8)
	vbox.add_child(mineral_row)
	var mineral_label := Label.new()
	mineral_label.text = LocalizationManager.t("settings.starting_minerals")
	mineral_label.custom_minimum_size = Vector2(120, 0)
	mineral_row.add_child(mineral_label)
	var mineral_spin := SpinBox.new()
	mineral_spin.min_value = 0
	mineral_spin.max_value = 99999
	mineral_spin.step = 50
	mineral_spin.value = _selected_starting_minerals
	mineral_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mineral_spin.value_changed.connect(func(v: float): _selected_starting_minerals = int(v))
	mineral_row.add_child(mineral_spin)

	var energy_row := HBoxContainer.new()
	energy_row.add_theme_constant_override("separation", 8)
	vbox.add_child(energy_row)
	var energy_label := Label.new()
	energy_label.text = LocalizationManager.t("settings.starting_energy")
	energy_label.custom_minimum_size = Vector2(120, 0)
	energy_row.add_child(energy_label)
	var energy_spin := SpinBox.new()
	energy_spin.min_value = 0
	energy_spin.max_value = 99999
	energy_spin.step = 50
	energy_spin.value = _selected_starting_energy
	energy_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	energy_spin.value_changed.connect(func(v: float): _selected_starting_energy = int(v))
	energy_row.add_child(energy_spin)
	
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)
	
	# 底部按钮行
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	
	var cancel_btn := Button.new()
	cancel_btn.text = LocalizationManager.t("settings.cancel")
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.pressed.connect(func(): _game_setup_panel.queue_free(); _game_setup_panel = null)
	btn_row.add_child(cancel_btn)
	
	var start_btn := Button.new()
	start_btn.text = LocalizationManager.t("settings.start_game")
	start_btn.custom_minimum_size = Vector2(130, 40)
	start_btn.add_theme_font_size_override("font_size", 16)
	var start_style := StyleBoxFlat.new()
	start_style.bg_color = Color(0.15, 0.35, 0.65)
	start_style.border_color = Color(0.3, 0.6, 1.0)
	start_style.set_border_width_all(2)
	start_style.set_corner_radius_all(6)
	start_style.set_content_margin_all(10)
	start_btn.add_theme_stylebox_override("normal", start_style)
	start_btn.pressed.connect(_on_start_single_player)
	btn_row.add_child(start_btn)

func _on_start_single_player() -> void:
	_save_settings()
	GameManager.fog_mode = _selected_fog_mode
	GameManager.starting_minerals = _selected_starting_minerals
	GameManager.starting_energy = _selected_starting_energy
	NetworkManager.set_game_speed_index(_selected_game_speed_index)
	get_tree().change_scene_to_file("res://scenes/game/GameWorld.tscn")

func _on_multiplayer() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby/Lobby.tscn")

func _on_settings() -> void:
	_build_game_setup_panel()

func _on_quit() -> void:
	get_tree().quit()

## ====== 设置持久化 ======

func _get_settings_path() -> String:
	return OS.get_user_data_dir().path_join(SETTINGS_FILE_NAME)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	var settings_path := _get_settings_path()
	cfg.load(settings_path)  # 先加载已有内容, 避免覆盖 Lobby 的设置
	cfg.set_value("game", "fog_mode", _selected_fog_mode)
	cfg.set_value("game", "game_speed_index", _selected_game_speed_index)
	cfg.set_value("game", "starting_minerals", _selected_starting_minerals)
	cfg.set_value("game", "starting_energy", _selected_starting_energy)
	cfg.save(settings_path)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_get_settings_path()) != OK:
		return
	_selected_fog_mode = cfg.get_value("game", "fog_mode", _selected_fog_mode)
	_selected_game_speed_index = cfg.get_value("game", "game_speed_index", _selected_game_speed_index)
	_selected_starting_minerals = cfg.get_value("game", "starting_minerals", _selected_starting_minerals)
	_selected_starting_energy = cfg.get_value("game", "starting_energy", _selected_starting_energy)

func _on_replay() -> void:
	if _replay_panel:
		_replay_panel.queue_free()
		_replay_panel = null
	_build_replay_panel()
	_replay_panel.visible = true

func _build_replay_panel() -> void:
	if _replay_panel and is_instance_valid(_replay_panel):
		_replay_panel.queue_free()
		_replay_panel = null

	_replay_panel = PanelContainer.new()
	_replay_panel.name = "ReplayPanel"
	_replay_panel.set_anchors_preset(Control.PRESET_CENTER)
	_replay_panel.offset_left = -280
	_replay_panel.offset_right = 280
	_replay_panel.offset_top = -220
	_replay_panel.offset_bottom = 220
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	style.border_color = Color(0.3, 0.5, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(16)
	_replay_panel.add_theme_stylebox_override("panel", style)
	add_child(_replay_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	_replay_panel.add_child(main_vbox)

	# 标题行
	var title_row := HBoxContainer.new()
	main_vbox.add_child(title_row)
	var title := Label.new()
	title.text = LocalizationManager.t("replay.title")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(func(): _replay_panel.queue_free(); _replay_panel = null)
	title_row.add_child(close_btn)

	# 滚动容器
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	main_vbox.add_child(scroll)

	_replay_list = VBoxContainer.new()
	_replay_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_replay_list)

	# 底部按钮行
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 12)
	bottom_row.alignment = BoxContainer.ALIGNMENT_END
	main_vbox.add_child(bottom_row)

	var delete_all_btn := Button.new()
	delete_all_btn.text = LocalizationManager.t("replay.delete_all")
	delete_all_btn.custom_minimum_size = Vector2(120, 32)
	delete_all_btn.add_theme_font_size_override("font_size", 13)
	var del_style := StyleBoxFlat.new()
	del_style.bg_color = Color(0.4, 0.12, 0.12)
	del_style.border_color = Color(0.7, 0.25, 0.25)
	del_style.set_border_width_all(1)
	del_style.set_corner_radius_all(4)
	del_style.set_content_margin_all(4)
	delete_all_btn.add_theme_stylebox_override("normal", del_style)
	var del_hover := StyleBoxFlat.new()
	del_hover.bg_color = Color(0.55, 0.15, 0.15)
	del_hover.border_color = Color(0.9, 0.3, 0.3)
	del_hover.set_border_width_all(1)
	del_hover.set_corner_radius_all(4)
	del_hover.set_content_margin_all(4)
	delete_all_btn.add_theme_stylebox_override("hover", del_hover)
	delete_all_btn.add_theme_color_override("font_color", Color(1, 0.8, 0.8))
	delete_all_btn.pressed.connect(_on_delete_all_replays)
	bottom_row.add_child(delete_all_btn)

	# 加载录像列表
	_refresh_replay_list()

func _refresh_replay_list() -> void:
	if not _replay_list:
		return
	for child in _replay_list.get_children():
		child.queue_free()

	var replays := ReplaySystem.list_replays()
	if replays.is_empty():
		var empty_label := Label.new()
		empty_label.text = LocalizationManager.t("replay.no_files")
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_replay_list.add_child(empty_label)
		return

	for replay_info in replays:
		var row := _create_replay_row(replay_info)
		_replay_list.add_child(row)

func _create_replay_row(info: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var filename: String = info.get("filename", "")
	var filepath: String = info.get("filepath", "")
	var date_str: String = info.get("date", "")
	var ticks: int = info.get("duration_ticks", 0)
	var duration := ticks * 0.05
	var mins := int(duration) / 60
	var secs := int(duration) % 60

	var label := Label.new()
	if date_str != "":
		label.text = "%s  (%02d:%02d)" % [date_str, mins, secs]
	else:
		label.text = filename
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	# 播放按钮
	var play_btn := Button.new()
	play_btn.text = LocalizationManager.t("replay.play")
	play_btn.custom_minimum_size = Vector2(70, 30)
	play_btn.add_theme_font_size_override("font_size", 13)
	play_btn.pressed.connect(_on_play_replay.bind(filepath))
	row.add_child(play_btn)

	# 删除按钮
	var del_btn := Button.new()
	del_btn.text = "🗑"
	del_btn.custom_minimum_size = Vector2(30, 30)
	del_btn.add_theme_font_size_override("font_size", 13)
	del_btn.pressed.connect(_on_delete_replay.bind(filepath))
	row.add_child(del_btn)

	return row

func _on_play_replay(filepath: String) -> void:
	ReplaySystem.start_replay(filepath)

func _on_delete_replay(filepath: String) -> void:
	ReplaySystem.delete_replay(filepath)
	_refresh_replay_list()

func _on_delete_all_replays() -> void:
	ReplaySystem.delete_all_replays()
	_refresh_replay_list()


## ====== 星空背景 ======
class StarField extends Control:
	var _stars: Array = []
	
	func _ready() -> void:
		for i in range(120):
			_stars.append({
				"pos": Vector2(randf(), randf()),
				"size": randf_range(0.5, 2.0),
				"speed": randf_range(0.001, 0.005),
				"brightness": randf_range(0.3, 1.0),
				"twinkle_speed": randf_range(1.0, 4.0),
			})
	
	func _process(_delta: float) -> void:
		queue_redraw()
	
	func _draw() -> void:
		var viewport_size := get_viewport_rect().size
		var time := Time.get_ticks_msec() * 0.001
		for s in _stars:
			var pos := Vector2(s["pos"].x * viewport_size.x, s["pos"].y * viewport_size.y)
			var twinkle: float = (sin(time * s["twinkle_speed"]) + 1.0) / 2.0
			var alpha: float = s["brightness"] * (0.5 + twinkle * 0.5)
			var c := Color(0.7, 0.8, 1.0, alpha)
			draw_circle(pos, s["size"], c)
