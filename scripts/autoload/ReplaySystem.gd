## ReplaySystem - 录像录制与回放 (Autoload)
## 利用 Lockstep 确定性架构: 只需记录初始配置 + 每 tick 的指令即可完整回放
extends Node

signal replay_tick_advanced(tick: int, total_ticks: int)
signal replay_finished
signal replay_speed_changed(speed: float)
signal replay_action_logged(tick: int, action_text: String)

## 录像数据结构
## {
##   "version": 2,
##   "date": "2026-02-27 15:30:00",
##   "duration_ticks": 12000,
##   "game_config": { map_seed, ... },
##   "players": { peer_id: {name, team_id, faction} },
##   "tick_data": { "0": [...cmds], "5": [...cmds], ... }  (只存有指令的 tick)
##   "camera_data": { "0": {peer_id: {x,y,zoom}}, ... }  玩家镜头数据
##   "stats_data": { "0": {team_id: {minerals, energy, unit_count, building_count, production_queue_size}}, ... }
## }

## 模式
enum Mode { NONE, RECORDING, PLAYING }
var mode: Mode = Mode.NONE

## 录制相关
var _record_data: Dictionary = {}
var _record_tick_data: Dictionary = {}  # tick -> commands
var _record_camera_data: Dictionary = {}  # tick -> {peer_id: {x, y, zoom}}
var _record_stats_data: Dictionary = {}  # tick -> {team_id: stats}

## 回放相关
var _replay_data: Dictionary = {}
var _replay_tick_data: Dictionary = {}
var _replay_camera_data: Dictionary = {}  # tick -> {peer_id: {x, y, zoom}}
var _replay_stats_data: Dictionary = {}  # tick -> {team_id: stats}
var _replay_current_tick: int = 0
var _replay_total_ticks: int = 0
var _replay_timer: float = 0.0
var _replay_paused: bool = false
var _replay_speed: float = 1.0
var _replay_tick_interval: float = 0.05

## 回放时的观战队伍 (控制迷雾)
var replay_view_team: int = -1  # -1 = 全图无迷雾

## 回放镜头模式
enum CameraMode { FREE, FOLLOW_PLAYER }
var replay_camera_mode: CameraMode = CameraMode.FREE
var replay_follow_peer_id: int = -1  # 跟随的玩家 peer_id

## 回放时最近一次各队伍的统计快照 (用于 HUD 实时显示)
var current_stats_snapshot: Dictionary = {}  # {team_id: {minerals, energy, unit_count, building_count, ...}}

## 回放操作日志 (最近 N 条)
var action_log: Array = []  # [{tick, text}]
const MAX_ACTION_LOG := 50

## 当前正在播放的录像路径
var _current_replay_path: String = ""

## 录像文件目录
const REPLAY_DIR := "user://replays/"
const REPLAY_EXTENSION := ".replay"
const REPLAY_TEMP_EXTENSION := ".replay.tmp"

## 实时保存：临时文件路径 + 刷新计数
var _temp_path: String = ""
var _dirty_ticks: int = 0
const FLUSH_INTERVAL_TICKS: int = 300  # 每 300 tick (~15 秒) 刷一次磁盘

func _ready() -> void:
	# 确保录像目录存在
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	# 崩溃恢复：将上次未正常结束的 .tmp 重命名为 .replay 供列表展示
	_recover_crashed_replays()

func _process(delta: float) -> void:
	if mode != Mode.PLAYING or _replay_paused:
		return
	
	_replay_timer += delta * _replay_speed
	while _replay_timer >= _replay_tick_interval and _replay_current_tick <= _replay_total_ticks:
		_replay_timer -= _replay_tick_interval
		_advance_replay_tick()

## ====== 录制 API ======

## 开始录制 (游戏开始时调用)
func start_recording(game_config: Dictionary, players_info: Dictionary) -> void:
	mode = Mode.RECORDING
	_record_tick_data = {}
	_record_camera_data = {}
	_record_stats_data = {}
	_dirty_ticks = 0
	_record_data = {
		"version": 2,
		"date": Time.get_datetime_string_from_system(),
		"duration_ticks": 0,
		"game_config": game_config.duplicate(true),
		"players": players_info.duplicate(true),
		"tick_data": {},
		"camera_data": {},
		"stats_data": {},
	}
	# 生成临时文件路径（与最终文件同名但加 .tmp 后缀）
	var dt := Time.get_datetime_dict_from_system()
	var basename := "replay_%04d%02d%02d_%02d%02d%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"],
	]
	_temp_path = REPLAY_DIR + basename + REPLAY_TEMP_EXTENSION
	# 立即写一次临时文件（哪怕是空录像头，也保证文件存在）
	_flush_to_temp()
	print("ReplaySystem: Recording started, temp file: %s" % _temp_path)

## 记录一个 tick 的指令 (由 GameWorld 在 _on_game_command 时调用)
func record_tick(tick: int, commands: Array) -> void:
	if mode != Mode.RECORDING:
		return
	if commands.size() > 0:
		# 深拷贝指令, 移除不必要的数据以减小文件大小
		var clean_cmds: Array = []
		for cmd in commands:
			var c: Dictionary = cmd.duplicate(true)
			# Vector2 需要转为可序列化格式
			for key in c:
				if c[key] is Vector2:
					c[key] = {"_v2": true, "x": c[key].x, "y": c[key].y}
			clean_cmds.append(c)
		_record_tick_data[tick] = clean_cmds
	_record_data["duration_ticks"] = tick
	# 定期刷新到临时文件
	_dirty_ticks += 1
	if _dirty_ticks >= FLUSH_INTERVAL_TICKS:
		_flush_to_temp()
		_dirty_ticks = 0

## 记录镜头数据 (由 GameWorld 每 tick 调用)
func record_camera(tick: int, peer_id: int, cam_pos: Vector2, cam_zoom: float) -> void:
	if mode != Mode.RECORDING:
		return
	if not _record_camera_data.has(tick):
		_record_camera_data[tick] = {}
	_record_camera_data[tick][peer_id] = {
		"x": cam_pos.x,
		"y": cam_pos.y,
		"zoom": cam_zoom,
	}

## 记录玩家统计快照 (由 GameWorld 每隔若干 tick 调用)
func record_stats(tick: int, team_stats: Dictionary) -> void:
	if mode != Mode.RECORDING:
		return
	# team_stats = {team_id: {minerals, energy, unit_count, building_count, production_queue_size}}
	var serializable: Dictionary = {}
	for team_id in team_stats:
		serializable[team_id] = team_stats[team_id].duplicate(true)
	_record_stats_data[tick] = serializable

## 将当前录像数据刷新写入临时文件
func _flush_to_temp() -> void:
	if _temp_path == "":
		return
	_record_data["tick_data"] = _record_tick_data
	_record_data["camera_data"] = _record_camera_data
	_record_data["stats_data"] = _record_stats_data
	var json_str := JSON.stringify(_record_data)
	var file := FileAccess.open(_temp_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
	else:
		push_warning("ReplaySystem: Failed to flush temp replay to %s" % _temp_path)

## 停止录制并保存
func stop_recording() -> String:
	if mode != Mode.RECORDING:
		return ""
	mode = Mode.NONE
	
	# 将 tick_data, camera_data, stats_data 合并进去
	_record_data["tick_data"] = _record_tick_data
	_record_data["camera_data"] = _record_camera_data
	_record_data["stats_data"] = _record_stats_data
	
	# 正式文件名：把临时文件的 .tmp 后缀替换为 .replay
	var path := _temp_path.replace(REPLAY_TEMP_EXTENSION, REPLAY_EXTENSION)
	
	# 写入正式文件
	var json_str := JSON.stringify(_record_data)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		print("ReplaySystem: Replay saved to %s (%d ticks)" % [path, _record_data["duration_ticks"]])
		# 删除临时文件
		if _temp_path != "" and FileAccess.file_exists(_temp_path):
			DirAccess.remove_absolute(_temp_path)
		_temp_path = ""
		_record_data.clear()
		_record_tick_data.clear()
		_record_camera_data.clear()
		_record_stats_data.clear()
		return path
	else:
		push_error("ReplaySystem: Failed to save replay to %s" % path)
		return ""

## ====== 回放 API ======

## 崩溃恢复：将上次游戏崩溃遗留的 .tmp 文件重命名为 .replay
func _recover_crashed_replays() -> void:
	var dir := DirAccess.open(REPLAY_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(REPLAY_TEMP_EXTENSION):
			var tmp_path := REPLAY_DIR + file_name
			var recovered_path := tmp_path.replace(REPLAY_TEMP_EXTENSION, REPLAY_EXTENSION)
			# 用 DirAccess.rename 重命名
			var d := DirAccess.open(REPLAY_DIR)
			if d:
				d.rename(file_name, file_name.replace(REPLAY_TEMP_EXTENSION, REPLAY_EXTENSION))
				print("ReplaySystem: Recovered crashed replay: %s" % recovered_path)
		file_name = dir.get_next()
	dir.list_dir_end()

## 列出所有录像文件
func list_replays() -> Array:
	var replays: Array = []
	var dir := DirAccess.open(REPLAY_DIR)
	if dir == null:
		return replays
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(REPLAY_EXTENSION):
			var info := _read_replay_header(REPLAY_DIR + file_name)
			if not info.is_empty():
				info["filename"] = file_name
				info["filepath"] = REPLAY_DIR + file_name
				replays.append(info)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	# 按日期倒序排列
	replays.sort_custom(func(a, b): return a.get("date", "") > b.get("date", ""))
	return replays

## 读取录像头信息 (不加载 tick_data, 用于列表显示)
func _read_replay_header(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json_str := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		return {}
	
	var data: Dictionary = json.data
	return {
		"date": data.get("date", ""),
		"duration_ticks": data.get("duration_ticks", 0),
		"players": data.get("players", {}),
		"game_config": data.get("game_config", {}),
	}

## 加载录像文件准备回放
func load_replay(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ReplaySystem: Cannot open replay file: %s" % path)
		return false
	var json_str := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		push_error("ReplaySystem: Invalid replay file: %s" % path)
		return false
	
	_replay_data = json.data
	# 解析 tick_data (JSON key 是字符串)
	_replay_tick_data = {}
	var raw_tick_data: Dictionary = _replay_data.get("tick_data", {})
	for tick_str in raw_tick_data:
		var tick_int := int(tick_str)
		_replay_tick_data[tick_int] = raw_tick_data[tick_str]
	
	# 解析 camera_data
	_replay_camera_data = {}
	var raw_camera_data: Dictionary = _replay_data.get("camera_data", {})
	for tick_str in raw_camera_data:
		var tick_int := int(tick_str)
		_replay_camera_data[tick_int] = raw_camera_data[tick_str]
	
	# 解析 stats_data
	_replay_stats_data = {}
	var raw_stats_data: Dictionary = _replay_data.get("stats_data", {})
	for tick_str in raw_stats_data:
		var tick_int := int(tick_str)
		_replay_stats_data[tick_int] = raw_stats_data[tick_str]
	
	_replay_total_ticks = int(_replay_data.get("duration_ticks", 0))
	_replay_current_tick = 0
	_replay_timer = 0.0
	_replay_paused = false
	_replay_speed = 1.0
	replay_view_team = -1
	replay_camera_mode = CameraMode.FREE
	replay_follow_peer_id = -1
	current_stats_snapshot = {}
	action_log.clear()
	
	print("ReplaySystem: Loaded replay with %d ticks" % _replay_total_ticks)
	return true

## 开始回放 (切换到 GameWorld 场景)
func start_replay(path: String) -> void:
	if not load_replay(path):
		return
	_current_replay_path = path
	mode = Mode.PLAYING
	# GameWorld 会在 _init_game 中检测 replay 模式
	get_tree().change_scene_to_file("res://scenes/game/GameWorld.tscn")

## 从头重新开始当前回放
func restart_replay() -> void:
	if _current_replay_path != "":
		start_replay(_current_replay_path)

## 获取回放的游戏配置
func get_replay_config() -> Dictionary:
	return _replay_data.get("game_config", {})

## 获取回放的玩家信息
func get_replay_players() -> Dictionary:
	return _replay_data.get("players", {})

## 推进回放 tick
func _advance_replay_tick() -> void:
	if _replay_current_tick > _replay_total_ticks:
		_on_replay_finished()
		return
	
	# 获取本 tick 的指令
	var commands: Array = []
	if _replay_tick_data.has(_replay_current_tick):
		commands = _replay_tick_data[_replay_current_tick]
		# 还原 Vector2
		for cmd in commands:
			for key in cmd:
				if cmd[key] is Dictionary and cmd[key].get("_v2", false):
					cmd[key] = Vector2(cmd[key]["x"], cmd[key]["y"])
	
	# 解析操作日志
	_parse_action_log(_replay_current_tick, commands)
	
	# 更新统计快照 (stats_data 每隔若干 tick 存一次, 取最近的数据)
	if _replay_stats_data.has(_replay_current_tick):
		current_stats_snapshot = _replay_stats_data[_replay_current_tick]
	
	# 发射和正常游戏一样的信号, GameWorld 统一处理
	NetworkManager.game_command_received.emit(_replay_current_tick, commands)
	
	_replay_current_tick += 1
	replay_tick_advanced.emit(_replay_current_tick, _replay_total_ticks)

func _on_replay_finished() -> void:
	_replay_paused = true
	replay_finished.emit()
	print("ReplaySystem: Replay finished at tick %d" % _replay_current_tick)

## 停止回放
func stop_replay() -> void:
	mode = Mode.NONE
	_replay_data.clear()
	_replay_tick_data.clear()
	_replay_camera_data.clear()
	_replay_stats_data.clear()
	_replay_current_tick = 0
	_replay_total_ticks = 0
	current_stats_snapshot.clear()
	action_log.clear()

## ====== 回放控制 ======

func toggle_pause() -> void:
	_replay_paused = not _replay_paused

func is_replay_paused() -> bool:
	return _replay_paused

func set_replay_speed(speed: float) -> void:
	_replay_speed = clampf(speed, 0.5, 16.0)
	replay_speed_changed.emit(_replay_speed)

func get_replay_speed() -> float:
	return _replay_speed

func get_replay_progress() -> float:
	if _replay_total_ticks <= 0:
		return 0.0
	return float(_replay_current_tick) / float(_replay_total_ticks)

func get_current_tick() -> int:
	return _replay_current_tick

func get_total_ticks() -> int:
	return _replay_total_ticks

## 快进到指定 tick (重新从头模拟)
func seek_to_tick(target_tick: int) -> void:
	# 暂停回放
	_replay_paused = true
	# 必须从头重新模拟, 发出重新加载信号
	# 这里简单实现: 先停止, 重置, 快速推进
	_replay_current_tick = 0
	_replay_timer = 0.0
	# TODO: 需要重新加载场景再快进, 暂不实现 seek

## 格式化 tick 为时间字符串 (mm:ss)
func format_tick_time(tick: int) -> String:
	var seconds: int = int(tick * _replay_tick_interval)
	var minutes: int = seconds / 60
	seconds = seconds % 60
	return "%02d:%02d" % [minutes, seconds]

## 删除录像文件
func delete_replay(path: String) -> bool:
	var err := DirAccess.remove_absolute(path)
	return err == OK

## 删除所有录像文件
func delete_all_replays() -> void:
	var dir := DirAccess.open(REPLAY_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(REPLAY_EXTENSION) or file_name.ends_with(REPLAY_TEMP_EXTENSION)):
			DirAccess.remove_absolute(REPLAY_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	print("ReplaySystem: All replays deleted")

## ====== 镜头跟踪 ======

## 获取某 tick 某玩家的镜头位置 (用于回放跟随模式)
func get_camera_at_tick(tick: int, peer_id: int) -> Dictionary:
	# 精确匹配
	if _replay_camera_data.has(tick):
		var tick_cams: Dictionary = _replay_camera_data[tick]
		var peer_key = peer_id  # 可能是 int 或 string
		if tick_cams.has(peer_key):
			return tick_cams[peer_key]
		# JSON 解析时 key 可能是字符串
		var peer_str := str(peer_id)
		if tick_cams.has(peer_str):
			return tick_cams[peer_str]
	# 向前搜索最近的帧 (最多 20 tick)
	for offset in range(1, 21):
		var t := tick - offset
		if t < 0:
			break
		if _replay_camera_data.has(t):
			var tick_cams: Dictionary = _replay_camera_data[t]
			var peer_key = peer_id
			if tick_cams.has(peer_key):
				return tick_cams[peer_key]
			var peer_str := str(peer_id)
			if tick_cams.has(peer_str):
				return tick_cams[peer_str]
	return {}

## 获取所有玩家 peer_id 列表
func get_player_peer_ids() -> Array:
	var players: Dictionary = _replay_data.get("players", {})
	var ids: Array = []
	for key in players:
		ids.append(int(key))
	ids.sort()
	return ids

## 获取玩家名称
func get_player_name(peer_id: int) -> String:
	var players: Dictionary = _replay_data.get("players", {})
	for key in players:
		if int(key) == peer_id:
			return str(players[key].get("name", "Player %d" % peer_id))
	return "Player %d" % peer_id

## 获取玩家队伍
func get_player_team(peer_id: int) -> int:
	var players: Dictionary = _replay_data.get("players", {})
	for key in players:
		if int(key) == peer_id:
			return int(players[key].get("team_id", 0))
	return 0

## ====== 操作日志解析 ======

## 将指令转化为可读文字，并加入日志
func _parse_action_log(tick: int, commands: Array) -> void:
	for cmd in commands:
		var text := _cmd_to_text(cmd)
		if text != "":
			var entry := {"tick": tick, "text": text, "time": format_tick_time(tick)}
			action_log.append(entry)
			if action_log.size() > MAX_ACTION_LOG:
				action_log.pop_front()
			replay_action_logged.emit(tick, text)

## 将单条命令转化为可读描述
func _cmd_to_text(cmd: Dictionary) -> String:
	var cmd_type: String = cmd.get("type", "")
	var team: int = cmd.get("team_id", -1)
	var team_label := "队伍%d" % (team + 1) if team >= 0 else ""
	
	match cmd_type:
		"move":
			return "%s 移动单位" % team_label
		"attack":
			return "%s 发起攻击" % team_label
		"gather":
			return "%s 采集资源" % team_label
		"return_resource":
			return "%s 运送资源" % team_label
		"stop":
			return "%s 停止单位" % team_label
		"build":
			var building_key: String = cmd.get("building_key", "")
			var bdata: Dictionary = GameConstants.BUILDING_DATA.get(building_key, {})
			var bname: String = str(bdata.get("name", building_key))
			return "%s 建造 %s" % [team_label, bname]
		"produce":
			var unit_key: String = cmd.get("unit_key", "")
			var udata: Dictionary = GameConstants.UNIT_DATA.get(unit_key, {})
			var uname: String = str(udata.get("name", unit_key))
			return "%s 生产 %s" % [team_label, uname]
		"chat":
			var sender_name: String = str(cmd.get("sender_name", "Player"))
			var channel: String = str(cmd.get("channel", "all"))
			var msg: String = str(cmd.get("message", ""))
			var ch_text := "全体"
			if channel == "team":
				ch_text = "队友"
			elif channel.begins_with("whisper"):
				ch_text = "私聊"
			return "[%s] %s: %s" % [ch_text, sender_name, msg]
		"cheat_set":
			var enabled: bool = bool(cmd.get("enabled", false))
			return "作弊 秒造模式%s" % ("开启" if enabled else "关闭")
	return ""

## ====== 实时统计 (回放时由 GameWorld 驱动) ======

## 从 GameManager 中实时收集统计数据 (回放时每 tick 调用)
func update_live_stats() -> void:
	if mode != Mode.PLAYING:
		return
	var stats: Dictionary = {}
	var players: Dictionary = _replay_data.get("players", {})
	var team_ids: Array = []
	for key in players:
		var tid: int = int(players[key].get("team_id", 0))
		if not team_ids.has(tid):
			team_ids.append(tid)
	
	for tid in team_ids:
		var minerals := GameManager.resource_system.get_minerals(tid)
		var energy := GameManager.resource_system.get_energy(tid)
		var units := GameManager.get_units_by_team(tid)
		var buildings := GameManager.get_buildings_by_team(tid)
		var prod_queue_size := 0
		for b in buildings:
			if is_instance_valid(b) and b is BaseBuilding:
				prod_queue_size += b.production_queue.size()
		stats[tid] = {
			"minerals": minerals,
			"energy": energy,
			"unit_count": units.size(),
			"building_count": buildings.size(),
			"production_queue_size": prod_queue_size,
		}
	current_stats_snapshot = stats
