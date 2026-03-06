## HUD - 游戏界面 (资源栏 + 底部面板 + 小地图)
class_name HUD
extends CanvasLayer

## 引用
var _resource_label: Label = null
var _game_time_label: Label = null
var _selection_panel: VBoxContainer = null
var _production_queue_strip: HBoxContainer = null
var _build_menu: GridContainer = null
var _minimap: MinimapSystem = null
var _message_label: Label = null
var _build_placement: BuildPlacementSystem = null
var _last_game_time_sec: int = -1

## 游戏内聊天 (透明浮动消息)
var _chat_container: VBoxContainer = null       # 浮动消息容器
var _chat_input_row: HBoxContainer = null       # 输入行
var _chat_input: LineEdit = null
var _chat_channel_btn: Button = null
var _chat_channel: String = "all"
var _chat_input_active: bool = false
var _chat_history_data: Array = []               # 所有历史消息 [{bbcode, time}]

## ESC菜单
var _esc_menu: PanelContainer = null
var _esc_menu_visible: bool = false
var _esc_title_label: Label = null
var _esc_resume_btn: Button = null
var _esc_pause_btn: Button = null                # ESC菜单内的暂停按钮
var _esc_history_btn: Button = null
var _esc_surrender_btn: Button = null            # ESC菜单内的投降按钮
var _esc_return_btn: Button = null
var _esc_speed_label: Label = null
var _esc_speed_down_btn: Button = null
var _esc_speed_up_btn: Button = null
var _has_surrendered: bool = false

## 投降确认
var _surrender_dialog: PanelContainer = null
var _surrender_title_label: Label = null
var _surrender_desc_label: Label = null
var _surrender_confirm_btn: Button = null
var _surrender_cancel_btn: Button = null

## 聊天历史面板
var _chat_history_panel: PanelContainer = null
var _chat_history_title_label: Label = null
var _chat_history_log: RichTextLabel = null

## 游戏结束覆盖
var _game_end_overlay: Control = null
var _game_end_label: Label = null
var _game_end_return_btn: Button = null

## 暂停系统
var _pause_overlay: Control = null
var _pause_title_label: Label = null
var _pause_info_label: Label = null
var _pause_remaining_label: Label = null
var _pause_resume_btn: Button = null

## 回放控制
var _replay_bar: PanelContainer = null
var _replay_bar_content: HBoxContainer = null
var _replay_bar_toggle_btn: Button = null
var _replay_bar_collapsed: bool = false
var _replay_progress: HSlider = null
var _replay_time_label: Label = null
var _replay_speed_label: Label = null
var _replay_pause_btn: Button = null
var _is_replay_mode: bool = false
var _camera_system: CameraSystem = null

## 回放增强: 玩家统计面板 + 操作日志 + 镜头模式
var _replay_stats_panel: PanelContainer = null
var _replay_stats_labels: Dictionary = {}  # {team_id: Label}
var _replay_stats_content: VBoxContainer = null
var _replay_stats_toggle_btn: Button = null
var _replay_stats_collapsed: bool = false
var _replay_stats_expanded_bottom: float = 300.0
var _replay_action_log_panel: PanelContainer = null
var _replay_action_log: RichTextLabel = null
var _replay_action_log_content: VBoxContainer = null
var _replay_action_log_toggle_btn: Button = null
var _replay_action_log_collapsed: bool = false
var _replay_camera_mode_btn: Button = null
var _replay_follow_btn: Button = null

var _local_team_id: int = 0
var _cached_units: Array = []
var _cached_buildings: Array = []

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_is_replay_mode = ReplaySystem.mode == ReplaySystem.Mode.PLAYING
	_build_ui()
	_build_chat_ui()
	_build_surrender_dialog()
	_build_esc_menu()
	_build_chat_history_panel()
	_build_game_end_overlay()
	_build_pause_ui()
	LocalizationManager.language_changed.connect(_on_language_changed)
	
	if _is_replay_mode:
		_build_replay_controls()
		_build_replay_stats_panel()
		_build_replay_action_log()
		# 回放模式隐藏不需要的UI
		_chat_input_row.visible = false
		_surrender_dialog.visible = false
		# 回放模式顶部显示观战模式提示
		if _resource_label:
			_resource_label.text = LocalizationManager.t("hud.replay_spectate")
	
	# 连接资源变化信号
	if GameManager.resource_system and not _is_replay_mode:
		GameManager.resource_system.resources_changed.connect(_on_resources_changed)
		GameManager.resource_system.insufficient_resources.connect(_on_insufficient_resources)
		_refresh_resource_label()
	
	# 连接网络聊天 & 投降信号
	NetworkManager.game_chat_received.connect(_on_game_chat_received)
	NetworkManager.player_surrendered.connect(_on_player_surrendered)
	GameManager.game_ended.connect(_on_game_ended)
	
	# 连接暂停信号
	NetworkManager.game_pause_requested.connect(_on_pause_requested)
	NetworkManager.game_resume_requested.connect(_on_resume_requested)
	NetworkManager.game_speed_changed.connect(_on_game_speed_changed)
	GameManager.game_paused.connect(_on_game_paused)
	GameManager.game_resumed.connect(_on_game_resumed)
	# 联机断线处理
	if NetworkManager.is_online:
		NetworkManager.disconnected_from_server.connect(_on_server_disconnected_ingame)
	_refresh_localized_static_texts()

func _on_language_changed(_lang_code: String) -> void:
	_refresh_localized_static_texts()
	if _is_replay_mode:
		if _resource_label:
			_resource_label.text = LocalizationManager.t("hud.replay_spectate")
	else:
		_refresh_resource_label()
	_update_game_timer()
	if _cached_units.size() > 0 or _cached_buildings.size() > 0:
		update_selection(_cached_units, _cached_buildings)

func _refresh_localized_static_texts() -> void:
	if _chat_input:
		_chat_input.placeholder_text = LocalizationManager.t("chat.input_placeholder")
	_refresh_chat_channel_button()

	if _esc_title_label:
		_esc_title_label.text = LocalizationManager.t("esc.title")
	if _esc_resume_btn:
		_esc_resume_btn.text = LocalizationManager.t("esc.resume")
	if _esc_history_btn:
		_esc_history_btn.text = LocalizationManager.t("esc.history")
	if _esc_surrender_btn and not _has_surrendered:
		_esc_surrender_btn.text = LocalizationManager.t("esc.surrender")
	if _esc_return_btn:
		_esc_return_btn.text = LocalizationManager.t("esc.return_menu")

	if _surrender_title_label:
		_surrender_title_label.text = LocalizationManager.t("surrender.title")
	if _surrender_desc_label:
		_surrender_desc_label.text = LocalizationManager.t("surrender.desc")
	if _surrender_confirm_btn:
		_surrender_confirm_btn.text = LocalizationManager.t("surrender.confirm")
	if _surrender_cancel_btn:
		_surrender_cancel_btn.text = LocalizationManager.t("surrender.continue")

	if _chat_history_title_label:
		_chat_history_title_label.text = LocalizationManager.t("esc.history")
	if _game_end_return_btn:
		_game_end_return_btn.text = LocalizationManager.t("game.return_menu")
	if _pause_title_label:
		_pause_title_label.text = LocalizationManager.t("pause.title")
	if _pause_resume_btn:
		_pause_resume_btn.text = LocalizationManager.t("pause.resume_btn")

	var sel_label := _selection_panel.get_node_or_null("SelectionInfo") as Label
	if sel_label and _cached_units.is_empty() and _cached_buildings.is_empty():
		sel_label.text = LocalizationManager.t("hud.no_selection")
	var queue_title := _selection_panel.get_node_or_null("QueueTitle") as Label
	if queue_title:
		queue_title.text = LocalizationManager.t("hud.production_queue")

	_update_esc_pause_hint()
	_update_esc_speed_ui()

func _refresh_chat_channel_button() -> void:
	if not _chat_channel_btn:
		return
	if _chat_channel == "team":
		_chat_channel_btn.text = LocalizationManager.t("chat.channel_team")
		_chat_channel_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	else:
		_chat_channel_btn.text = LocalizationManager.t("chat.channel_all")
		_chat_channel_btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))

func _get_unit_state_text(state: int) -> String:
	if state == GameConstants.UnitState.IDLE:
		return LocalizationManager.t("unit.state.idle")
	if state == GameConstants.UnitState.MOVING:
		return LocalizationManager.t("unit.state.moving")
	if state == GameConstants.UnitState.GATHERING:
		return LocalizationManager.t("unit.state.gathering")
	if state == GameConstants.UnitState.RETURNING:
		return LocalizationManager.t("unit.state.returning")
	if state == GameConstants.UnitState.BUILDING:
		return LocalizationManager.t("unit.state.building")
	return ""

func _format_unit_info_text(u: BaseUnit, data: Dictionary) -> String:
	var localized_unit_name := LocalizationManager.get_unit_name(u.unit_data_key, str(data.get("name", "Unit")))
	var info := LocalizationManager.t("hud.hp_format", [
		localized_unit_name, u.hp, u.max_hp, u.attack_power
	])
	if u.max_shield > 0:
		info += LocalizationManager.t("hud.shield_format", [u.shield, u.max_shield])
	if u.can_gather:
		var state_text := _get_unit_state_text(u.current_state)
		if state_text != "":
			info += "  [%s]" % state_text
		if u.carried_resource > 0:
			var res_name := LocalizationManager.t("resource.mineral_short") if u.carried_resource_type == GameConstants.ResourceType.MINERAL else LocalizationManager.t("resource.energy_short")
			info += LocalizationManager.t("hud.carry_format", [res_name, u.carried_resource, GameConstants.WORKER_CARRY_AMOUNT])
	return info

func _build_ui() -> void:
	# ====== 顶部资源栏 ======
	var top_bar := PanelContainer.new()
	top_bar.name = "TopBar"
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.05, 0.08, 0.15, 0.85)
	top_style.set_content_margin_all(8)
	top_bar.add_theme_stylebox_override("panel", top_style)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_top = 0
	top_bar.offset_bottom = 40
	add_child(top_bar)
	
	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 30)
	top_bar.add_child(top_hbox)
	
	_resource_label = Label.new()
	_resource_label.text = LocalizationManager.t("hud.resource_format", [400, 200, 0])
	_resource_label.add_theme_font_size_override("font_size", 16)
	_resource_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	top_hbox.add_child(_resource_label)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(top_spacer)

	_game_time_label = Label.new()
	_game_time_label.text = LocalizationManager.t("hud.timer", ["00:00"])
	_game_time_label.add_theme_font_size_override("font_size", 16)
	_game_time_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_game_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_hbox.add_child(_game_time_label)
	
	# ====== 右侧面板 (小地图 + 建造栏 + 选中信息 垂直排列) ======
	var right_panel := PanelContainer.new()
	right_panel.name = "RightPanel"
	var rp_style := StyleBoxFlat.new()
	rp_style.bg_color = Color(0.05, 0.08, 0.15, 0.85)
	rp_style.set_content_margin_all(8)
	right_panel.add_theme_stylebox_override("panel", rp_style)
	right_panel.anchor_left = 1.0
	right_panel.anchor_top = 0.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -240
	right_panel.offset_top = 40  # 顶部栏高度
	right_panel.offset_right = 0
	right_panel.offset_bottom = 0
	add_child(right_panel)
	
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right_vbox)
	
	# 小地图 (上)
	var minimap_container := PanelContainer.new()
	minimap_container.custom_minimum_size = Vector2(220, 220)
	var mm_style := StyleBoxFlat.new()
	mm_style.bg_color = Color(0, 0, 0, 0.9)
	minimap_container.add_theme_stylebox_override("panel", mm_style)
	right_vbox.add_child(minimap_container)
	
	_minimap = MinimapSystem.new()
	_minimap.name = "Minimap"
	minimap_container.add_child(_minimap)
	
	# 建造菜单 (下)
	var action_panel := PanelContainer.new()
	action_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ap_style := StyleBoxFlat.new()
	ap_style.bg_color = Color(0.08, 0.1, 0.18, 0.7)
	ap_style.set_content_margin_all(6)
	action_panel.add_theme_stylebox_override("panel", ap_style)
	right_vbox.add_child(action_panel)
	
	_build_menu = GridContainer.new()
	_build_menu.columns = 3
	_build_menu.add_theme_constant_override("h_separation", 4)
	_build_menu.add_theme_constant_override("v_separation", 4)
	_build_menu.name = "BuildMenu"
	action_panel.add_child(_build_menu)
	
	# 选中信息 + 生产队列 (最下)
	_selection_panel = VBoxContainer.new()
	_selection_panel.name = "SelectionPanel"
	_selection_panel.add_theme_constant_override("separation", 4)
	right_vbox.add_child(_selection_panel)
	
	var sel_label := Label.new()
	sel_label.name = "SelectionInfo"
	sel_label.text = LocalizationManager.t("hud.no_selection")
	sel_label.add_theme_font_size_override("font_size", 13)
	sel_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_panel.add_child(sel_label)

	var queue_title := Label.new()
	queue_title.name = "QueueTitle"
	queue_title.text = LocalizationManager.t("hud.production_queue")
	queue_title.add_theme_font_size_override("font_size", 12)
	queue_title.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	queue_title.visible = false
	_selection_panel.add_child(queue_title)

	_production_queue_strip = HBoxContainer.new()
	_production_queue_strip.name = "ProductionQueueStrip"
	_production_queue_strip.add_theme_constant_override("separation", 6)
	_production_queue_strip.visible = false
	_selection_panel.add_child(_production_queue_strip)
	
	# ====== 消息标签 (屏幕中上) ======
	_message_label = Label.new()
	_message_label.name = "MessageLabel"
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_label.position = Vector2(-200, 50)
	_message_label.size = Vector2(400, 30)
	_message_label.add_theme_font_size_override("font_size", 18)
	_message_label.add_theme_color_override("font_color", Color(1, 1, 0.3))
	_message_label.modulate.a = 0.0
	add_child(_message_label)

## ====== 公共接口 ======

func setup_minimap(map: MapSystem, game_world: Node2D, camera: Camera2D, local_team: int, fog: FogOfWarSystem = null) -> void:
	_local_team_id = local_team
	if camera is CameraSystem:
		_camera_system = camera
	if _minimap:
		_minimap.setup(map, game_world, camera, local_team, fog)
	_refresh_resource_label()

## 设置建筑放置系统引用
func setup_build_system(bp: BuildPlacementSystem) -> void:
	_build_placement = bp

## 更新选中信息
func _process(_delta: float) -> void:
	_update_game_timer()

	# 回放模式: 刷新进度条
	if _is_replay_mode and _replay_bar and _replay_bar.visible:
		_update_replay_progress()
	
	# 回放模式: 刷新玩家统计面板
	if _is_replay_mode and _replay_stats_panel and _replay_stats_panel.visible:
		_update_replay_stats()
	
	# 实时刷新选中单位的状态信息
	if _cached_units.size() == 1 and is_instance_valid(_cached_units[0]):
		var u: BaseUnit = _cached_units[0]
		var info_label := _selection_panel.get_node_or_null("SelectionInfo") as Label
		if info_label:
			var data: Dictionary = GameConstants.UNIT_DATA.get(u.unit_data_key, {})
			info_label.text = _format_unit_info_text(u, data)
	elif _cached_buildings.size() == 1 and is_instance_valid(_cached_buildings[0]):
		var b: BaseBuilding = _cached_buildings[0]
		var info_label := _selection_panel.get_node_or_null("SelectionInfo") as Label
		if info_label:
			_update_single_building_info(info_label, b)
			_update_production_queue_strip(b)

func update_selection(units: Array, buildings: Array) -> void:
	_cached_units = units
	_cached_buildings = buildings
	# 清空建造菜单
	for child in _build_menu.get_children():
		child.queue_free()
	
	var info_label := _selection_panel.get_node_or_null("SelectionInfo") as Label
	if not info_label:
		return
	
	if units.size() > 0:
		_clear_production_queue_strip()
		if units.size() == 1:
			var u: BaseUnit = units[0]
			var data: Dictionary = GameConstants.UNIT_DATA.get(u.unit_data_key, {})
			info_label.text = _format_unit_info_text(u, data)
		else:
			info_label.text = LocalizationManager.t("hud.selected_units", [units.size()])
		
		# 检查选中单位中是否有工人，显示建造菜单
		var has_builder := false
		for u in units:
			if is_instance_valid(u) and u.can_build:
				has_builder = true
				break
		if has_builder:
			_show_worker_build_options()
	elif buildings.size() > 0:
		var b: BaseBuilding = buildings[0]
		_update_single_building_info(info_label, b)
		_update_production_queue_strip(b)
		
		# 显示建造菜单
		_show_build_options(b)
	else:
		_clear_production_queue_strip()
		info_label.text = LocalizationManager.t("hud.no_selection")

func _update_single_building_info(info_label: Label, b: BaseBuilding) -> void:
	var data: Dictionary = GameConstants.BUILDING_DATA.get(b.building_data_key, {})
	var building_name: String = LocalizationManager.get_building_name(b.building_data_key, str(data.get("name", "Building")))
	info_label.text = "%s  HP: %d/%d" % [building_name, b.hp, b.max_hp]

	if not b.is_built:
		info_label.text += LocalizationManager.t("building.constructing", [int(b.build_progress * 100)])
	else:
		info_label.text += LocalizationManager.t("building.completed")

	if b.production_queue.is_empty():
		info_label.text += LocalizationManager.t("building.queue_empty")

func _clear_production_queue_strip() -> void:
	if not _production_queue_strip:
		return
	for child in _production_queue_strip.get_children():
		child.queue_free()
	_production_queue_strip.visible = false
	var queue_title := _selection_panel.get_node_or_null("QueueTitle") as Label
	if queue_title:
		queue_title.visible = false

func _update_production_queue_strip(building: BaseBuilding) -> void:
	if not _production_queue_strip:
		return

	for child in _production_queue_strip.get_children():
		child.queue_free()

	var queue_title := _selection_panel.get_node_or_null("QueueTitle") as Label
	if building.production_queue.is_empty():
		_production_queue_strip.visible = false
		if queue_title:
			queue_title.visible = false
		return

	if queue_title:
		queue_title.visible = true
	_production_queue_strip.visible = true

	var total: int = building.production_queue.size()
	var visible_limit: int = 5
	var normal_count: int = mini(total, visible_limit)
	if total > visible_limit:
		normal_count = visible_limit - 1

	for i in range(normal_count):
		var item: Dictionary = building.production_queue[i]
		var unit_key: String = str(item.get("unit_key", ""))
		var unit_data: Dictionary = GameConstants.UNIT_DATA.get(unit_key, {})
		var unit_name: String = LocalizationManager.get_unit_name(unit_key, str(unit_data.get("name", unit_key)))
		var display_no: int = total - i
		var progress: float = 0.0
		if i == 0:
			progress = clampf(float(item.get("progress", 0.0)), 0.0, 1.0)

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(96, 54)
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.12, 0.16, 0.24, 0.92)
		card_style.border_color = Color(0.35, 0.45, 0.6)
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(4)
		card_style.set_content_margin_all(4)
		card.add_theme_stylebox_override("panel", card_style)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		card.add_child(vbox)

		var top := Label.new()
		top.text = "[%d] %s" % [display_no, unit_name]
		top.add_theme_font_size_override("font_size", 11)
		top.add_theme_color_override("font_color", Color(0.88, 0.9, 1.0))
		vbox.add_child(top)

		if i == 0:
			var pb := ProgressBar.new()
			pb.min_value = 0.0
			pb.max_value = 100.0
			pb.value = progress * 100.0
			pb.custom_minimum_size = Vector2(0, 12)
			pb.show_percentage = false
			vbox.add_child(pb)

			var ptext := Label.new()
			ptext.text = "%d%%" % int(progress * 100.0)
			ptext.add_theme_font_size_override("font_size", 10)
			ptext.add_theme_color_override("font_color", Color(0.85, 0.95, 0.7))
			vbox.add_child(ptext)
		else:
			var waiting := Label.new()
			waiting.text = LocalizationManager.t("building.queue_waiting")
			waiting.add_theme_font_size_override("font_size", 10)
			waiting.add_theme_color_override("font_color", Color(0.72, 0.76, 0.85))
			vbox.add_child(waiting)

		_production_queue_strip.add_child(card)

	if total > visible_limit:
		var hidden_count: int = total - normal_count
		var stack := Control.new()
		stack.custom_minimum_size = Vector2(96, 54)

		for j in range(3):
			var layer := PanelContainer.new()
			layer.custom_minimum_size = Vector2(86, 48)
			layer.position = Vector2(2 + j * 3, 1 + j * 2)
			var layer_style := StyleBoxFlat.new()
			layer_style.bg_color = Color(0.10, 0.13, 0.20, 0.75 - j * 0.15)
			layer_style.border_color = Color(0.28, 0.36, 0.5)
			layer_style.set_border_width_all(1)
			layer_style.set_corner_radius_all(4)
			layer.add_theme_stylebox_override("panel", layer_style)
			stack.add_child(layer)

		var top_card := PanelContainer.new()
		top_card.custom_minimum_size = Vector2(86, 48)
		top_card.position = Vector2(8, 5)
		var top_style := StyleBoxFlat.new()
		top_style.bg_color = Color(0.16, 0.2, 0.3, 0.95)
		top_style.border_color = Color(0.45, 0.58, 0.8)
		top_style.set_border_width_all(1)
		top_style.set_corner_radius_all(4)
		top_card.add_theme_stylebox_override("panel", top_style)
		stack.add_child(top_card)

		var center := CenterContainer.new()
		top_card.add_child(center)
		var text := Label.new()
		text.text = "+%d" % hidden_count
		text.add_theme_font_size_override("font_size", 18)
		text.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		center.add_child(text)

		_production_queue_strip.add_child(stack)

func _build_production_queue_text(building: BaseBuilding) -> String:
	if building.production_queue.is_empty():
		return LocalizationManager.t("building.queue_empty")

	var total: int = building.production_queue.size()
	var items: Array[String] = []
	for i in range(total):
		var item: Dictionary = building.production_queue[i]
		var unit_key: String = item.get("unit_key", "")
		var unit_data: Dictionary = GameConstants.UNIT_DATA.get(unit_key, {})
		var unit_name: String = LocalizationManager.get_unit_name(unit_key, str(unit_data.get("name", unit_key)))
		var display_no: int = total - i
		if i == 0:
			var pct := int(clampf(item.get("progress", 0.0), 0.0, 1.0) * 100.0)
			items.append("[%d]%s(%d%%)" % [display_no, unit_name, pct])
		else:
			items.append("[%d]%s" % [display_no, unit_name])
	return LocalizationManager.t("building.queue_prefix") + "  |  ".join(items)

## 显示消息
func show_message(text: String, duration: float = 2.0) -> void:
	_message_label.text = text
	_message_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(_message_label, "modulate:a", 0.0, 0.5)

## ====== 内部 ======

func _on_resources_changed(team_id: int, minerals: int, energy: int) -> void:
	if team_id == _local_team_id:
		var unit_count := GameManager.get_units_by_team(team_id).size()
		_resource_label.text = LocalizationManager.t("hud.resource_format", [minerals, energy, unit_count])

func _refresh_resource_label() -> void:
	if not GameManager.resource_system:
		return
	var minerals := GameManager.resource_system.get_minerals(_local_team_id)
	var energy := GameManager.resource_system.get_energy(_local_team_id)
	_on_resources_changed(_local_team_id, minerals, energy)

func _on_insufficient_resources(team_id: int, type: String) -> void:
	if team_id == _local_team_id:
		if type == "mineral":
			show_message(LocalizationManager.t("msg.insufficient_minerals"))
		else:
			show_message(LocalizationManager.t("msg.insufficient_energy"))

func _show_build_options(building: BaseBuilding) -> void:
	if not building.is_built:
		return
	if _is_replay_mode:
		return  # 回放模式下不显示生产按钮
	
	# 生产单位按钮
	for unit_type_short in building.can_produce:
		# 查找完整key (根据阵营)
		var full_key := _resolve_unit_key(unit_type_short, building.team_id)
		var data: Dictionary = GameConstants.UNIT_DATA.get(full_key, {})
		if data.is_empty():
			continue
		
		var btn := Button.new()
		var unit_name: String = LocalizationManager.get_unit_name(full_key, str(data.get("name", "?")))
		btn.text = "%s\n%d/%d" % [unit_name, data.get("cost_mineral", 0), data.get("cost_energy", 0)]
		btn.custom_minimum_size = Vector2(68, 55)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_produce_pressed.bind(building, full_key))
		_build_menu.add_child(btn)

func _resolve_unit_key(short_type: String, team_id: int) -> String:
	# 根据阵营前缀匹配
	var prefix := "sa_" if team_id == 0 else "st_"
	var key := prefix + short_type
	if GameConstants.UNIT_DATA.has(key):
		return key
	# 尝试直接匹配
	for k in GameConstants.UNIT_DATA:
		if k.ends_with(short_type):
			var data: Dictionary = GameConstants.UNIT_DATA[k]
			if data.get("faction", -1) == team_id or true:
				return k
	return ""

func _on_produce_pressed(building: BaseBuilding, unit_key: String) -> void:
	var data: Dictionary = GameConstants.UNIT_DATA.get(unit_key, {})
	if data.is_empty():
		return
	
	var cost_m: int = data.get("cost_mineral", 0)
	var cost_e: int = data.get("cost_energy", 0)
	
	# 只检查资源是否足够，实际扣费在 _execute_command 中统一处理
	if GameManager.resource_system.can_afford(building.team_id, cost_m, cost_e):
		NetworkManager.send_command({
			"type": "produce",
			"building_id": building.entity_id,
			"unit_key": unit_key,
			"team_id": building.team_id,
		})
		AudioManager.play_event_sfx("queue_add")
	else:
		AudioManager.play_event_sfx("ui_error")
		show_message(LocalizationManager.t("msg.insufficient_resources"))

## 工人建造菜单 (显示所有可建造的建筑)
func _show_worker_build_options() -> void:
	for key in GameConstants.BUILDING_DATA:
		var data: Dictionary = GameConstants.BUILDING_DATA[key]
		var cost_m: int = data.get("cost_mineral", 0)
		var cost_e: int = data.get("cost_energy", 0)
		var btn := Button.new()
		var building_name: String = LocalizationManager.get_building_name(key, str(data.get("name", "?")))
		btn.text = "%s\n%s" % [building_name, LocalizationManager.t("building.cost_format", [cost_m, cost_e])]
		btn.custom_minimum_size = Vector2(68, 55)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_build_pressed.bind(key))
		_build_menu.add_child(btn)

func _on_build_pressed(building_key: String) -> void:
	if _build_placement:
		AudioManager.play_event_sfx("ui_click")
		_build_placement.start_placement(building_key)
	else:
		AudioManager.play_event_sfx("ui_error")
		show_message(LocalizationManager.t("msg.build_not_init"))

## ====== 游戏内聊天 (透明浮动消息) ======

func _build_chat_ui() -> void:
	# 消息容器 (左下角，完全透明，不挡操作)
	_chat_container = VBoxContainer.new()
	_chat_container.name = "ChatMessages"
	_chat_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_container.anchor_top = 0.5
	_chat_container.anchor_bottom = 1.0
	_chat_container.offset_left = 10
	_chat_container.offset_right = 420
	_chat_container.offset_top = 0
	_chat_container.offset_bottom = -190  # 底部面板上方
	_chat_container.add_theme_constant_override("separation", 2)
	_chat_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_container.alignment = BoxContainer.ALIGNMENT_END  # 消息从下往上堆叠
	add_child(_chat_container)

	# 输入行 (默认隐藏)
	_chat_input_row = HBoxContainer.new()
	_chat_input_row.name = "ChatInputRow"
	_chat_input_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_input_row.anchor_top = 1.0
	_chat_input_row.anchor_bottom = 1.0
	_chat_input_row.offset_left = 10
	_chat_input_row.offset_right = 420
	_chat_input_row.offset_top = -218
	_chat_input_row.offset_bottom = -190
	_chat_input_row.add_theme_constant_override("separation", 4)
	_chat_input_row.visible = false
	add_child(_chat_input_row)

	_chat_channel_btn = Button.new()
	_chat_channel_btn.text = LocalizationManager.t("chat.channel_all")
	_chat_channel_btn.custom_minimum_size = Vector2(60, 26)
	_chat_channel_btn.add_theme_font_size_override("font_size", 12)
	var ch_style := StyleBoxFlat.new()
	ch_style.bg_color = Color(0.1, 0.15, 0.25, 0.7)
	ch_style.set_corner_radius_all(3)
	ch_style.set_content_margin_all(2)
	_chat_channel_btn.add_theme_stylebox_override("normal", ch_style)
	_chat_channel_btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_chat_channel_btn.pressed.connect(_on_channel_cycle)
	_chat_input_row.add_child(_chat_channel_btn)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = LocalizationManager.t("chat.input_placeholder")
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.custom_minimum_size.y = 26
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.03, 0.05, 0.1, 0.75)
	input_style.border_color = Color(0.2, 0.3, 0.5, 0.5)
	input_style.set_border_width_all(1)
	input_style.set_corner_radius_all(3)
	input_style.set_content_margin_all(4)
	_chat_input.add_theme_stylebox_override("normal", input_style)
	_chat_input.add_theme_font_size_override("font_size", 13)
	_chat_input.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_input.focus_entered.connect(func(): _chat_input_active = true)
	_chat_input.focus_exited.connect(func(): _chat_input_active = false)
	_chat_input_row.add_child(_chat_input)

## 添加一条浮动聊天消息 (自动淡出消失)
func _add_floating_message(bbcode_text: String) -> void:
	var msg := RichTextLabel.new()
	msg.bbcode_enabled = true
	msg.fit_content = true
	msg.scroll_active = false
	msg.custom_minimum_size.x = 400
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg.add_theme_font_size_override("normal_font_size", 13)
	# 半透明文字阴影效果
	msg.add_theme_constant_override("shadow_offset_x", 1)
	msg.add_theme_constant_override("shadow_offset_y", 1)
	msg.add_theme_color_override("default_color", Color(1, 1, 1, 0.95))
	msg.text = bbcode_text
	_chat_container.add_child(msg)
	# 限制最多显示8条浮动消息
	while _chat_container.get_child_count() > 8:
		var oldest := _chat_container.get_child(0)
		_chat_container.remove_child(oldest)
		oldest.queue_free()
	# 10秒后淡出消失
	var tween := create_tween()
	tween.tween_interval(10.0)
	tween.tween_property(msg, "modulate:a", 0.0, 2.0)
	tween.tween_callback(msg.queue_free)

func _build_surrender_dialog() -> void:
	_surrender_dialog = PanelContainer.new()
	_surrender_dialog.name = "SurrenderDialog"
	_surrender_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_surrender_dialog.offset_left = -200
	_surrender_dialog.offset_right = 200
	_surrender_dialog.offset_top = -100
	_surrender_dialog.offset_bottom = 100
	_surrender_dialog.visible = false

	var dialog_style := StyleBoxFlat.new()
	dialog_style.bg_color = Color(0.08, 0.06, 0.12, 0.95)
	dialog_style.border_color = Color(0.5, 0.2, 0.2)
	dialog_style.set_border_width_all(2)
	dialog_style.set_corner_radius_all(10)
	dialog_style.set_content_margin_all(20)
	_surrender_dialog.add_theme_stylebox_override("panel", dialog_style)
	add_child(_surrender_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_surrender_dialog.add_child(vbox)

	_surrender_title_label = Label.new()
	_surrender_title_label.name = "SurrenderTitle"
	_surrender_title_label.text = LocalizationManager.t("surrender.title")
	_surrender_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_surrender_title_label.add_theme_font_size_override("font_size", 24)
	_surrender_title_label.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	vbox.add_child(_surrender_title_label)

	_surrender_desc_label = Label.new()
	_surrender_desc_label.name = "SurrenderDesc"
	_surrender_desc_label.text = LocalizationManager.t("surrender.desc")
	_surrender_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_surrender_desc_label.add_theme_font_size_override("font_size", 15)
	_surrender_desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_surrender_desc_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 20)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_surrender_confirm_btn = Button.new()
	_surrender_confirm_btn.name = "SurrenderConfirmBtn"
	_surrender_confirm_btn.text = LocalizationManager.t("surrender.confirm")
	_surrender_confirm_btn.custom_minimum_size = Vector2(120, 40)
	var confirm_style := StyleBoxFlat.new()
	confirm_style.bg_color = Color(0.6, 0.15, 0.15)
	confirm_style.border_color = Color(0.9, 0.3, 0.3)
	confirm_style.set_border_width_all(1)
	confirm_style.set_corner_radius_all(5)
	confirm_style.set_content_margin_all(8)
	_surrender_confirm_btn.add_theme_stylebox_override("normal", confirm_style)
	var confirm_hover := StyleBoxFlat.new()
	confirm_hover.bg_color = Color(0.75, 0.2, 0.2)
	confirm_hover.border_color = Color(1, 0.4, 0.4)
	confirm_hover.set_border_width_all(1)
	confirm_hover.set_corner_radius_all(5)
	confirm_hover.set_content_margin_all(8)
	_surrender_confirm_btn.add_theme_stylebox_override("hover", confirm_hover)
	_surrender_confirm_btn.add_theme_font_size_override("font_size", 16)
	_surrender_confirm_btn.add_theme_color_override("font_color", Color(1, 0.9, 0.9))
	_surrender_confirm_btn.pressed.connect(_on_surrender_confirmed)
	btn_row.add_child(_surrender_confirm_btn)

	_surrender_cancel_btn = Button.new()
	_surrender_cancel_btn.name = "SurrenderCancelBtn"
	_surrender_cancel_btn.text = LocalizationManager.t("surrender.continue")
	_surrender_cancel_btn.custom_minimum_size = Vector2(120, 40)
	var cancel_style := StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.15, 0.3, 0.15)
	cancel_style.border_color = Color(0.3, 0.7, 0.3)
	cancel_style.set_border_width_all(1)
	cancel_style.set_corner_radius_all(5)
	cancel_style.set_content_margin_all(8)
	_surrender_cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	var cancel_hover := StyleBoxFlat.new()
	cancel_hover.bg_color = Color(0.2, 0.45, 0.2)
	cancel_hover.border_color = Color(0.4, 0.9, 0.4)
	cancel_hover.set_border_width_all(1)
	cancel_hover.set_corner_radius_all(5)
	cancel_hover.set_content_margin_all(8)
	_surrender_cancel_btn.add_theme_stylebox_override("hover", cancel_hover)
	_surrender_cancel_btn.add_theme_font_size_override("font_size", 16)
	_surrender_cancel_btn.add_theme_color_override("font_color", Color(0.9, 1, 0.9))
	_surrender_cancel_btn.pressed.connect(_on_surrender_cancelled)
	btn_row.add_child(_surrender_cancel_btn)

## ====== ESC 游戏菜单 ======

func _build_esc_menu() -> void:
	_esc_menu = PanelContainer.new()
	_esc_menu.name = "EscMenu"
	_esc_menu.set_anchors_preset(Control.PRESET_CENTER)
	_esc_menu.offset_left = -160
	_esc_menu.offset_right = 160
	_esc_menu.offset_top = -180
	_esc_menu.offset_bottom = 180
	_esc_menu.visible = false
	_esc_menu.process_mode = Node.PROCESS_MODE_ALWAYS

	var menu_style := StyleBoxFlat.new()
	menu_style.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	menu_style.border_color = Color(0.25, 0.35, 0.6)
	menu_style.set_border_width_all(2)
	menu_style.set_corner_radius_all(12)
	menu_style.set_content_margin_all(20)
	_esc_menu.add_theme_stylebox_override("panel", menu_style)
	add_child(_esc_menu)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_esc_menu.add_child(vbox)

	_esc_title_label = Label.new()
	_esc_title_label.name = "EscTitle"
	_esc_title_label.text = LocalizationManager.t("esc.title")
	_esc_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_esc_title_label.add_theme_font_size_override("font_size", 22)
	_esc_title_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	vbox.add_child(_esc_title_label)

	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep)

	# 继续游戏
	_esc_resume_btn = _add_esc_button(vbox, LocalizationManager.t("esc.resume"), Color(0.15, 0.35, 0.15), Color(0.3, 0.8, 0.3), _on_esc_resume)

	# 暂停/恢复
	_esc_pause_btn = _add_esc_button(vbox, LocalizationManager.t("esc.pause"), Color(0.15, 0.15, 0.35), Color(0.3, 0.3, 0.8), _on_esc_pause)

	# 速度控制
	var speed_row := HBoxContainer.new()
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_row.add_theme_constant_override("separation", 8)
	vbox.add_child(speed_row)

	_esc_speed_down_btn = Button.new()
	_esc_speed_down_btn.text = "◀"
	_esc_speed_down_btn.custom_minimum_size = Vector2(44, 32)
	_esc_speed_down_btn.pressed.connect(_on_esc_speed_slower)
	speed_row.add_child(_esc_speed_down_btn)

	_esc_speed_label = Label.new()
	_esc_speed_label.text = LocalizationManager.t("esc.speed_format", ["1.0x"])
	_esc_speed_label.custom_minimum_size = Vector2(140, 0)
	_esc_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_esc_speed_label.add_theme_font_size_override("font_size", 14)
	_esc_speed_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	speed_row.add_child(_esc_speed_label)

	_esc_speed_up_btn = Button.new()
	_esc_speed_up_btn.text = "▶"
	_esc_speed_up_btn.custom_minimum_size = Vector2(44, 32)
	_esc_speed_up_btn.pressed.connect(_on_esc_speed_faster)
	speed_row.add_child(_esc_speed_up_btn)

	# 查看历史消息
	_esc_history_btn = _add_esc_button(vbox, LocalizationManager.t("esc.history"), Color(0.2, 0.2, 0.15), Color(0.6, 0.6, 0.3), _on_view_history)

	# 投降
	_esc_surrender_btn = _add_esc_button(vbox, LocalizationManager.t("esc.surrender"), Color(0.35, 0.12, 0.12), Color(0.8, 0.3, 0.3), _on_esc_surrender)

	# 回到主菜单
	_esc_return_btn = _add_esc_button(vbox, LocalizationManager.t("esc.return_menu"), Color(0.25, 0.15, 0.1), Color(0.7, 0.4, 0.2), _on_return_to_menu)

	# 暂停次数提示
	var pause_hint := Label.new()
	pause_hint.name = "PauseHint"
	pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_hint.add_theme_font_size_override("font_size", 12)
	pause_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	vbox.add_child(pause_hint)
	_update_esc_pause_hint()
	_update_esc_speed_ui()

func _add_esc_button(parent: VBoxContainer, text: String, bg_color: Color, border_color: Color, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(260, 38)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", style)
	var hover := StyleBoxFlat.new()
	hover.bg_color = bg_color * 1.4
	hover.border_color = border_color * 1.3
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(5)
	hover.set_content_margin_all(6)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _update_esc_pause_hint() -> void:
	if not _esc_menu:
		return
	var hint := _esc_menu.get_node_or_null("VBoxContainer") as VBoxContainer
	if not hint:
		return
	var label := _esc_menu.find_child("PauseHint", true, false) as Label
	if not label:
		return
	if GameManager.is_single_player():
		label.text = LocalizationManager.t("esc.single_unlimited")
	else:
		var remaining := GameManager.get_pause_remaining(NetworkManager.peer_id)
		label.text = LocalizationManager.t("esc.pause_remaining", [remaining, GameManager._max_pause_count])
	# 更新暂停按钮文字
	if _esc_pause_btn:
		if GameManager.is_paused:
			_esc_pause_btn.text = LocalizationManager.t("esc.resume_game")
		else:
			_esc_pause_btn.text = LocalizationManager.t("esc.pause")

## ====== 聊天历史面板 ======

func _build_chat_history_panel() -> void:
	_chat_history_panel = PanelContainer.new()
	_chat_history_panel.name = "ChatHistoryPanel"
	_chat_history_panel.set_anchors_preset(Control.PRESET_CENTER)
	_chat_history_panel.offset_left = -300
	_chat_history_panel.offset_right = 300
	_chat_history_panel.offset_top = -250
	_chat_history_panel.offset_bottom = 250
	_chat_history_panel.visible = false
	_chat_history_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.06, 0.12, 0.95)
	panel_style.border_color = Color(0.3, 0.4, 0.5)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(16)
	_chat_history_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_chat_history_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_chat_history_panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	_chat_history_title_label = Label.new()
	_chat_history_title_label.name = "ChatHistoryTitle"
	_chat_history_title_label.text = LocalizationManager.t("esc.history")
	_chat_history_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_history_title_label.add_theme_font_size_override("font_size", 18)
	_chat_history_title_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	header.add_child(_chat_history_title_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.3, 0.1, 0.1, 0.8)
	close_style.set_corner_radius_all(4)
	close_style.set_content_margin_all(2)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(func(): _chat_history_panel.visible = false)
	header.add_child(close_btn)

	_chat_history_log = RichTextLabel.new()
	_chat_history_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_history_log.bbcode_enabled = true
	_chat_history_log.scroll_following = true
	_chat_history_log.add_theme_font_size_override("normal_font_size", 13)
	var log_bg := StyleBoxFlat.new()
	log_bg.bg_color = Color(0, 0, 0, 0.3)
	log_bg.set_corner_radius_all(4)
	log_bg.set_content_margin_all(6)
	_chat_history_log.add_theme_stylebox_override("normal", log_bg)
	vbox.add_child(_chat_history_log)

## ====== 游戏结束覆盖 ======

func _build_game_end_overlay() -> void:
	_game_end_overlay = Control.new()
	_game_end_overlay.name = "GameEndOverlay"
	_game_end_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_end_overlay.visible = false
	_game_end_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_game_end_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	_game_end_overlay.add_child(bg)

	var center_panel := PanelContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	center_panel.offset_left = -200
	center_panel.offset_right = 200
	center_panel.offset_top = -100
	center_panel.offset_bottom = 100
	var end_style := StyleBoxFlat.new()
	end_style.bg_color = Color(0.06, 0.06, 0.12, 0.95)
	end_style.border_color = Color(0.4, 0.4, 0.6)
	end_style.set_border_width_all(2)
	end_style.set_corner_radius_all(12)
	end_style.set_content_margin_all(24)
	center_panel.add_theme_stylebox_override("panel", end_style)
	_game_end_overlay.add_child(center_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center_panel.add_child(vbox)

	_game_end_label = Label.new()
	_game_end_label.text = ""
	_game_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_end_label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(_game_end_label)

	_game_end_return_btn = Button.new()
	_game_end_return_btn.name = "GameEndReturnBtn"
	_game_end_return_btn.text = LocalizationManager.t("game.return_menu")
	_game_end_return_btn.custom_minimum_size = Vector2(180, 44)
	_game_end_return_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	var ret_style := StyleBoxFlat.new()
	ret_style.bg_color = Color(0.15, 0.25, 0.4)
	ret_style.border_color = Color(0.3, 0.5, 0.8)
	ret_style.set_border_width_all(1)
	ret_style.set_corner_radius_all(6)
	ret_style.set_content_margin_all(8)
	_game_end_return_btn.add_theme_stylebox_override("normal", ret_style)
	var ret_hover := StyleBoxFlat.new()
	ret_hover.bg_color = Color(0.2, 0.35, 0.55)
	ret_hover.border_color = Color(0.4, 0.6, 1.0)
	ret_hover.set_border_width_all(1)
	ret_hover.set_corner_radius_all(6)
	ret_hover.set_content_margin_all(8)
	_game_end_return_btn.add_theme_stylebox_override("hover", ret_hover)
	_game_end_return_btn.add_theme_font_size_override("font_size", 18)
	_game_end_return_btn.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	_game_end_return_btn.pressed.connect(_on_return_to_menu)
	vbox.add_child(_game_end_return_btn)

## ====== 输入处理 ======

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Tab 键切换频道 (聊天输入激活时)
		if event.keycode == KEY_TAB and _chat_input_active:
			_on_channel_cycle()
			get_viewport().set_input_as_handled()
			return
		# Enter 键打开/发送聊天
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if _chat_input_active:
				pass  # text_submitted 处理
			elif not _esc_menu_visible:
				_open_chat_input()
				get_viewport().set_input_as_handled()
		# Escape 键: 关闭优先级 聊天 > 历史 > 投降 > ESC菜单 > 打开ESC菜单
		elif event.keycode == KEY_ESCAPE:
			if _chat_input_active:
				_close_chat_input()
			elif _chat_history_panel.visible:
				_chat_history_panel.visible = false
			elif _surrender_dialog.visible:
				_surrender_dialog.visible = false
			elif _esc_menu_visible:
				_toggle_esc_menu()
			else:
				_toggle_esc_menu()
			get_viewport().set_input_as_handled()

func _toggle_esc_menu() -> void:
	_esc_menu_visible = not _esc_menu_visible
	_esc_menu.visible = _esc_menu_visible
	if _esc_menu_visible:
		_update_esc_pause_hint()
		_update_esc_speed_ui()

func _can_adjust_game_speed() -> bool:
	return (not _is_replay_mode) and NetworkManager.can_adjust_game_speed()

func _update_esc_speed_ui() -> void:
	if not _esc_speed_label:
		return

	if _is_replay_mode:
		_esc_speed_label.text = LocalizationManager.t("esc.speed_replay")
		if _esc_speed_down_btn:
			_esc_speed_down_btn.disabled = true
		if _esc_speed_up_btn:
			_esc_speed_up_btn.disabled = true
		return

	if not NetworkManager.can_adjust_game_speed():
		_esc_speed_label.text = LocalizationManager.t("esc.speed_online_fixed")
		if _esc_speed_down_btn:
			_esc_speed_down_btn.disabled = true
		if _esc_speed_up_btn:
			_esc_speed_up_btn.disabled = true
		return

	var idx := NetworkManager.get_game_speed_index()
	var count := NetworkManager.get_game_speed_count()
	_esc_speed_label.text = LocalizationManager.t("esc.speed_format", [NetworkManager.get_game_speed_label()])
	if _esc_speed_down_btn:
		_esc_speed_down_btn.disabled = idx <= 0
	if _esc_speed_up_btn:
		_esc_speed_up_btn.disabled = idx >= count - 1

func _open_chat_input() -> void:
	_chat_input_row.visible = true
	_chat_input.grab_focus()
	_chat_input.text = ""

func _close_chat_input() -> void:
	_chat_input.release_focus()
	_chat_input_row.visible = false
	_chat_input_active = false

func _on_chat_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		_close_chat_input()
		return
	# 单机模式作弊指令
	if text.strip_edges() == "cheat" and GameManager.is_single_player():
		NetworkManager.send_command({
			"type": "cheat_set",
			"enabled": not GameManager.cheat_instant_build,
			"team_id": _local_team_id,
		})
		_chat_input.text = ""
		_close_chat_input()
		return
	NetworkManager.send_game_chat(text, _chat_channel)
	_chat_input.text = ""
	_close_chat_input()

func _on_channel_cycle() -> void:
	if _chat_channel == "all":
		_chat_channel = "team"
	else:
		_chat_channel = "all"
	_refresh_chat_channel_button()

func _on_game_chat_received(sender_id: int, sender_name: String, channel: String, msg: String) -> void:
	var channel_tag := ""
	var name_color := "white"
	if channel == "all":
		channel_tag = "[color=gray]%s[/color]" % LocalizationManager.t("chat.channel_all")
		name_color = "cyan"
	elif channel == "team":
		channel_tag = "[color=green]%s[/color]" % LocalizationManager.t("chat.channel_team")
		name_color = "green"
	elif channel.begins_with("whisper"):
		channel_tag = "[color=magenta]%s[/color]" % LocalizationManager.t("chat.channel_whisper")
		name_color = "magenta"
	var bbcode := "%s [color=%s]%s:[/color] %s" % [channel_tag, name_color, sender_name, msg]
	# 存入历史
	_chat_history_data.append(bbcode)
	if _chat_history_log:
		_chat_history_log.append_text(bbcode + "\n")
	# 浮动显示
	_add_floating_message(bbcode)

## 系统消息 (同时存入历史和浮动)
func _add_system_message(bbcode: String) -> void:
	_chat_history_data.append(bbcode)
	if _chat_history_log:
		_chat_history_log.append_text(bbcode + "\n")
	_add_floating_message(bbcode)

## ====== ESC菜单回调 ======

func _on_esc_resume() -> void:
	_toggle_esc_menu()

func _on_esc_pause() -> void:
	if GameManager.is_paused:
		if GameManager.is_single_player():
			GameManager.resume_game(NetworkManager.peer_id)
		else:
			NetworkManager.request_resume()
	else:
		if GameManager.is_single_player():
			GameManager.pause_game(NetworkManager.peer_id)
		else:
			var remaining := GameManager.get_pause_remaining(NetworkManager.peer_id)
			if remaining == 0:
				show_message(LocalizationManager.t("esc.pause_exhausted", [GameManager._max_pause_count]))
				return
			NetworkManager.request_pause()
	_update_esc_pause_hint()

func _on_esc_speed_slower() -> void:
	if not _can_adjust_game_speed():
		return
	if NetworkManager.adjust_game_speed(-1):
		show_message(LocalizationManager.t("game.speed_format", [NetworkManager.get_game_speed_label()]), 1.2)
	_update_esc_speed_ui()

func _on_esc_speed_faster() -> void:
	if not _can_adjust_game_speed():
		return
	if NetworkManager.adjust_game_speed(1):
		show_message(LocalizationManager.t("game.speed_format", [NetworkManager.get_game_speed_label()]), 1.2)
	_update_esc_speed_ui()

func _on_game_speed_changed(_speed_index: int, _speed_label: String) -> void:
	_update_esc_speed_ui()

func _on_view_history() -> void:
	_toggle_esc_menu()
	_chat_history_panel.visible = true

func _on_esc_surrender() -> void:
	if _has_surrendered:
		show_message(LocalizationManager.t("surrender.already"))
		return
	_toggle_esc_menu()
	_surrender_dialog.visible = true

func _on_return_to_menu() -> void:
	# 停止录像 (如果仍在录制)
	if ReplaySystem.mode == ReplaySystem.Mode.RECORDING:
		ReplaySystem.stop_recording()
	# 停止回放
	if ReplaySystem.mode == ReplaySystem.Mode.PLAYING:
		ReplaySystem.stop_replay()
	# 恢复暂停状态
	get_tree().paused = false
	GameManager.is_paused = false
	# 联机游戏中途离开视为投降 (通知对方获胜)
	if NetworkManager.is_online and (GameManager.current_state == GameManager.GameState.PLAYING or GameManager.current_state == GameManager.GameState.PAUSED):
		NetworkManager.surrender()
	GameManager.current_state = GameManager.GameState.MENU
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")

## ====== 投降 & 结束 ======

func _on_surrender_confirmed() -> void:
	if _has_surrendered:
		_surrender_dialog.visible = false
		return
	_has_surrendered = true
	_set_surrender_disabled()
	_surrender_dialog.visible = false
	NetworkManager.surrender()
	if NetworkManager.players.size() <= 1:
		_on_player_surrendered(NetworkManager.peer_id, _local_team_id)

func _on_surrender_cancelled() -> void:
	_surrender_dialog.visible = false

func _on_player_surrendered(surrendering_peer: int, team_id: int) -> void:
	var pname: String = NetworkManager.players.get(surrendering_peer, {}).get("name", "Opponent")
	if surrendering_peer == NetworkManager.peer_id:
		_has_surrendered = true
		_set_surrender_disabled()
		_add_system_message("[color=red]%s[/color]" % LocalizationManager.t("sys.you_surrendered"))
	else:
		_add_system_message("[color=yellow]%s[/color]" % LocalizationManager.t("sys.player_quit", [pname]))
	# 仅销毁该玩家实体，胜负由存活队伍数判定
	GameManager.forfeit_peer(surrendering_peer)

func _set_surrender_disabled() -> void:
	if _esc_surrender_btn:
		_esc_surrender_btn.disabled = true
		_esc_surrender_btn.text = LocalizationManager.t("surrender.done")

func _on_game_ended(winner_team: int) -> void:
	# 自动保存录像
	if ReplaySystem.mode == ReplaySystem.Mode.RECORDING:
		var path := ReplaySystem.stop_recording()
		if path != "":
			_add_system_message("[color=cyan]%s[/color]" % LocalizationManager.t("replay.saved", [path.get_file()]))
	
	# 显示游戏结束覆盖层，含回到主菜单按钮
	_game_end_overlay.visible = true
	if winner_team == _local_team_id:
		_game_end_label.text = LocalizationManager.t("game.victory")
		_game_end_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	else:
		_game_end_label.text = LocalizationManager.t("game.defeat")
		_game_end_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))

## ====== 暂停系统 ======

func _build_pause_ui() -> void:
	# 暂停覆盖层 (全屏半透明)
	_pause_overlay = Control.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.5)
	_pause_overlay.add_child(bg)

	var center_vbox := VBoxContainer.new()
	center_vbox.set_anchors_preset(Control.PRESET_CENTER)
	center_vbox.offset_left = -200
	center_vbox.offset_right = 200
	center_vbox.offset_top = -120
	center_vbox.offset_bottom = 120
	center_vbox.add_theme_constant_override("separation", 16)
	_pause_overlay.add_child(center_vbox)

	var pause_panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.16, 0.95)
	panel_style.border_color = Color(0.3, 0.4, 0.8)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(24)
	pause_panel.add_theme_stylebox_override("panel", panel_style)
	center_vbox.add_child(pause_panel)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 12)
	pause_panel.add_child(inner_vbox)

	_pause_title_label = Label.new()
	_pause_title_label.name = "PauseTitle"
	_pause_title_label.text = LocalizationManager.t("pause.title")
	_pause_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_title_label.add_theme_font_size_override("font_size", 28)
	_pause_title_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	inner_vbox.add_child(_pause_title_label)

	_pause_info_label = Label.new()
	_pause_info_label.text = ""
	_pause_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_info_label.add_theme_font_size_override("font_size", 16)
	_pause_info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	inner_vbox.add_child(_pause_info_label)

	_pause_remaining_label = Label.new()
	_pause_remaining_label.text = ""
	_pause_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_remaining_label.add_theme_font_size_override("font_size", 14)
	_pause_remaining_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	inner_vbox.add_child(_pause_remaining_label)

	_pause_resume_btn = Button.new()
	_pause_resume_btn.name = "PauseResumeBtn"
	_pause_resume_btn.text = LocalizationManager.t("pause.resume_btn")
	_pause_resume_btn.custom_minimum_size = Vector2(180, 44)
	_pause_resume_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	var resume_style := StyleBoxFlat.new()
	resume_style.bg_color = Color(0.15, 0.35, 0.15)
	resume_style.border_color = Color(0.3, 0.8, 0.3)
	resume_style.set_border_width_all(1)
	resume_style.set_corner_radius_all(6)
	resume_style.set_content_margin_all(8)
	_pause_resume_btn.add_theme_stylebox_override("normal", resume_style)
	var resume_hover := StyleBoxFlat.new()
	resume_hover.bg_color = Color(0.2, 0.5, 0.2)
	resume_hover.border_color = Color(0.4, 1, 0.4)
	resume_hover.set_border_width_all(1)
	resume_hover.set_corner_radius_all(6)
	resume_hover.set_content_margin_all(8)
	_pause_resume_btn.add_theme_stylebox_override("hover", resume_hover)
	_pause_resume_btn.add_theme_font_size_override("font_size", 18)
	_pause_resume_btn.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	_pause_resume_btn.pressed.connect(_on_resume_btn_pressed)
	inner_vbox.add_child(_pause_resume_btn)

func _on_pause_btn_pressed() -> void:
	if GameManager.is_paused:
		if GameManager.is_single_player():
			GameManager.resume_game(NetworkManager.peer_id)
		else:
			NetworkManager.request_resume()
	else:
		if GameManager.is_single_player():
			GameManager.pause_game(NetworkManager.peer_id)
		else:
			var remaining := GameManager.get_pause_remaining(NetworkManager.peer_id)
			if remaining == 0:
				show_message(LocalizationManager.t("esc.pause_exhausted", [GameManager._max_pause_count]))
				return
			NetworkManager.request_pause()

func _on_resume_btn_pressed() -> void:
	if GameManager.is_single_player():
		GameManager.resume_game(NetworkManager.peer_id)
	else:
		NetworkManager.request_resume()

func _on_pause_requested(by_peer: int) -> void:
	var success := GameManager.pause_game(by_peer)
	if not success and by_peer == NetworkManager.peer_id:
		var remaining := GameManager.get_pause_remaining(by_peer)
		if remaining == 0:
			show_message(LocalizationManager.t("esc.pause_exhausted_short"))

func _on_resume_requested(by_peer: int) -> void:
	GameManager.resume_game(by_peer)

func _on_server_disconnected_ingame() -> void:
	# 服务器(主机)断线 → 客户端视为对方弃权，本方获胜
	if GameManager.current_state != GameManager.GameState.PLAYING and GameManager.current_state != GameManager.GameState.PAUSED:
		return
	_add_system_message("[color=yellow]%s[/color]" % LocalizationManager.t("sys.opponent_disconnected"))
	GameManager.current_state = GameManager.GameState.ENDED
	GameManager.game_ended.emit(_local_team_id)

func _on_game_paused(by_peer: int) -> void:
	_pause_overlay.visible = true
	
	var player_name: String = NetworkManager.players.get(by_peer, {}).get("name", "Player")
	if by_peer == NetworkManager.peer_id:
		_pause_info_label.text = LocalizationManager.t("pause.you_paused")
	else:
		_pause_info_label.text = LocalizationManager.t("pause.player_paused", [player_name])
	
	if GameManager.is_single_player():
		_pause_remaining_label.text = LocalizationManager.t("esc.single_unlimited")
	else:
		var remaining := GameManager.get_pause_remaining(NetworkManager.peer_id)
		_pause_remaining_label.text = LocalizationManager.t("pause.remaining", [remaining, GameManager._max_pause_count])
	
	_add_system_message("[color=yellow]%s[/color]" % LocalizationManager.t("sys.game_paused"))
	_update_esc_pause_hint()

func _on_game_resumed(_by_peer: int) -> void:
	_pause_overlay.visible = false
	_add_system_message("[color=yellow]%s[/color]" % LocalizationManager.t("sys.game_resumed"))
	_update_esc_pause_hint()

## ====== 回放控制 ======

func _build_replay_controls() -> void:
	# 底部回放控制条 (可折叠)
	_replay_bar = PanelContainer.new()
	_replay_bar.name = "ReplayBar"
	_replay_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_replay_bar.offset_top = -96  # 展开高度: 标题行 + 控制行
	_replay_bar.offset_bottom = 0
	_replay_bar.offset_right = -240  # 为右侧面板留空
	_replay_bar.process_mode = Node.PROCESS_MODE_ALWAYS
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.05, 0.08, 0.15, 0.9)
	bar_style.border_color = Color(0.3, 0.4, 0.6)
	bar_style.border_width_top = 1
	bar_style.set_content_margin_all(8)
	_replay_bar.add_theme_stylebox_override("panel", bar_style)
	add_child(_replay_bar)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 6)
	_replay_bar.add_child(outer_vbox)

	# ── 标题行 (始终可见) ──
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	outer_vbox.add_child(header_row)

	var bar_title := Label.new()
	bar_title.text = "回放控制"
	bar_title.add_theme_font_size_override("font_size", 13)
	bar_title.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	header_row.add_child(bar_title)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_spacer)

	_replay_bar_toggle_btn = Button.new()
	_replay_bar_toggle_btn.text = "▼ 折叠"
	_replay_bar_toggle_btn.custom_minimum_size = Vector2(72, 24)
	_replay_bar_toggle_btn.add_theme_font_size_override("font_size", 12)
	_replay_bar_toggle_btn.pressed.connect(_on_replay_bar_toggle)
	header_row.add_child(_replay_bar_toggle_btn)

	# ── 控制行 (可折叠) ──
	_replay_bar_content = HBoxContainer.new()
	_replay_bar_content.add_theme_constant_override("separation", 12)
	outer_vbox.add_child(_replay_bar_content)

	# 重新开始按钮
	var restart_btn := Button.new()
	restart_btn.text = "⏮"
	restart_btn.custom_minimum_size = Vector2(36, 36)
	restart_btn.add_theme_font_size_override("font_size", 18)
	restart_btn.tooltip_text = "从头开始"
	restart_btn.pressed.connect(_on_replay_restart)
	_replay_bar_content.add_child(restart_btn)

	# 回放/暂停按钮
	_replay_pause_btn = Button.new()
	_replay_pause_btn.text = "⏸"
	_replay_pause_btn.custom_minimum_size = Vector2(36, 36)
	_replay_pause_btn.add_theme_font_size_override("font_size", 18)
	_replay_pause_btn.pressed.connect(_on_replay_toggle_pause)
	_replay_bar_content.add_child(_replay_pause_btn)

	# 减速
	var slow_btn := Button.new()
	slow_btn.text = "◀◀"
	slow_btn.custom_minimum_size = Vector2(36, 36)
	slow_btn.add_theme_font_size_override("font_size", 14)
	slow_btn.pressed.connect(_on_replay_slower)
	_replay_bar_content.add_child(slow_btn)

	# 速度标签
	_replay_speed_label = Label.new()
	_replay_speed_label.text = "1.0x"
	_replay_speed_label.add_theme_font_size_override("font_size", 16)
	_replay_speed_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	_replay_speed_label.custom_minimum_size = Vector2(50, 0)
	_replay_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_replay_bar_content.add_child(_replay_speed_label)

	# 加速
	var fast_btn := Button.new()
	fast_btn.text = "▶▶"
	fast_btn.custom_minimum_size = Vector2(36, 36)
	fast_btn.add_theme_font_size_override("font_size", 14)
	fast_btn.pressed.connect(_on_replay_faster)
	_replay_bar_content.add_child(fast_btn)

	# 进度条
	_replay_progress = HSlider.new()
	_replay_progress.min_value = 0.0
	_replay_progress.max_value = 1.0
	_replay_progress.step = 0.001
	_replay_progress.value = 0.0
	_replay_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_progress.custom_minimum_size = Vector2(200, 0)
	_replay_progress.editable = false  # 只读进度条
	_replay_bar_content.add_child(_replay_progress)

	# 时间标签
	_replay_time_label = Label.new()
	_replay_time_label.text = "00:00 / 00:00"
	_replay_time_label.add_theme_font_size_override("font_size", 14)
	_replay_time_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	_replay_time_label.custom_minimum_size = Vector2(120, 0)
	_replay_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_replay_bar_content.add_child(_replay_time_label)

	# 回到主菜单
	var menu_btn := Button.new()
	menu_btn.text = "退出回放"
	menu_btn.custom_minimum_size = Vector2(80, 36)
	menu_btn.add_theme_font_size_override("font_size", 14)
	menu_btn.pressed.connect(_on_return_to_menu)
	_replay_bar_content.add_child(menu_btn)

	# 连接回放信号
	ReplaySystem.replay_finished.connect(_on_replay_finished)
	ReplaySystem.replay_speed_changed.connect(_on_replay_speed_changed)

## ====== 回放: 玩家统计面板 (右侧) ======
func _build_replay_stats_panel() -> void:
	_replay_stats_panel = PanelContainer.new()
	_replay_stats_panel.name = "ReplayStatsPanel"
	_replay_stats_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_replay_stats_panel.anchor_left = 1.0
	_replay_stats_panel.anchor_right = 1.0
	_replay_stats_panel.anchor_top = 0.0
	_replay_stats_panel.anchor_bottom = 0.0
	_replay_stats_panel.offset_left = -528  # 右侧面板宽240 + 间距8 + 本面板宽280 = 528
	_replay_stats_panel.offset_right = -248  # 右侧面板宽240 + 间距8
	_replay_stats_panel.offset_top = 48
	_replay_stats_panel.offset_bottom = 300
	_replay_stats_expanded_bottom = 300.0
	_replay_stats_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_replay_stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.06, 0.12, 0.88)
	panel_style.border_color = Color(0.2, 0.35, 0.6)
	panel_style.border_width_left = 2
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(10)
	_replay_stats_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_replay_stats_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 6)
	_replay_stats_panel.add_child(outer_vbox)

	# 标题行 (始终可见)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	outer_vbox.add_child(title_row)

	var title := Label.new()
	title.text = "玩家统计"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	_replay_stats_toggle_btn = Button.new()
	_replay_stats_toggle_btn.text = "▼"
	_replay_stats_toggle_btn.custom_minimum_size = Vector2(28, 24)
	_replay_stats_toggle_btn.add_theme_font_size_override("font_size", 11)
	_replay_stats_toggle_btn.pressed.connect(_on_replay_stats_toggle)
	title_row.add_child(_replay_stats_toggle_btn)

	# 可折叠内容
	_replay_stats_content = VBoxContainer.new()
	_replay_stats_content.add_theme_constant_override("separation", 6)
	outer_vbox.add_child(_replay_stats_content)

	# 镜头模式按钮
	_replay_camera_mode_btn = Button.new()
	_replay_camera_mode_btn.text = "自由镜头"
	_replay_camera_mode_btn.custom_minimum_size = Vector2(80, 24)
	_replay_camera_mode_btn.add_theme_font_size_override("font_size", 11)
	_replay_camera_mode_btn.pressed.connect(_on_replay_camera_mode_toggle)
	_replay_stats_content.add_child(_replay_camera_mode_btn)

	var sep := HSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(0.2, 0.3, 0.5, 0.5)
	sep.add_theme_stylebox_override("separator", sep_style)
	_replay_stats_content.add_child(sep)

	var vbox := _replay_stats_content

	# 为每个队伍生成统计标签
	var players: Dictionary = ReplaySystem.get_replay_players()
	var team_ids: Array = []
	for key in players:
		var tid: int = int(players[key].get("team_id", 0))
		if not team_ids.has(tid):
			team_ids.append(tid)
	team_ids.sort()

	var team_colors: Array = [
		Color(0.3, 0.6, 1.0),   # 队伍1 蓝色
		Color(1.0, 0.35, 0.3),  # 队伍2 红色
		Color(0.3, 0.9, 0.4),   # 队伍3 绿色
		Color(1.0, 0.8, 0.2),   # 队伍4 黄色
		Color(0.1, 0.85, 0.9),  # 队伍5 青色
		Color(0.7, 0.2, 0.9),   # 队伍6 紫色
		Color(0.95, 0.5, 0.1),  # 队伍7 橙色
		Color(0.9, 0.9, 0.9),   # 队伍8 白色
	]

	for tid in team_ids:
		var team_container := VBoxContainer.new()
		team_container.add_theme_constant_override("separation", 2)
		vbox.add_child(team_container)

		# 队伍名称行 + 跟随镜头按钮
		var team_row := HBoxContainer.new()
		team_row.add_theme_constant_override("separation", 6)
		team_container.add_child(team_row)

		# 找到该队伍所有玩家名
		var team_player_names: Array = []
		var team_peer_id: int = -1
		for key in players:
			if int(players[key].get("team_id", 0)) == tid:
				team_player_names.append(str(players[key].get("name", "Player")))
				if team_peer_id < 0:
					team_peer_id = int(key)

		var color_idx: int = int(tid) % team_colors.size()
		var team_name_label := Label.new()
		team_name_label.text = "■ 队伍%d: %s" % [tid + 1, ", ".join(team_player_names)]
		team_name_label.add_theme_font_size_override("font_size", 13)
		team_name_label.add_theme_color_override("font_color", team_colors[color_idx])
		team_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		team_row.add_child(team_name_label)

		# 跟随此玩家镜头按钮
		var follow_btn := Button.new()
		follow_btn.text = "👁"
		follow_btn.custom_minimum_size = Vector2(28, 22)
		follow_btn.add_theme_font_size_override("font_size", 12)
		follow_btn.tooltip_text = "跟随此玩家镜头"
		follow_btn.pressed.connect(_on_replay_follow_player.bind(team_peer_id))
		team_row.add_child(follow_btn)

		# 统计数据标签
		var stats_label := Label.new()
		stats_label.text = "矿石: --  能源: --  单位: --  建筑: --  生产: --"
		stats_label.add_theme_font_size_override("font_size", 12)
		stats_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
		stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		team_container.add_child(stats_label)

		_replay_stats_labels[tid] = stats_label

		# 队伍间分隔
		if tid != team_ids.back():
			var tsep := HSeparator.new()
			var tsep_style := StyleBoxLine.new()
			tsep_style.color = Color(0.15, 0.2, 0.35, 0.4)
			tsep.add_theme_stylebox_override("separator", tsep_style)
			vbox.add_child(tsep)

## ====== 回放: 操作日志面板 (左侧) ======
func _build_replay_action_log() -> void:
	_replay_action_log_panel = PanelContainer.new()
	_replay_action_log_panel.name = "ReplayActionLog"
	_replay_action_log_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_replay_action_log_panel.anchor_left = 0.0
	_replay_action_log_panel.anchor_right = 0.0
	_replay_action_log_panel.anchor_top = 0.0
	_replay_action_log_panel.anchor_bottom = 1.0
	_replay_action_log_panel.offset_left = 0
	_replay_action_log_panel.offset_right = 260
	_replay_action_log_panel.offset_top = 48
	_replay_action_log_panel.offset_bottom = -200
	_replay_action_log_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_replay_action_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.06, 0.12, 0.8)
	panel_style.border_color = Color(0.2, 0.3, 0.5)
	panel_style.border_width_right = 1
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(8)
	_replay_action_log_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_replay_action_log_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 4)
	_replay_action_log_panel.add_child(outer_vbox)

	# 标题行 (始终可见)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	outer_vbox.add_child(title_row)

	var title := Label.new()
	title.text = "操作日志"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	_replay_action_log_toggle_btn = Button.new()
	_replay_action_log_toggle_btn.text = "▼"
	_replay_action_log_toggle_btn.custom_minimum_size = Vector2(28, 22)
	_replay_action_log_toggle_btn.add_theme_font_size_override("font_size", 11)
	_replay_action_log_toggle_btn.pressed.connect(_on_replay_action_log_toggle)
	title_row.add_child(_replay_action_log_toggle_btn)

	# 可折叠内容
	_replay_action_log_content = VBoxContainer.new()
	_replay_action_log_content.add_theme_constant_override("separation", 4)
	_replay_action_log_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_replay_action_log_content)

	var sep := HSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(0.2, 0.3, 0.5, 0.5)
	sep.add_theme_stylebox_override("separator", sep_style)
	_replay_action_log_content.add_child(sep)

	_replay_action_log = RichTextLabel.new()
	_replay_action_log.bbcode_enabled = true
	_replay_action_log.scroll_following = true
	_replay_action_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_replay_action_log.add_theme_font_size_override("normal_font_size", 11)
	_replay_action_log.add_theme_color_override("default_color", Color(0.7, 0.75, 0.85))
	_replay_action_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_replay_action_log_content.add_child(_replay_action_log)

	# 连接操作日志信号
	ReplaySystem.replay_action_logged.connect(_on_replay_action_logged)

## ====== 回放统计/操作刷新 ======

func _update_replay_stats() -> void:
	var stats: Dictionary = ReplaySystem.current_stats_snapshot
	if stats.is_empty():
		return
	for tid in _replay_stats_labels:
		var label: Label = _replay_stats_labels[tid]
		var team_key = tid  # may be int
		var s: Dictionary = {}
		# 尝试 int key 或 string key
		if stats.has(team_key):
			s = stats[team_key]
		elif stats.has(str(team_key)):
			s = stats[str(team_key)]
		if s.is_empty():
			continue
		var minerals: int = int(s.get("minerals", 0))
		var energy: int = int(s.get("energy", 0))
		var unit_count: int = int(s.get("unit_count", 0))
		var building_count: int = int(s.get("building_count", 0))
		var prod: int = int(s.get("production_queue_size", 0))
		label.text = "矿石: %d  能源: %d\n单位: %d  建筑: %d  生产队列: %d" % [minerals, energy, unit_count, building_count, prod]

func _on_replay_action_logged(_tick: int, action_text: String) -> void:
	if _replay_action_log == null:
		return
	var time_str := ReplaySystem.format_tick_time(_tick)
	_replay_action_log.append_text("[color=#8899bb][%s][/color] %s\n" % [time_str, action_text])

func _on_replay_camera_mode_toggle() -> void:
	if ReplaySystem.replay_camera_mode == ReplaySystem.CameraMode.FREE:
		# 切换到跟随模式 — 默认跟随第一个玩家
		ReplaySystem.replay_camera_mode = ReplaySystem.CameraMode.FOLLOW_PLAYER
		var peer_ids := ReplaySystem.get_player_peer_ids()
		if peer_ids.size() > 0 and ReplaySystem.replay_follow_peer_id < 0:
			ReplaySystem.replay_follow_peer_id = peer_ids[0]
		if _replay_camera_mode_btn:
			var name := ReplaySystem.get_player_name(ReplaySystem.replay_follow_peer_id)
			_replay_camera_mode_btn.text = "跟随: %s" % name
	else:
		ReplaySystem.replay_camera_mode = ReplaySystem.CameraMode.FREE
		if _replay_camera_mode_btn:
			_replay_camera_mode_btn.text = "自由镜头"

func _on_replay_follow_player(peer_id: int) -> void:
	ReplaySystem.replay_camera_mode = ReplaySystem.CameraMode.FOLLOW_PLAYER
	ReplaySystem.replay_follow_peer_id = peer_id
	if _replay_camera_mode_btn:
		var name := ReplaySystem.get_player_name(peer_id)
		_replay_camera_mode_btn.text = "跟随: %s" % name

func _update_game_timer() -> void:
	if not _game_time_label:
		return

	var current_tick: int = ReplaySystem.get_current_tick() if _is_replay_mode else NetworkManager.current_tick
	var elapsed_seconds := int(current_tick * NetworkManager.DEFAULT_TICK_INTERVAL)
	if elapsed_seconds == _last_game_time_sec:
		return
	_last_game_time_sec = elapsed_seconds
	_game_time_label.text = LocalizationManager.t("hud.timer", [_format_elapsed_seconds(elapsed_seconds)])

func _format_elapsed_seconds(total_seconds: int) -> String:
	var hours := total_seconds / 3600
	var mins := (total_seconds % 3600) / 60
	var secs := total_seconds % 60
	if hours > 0:
		return "%02d:%02d:%02d" % [hours, mins, secs]
	return "%02d:%02d" % [mins, secs]

func _update_replay_progress() -> void:
	if ReplaySystem.mode != ReplaySystem.Mode.PLAYING:
		return
	var progress := ReplaySystem.get_replay_progress()
	_replay_progress.value = progress
	
	var current_tick: int = ReplaySystem.get_current_tick()
	var total_ticks: int = ReplaySystem.get_total_ticks()
	var tick_interval: float = NetworkManager.DEFAULT_TICK_INTERVAL
	var current_time := current_tick * tick_interval
	var total_time := total_ticks * tick_interval
	_replay_time_label.text = "%s / %s" % [_format_time(current_time), _format_time(total_time)]

func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%02d:%02d" % [mins, secs]

func _on_replay_toggle_pause() -> void:
	ReplaySystem.toggle_pause()
	_replay_pause_btn.text = "▶" if ReplaySystem.is_replay_paused() else "⏸"

func _on_replay_slower() -> void:
	var speeds := [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
	var idx := _find_speed_index(speeds, ReplaySystem.get_replay_speed())
	if idx > 0:
		ReplaySystem.set_replay_speed(speeds[idx - 1])

func _on_replay_faster() -> void:
	var speeds := [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
	var idx := _find_speed_index(speeds, ReplaySystem.get_replay_speed())
	if idx < speeds.size() - 1:
		ReplaySystem.set_replay_speed(speeds[idx + 1])

func _find_speed_index(speeds: Array, current: float) -> int:
	var best := 0
	var best_diff := absf(speeds[0] - current)
	for i in range(speeds.size()):
		var diff := absf(speeds[i] - current)
		if diff < best_diff:
			best_diff = diff
			best = i
	return best

func _on_replay_speed_changed(new_speed: float) -> void:
	if _replay_speed_label:
		_replay_speed_label.text = "%.1fx" % new_speed

func _on_replay_bar_toggle() -> void:
	_replay_bar_collapsed = not _replay_bar_collapsed
	_replay_bar_content.visible = not _replay_bar_collapsed
	_replay_bar_toggle_btn.text = "▲ 展开" if _replay_bar_collapsed else "▼ 折叠"
	_replay_bar.offset_top = -44 if _replay_bar_collapsed else -96
	# 同步更新相机底部补偿，防止地图底部出现黑边
	if _camera_system:
		_camera_system.hud_bottom_height = 44.0 if _replay_bar_collapsed else 96.0

func _on_replay_stats_toggle() -> void:
	_replay_stats_collapsed = not _replay_stats_collapsed
	_replay_stats_content.visible = not _replay_stats_collapsed
	_replay_stats_toggle_btn.text = "▶" if _replay_stats_collapsed else "▼"
	_replay_stats_panel.offset_bottom = float(_replay_stats_panel.offset_top) + 44.0 if _replay_stats_collapsed else _replay_stats_expanded_bottom

func _on_replay_action_log_toggle() -> void:
	_replay_action_log_collapsed = not _replay_action_log_collapsed
	_replay_action_log_content.visible = not _replay_action_log_collapsed
	_replay_action_log_toggle_btn.text = "▶" if _replay_action_log_collapsed else "▼"
	if _replay_action_log_collapsed:
		# 折叠: 改用 anchor_bottom=0 + 绝对高度 44px
		_replay_action_log_panel.anchor_bottom = 0.0
		_replay_action_log_panel.offset_bottom = _replay_action_log_panel.offset_top + 44.0
	else:
		# 展开: 恢复 anchor_bottom=1 + offset -200
		_replay_action_log_panel.anchor_bottom = 1.0
		_replay_action_log_panel.offset_bottom = -200

func _on_replay_restart() -> void:
	ReplaySystem.restart_replay()

func _on_replay_finished() -> void:
	if _replay_pause_btn:
		_replay_pause_btn.text = "▶"
	show_message("回放结束")
