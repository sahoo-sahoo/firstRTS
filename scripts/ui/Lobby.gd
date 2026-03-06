## 联机大厅界面 - 创建/加入房间、玩家列表、准备、聊天
extends Control

const SETTINGS_PATH := "user://game_settings.cfg"
const RANDOM_SPAWN_OPTION_ID := 999
const RANDOM_COLOR_OPTION_ID := 998
const PLAYER_COLOR_OPTIONS := [
	{"id": 0, "name": "蓝色"},
	{"id": 1, "name": "红色"},
	{"id": 2, "name": "绿色"},
	{"id": 3, "name": "黄色"},
	{"id": 4, "name": "青色"},
	{"id": 5, "name": "紫色"},
	{"id": 6, "name": "橙色"},
	{"id": 7, "name": "白色"},
]

## UI 引用
var _status_label: Label = null
var _player_list: VBoxContainer = null
var _chat_log: RichTextLabel = null
var _chat_input: LineEdit = null
var _ip_input: LineEdit = null
var _port_input: LineEdit = null
var _name_input: LineEdit = null
var _host_btn: Button = null
var _join_btn: Button = null
var _ready_btn: Button = null
var _start_btn: Button = null
var _back_btn: Button = null
var _faction_btn: Button = null
var _fog_mode_option: OptionButton = null
var _speed_option: OptionButton = null
var _starting_minerals_spin: SpinBox = null
var _starting_energy_spin: SpinBox = null

var _is_ready: bool = false
var _selected_faction: int = 0  # 0=钢铁联盟, 1=暗影科技
var _selected_fog_mode: int = GameConstants.FogMode.NONE
var _selected_game_speed_index: int = 4
var _selected_starting_minerals: int = GameConstants.STARTING_MINERALS
var _selected_starting_energy: int = GameConstants.STARTING_ENERGY
var _saved_player_name: String = "玩家1"
var _saved_ip: String = "127.0.0.1"
var _saved_port: String = "7777"

func _ready() -> void:
	_load_settings()
	_build_ui()
	_connect_signals()

func _build_ui() -> void:
	# 全屏背景
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 主布局: 上标题 + 中间内容 + 底部按钮
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 10)
	var margin := 20
	main_vbox.offset_left = margin
	main_vbox.offset_top = margin
	main_vbox.offset_right = -margin
	main_vbox.offset_bottom = -margin
	add_child(main_vbox)

	# ===== 标题栏 =====
	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 20)
	main_vbox.add_child(title_bar)

	var title := Label.new()
	title.text = "联 机 大 厅"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	title_bar.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(spacer)

	_status_label = Label.new()
	_status_label.text = "未连接"
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.3))
	title_bar.add_child(_status_label)

	# ===== 分隔线 =====
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	main_vbox.add_child(sep)

	# ===== 中间区域: 左(连接+玩家) + 右(聊天) =====
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(content_hbox)

	# --- 左侧面板 ---
	var left_panel := VBoxContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 1.0
	left_panel.add_theme_constant_override("separation", 12)
	content_hbox.add_child(left_panel)

	# 连接设置
	var conn_inner := _create_panel_flat("连接设置", left_panel)

	var conn_grid := GridContainer.new()
	conn_grid.columns = 2
	conn_grid.add_theme_constant_override("h_separation", 10)
	conn_grid.add_theme_constant_override("v_separation", 8)
	conn_inner.add_child(conn_grid)

	conn_grid.add_child(_create_label("昵称:"))
	_name_input = _create_line_edit(_saved_player_name, 200)
	conn_grid.add_child(_name_input)

	conn_grid.add_child(_create_label("IP地址:"))
	_ip_input = _create_line_edit(_saved_ip, 200)
	conn_grid.add_child(_ip_input)

	conn_grid.add_child(_create_label("端口:"))
	_port_input = _create_line_edit(_saved_port, 200)
	conn_grid.add_child(_port_input)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	conn_inner.add_child(btn_row)

	_host_btn = _create_action_button("创建房间", Color(0.2, 0.5, 0.2))
	btn_row.add_child(_host_btn)
	_host_btn.pressed.connect(_on_host_pressed)

	_join_btn = _create_action_button("加入房间", Color(0.2, 0.3, 0.6))
	btn_row.add_child(_join_btn)
	_join_btn.pressed.connect(_on_join_pressed)

	# 阵营选择
	var faction_inner := _create_panel_flat("阵营选择", left_panel)

	if _selected_faction == 0:
		_faction_btn = _create_action_button("钢铁联盟 (蓝方)", Color(0.15, 0.3, 0.6))
	else:
		_faction_btn = _create_action_button("暗影科技 (红方)", Color(0.5, 0.15, 0.2))
	_faction_btn.custom_minimum_size.x = 280
	faction_inner.add_child(_faction_btn)
	_faction_btn.pressed.connect(_on_faction_toggle)

	# 游戏设置 (战争迷雾)
	var settings_inner := _create_panel_flat("游戏设置", left_panel)
	var fog_hbox := HBoxContainer.new()
	fog_hbox.add_theme_constant_override("separation", 10)
	settings_inner.add_child(fog_hbox)
	var fog_label := _create_label("战争迷雾:")
	fog_hbox.add_child(fog_label)
	_fog_mode_option = OptionButton.new()
	_fog_mode_option.add_item("无迷雾", GameConstants.FogMode.NONE)
	_fog_mode_option.add_item("未探索全黑", GameConstants.FogMode.FULL_BLACK)
	_fog_mode_option.add_item("未探索显示地形", GameConstants.FogMode.TERRAIN_ONLY)
	_fog_mode_option.add_item("探索后始终可见", GameConstants.FogMode.EXPLORED_VISIBLE)
	# 根据已加载的设置选择对应项
	for i in _fog_mode_option.item_count:
		if _fog_mode_option.get_item_id(i) == _selected_fog_mode:
			_fog_mode_option.selected = i
			break
	_fog_mode_option.custom_minimum_size.x = 190
	_fog_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fog_mode_option.item_selected.connect(_on_fog_mode_selected)
	fog_hbox.add_child(_fog_mode_option)

	var speed_hbox := HBoxContainer.new()
	speed_hbox.add_theme_constant_override("separation", 10)
	settings_inner.add_child(speed_hbox)
	var speed_label := _create_label("游戏速度:")
	speed_hbox.add_child(speed_label)
	_speed_option = OptionButton.new()
	_speed_option.add_item("0.5x", 0)
	_speed_option.add_item("1.0x", 1)
	_speed_option.add_item("1.5x", 2)
	_speed_option.add_item("2.0x", 3)
	_speed_option.add_item("∞ 不限速", 4)
	_speed_option.selected = _selected_game_speed_index
	_speed_option.custom_minimum_size.x = 190
	_speed_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_option.item_selected.connect(_on_speed_selected)
	speed_hbox.add_child(_speed_option)

	var mineral_hbox := HBoxContainer.new()
	mineral_hbox.add_theme_constant_override("separation", 10)
	settings_inner.add_child(mineral_hbox)
	var mineral_label := _create_label("初始矿石:")
	mineral_hbox.add_child(mineral_label)
	_starting_minerals_spin = SpinBox.new()
	_starting_minerals_spin.min_value = 0
	_starting_minerals_spin.max_value = 99999
	_starting_minerals_spin.step = 50
	_starting_minerals_spin.value = _selected_starting_minerals
	_starting_minerals_spin.custom_minimum_size.x = 190
	_starting_minerals_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_starting_minerals_spin.value_changed.connect(_on_starting_minerals_changed)
	mineral_hbox.add_child(_starting_minerals_spin)

	var energy_hbox := HBoxContainer.new()
	energy_hbox.add_theme_constant_override("separation", 10)
	settings_inner.add_child(energy_hbox)
	var energy_label := _create_label("初始能源:")
	energy_hbox.add_child(energy_label)
	_starting_energy_spin = SpinBox.new()
	_starting_energy_spin.min_value = 0
	_starting_energy_spin.max_value = 99999
	_starting_energy_spin.step = 50
	_starting_energy_spin.value = _selected_starting_energy
	_starting_energy_spin.custom_minimum_size.x = 190
	_starting_energy_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_starting_energy_spin.value_changed.connect(_on_starting_energy_changed)
	energy_hbox.add_child(_starting_energy_spin)
	# 客户端进入时禁用下拉 (只有主机可修改)
	if NetworkManager.is_connected and NetworkManager.role != NetworkManager.Role.SERVER:
		_fog_mode_option.disabled = true
		_speed_option.disabled = true
		_starting_minerals_spin.editable = false
		_starting_energy_spin.editable = false

	# 玩家列表
	var players_inner := _create_panel_flat("玩家列表", left_panel)

	_player_list = VBoxContainer.new()
	_player_list.add_theme_constant_override("separation", 6)
	players_inner.add_child(_player_list)

	# --- 右侧面板: 聊天 ---
	var right_panel := VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	right_panel.add_theme_constant_override("separation", 8)
	content_hbox.add_child(right_panel)

	var chat_title := Label.new()
	chat_title.text = "聊天"
	chat_title.add_theme_font_size_override("font_size", 18)
	chat_title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	right_panel.add_child(chat_title)

	_chat_log = RichTextLabel.new()
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	var chat_style := StyleBoxFlat.new()
	chat_style.bg_color = Color(0.04, 0.06, 0.1)
	chat_style.border_color = Color(0.15, 0.2, 0.35)
	chat_style.set_border_width_all(1)
	chat_style.set_corner_radius_all(4)
	chat_style.set_content_margin_all(8)
	_chat_log.add_theme_stylebox_override("normal", chat_style)
	right_panel.add_child(_chat_log)

	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 6)
	right_panel.add_child(chat_row)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "输入消息..."
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.custom_minimum_size.y = 36
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.08, 0.1, 0.18)
	input_style.border_color = Color(0.2, 0.3, 0.5)
	input_style.set_border_width_all(1)
	input_style.set_corner_radius_all(4)
	input_style.set_content_margin_all(6)
	_chat_input.add_theme_stylebox_override("normal", input_style)
	_chat_input.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	chat_row.add_child(_chat_input)
	_chat_input.text_submitted.connect(_on_chat_submit)

	var send_btn := _create_action_button("发送", Color(0.2, 0.4, 0.6))
	send_btn.custom_minimum_size = Vector2(70, 36)
	chat_row.add_child(send_btn)
	send_btn.pressed.connect(func(): _on_chat_submit(_chat_input.text))

	# ===== 底部按钮栏 =====
	var sep2 := HSeparator.new()
	sep2.add_theme_constant_override("separation", 4)
	main_vbox.add_child(sep2)

	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 12)
	main_vbox.add_child(bottom_bar)

	_back_btn = _create_action_button("返回主菜单", Color(0.4, 0.2, 0.2))
	bottom_bar.add_child(_back_btn)
	_back_btn.pressed.connect(_on_back_pressed)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(bottom_spacer)

	_ready_btn = _create_action_button("准备", Color(0.2, 0.5, 0.2))
	_ready_btn.custom_minimum_size.x = 140
	_ready_btn.disabled = true
	bottom_bar.add_child(_ready_btn)
	_ready_btn.pressed.connect(_on_ready_pressed)

	_start_btn = _create_action_button("开始游戏", Color(0.6, 0.4, 0.1))
	_start_btn.custom_minimum_size.x = 160
	_start_btn.disabled = true
	_start_btn.visible = false
	bottom_bar.add_child(_start_btn)
	_start_btn.pressed.connect(_on_start_pressed)

func _connect_signals() -> void:
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)
	NetworkManager.connection_failed_signal.connect(_on_connection_failed)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.player_info_updated.connect(_on_player_info_updated)
	NetworkManager.all_players_ready.connect(_on_all_ready)
	NetworkManager.chat_message_received.connect(_on_chat_received)
	NetworkManager.game_starting.connect(_on_game_starting)
	NetworkManager.lobby_config_updated.connect(_on_lobby_config_updated)

## ====== UI 工厂 ======

func _create_panel_flat(title_text: String, parent: VBoxContainer) -> VBoxContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.18)
	style.border_color = Color(0.15, 0.22, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)

	var panel_bg := PanelContainer.new()
	panel_bg.add_theme_stylebox_override("panel", style)
	parent.add_child(panel_bg)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	panel_bg.add_child(inner)

	var lbl := Label.new()
	lbl.text = title_text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	inner.add_child(lbl)

	return inner

func _create_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	return lbl

func _create_line_edit(default: String, min_width: int = 150) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = default
	edit.custom_minimum_size = Vector2(min_width, 32)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14)
	style.border_color = Color(0.2, 0.3, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(6)
	edit.add_theme_stylebox_override("normal", style)
	edit.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	return edit

func _create_action_button(text: String, bg_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(120, 40)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.border_color = bg_color.lightened(0.3)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	normal.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = bg_color.lightened(0.15)
	hover.border_color = bg_color.lightened(0.5)
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(5)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = bg_color.darkened(0.2)
	pressed.border_color = bg_color.lightened(0.2)
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(5)
	pressed.set_content_margin_all(8)
	btn.add_theme_stylebox_override("pressed", pressed)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.15, 0.15, 0.2)
	disabled.border_color = Color(0.25, 0.25, 0.3)
	disabled.set_border_width_all(1)
	disabled.set_corner_radius_all(5)
	disabled.set_content_margin_all(8)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	btn.pressed.connect(func(): AudioManager.play_ui_click())
	return btn

## ====== 按钮回调 ======

func _on_host_pressed() -> void:
	_save_settings()
	var port := int(_port_input.text)
	var err := NetworkManager.host_game(port)
	if err == OK:
		var lan_ip := NetworkManager.get_local_lan_ip()
		_status_label.text = "房间已创建 | 其他玩家请连接: %s:%d" % [lan_ip, port]
		_status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		_ip_input.text = lan_ip  # 将居域网 IP 回写到输入框，方便复制
		_host_btn.disabled = true
		_join_btn.disabled = true
		_ready_btn.visible = false  # 主机不需要准备按钮
		_start_btn.visible = true
		_fog_mode_option.disabled = false  # 主机可修改
		_speed_option.disabled = false
		_starting_minerals_spin.editable = true
		_starting_energy_spin.editable = true
		NetworkManager.set_player_info({"name": _name_input.text, "faction": _selected_faction})
		NetworkManager.lobby_config["fog_mode"] = _selected_fog_mode  # 初始化大厅配置
		NetworkManager.lobby_config["game_speed_index"] = _selected_game_speed_index
		NetworkManager.lobby_config["starting_minerals"] = _selected_starting_minerals
		NetworkManager.lobby_config["starting_energy"] = _selected_starting_energy
		NetworkManager.broadcast_lobby_config({
			"fog_mode": _selected_fog_mode,
			"game_speed_index": _selected_game_speed_index,
			"starting_minerals": _selected_starting_minerals,
			"starting_energy": _selected_starting_energy,
		})
		_refresh_player_list()
		_add_system_message("你创建了房间，等待其他玩家加入...")
	else:
		_status_label.text = "创建失败!"
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))

func _on_join_pressed() -> void:
	_save_settings()
	var ip := _ip_input.text
	var port := int(_port_input.text)
	var err := NetworkManager.join_game(ip, port)
	if err == OK:
		_status_label.text = "正在连接 %s:%d..." % [ip, port]
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
		_host_btn.disabled = true
		_join_btn.disabled = true
		_add_system_message("正在连接服务器...")
	else:
		_status_label.text = "连接失败!"
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))

func _on_ready_pressed() -> void:
	_is_ready = not _is_ready
	NetworkManager.set_ready(_is_ready)
	if _is_ready:
		_ready_btn.text = "取消准备"
		_add_system_message("你已准备就绪")
	else:
		_ready_btn.text = "准备"
		_add_system_message("你取消了准备")
	_refresh_player_list()

func _on_start_pressed() -> void:
	# 检查非主机玩家是否全部准备
	var all_ready := true
	for pid in NetworkManager.players:
		if pid == 1:
			continue  # 主机不需要准备
		if not NetworkManager.players[pid].get("ready", false):
			all_ready = false
			break
	# 检查出生点是否有重复
	var used_spawns: Dictionary = {}
	var has_duplicate_spawn := false
	for pid in NetworkManager.players:
		var spawn_slot: int = int(NetworkManager.players[pid].get("spawn_slot", 0))
		if spawn_slot < 0:
			continue  # 随机位置允许重复选择
		if used_spawns.has(spawn_slot):
			has_duplicate_spawn = true
			break
		used_spawns[spawn_slot] = true
	if NetworkManager.players.size() < 2:
		_add_system_message("[color=red]至少需要2名玩家才能开始![/color]")
		return
	if not all_ready:
		_add_system_message("[color=red]还有玩家未准备![/color]")
		return
	if has_duplicate_spawn:
		_add_system_message("[color=red]存在重复出生位置，请先调整后再开始![/color]")
		return
	# 广播开始游戏
	var config := {
		"map_seed": randi(),
		"player_count": NetworkManager.players.size(),
		"fog_mode": _selected_fog_mode,
		"game_speed_index": _selected_game_speed_index,
		"starting_minerals": _selected_starting_minerals,
		"starting_energy": _selected_starting_energy,
	}
	NetworkManager.broadcast_game_start(config)

func _on_team_selected(index: int, pid: int, team_option: OptionButton) -> void:
	var new_team_id := team_option.get_item_id(index)
	if pid == NetworkManager.peer_id:
		NetworkManager.set_player_info({"team_id": new_team_id})
	else:
		# 主机为其他玩家分配队伍
		NetworkManager.assign_player_team(pid, new_team_id)

func _on_faction_selected(index: int, pid: int, faction_option: OptionButton) -> void:
	var faction_id := faction_option.get_item_id(index)
	if pid == NetworkManager.peer_id:
		NetworkManager.set_player_info({"faction": faction_id})
	else:
		NetworkManager.assign_player_faction(pid, faction_id)

func _on_color_selected(index: int, pid: int, color_option: OptionButton) -> void:
	var selected_id := color_option.get_item_id(index)
	var selected_color := -1 if selected_id == RANDOM_COLOR_OPTION_ID else selected_id
	if selected_color < 0:
		if pid == NetworkManager.peer_id:
			NetworkManager.set_player_info({"color_id": -1})
		else:
			NetworkManager.assign_player_color(pid, -1)
		return
	# 颜色不允许重复（静默回退）
	for other_pid in NetworkManager.players:
		if other_pid == pid:
			continue
		var other_color: int = int(NetworkManager.players[other_pid].get("color_id", -1))
		if other_color >= 0 and other_color == selected_color:
			var cur_color: int = int(NetworkManager.players.get(pid, {}).get("color_id", 0))
			var target_id := RANDOM_COLOR_OPTION_ID if cur_color < 0 else cur_color
			for i in range(color_option.item_count):
				if color_option.get_item_id(i) == target_id:
					color_option.select(i)
					break
			return
	if pid == NetworkManager.peer_id:
		NetworkManager.set_player_info({"color_id": selected_color})
	else:
		NetworkManager.assign_player_color(pid, selected_color)

func _on_spawn_selected(index: int, pid: int, spawn_option: OptionButton) -> void:
	var selected_id := spawn_option.get_item_id(index)
	var new_slot := -1 if selected_id == RANDOM_SPAWN_OPTION_ID else selected_id
	if new_slot < 0:
		# 随机位置允许重复
		if pid == NetworkManager.peer_id:
			NetworkManager.set_player_info({"spawn_slot": -1})
		else:
			NetworkManager.assign_player_spawn(pid, -1)
		return
	# 不允许选择已被其他玩家占用的位置
	for other_pid in NetworkManager.players:
		if other_pid == pid:
			continue
		var other_slot: int = int(NetworkManager.players[other_pid].get("spawn_slot", -1))
		if other_slot >= 0 and other_slot == new_slot:
			var cur_slot: int = int(NetworkManager.players.get(pid, {}).get("spawn_slot", 0))
			var target_id := RANDOM_SPAWN_OPTION_ID if cur_slot < 0 else cur_slot
			for i in range(spawn_option.item_count):
				if spawn_option.get_item_id(i) == target_id:
					spawn_option.select(i)
					break
			return
	if pid == NetworkManager.peer_id:
		NetworkManager.set_player_info({"spawn_slot": new_slot})
	else:
		# 主机为其他玩家分配出生位置
		NetworkManager.assign_player_spawn(pid, new_slot)

func _on_fog_mode_selected(index: int) -> void:
	_selected_fog_mode = _fog_mode_option.get_item_id(index)
	_save_settings()
	# 主机实时广播设置给所有客户端
	if NetworkManager.role == NetworkManager.Role.SERVER:
		NetworkManager.broadcast_lobby_config({"fog_mode": _selected_fog_mode})

func _on_speed_selected(index: int) -> void:
	_selected_game_speed_index = _speed_option.get_item_id(index)
	_save_settings()
	if NetworkManager.role == NetworkManager.Role.SERVER:
		NetworkManager.broadcast_lobby_config({"game_speed_index": _selected_game_speed_index})

func _on_starting_minerals_changed(value: float) -> void:
	_selected_starting_minerals = int(value)
	_save_settings()
	if NetworkManager.role == NetworkManager.Role.SERVER:
		NetworkManager.broadcast_lobby_config({"starting_minerals": _selected_starting_minerals})

func _on_starting_energy_changed(value: float) -> void:
	_selected_starting_energy = int(value)
	_save_settings()
	if NetworkManager.role == NetworkManager.Role.SERVER:
		NetworkManager.broadcast_lobby_config({"starting_energy": _selected_starting_energy})

func _on_lobby_config_updated(config: Dictionary) -> void:
	if config.has("fog_mode"):
		var old_fog_mode := _selected_fog_mode
		_selected_fog_mode = config["fog_mode"]
		# 将下拉切到对应项
		for i in _fog_mode_option.item_count:
			if _fog_mode_option.get_item_id(i) == _selected_fog_mode:
				_fog_mode_option.selected = i
				break
		if not NetworkManager.role == NetworkManager.Role.SERVER and old_fog_mode != _selected_fog_mode:
			_add_system_message("[color=cyan][大厅设置] 迷雾模式已更新为: %s[/color]" % _fog_mode_option.get_item_text(_fog_mode_option.selected))
	if config.has("game_speed_index"):
		_selected_game_speed_index = int(config["game_speed_index"])
		for i in range(_speed_option.item_count):
			if _speed_option.get_item_id(i) == _selected_game_speed_index:
				_speed_option.selected = i
				break
	if config.has("starting_minerals"):
		_selected_starting_minerals = int(config["starting_minerals"])
		if _starting_minerals_spin:
			_starting_minerals_spin.value = _selected_starting_minerals
	if config.has("starting_energy"):
		_selected_starting_energy = int(config["starting_energy"])
		if _starting_energy_spin:
			_starting_energy_spin.value = _selected_starting_energy

func _on_faction_toggle() -> void:
	_selected_faction = 1 - _selected_faction
	_save_settings()
	if _selected_faction == 0:
		_faction_btn.text = "钢铁联盟 (蓝方)"
		var normal: StyleBoxFlat = _faction_btn.get_theme_stylebox("normal") as StyleBoxFlat
		if normal:
			normal.bg_color = Color(0.15, 0.3, 0.6)
	else:
		_faction_btn.text = "暗影科技 (红方)"
		var normal: StyleBoxFlat = _faction_btn.get_theme_stylebox("normal") as StyleBoxFlat
		if normal:
			normal.bg_color = Color(0.5, 0.15, 0.2)
	# 仅在已连接时同步阵营信息到网络
	if NetworkManager.is_connected:
		NetworkManager.set_player_info({"faction": _selected_faction})

func _on_back_pressed() -> void:
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")

func _on_chat_submit(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	NetworkManager.send_chat(text)
	_chat_input.text = ""
	_chat_input.grab_focus()

## ====== 网络回调 ======

func _on_connected() -> void:
	_status_label.text = "已连接到服务器"
	_status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	_ready_btn.disabled = false
	_fog_mode_option.disabled = true  # 客户端不可修改
	_speed_option.disabled = true
	_starting_minerals_spin.editable = false
	_starting_energy_spin.editable = false
	NetworkManager.set_player_info({"name": _name_input.text, "faction": _selected_faction})
	_add_system_message("成功连接到服务器!")
	_refresh_player_list()

func _on_disconnected() -> void:
	_status_label.text = "已断开连接"
	_status_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	_host_btn.disabled = false
	_join_btn.disabled = false
	_ready_btn.disabled = true
	_start_btn.visible = false
	_is_ready = false
	_ready_btn.text = "准备"
	_add_system_message("[color=red]与服务器断开连接[/color]")
	_refresh_player_list()

func _on_connection_failed() -> void:
	_status_label.text = "连接失败!"
	_status_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	_host_btn.disabled = false
	_join_btn.disabled = false
	_add_system_message("[color=red]无法连接到服务器，请检查 IP 和端口[/color]")

func _on_player_joined(p_peer_id: int, info: Dictionary) -> void:
	var pname: String = info.get("name", "Player_%d" % p_peer_id)
	_add_system_message("[color=cyan]%s 加入了房间[/color]" % pname)
	_refresh_player_list()
	_refresh_start_btn()

func _on_player_info_updated(_p_peer_id: int, _info: Dictionary) -> void:
	_refresh_player_list()
	_refresh_start_btn()

func _on_player_left(p_peer_id: int) -> void:
	var pname: String = NetworkManager.players.get(p_peer_id, {}).get("name", "Player_%d" % p_peer_id)
	_add_system_message("[color=yellow]%s 离开了房间[/color]" % pname)
	_refresh_player_list()
	_refresh_start_btn()

func _on_all_ready() -> void:
	_add_system_message("[color=green]所有玩家已准备就绪！[/color]")
	_refresh_start_btn()

## 实时更新开始按钮状态（灰色/可点击）
func _refresh_start_btn() -> void:
	if not _start_btn or not _start_btn.visible:
		return
	var player_count := NetworkManager.players.size()
	if player_count < 2:
		_start_btn.disabled = true
		return
	# 出生点重复时，禁止开始
	var used_spawns: Dictionary = {}
	for pid in NetworkManager.players:
		var spawn_slot: int = int(NetworkManager.players[pid].get("spawn_slot", 0))
		if spawn_slot < 0:
			continue  # 随机位置允许重复选择
		if used_spawns.has(spawn_slot):
			_start_btn.disabled = true
			return
		used_spawns[spawn_slot] = true
	for pid in NetworkManager.players:
		if pid == 1:
			continue  # 主机自动就绪
		if not NetworkManager.players[pid].get("ready", false):
			_start_btn.disabled = true
			return
	_start_btn.disabled = false

func _on_chat_received(sender_name: String, msg: String) -> void:
	_chat_log.append_text("[color=white][b]%s:[/b][/color] %s\n" % [sender_name, msg])

func _on_game_starting(config: Dictionary) -> void:
	_add_system_message("[color=lime]游戏即将开始...[/color]")
	# 延迟一帧后切换场景，确保消息发送完毕
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://scenes/game/GameWorld.tscn")

## ====== 辅助方法 ======

func _add_system_message(bbcode_text: String) -> void:
	_chat_log.append_text("[color=gray][系统][/color] %s\n" % bbcode_text)

func _refresh_player_list() -> void:
	# 清除旧条目
	for child in _player_list.get_children():
		child.queue_free()

	var players := NetworkManager.players
	if players.is_empty():
		var empty_lbl := _create_label("暂无玩家")
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_player_list.add_child(empty_lbl)
		return

	for pid in players:
		var info: Dictionary = players[pid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		# 阵营色块
		var color_idx: int = int(info.get("color_id", 0))
		var palette: Array[Color] = [Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.3), Color(0.2, 0.85, 0.35), Color(1.0, 0.82, 0.1)]
		var faction_color: Color = palette[posmod(color_idx, palette.size())]
		var color_rect := ColorRect.new()
		color_rect.color = faction_color
		color_rect.custom_minimum_size = Vector2(12, 12)
		row.add_child(color_rect)

		# 玩家名
		var name_label := Label.new()
		var pname: String = info.get("name", "Player_%d" % pid)
		name_label.text = pname
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		row.add_child(name_label)

		# 队伍/位置（下拉选择：本人或主机可改）
		var cur_team: int = int(info.get("team_id", 0))
		var cur_spawn: int = int(info.get("spawn_slot", 0))
		var cur_faction: int = int(info.get("faction", 0))
		var cur_color_id: int = int(info.get("color_id", 0))
		var team_colors: Array = [
			Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.3), Color(0.2, 0.85, 0.35), Color(1.0, 0.82, 0.1),
			Color(0.1, 0.85, 0.9), Color(0.7, 0.2, 0.9), Color(0.95, 0.5, 0.1), Color(0.9, 0.9, 0.9)
		]
		var tc: Color = team_colors[posmod(cur_color_id, team_colors.size())]
		var can_edit: bool = (pid == NetworkManager.peer_id) or (NetworkManager.peer_id == 1)
		if can_edit:
			var team_option := OptionButton.new()
			var max_teams := mini(8, maxi(2, NetworkManager.players.size()))
			for t in range(max_teams):
				team_option.add_item("队伍 %d" % (t + 1), t)
			for i in range(team_option.item_count):
				if team_option.get_item_id(i) == cur_team:
					team_option.select(i)
					break
			team_option.custom_minimum_size = Vector2(90, 28)
			team_option.item_selected.connect(_on_team_selected.bind(pid, team_option))
			row.add_child(team_option)

			var faction_option := OptionButton.new()
			faction_option.add_item("钢铁联盟", GameConstants.Faction.STEEL_ALLIANCE)
			faction_option.add_item("暗影科技", GameConstants.Faction.SHADOW_TECH)
			for i in range(faction_option.item_count):
				if faction_option.get_item_id(i) == cur_faction:
					faction_option.select(i)
					break
			faction_option.custom_minimum_size = Vector2(92, 28)
			faction_option.item_selected.connect(_on_faction_selected.bind(pid, faction_option))
			row.add_child(faction_option)

			var color_option := OptionButton.new()
			color_option.add_item("随机颜色", RANDOM_COLOR_OPTION_ID)
			for opt in PLAYER_COLOR_OPTIONS:
				color_option.add_item(opt["name"], opt["id"])
			var selected_color_id := RANDOM_COLOR_OPTION_ID if cur_color_id < 0 else cur_color_id
			for i in range(color_option.item_count):
				if color_option.get_item_id(i) == selected_color_id:
					color_option.select(i)
					break
			color_option.custom_minimum_size = Vector2(80, 28)
			color_option.item_selected.connect(_on_color_selected.bind(pid, color_option))
			row.add_child(color_option)

			var spawn_option := OptionButton.new()
			spawn_option.add_item("随机位置", RANDOM_SPAWN_OPTION_ID)
			var _spawn_names := ["1-左上角", "2-上中", "3-右上角", "4-左中", "5-右中", "6-左下角", "7-下中", "8-右下角"]
			for s in range(8):
				spawn_option.add_item(_spawn_names[s], s)
			var selected_spawn_id := RANDOM_SPAWN_OPTION_ID if cur_spawn < 0 else cur_spawn
			for i in range(spawn_option.item_count):
				if spawn_option.get_item_id(i) == selected_spawn_id:
					spawn_option.select(i)
					break
			spawn_option.custom_minimum_size = Vector2(90, 28)
			spawn_option.item_selected.connect(_on_spawn_selected.bind(pid, spawn_option))
			row.add_child(spawn_option)
		else:
			var team_label := Label.new()
			var _spawn_label_names: Array[String] = ["1-左上角", "2-上中", "3-右上角", "4-左中", "5-右中", "6-左下角", "7-下中", "8-右下角"]
			var pos_text: String = "随机" if cur_spawn < 0 else _spawn_label_names[clampi(cur_spawn, 0, 7)]
			var fac_text := "钢铁" if cur_faction == GameConstants.Faction.STEEL_ALLIANCE else "暗影"
			var _color_names: Array[String] = ["蓝", "红", "绿", "黄", "青", "紫", "橙", "白"]
			var color_text: String = "随机" if cur_color_id < 0 else _color_names[clampi(cur_color_id, 0, 7)]
			team_label.text = "队伍 %d / %s / %s / %s" % [cur_team + 1, fac_text, color_text, pos_text]
			team_label.add_theme_font_size_override("font_size", 13)
			team_label.add_theme_color_override("font_color", tc)
			row.add_child(team_label)

		# 准备状态 (主机显示房主标识)
		var ready_label := Label.new()
		if pid == 1:
			ready_label.text = "👑 房主"
			ready_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		elif info.get("ready", false):
			ready_label.text = "✓ 已准备"
			ready_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		else:
			ready_label.text = "未准备"
			ready_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.3))
		ready_label.add_theme_font_size_override("font_size", 13)
		row.add_child(ready_label)

		_player_list.add_child(row)

## ====== 设置持久化 ======

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 先加载已有内容, 避免覆盖 MainMenu 的设置
	cfg.set_value("game", "fog_mode", _selected_fog_mode)
	cfg.set_value("game", "game_speed_index", _selected_game_speed_index)
	cfg.set_value("game", "starting_minerals", _selected_starting_minerals)
	cfg.set_value("game", "starting_energy", _selected_starting_energy)
	cfg.set_value("lobby", "player_name", _name_input.text if _name_input else _saved_player_name)
	cfg.set_value("lobby", "ip", _ip_input.text if _ip_input else _saved_ip)
	cfg.set_value("lobby", "port", _port_input.text if _port_input else _saved_port)
	cfg.set_value("lobby", "faction", _selected_faction)
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_selected_fog_mode = cfg.get_value("game", "fog_mode", _selected_fog_mode)
	_selected_game_speed_index = cfg.get_value("game", "game_speed_index", _selected_game_speed_index)
	_selected_starting_minerals = cfg.get_value("game", "starting_minerals", _selected_starting_minerals)
	_selected_starting_energy = cfg.get_value("game", "starting_energy", _selected_starting_energy)
	_saved_player_name = cfg.get_value("lobby", "player_name", _saved_player_name)
	_saved_ip = cfg.get_value("lobby", "ip", _saved_ip)
	_saved_port = cfg.get_value("lobby", "port", _saved_port)
	_selected_faction = cfg.get_value("lobby", "faction", _selected_faction)
