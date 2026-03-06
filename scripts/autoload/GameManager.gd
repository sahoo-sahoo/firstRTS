## GameManager - 全局游戏状态管理 (Autoload)
extends Node

signal game_started
signal game_ended(winner_team: int)
signal game_paused(by_peer: int)
signal game_resumed(by_peer: int)

## 游戏状态
enum GameState { MENU, LOADING, PLAYING, PAUSED, ENDED }
var current_state: GameState = GameState.MENU

## 当前游戏配置
var local_team_id: int = 0
var player_count: int = 2
var map_seed: int = 0
var fog_mode: int = GameConstants.FogMode.NONE  ## 战争迷雾模式
var starting_minerals: int = GameConstants.STARTING_MINERALS
var starting_energy: int = GameConstants.STARTING_ENERGY

## 实体管理
var _next_entity_id: int = 1
var _all_units: Array = []
var _all_buildings: Array = []
var _all_resources: Array = []

## 弃权/自爆标志 (避免批量销毁时重复触发胜负检查)
var _forfeiting: bool = false

## 作弊: 秒造 (单机模式聊天输入 cheat 开启/关闭)
var cheat_instant_build: bool = false

## 暂停系统
var is_paused: bool = false
var _pause_counts: Dictionary = {}  # {peer_id: int} 已使用暂停次数
var _max_pause_count: int = 3       # 多人对战最大暂停次数
var _paused_by: int = 0             # 当前暂停发起者 peer_id

## 资源系统引用
var resource_system: ResourceSystem = null

func _ready() -> void:
	resource_system = ResourceSystem.new()
	resource_system.name = "ResourceSystem"
	add_child(resource_system)

## 分配唯一实体ID
func allocate_entity_id() -> int:
	var id := _next_entity_id
	_next_entity_id += 1
	return id

## 注册实体
func register_unit(unit: BaseUnit) -> void:
	unit.entity_id = allocate_entity_id()
	_all_units.append(unit)
	unit.unit_died.connect(_on_unit_died)
	unit.resource_delivered.connect(_on_resource_delivered)

func register_building(building: BaseBuilding) -> void:
	building.entity_id = allocate_entity_id()
	_all_buildings.append(building)
	building.building_destroyed.connect(_on_building_destroyed)

func register_resource(res_node: ResourceNode) -> void:
	res_node.entity_id = allocate_entity_id()
	_all_resources.append(res_node)
	res_node.resource_depleted.connect(_on_resource_depleted)

## 查询接口
func get_units_by_team(team_id: int) -> Array:
	return _all_units.filter(func(u): return is_instance_valid(u) and u.team_id == team_id)

func get_buildings_by_team(team_id: int) -> Array:
	return _all_buildings.filter(func(b): return is_instance_valid(b) and b.team_id == team_id)

func get_nearest_depot(team_id: int, world_pos: Vector2) -> BaseBuilding:
	var closest: BaseBuilding = null
	var closest_dist := INF
	for b in _all_buildings:
		if is_instance_valid(b) and b.team_id == team_id and b.is_resource_depot:
			var dist := world_pos.distance_to(b.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = b
	return closest

## 开始游戏
func start_game(config: Dictionary = {}) -> void:
	local_team_id = config.get("team_id", 0)
	player_count = config.get("player_count", 2)
	map_seed = config.get("map_seed", randi())
	
	# 未在 config 中指定时，保留 MainMenu 已通过 fog_mode 属性设置的值
	fog_mode = config.get("fog_mode", fog_mode)
	starting_minerals = int(config.get("starting_minerals", starting_minerals))
	starting_energy = int(config.get("starting_energy", starting_energy))
	
	# 重置实体状态 (确保多局游戏 ID 一致)
	_next_entity_id = 1
	_all_units.clear()
	_all_buildings.clear()
	_all_resources.clear()
	cheat_instant_build = false
	
	# 初始化资源
	for i in range(player_count):
		resource_system.init_player(i, starting_minerals, starting_energy)
	
	# 重置暂停计数
	is_paused = false
	_pause_counts.clear()
	_paused_by = 0
	
	current_state = GameState.PLAYING
	game_started.emit()

## ====== 暂停系统 ======

func is_single_player() -> bool:
	return not NetworkManager.is_online

func get_pause_remaining(p_peer_id: int) -> int:
	if is_single_player():
		return -1  # 无限
	var used: int = _pause_counts.get(p_peer_id, 0)
	return maxi(0, _max_pause_count - used)

func pause_game(by_peer: int) -> bool:
	if current_state != GameState.PLAYING:
		return false
	if is_paused:
		return false
	# 多人检查次数
	if not is_single_player():
		var used: int = _pause_counts.get(by_peer, 0)
		if used >= _max_pause_count:
			return false
		_pause_counts[by_peer] = used + 1
	
	is_paused = true
	_paused_by = by_peer
	current_state = GameState.PAUSED
	get_tree().paused = true
	game_paused.emit(by_peer)
	return true

func resume_game(by_peer: int) -> bool:
	if not is_paused:
		return false
	# 任意玩家均可恢复（联机模式下双方都能点继续）
	is_paused = false
	_paused_by = 0
	current_state = GameState.PLAYING
	get_tree().paused = false
	game_resumed.emit(by_peer)
	return true

## 弃权: 销毁某个玩家拥有的全部单位和建筑，然后检查胜负
func forfeit_peer(peer_id: int) -> void:
	if current_state != GameState.PLAYING and current_state != GameState.PAUSED:
		return
	_forfeiting = true
	for unit in _all_units.duplicate():
		if is_instance_valid(unit):
			if unit.owner_peer_id == peer_id:
				unit.take_damage(999999)
	for building in _all_buildings.duplicate():
		if is_instance_valid(building):
			if building.owner_peer_id == peer_id:
				building.take_damage(999999)
	_forfeiting = false
	check_win_condition()


## 检查胜负（支持多队伍/结盟）
func check_win_condition() -> void:
	if _forfeiting:
		return
	if current_state != GameState.PLAYING and current_state != GameState.PAUSED:
		return
	# 统计仍有实体存活的队伍
	var alive_teams: Array = []
	for unit in _all_units:
		if is_instance_valid(unit) and not alive_teams.has(unit.team_id):
			alive_teams.append(unit.team_id)
	for building in _all_buildings:
		if is_instance_valid(building) and not alive_teams.has(building.team_id):
			alive_teams.append(building.team_id)
	# 仅剩 1 支队伍（或全灭）时判断胜负
	if alive_teams.size() <= 1:
		var winner_team: int = alive_teams[0] if alive_teams.size() == 1 else -1
		current_state = GameState.ENDED
		game_ended.emit(winner_team)

## ====== 回调 ======

func _on_unit_died(unit: BaseUnit) -> void:
	_all_units.erase(unit)
	check_win_condition()

func _on_building_destroyed(building: BaseBuilding) -> void:
	_all_buildings.erase(building)
	check_win_condition()

func _on_resource_depleted(res_node: ResourceNode) -> void:
	_all_resources.erase(res_node)

func _on_resource_delivered(unit: BaseUnit, amount: int) -> void:
	# 使用工人携带的资源类型 (确定性)
	if unit.carried_resource_type == GameConstants.ResourceType.ENERGY:
		resource_system.add_energy(unit.team_id, amount)
	else:
		resource_system.add_minerals(unit.team_id, amount)
