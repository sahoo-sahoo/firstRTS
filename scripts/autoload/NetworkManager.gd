## NetworkManager - 网络连接与指令同步 (Autoload)
## Lockstep 架构：所有客户端发送指令，服务器收集后统一广播
extends Node

signal connected_to_server
signal disconnected_from_server
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal player_info_updated(peer_id: int, player_info: Dictionary)
signal game_command_received(tick: int, commands: Array)
signal all_players_ready
signal chat_message_received(sender_name: String, message: String)
signal game_chat_received(sender_id: int, sender_name: String, channel: String, message: String)
signal game_starting(config: Dictionary)
signal player_surrendered(peer_id: int, team_id: int)
signal game_pause_requested(by_peer: int)
signal game_resume_requested(by_peer: int)
signal connection_failed_signal
signal lobby_config_updated(config: Dictionary)
signal game_speed_changed(speed_index: int, speed_label: String)

## 大厅设置 (主机维护, 同步给客户端)
var lobby_config: Dictionary = {
	"fog_mode": 0,
	"game_speed_index": 4,
	"starting_minerals": 400,
	"starting_energy": 200,
}

## 网络角色
enum Role { NONE, SERVER, CLIENT }
var role: Role = Role.NONE

## 当前连接状态
var is_connected: bool = false
var peer_id: int = 0

## 游戏是否已开始 (防止大厅中跑 tick 循环)
var is_game_active: bool = false

## 是否真正的联机 (区分单机离线)
var is_online: bool = false

## 玩家信息 {peer_id: {name, team_id, spawn_slot, faction, color_id, ready}}
var players: Dictionary = {}

## 游戏配置 (开始游戏时由服务器设定)
var game_config: Dictionary = {}

## Lockstep 相关
var current_tick: int = 0
var _command_buffer: Dictionary = {}  # {tick: {peer_id: [commands]}}
var _local_commands: Array = []       # 本帧累积的本地指令
var _tick_interval: float = 0.05      # 50ms per tick = 20 ticks/sec
var _tick_timer: float = 0.0
var _input_delay: int = 2             # 输入延迟帧数 (平滑)
var _players_game_ready: Dictionary = {}  # 游戏场景加载确认

## 游戏速度 (仅离线对战可调)
const DEFAULT_TICK_INTERVAL: float = 0.05
const GAME_SPEED_PRESETS: Array = [0.5, 1.0, 1.5, 2.0, -1.0]  # -1.0 = 不限速
var _game_speed_index: int = 1

## 连接参数
var _server_ip: String = "127.0.0.1"
var _server_port: int = 7777
var _max_players: int = 8

func _pick_random_available_color(exclude_peer_id: int = -1) -> int:
	var palette := [0, 1, 2, 3, 4, 5, 6, 7]
	var used: Dictionary = {}
	for pid in players:
		if int(pid) == exclude_peer_id:
			continue
		var color_id: int = int(players[pid].get("color_id", -1))
		if color_id >= 0:
			used[color_id] = true
	var available: Array = []
	for color_id in palette:
		if not used.has(color_id):
			available.append(color_id)
	if available.is_empty():
		return palette[randi() % palette.size()]
	return int(available[randi() % available.size()])

func _pick_available_spawn_slot(preferred: int) -> int:
	var used: Dictionary = {}
	for pid in players:
		var slot: int = int(players[pid].get("spawn_slot", -1))
		if slot >= 0:
			used[slot] = true
	if not used.has(preferred):
		return preferred
	for s in range(8):
		if not used.has(s):
			return s
	return preferred  # 全部占满则回退

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)

func _process(delta: float) -> void:
	if not is_game_active:
		return

	if _tick_interval <= 0.0:
		_process_tick()
		return

	_tick_timer += delta
	while _tick_timer >= _tick_interval:
		_tick_timer -= _tick_interval
		_process_tick()

func can_adjust_game_speed() -> bool:
	return not is_online

func get_game_speed_count() -> int:
	return GAME_SPEED_PRESETS.size()

func get_game_speed_index() -> int:
	return _game_speed_index

func get_game_speed_label(index: int = -1) -> String:
	var idx := _game_speed_index if index < 0 else clampi(index, 0, GAME_SPEED_PRESETS.size() - 1)
	if idx == GAME_SPEED_PRESETS.size() - 1:
		return "∞"
	return "%.1fx" % float(GAME_SPEED_PRESETS[idx])

func set_game_speed_index(index: int) -> bool:
	if not can_adjust_game_speed():
		return false
	_game_speed_index = clampi(index, 0, GAME_SPEED_PRESETS.size() - 1)
	_apply_game_speed()
	return true

func adjust_game_speed(step: int) -> bool:
	if not can_adjust_game_speed():
		return false
	var next_idx := clampi(_game_speed_index + step, 0, GAME_SPEED_PRESETS.size() - 1)
	if next_idx == _game_speed_index:
		return false
	_game_speed_index = next_idx
	_apply_game_speed()
	return true

func reset_game_speed() -> void:
	_game_speed_index = 1
	_apply_game_speed()

func _apply_game_speed() -> void:
	if _game_speed_index == GAME_SPEED_PRESETS.size() - 1:
		_tick_interval = 0.0
	else:
		var scale: float = float(GAME_SPEED_PRESETS[_game_speed_index])
		_tick_interval = DEFAULT_TICK_INTERVAL / scale
	_tick_timer = 0.0
	game_speed_changed.emit(_game_speed_index, get_game_speed_label())

## ====== 公共接口 ======

## 获取局域网 IP（过滤 127.x 和 IPv6）
func get_local_lan_ip() -> String:
	var addresses := IP.get_local_addresses()
	for addr in addresses:
		# 只要 192.168.x.x 、 10.x.x.x 、1 72.16-31.x.x 等私有地址
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
		if addr.begins_with("172."):
			var parts := addr.split(".")
			if parts.size() >= 2:
				var second := int(parts[1])
				if second >= 16 and second <= 31:
					return addr
	# 实验性：可能是隔离网络，返回第一个非回环地址
	for addr in addresses:
		if not ":" in addr and addr != "127.0.0.1":
			return addr
	return "127.0.0.1"

## 创建服务器
func host_game(port: int = 7777, max_players: int = 8) -> Error:
	_server_port = port
	_max_players = max_players
	
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		push_error("NetworkManager: Failed to create server: %s" % error_string(err))
		return err
	
	multiplayer.multiplayer_peer = peer
	role = Role.SERVER
	is_connected = true
	is_online = true
	peer_id = 1
	
	# 尝试添加 Windows 防火墙放行规则（局域网端口放行）
	_add_firewall_rule(port)
	
	# 服务器自身也是玩家 (主机自动准备)
	players[1] = {"name": "Host", "team_id": 0, "spawn_slot": 0, "faction": 0, "color_id": _pick_random_available_color(), "ready": true}
	
	print("NetworkManager: Server started on port %d, LAN IP: %s" % [port, get_local_lan_ip()])
	return OK

## 尝试添加 Windows 防火墙放行入站规则
func _add_firewall_rule(port: int) -> void:
	if OS.get_name() != "Windows":
		return
	var rule_name := "firstRTS_port_%d" % port
	# 先尝试删除旧规则，再新建（静默失败不报错）
	OS.execute("netsh", [
		"advfirewall", "firewall", "delete", "rule",
		"name=" + rule_name
	], [], false)
	# 添加 UDP 放行（ENet 使用 UDP）
	var result_udp := OS.execute("netsh", [
		"advfirewall", "firewall", "add", "rule",
		"name=" + rule_name,
		"dir=in",
		"action=allow",
		"protocol=UDP",
		"localport=" + str(port),
		"profile=private,domain"
	], [], false)
	# 添加 TCP 放行
	var result_tcp := OS.execute("netsh", [
		"advfirewall", "firewall", "add", "rule",
		"name=" + rule_name + "_tcp",
		"dir=in",
		"action=allow",
		"protocol=TCP",
		"localport=" + str(port),
		"profile=private,domain"
	], [], false)
	print("NetworkManager: Firewall rule added for port %d (UDP=%d, TCP=%d)" % [port, result_udp, result_tcp])

## 加入服务器
func join_game(ip: String = "127.0.0.1", port: int = 7777) -> Error:
	_server_ip = ip
	_server_port = port
	
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("NetworkManager: Failed to connect: %s" % error_string(err))
		return err
	
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	is_online = true
	
	print("NetworkManager: Connecting to %s:%d" % [ip, port])
	return OK

## 断开连接
func disconnect_game() -> void:
	multiplayer.multiplayer_peer = null
	role = Role.NONE
	is_connected = false
	is_game_active = false
	is_online = false
	players.clear()
	_command_buffer.clear()
	_local_commands.clear()
	current_tick = 0
	_tick_timer = 0.0

## 发送游戏指令 (本地调用)
func send_command(command: Dictionary) -> void:
	command["peer_id"] = peer_id
	if is_online:
		command["tick"] = current_tick + _input_delay
	else:
		command["tick"] = current_tick
	_local_commands.append(command)

## 设置玩家信息
func set_player_info(info: Dictionary) -> void:
	# 未分配 peer_id 时不操作 (防止产生 players[0] 幽灵条目)
	if peer_id == 0:
		return
	# 更新本地
	if players.has(peer_id):
		players[peer_id].merge(info, true)
	else:
		players[peer_id] = info
	# 只有已连接时才发 RPC
	if is_connected:
		_rpc_set_player_info.rpc(info)
	# 本地触发信息更新 (不是加入)
	player_info_updated.emit(peer_id, players[peer_id])

## 标记准备状态
func set_ready(ready: bool) -> void:
	# 本地更新
	if players.has(peer_id):
		players[peer_id]["ready"] = ready
	# 只有已连接时才发 RPC
	if is_connected:
		_rpc_set_ready.rpc(ready)
	# 本地检查
	_check_all_ready()

## 单机模式 (离线玩)
func start_offline() -> void:
	role = Role.SERVER
	is_connected = true
	is_game_active = false
	is_online = false
	peer_id = 1
	players[1] = {"name": "Player", "team_id": 0, "spawn_slot": 0, "faction": 0, "color_id": 0, "ready": true}

## ====== Lockstep 处理 ======

func _process_tick() -> void:
	# 处理本地指令
	if _local_commands.size() > 0:
		if role == Role.SERVER:
			# 服务器: 直接放入缓冲区
			for cmd in _local_commands:
				var tick: int = cmd.get("tick", current_tick)
				if not _command_buffer.has(tick):
					_command_buffer[tick] = {}
				if not _command_buffer[tick].has(peer_id):
					_command_buffer[tick][peer_id] = []
				_command_buffer[tick][peer_id].append(cmd)
		else:
			# 客户端: 发给服务器
			_rpc_submit_commands.rpc_id(1, _local_commands)
		_local_commands.clear()
	
	# 服务器：收集并广播
	if role == Role.SERVER:
		var tick_commands: Array = []
		if _command_buffer.has(current_tick):
			for pid in _command_buffer[current_tick]:
				tick_commands.append_array(_command_buffer[current_tick][pid])
			_command_buffer.erase(current_tick)
		
		if is_online:
			_rpc_execute_tick.rpc(current_tick, tick_commands)
		else:
			game_command_received.emit(current_tick, tick_commands)
	
	current_tick += 1

## ====== RPC 方法 ======

@rpc("any_peer", "reliable")
func _rpc_submit_commands(commands: Array) -> void:
	# 服务器端接收指令
	var sender := multiplayer.get_remote_sender_id()
	for cmd in commands:
		var tick: int = cmd.get("tick", current_tick)
		if not _command_buffer.has(tick):
			_command_buffer[tick] = {}
		if not _command_buffer[tick].has(sender):
			_command_buffer[tick][sender] = []
		_command_buffer[tick][sender].append(cmd)

@rpc("authority", "call_local", "reliable")
func _rpc_execute_tick(tick: int, commands: Array) -> void:
	# 所有客户端执行 (call_local 使主机也处理 tick)
	game_command_received.emit(tick, commands)

@rpc("any_peer", "reliable")
func _rpc_set_player_info(info: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var is_new: bool = (not players.has(sender)) or str(players[sender].get("name", "")).begins_with("Player_")
	# 服务器侧约束：颜色不允许重复
	if role == Role.SERVER and info.has("color_id"):
		var wanted_color := int(info.get("color_id", -1))
		if wanted_color >= 0:
			for pid in players:
				if int(pid) == sender:
					continue
				if int(players[pid].get("color_id", -1)) == wanted_color:
					info.erase("color_id")
					break
	if players.has(sender):
		players[sender].merge(info, true)
	else:
		players[sender] = info
	# 服务器: 首次收到真实昵称时发 player_joined，之后发 info_updated
	if role == Role.SERVER and is_new and info.has("name"):
		player_joined.emit(sender, players[sender])
	else:
		player_info_updated.emit(sender, players[sender])
	# 服务器: 收到玩家信息后广播完整列表给所有客户端
	if role == Role.SERVER:
		_rpc_sync_all_players.rpc(players)
		# 并将当前大厅设置发给新加入的玩家
		_rpc_lobby_config.rpc_id(sender, lobby_config)

@rpc("any_peer", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["ready"] = ready
	_check_all_ready()
	# 刷新 UI (信息更新，不是加入)
	player_info_updated.emit(sender, players.get(sender, {}))

func _check_all_ready() -> void:
	var all_ready := true
	for pid in players:
		# 主机 (pid==1) 自动准备，不检查
		if pid == 1:
			continue
		if not players[pid].get("ready", false):
			all_ready = false
			break
	if all_ready and players.size() >= 2:
		all_players_ready.emit()

## ====== 连接回调 ======

func _on_peer_connected(id: int) -> void:
	print("NetworkManager: Peer connected: %d" % id)
	if role == Role.SERVER:
		# 服务器: 先创建条目占位 (team_id 根据人数分配)，但不发 player_joined
		# 等 _rpc_set_player_info 收到真实昵称后再通知 UI
		var next_index := players.size()
		var team_id := next_index
		var spawn_slot := _pick_available_spawn_slot(next_index)
		players[id] = {"name": "Player_%d" % id, "team_id": team_id, "spawn_slot": spawn_slot, "faction": 0, "color_id": _pick_random_available_color(), "ready": false}
	# 客户端: 不创建 players 条目，等 _rpc_sync_all_players 统一同步

@rpc("authority", "reliable")
func _rpc_sync_all_players(all_players: Dictionary) -> void:
	var old_ids := players.keys()
	players = all_players
	# 新加入的 peer 发 player_joined，已有的发 info_updated
	for pid in players:
		if pid not in old_ids:
			player_joined.emit(pid, players[pid])
		else:
			player_info_updated.emit(pid, players[pid])

func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: Peer disconnected: %d" % id)
	# 游戏进行中断线: 服务器广播该玩家弃权 (在 erase 前捕获 team_id)
	if is_game_active and role == Role.SERVER and players.has(id):
		var team_id: int = players[id].get("team_id", -1)
		if team_id >= 0:
			_rpc_surrender.rpc(id, team_id)
	players.erase(id)
	player_left.emit(id)

func _on_connected_to_server() -> void:
	is_connected = true
	peer_id = multiplayer.get_unique_id()
	print("NetworkManager: Connected to server as peer %d" % peer_id)
	connected_to_server.emit()

func _on_server_disconnected() -> void:
	is_connected = false
	is_game_active = false
	is_online = false
	role = Role.NONE
	print("NetworkManager: Disconnected from server")
	disconnected_from_server.emit()

func _on_connection_failed() -> void:
	is_connected = false
	role = Role.NONE
	multiplayer.multiplayer_peer = null
	print("NetworkManager: Connection failed")
	connection_failed_signal.emit()

## ====== 聊天 ======

func send_chat(msg: String) -> void:
	var sender_name: String = players.get(peer_id, {}).get("name", "Unknown")
	_rpc_chat.rpc(sender_name, msg)
	# 本地也显示 (rpc 默认不 call_local)
	chat_message_received.emit(sender_name, msg)

@rpc("any_peer", "reliable")
func _rpc_chat(sender_name: String, msg: String) -> void:
	chat_message_received.emit(sender_name, msg)

## ====== 游戏内聊天 (支持频道) ======

## channel: "all" = 全体, "team" = 队友, "whisper:peer_id" = 私聊
func send_game_chat(msg: String, channel: String = "all") -> void:
	var sender_name: String = players.get(peer_id, {}).get("name", "Player")
	var sender_team: int = players.get(peer_id, {}).get("team_id", 0)
	if msg.strip_edges().is_empty():
		return
	send_command({
		"type": "chat",
		"sender_id": peer_id,
		"sender_name": sender_name,
		"team_id": sender_team,
		"channel": channel,
		"message": msg,
	})

@rpc("any_peer", "reliable")
func _rpc_game_chat(sender_id: int, sender_name: String, channel: String, msg: String) -> void:
	game_chat_received.emit(sender_id, sender_name, channel, msg)

## ====== 大厅设置同步 ======

## 主机调用: 将当前大厅设置广播给所有客户端
func broadcast_lobby_config(config: Dictionary) -> void:
	if role != Role.SERVER:
		return
	lobby_config.merge(config, true)
	_rpc_lobby_config.rpc(lobby_config)

@rpc("authority", "call_local", "reliable")
func _rpc_lobby_config(config: Dictionary) -> void:
	lobby_config = config
	lobby_config_updated.emit(config)

## ====== 投降 ======

func surrender() -> void:
	var team_id: int = players.get(peer_id, {}).get("team_id", 0)
	_rpc_surrender.rpc(peer_id, team_id)

@rpc("any_peer", "call_local", "reliable")
func _rpc_surrender(surrendering_peer: int, team_id: int) -> void:
	player_surrendered.emit(surrendering_peer, team_id)

## ====== 暂停 ======

func request_pause() -> void:
	_rpc_pause.rpc(peer_id)

func request_resume() -> void:
	_rpc_resume.rpc(peer_id)

@rpc("any_peer", "call_local", "reliable")
func _rpc_pause(by_peer: int) -> void:
	game_pause_requested.emit(by_peer)

@rpc("any_peer", "call_local", "reliable")
func _rpc_resume(by_peer: int) -> void:
	game_resume_requested.emit(by_peer)

## ====== 大厅队伍管理 ======

## 主机专用: 修改任意玩家的队伍 ID 并广播
func assign_player_team(target_peer_id: int, team_id: int) -> void:
	if role != Role.SERVER:
		return
	if players.has(target_peer_id):
		players[target_peer_id]["team_id"] = team_id
	_rpc_sync_all_players.rpc(players)
	player_info_updated.emit(target_peer_id, players.get(target_peer_id, {}))

## 主机专用: 修改任意玩家的阵营并广播
func assign_player_faction(target_peer_id: int, faction_id: int) -> void:
	if role != Role.SERVER:
		return
	if players.has(target_peer_id):
		players[target_peer_id]["faction"] = faction_id
	_rpc_sync_all_players.rpc(players)
	player_info_updated.emit(target_peer_id, players.get(target_peer_id, {}))

## 主机专用: 修改任意玩家颜色并广播 (颜色不可重复)
func assign_player_color(target_peer_id: int, color_id: int) -> bool:
	if role != Role.SERVER:
		return false
	if not players.has(target_peer_id):
		return false
	if color_id >= 0:
		for pid in players:
			if int(pid) == target_peer_id:
				continue
			if int(players[pid].get("color_id", -1)) == color_id:
				return false
		players[target_peer_id]["color_id"] = color_id
	else:
		players[target_peer_id]["color_id"] = -1
	_rpc_sync_all_players.rpc(players)
	player_info_updated.emit(target_peer_id, players.get(target_peer_id, {}))
	return true

## 主机专用: 修改任意玩家的出生位置并广播
func assign_player_spawn(target_peer_id: int, spawn_slot: int) -> void:
	if role != Role.SERVER:
		return
	if players.has(target_peer_id):
		players[target_peer_id]["spawn_slot"] = -1 if spawn_slot < 0 else clampi(spawn_slot, 0, 3)
	_rpc_sync_all_players.rpc(players)
	player_info_updated.emit(target_peer_id, players.get(target_peer_id, {}))

## ====== 开始游戏广播 ======

func broadcast_game_start(config: Dictionary = {}) -> void:
	if role != Role.SERVER:
		return
	_rpc_game_start.rpc(config)

@rpc("authority", "call_local", "reliable")
func _rpc_game_start(config: Dictionary) -> void:
	is_game_active = false
	current_tick = 0
	_tick_timer = 0.0
	_command_buffer.clear()
	_local_commands.clear()
	_players_game_ready.clear()
	game_config = config
	var cfg_speed_index: int = int(config.get("game_speed_index", _game_speed_index))
	_game_speed_index = clampi(cfg_speed_index, 0, GAME_SPEED_PRESETS.size() - 1)
	_apply_game_speed()
	game_starting.emit(config)

## 游戏场景加载完成确认
func confirm_game_ready() -> void:
	if not is_online:
		is_game_active = true
		return
	if role == Role.SERVER:
		_players_game_ready[peer_id] = true
		_check_all_game_ready()
	else:
		_rpc_confirm_game_ready.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_confirm_game_ready() -> void:
	var sender := multiplayer.get_remote_sender_id()
	_players_game_ready[sender] = true
	_check_all_game_ready()

func _check_all_game_ready() -> void:
	for pid in players:
		if not _players_game_ready.get(pid, false):
			return
	_rpc_start_simulation.rpc()

@rpc("authority", "call_local", "reliable")
func _rpc_start_simulation() -> void:
	is_game_active = true
	current_tick = 0
	_tick_timer = 0.0
