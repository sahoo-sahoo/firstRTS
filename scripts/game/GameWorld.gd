## GameWorld - 主游戏场景，组装所有系统
extends Node2D

const AI_SYSTEM_SCRIPT := preload("res://scripts/systems/AISystem.gd")
const BASE_UNIT_SCRIPT := preload("res://scripts/entities/BaseUnit.gd")
const BASE_BUILDING_SCRIPT := preload("res://scripts/entities/BaseBuilding.gd")
const RESOURCE_NODE_SCRIPT := preload("res://scripts/entities/ResourceNode.gd")

## 系统引用
var map_system: MapSystem = null
var camera_system: CameraSystem = null
var selection_system: SelectionSystem = null
var fog_system: FogOfWarSystem = null
var ai_system: AISystem = null
var build_placement: BuildPlacementSystem = null
var hud: HUD = null

## 实体容器
var entity_layer: Node2D = null
var effect_layer: Node2D = null

## 本地玩家
var local_team_id: int = 0
var local_faction: GameConstants.Faction = GameConstants.Faction.STEEL_ALLIANCE

## 建筑出兵点轮换计数（避免单位叠在一起）
var _spawn_slot_counter: Dictionary = {}

## H 键基地视角切换
var _last_base_cycle_ms: int = 0
var _base_cycle_index: int = -1
const BASE_CYCLE_WINDOW_MS: int = 5000

## 回放模式
var is_replay_mode: bool = false

func _ready() -> void:
	_init_layers()
	_init_systems()
	_init_game()

func _init_layers() -> void:
	# 地图层
	map_system = MapSystem.new()
	map_system.name = "MapSystem"
	add_child(map_system)
	
	# 实体层 (单位、建筑、资源)
	entity_layer = Node2D.new()
	entity_layer.name = "EntityLayer"
	add_child(entity_layer)
	
	# 特效层
	effect_layer = Node2D.new()
	effect_layer.name = "EffectLayer"
	add_child(effect_layer)
	
	# 战斗特效系统 (挂在特效层下)
	var combat_fx := CombatEffects.new()
	combat_fx.name = "CombatEffects"
	effect_layer.add_child(combat_fx)
	
	# 迷雾层 (在实体层之上)
	fog_system = FogOfWarSystem.new()
	fog_system.name = "FogOfWar"
	add_child(fog_system)
	
	# 选择系统 (绘制框选框)
	selection_system = SelectionSystem.new()
	selection_system.name = "SelectionSystem"
	add_child(selection_system)
	
	# 建筑放置系统
	build_placement = BuildPlacementSystem.new()
	build_placement.name = "BuildPlacement"
	add_child(build_placement)

func _init_systems() -> void:
	# 相机
	camera_system = CameraSystem.new()
	camera_system.name = "Camera"
	add_child(camera_system)
	
	# HUD (CanvasLayer)
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	
	# 等地图生成完再设置
	map_system.map_generated.connect(_on_map_ready)

func _on_map_ready() -> void:
	var map_pixel_size := map_system.get_map_pixel_size()
	
	# 设置相机边界
	camera_system.setup(map_pixel_size)
	# 回放模式底部有 96px 回放控制条，补偿避免地图底部被遮挡
	camera_system.hud_bottom_height = 96.0 if is_replay_mode else 0.0
	
	# 设置选择系统
	if not is_replay_mode:
		selection_system.setup(camera_system, entity_layer, local_team_id)
		selection_system.selection_changed.connect(_on_selection_changed)
	else:
		# 回放模式: 允许选中任意队伍的单位 (仅查看)
		selection_system.setup(camera_system, entity_layer, local_team_id, true)
		selection_system.selection_changed.connect(_on_selection_changed)
	
	# 设置迷雾 (回放模式或无迷雾模式下隐藏)
	if is_replay_mode or GameManager.fog_mode == GameConstants.FogMode.NONE:
		fog_system.visible = false
	else:
		fog_system.setup(map_pixel_size, entity_layer, local_team_id, GameManager.fog_mode)
	
	# 设置建筑放置 (回放模式下禁用)
	if not is_replay_mode:
		build_placement.setup(map_system, local_team_id)
		build_placement.building_placed.connect(_on_building_placed)
	
	# 设置小地图（传入迷雾系统引用，用于遮罩同步）
	hud.setup_minimap(map_system, entity_layer, camera_system, local_team_id, fog_system if fog_system.visible else null)
	
	# 设置建造系统引用
	if not is_replay_mode:
		hud.setup_build_system(build_placement)

func _init_game() -> void:
	# === 检测回放模式 ===
	if ReplaySystem.mode == ReplaySystem.Mode.PLAYING:
		_init_replay_mode()
		return
	
	var is_multiplayer := NetworkManager.is_connected and NetworkManager.role != NetworkManager.Role.NONE
	var config: Dictionary = {}
	
	if is_multiplayer:
		# === 联机模式: 从 NetworkManager 读取配置 ===
		config = NetworkManager.game_config
		var my_info: Dictionary = NetworkManager.players.get(NetworkManager.peer_id, {})
		local_team_id = my_info.get("team_id", 0)
		local_faction = my_info.get("faction", 0) as GameConstants.Faction
		
		# 地图种子从服务器配置获取 (保证所有客户端一致)
		var seed_val: int = config.get("map_seed", randi())
		map_system.map_seed = seed_val
		
		# 开始游戏
		GameManager.start_game({
			"team_id": local_team_id,
			"player_count": NetworkManager.players.size(),
			"map_seed": seed_val,
			"fog_mode": config.get("fog_mode", GameConstants.FogMode.FULL_BLACK),
			"starting_minerals": int(config.get("starting_minerals", GameConstants.STARTING_MINERALS)),
			"starting_energy": int(config.get("starting_energy", GameConstants.STARTING_ENERGY)),
		})
		
		# 开始录制
		ReplaySystem.start_recording(
			{
				"map_seed": seed_val,
				"player_count": NetworkManager.players.size(),
				"starting_minerals": GameManager.starting_minerals,
				"starting_energy": GameManager.starting_energy,
				"fog_mode": GameManager.fog_mode,
			},
			NetworkManager.players.duplicate(true)
		)
	else:
		# === 单机模式 ===
		var seed_val := randi()
		map_system.map_seed = seed_val
		NetworkManager.start_offline()
		# 把 AI 也加入 NetworkManager.players, 确保单机和回放走同一条生成路径
		NetworkManager.players[2] = {"name": "AI", "team_id": 1, "spawn_slot": 3, "faction": 1, "color_id": 1, "ready": true}
		
		GameManager.start_game({
			"team_id": local_team_id,
			"player_count": 2,
			"map_seed": seed_val,
		})
		
		# 单机也录制 (使用 NetworkManager.players 确保与回放完全一致)
		ReplaySystem.start_recording(
			{
				"map_seed": seed_val,
				"player_count": 2,
				"starting_minerals": GameManager.starting_minerals,
				"starting_energy": GameManager.starting_energy,
				"fog_mode": GameManager.fog_mode,
			},
			NetworkManager.players.duplicate(true)
		)
	
	# 回调连接
	NetworkManager.game_command_received.connect(_on_game_command)
	
	# AI 系统 (仅单机模式)
	if not is_multiplayer:
		ai_system = AI_SYSTEM_SCRIPT.new() as AISystem
		ai_system.name = "AISystem"
		add_child(ai_system)
		ai_system.setup(entity_layer, 1, GameConstants.Faction.SHADOW_TECH, AISystem.Difficulty.MEDIUM)
	
	# 等地图就绪后放初始单位 (用 call_deferred 确保地图生成完毕)
	call_deferred("_spawn_initial_entities")

## 回放模式初始化
func _init_replay_mode() -> void:
	is_replay_mode = true
	var config: Dictionary = ReplaySystem.get_replay_config()
	var replay_players: Dictionary = ReplaySystem.get_replay_players()
	
	# 设置 NetworkManager 为离线模式
	NetworkManager.start_offline()
	NetworkManager.players = replay_players.duplicate(true)
	
	# 观战视角: 默认玩家1
	local_team_id = -1  # 全局视角 (无迷雾)
	
	var seed_val: int = int(config.get("map_seed", 0))
	var player_count: int = int(config.get("player_count", 2))
	map_system.map_seed = seed_val
	
	GameManager.start_game({
		"team_id": 0,
		"player_count": player_count,
		"map_seed": seed_val,
		"starting_minerals": int(config.get("starting_minerals", GameConstants.STARTING_MINERALS)),
		"starting_energy": int(config.get("starting_energy", GameConstants.STARTING_ENERGY)),
		"fog_mode": int(config.get("fog_mode", GameConstants.FogMode.NONE)),
	})
	
	# 不连接 NetworkManager 的 game_command_received — ReplaySystem 会直接 emit 它
	NetworkManager.game_command_received.connect(_on_game_command)
	
	call_deferred("_spawn_initial_entities_replay")

## ====== 生成初始实体 ======

func _unhandled_input(event: InputEvent) -> void:
	if is_replay_mode:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_H:
			_jump_to_primary_base()
			return
		# B = 建造菜单快捷键 (选中工人时)
		if event.keycode == KEY_B:
			_open_build_menu()
		# 数字键快捷建造
		elif event.keycode == KEY_Q and event.alt_pressed:
			build_placement.start_placement("barracks")
		elif event.keycode == KEY_W and event.alt_pressed:
			build_placement.start_placement("factory")
		elif event.keycode == KEY_E and event.alt_pressed:
			build_placement.start_placement("defense_tower")
		elif event.keycode == KEY_R and event.alt_pressed:
			build_placement.start_placement("power_plant")

func _open_build_menu() -> void:
	# 检查是否选中了工人
	var has_worker := false
	for unit in selection_system.selected_units:
		if is_instance_valid(unit) and unit.can_build:
			has_worker = true
			break
	if has_worker:
		hud.show_message("Alt+Q=兵营 Alt+W=工厂 Alt+E=防御塔 Alt+R=发电厂", 3.0)

func _jump_to_primary_base() -> void:
	if camera_system == null:
		return
	var now_ms: int = Time.get_ticks_msec()
	var cycle_bases := _get_cycle_bases()
	if cycle_bases.is_empty():
		return

	if now_ms - _last_base_cycle_ms <= BASE_CYCLE_WINDOW_MS and _base_cycle_index >= 0:
		_base_cycle_index = (_base_cycle_index + 1) % cycle_bases.size()
	else:
		_base_cycle_index = _find_local_primary_base_index(cycle_bases)
		if _base_cycle_index < 0:
			_base_cycle_index = 0

	_last_base_cycle_ms = now_ms
	var target: BaseBuilding = cycle_bases[_base_cycle_index]
	camera_system.jump_to(target.global_position)
	if target.team_id == local_team_id:
		hud.show_message("已定位我方主基地", 1.0)
	else:
		hud.show_message("切换到队伍 %d 基地" % (target.team_id + 1), 1.0)

func _get_cycle_bases() -> Array[BaseBuilding]:
	var bases: Array[BaseBuilding] = []
	for building in GameManager._all_buildings:
		if not is_instance_valid(building):
			continue
		if building.hp <= 0:
			continue
		if building.team_id != local_team_id:
			continue
		if building.building_data_key != "command_center":
			continue
		bases.append(building)
	bases.sort_custom(func(a: BaseBuilding, b: BaseBuilding):
		return a.entity_id < b.entity_id
	)
	return bases

func _find_local_primary_base_index(bases: Array[BaseBuilding]) -> int:
	var best_index: int = -1
	var best_entity_id: int = 2147483647
	for i in range(bases.size()):
		var b := bases[i]
		if b.team_id != local_team_id:
			continue
		if b.entity_id < best_entity_id:
			best_entity_id = b.entity_id
			best_index = i
	return best_index

## 根据 team_id 和阵营决定工人类型
func _get_worker_key(team_id: int) -> String:
	var faction: int = _get_team_faction(team_id)
	if faction == GameConstants.Faction.SHADOW_TECH:
		return "st_worker"
	return "sa_worker"

## 获取某个 team 的阵营
func _get_team_faction(team_id: int) -> int:
	# 从 NetworkManager.players 查找 (兼容 int/string key)
	for pid in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[pid]
		if int(info.get("team_id", -1)) == team_id:
			return int(info.get("faction", team_id))  # 默认 team0=faction0, team1=faction1
	# 默认: team 0 = 钢铁联盟, team 1 = 暗影科技
	return team_id

func _spawn_initial_entities() -> void:
	_spawn_initial_entities_common()
	
	# 相机跳转到己方基地
	var spawn_positions := _get_spawn_positions()
	if NetworkManager.players.size() > 1:
		var peer_ids := NetworkManager.players.keys()
		peer_ids.sort()
		var slot_map := _resolve_spawn_slot_map(peer_ids, spawn_positions.size())
		var my_slot := int(slot_map.get(NetworkManager.peer_id, 0))
		if my_slot >= 0 and my_slot < spawn_positions.size():
			camera_system.jump_to(spawn_positions[my_slot])
		else:
			camera_system.jump_to(spawn_positions[0])
	else:
		camera_system.jump_to(spawn_positions[0])
	
	# 确认游戏场景加载完成，开始同步仿真
	NetworkManager.confirm_game_ready()

func _spawn_initial_entities_replay() -> void:
	# 回放模式: 生成初始实体, 不确认 game_ready (由 ReplaySystem 驱动 tick)
	_spawn_initial_entities_common()
	# 相机默认看第一个出生点
	var spawn_positions := _get_spawn_positions()
	camera_system.jump_to(spawn_positions[0])

func _get_spawn_positions() -> Array[Vector2]:
	var ts := GameConstants.TILE_SIZE
	var mw := GameConstants.MAP_WIDTH
	var mh := GameConstants.MAP_HEIGHT
	# 8 个出生点：4 角 + 4 边中点，间距均匀，兼容 2~8 人
	return [
		Vector2(8 * ts,        8 * ts),          # 0 左上角
		Vector2((mw/2) * ts,   8 * ts),          # 1 上中
		Vector2((mw-8) * ts,   8 * ts),          # 2 右上角
		Vector2(8 * ts,        (mh/2) * ts),     # 3 左中
		Vector2((mw-8) * ts,   (mh/2) * ts),     # 4 右中
		Vector2(8 * ts,        (mh-8) * ts),     # 5 左下角
		Vector2((mw/2) * ts,   (mh-8) * ts),     # 6 下中
		Vector2((mw-8) * ts,   (mh-8) * ts),     # 7 右下角
	]

func _resolve_spawn_slot_map(peer_ids: Array, slot_count: int) -> Dictionary:
	var slot_map: Dictionary = {}
	var used_slots: Dictionary = {}
	# 第一轮：先按固定请求分配可用位置（spawn_slot >= 0）
	for peer in peer_ids:
		var peer_id: int = int(peer)
		var info: Dictionary = NetworkManager.players.get(peer, {})
		var wanted: int = int(info.get("spawn_slot", 0))
		if wanted < 0:
			continue
		var slot := clampi(wanted, 0, slot_count - 1)
		if not used_slots.has(slot):
			slot_map[peer_id] = slot
			used_slots[slot] = true
	# 第二轮：随机请求分配空位（spawn_slot == -1），按 map_seed+peer_id 确定性随机
	for peer in peer_ids:
		var peer_id: int = int(peer)
		if slot_map.has(peer_id):
			continue
		var info: Dictionary = NetworkManager.players.get(peer, {})
		var wanted: int = int(info.get("spawn_slot", 0))
		if wanted >= 0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = int(GameManager.map_seed * 131 + peer_id * 977)
		var start_slot := rng.randi_range(0, slot_count - 1)
		for offset in range(slot_count):
			var candidate := (start_slot + offset) % slot_count
			if not used_slots.has(candidate):
				slot_map[peer_id] = candidate
				used_slots[candidate] = true
				break
	# 第三轮：剩余未分配玩家兜底分配空位
	for peer in peer_ids:
		var peer_id: int = int(peer)
		if slot_map.has(peer_id):
			continue
		for candidate in range(slot_count):
			if not used_slots.has(candidate):
				slot_map[peer_id] = candidate
				used_slots[candidate] = true
				break
	return slot_map

func _resolve_color_id_map(peer_ids: Array) -> Dictionary:
	var color_map: Dictionary = {}
	var used_colors: Dictionary = {}
	# 固定颜色先占位（color_id >= 0）
	for peer in peer_ids:
		var peer_id: int = int(peer)
		var info: Dictionary = NetworkManager.players.get(peer, {})
		var wanted: int = int(info.get("color_id", -1))
		if wanted < 0:
			continue
		var color_id := posmod(wanted, 4)
		if not used_colors.has(color_id):
			color_map[peer_id] = color_id
			used_colors[color_id] = true
	# 随机颜色分配可用色（color_id == -1）
	for peer in peer_ids:
		var peer_id: int = int(peer)
		if color_map.has(peer_id):
			continue
		var info: Dictionary = NetworkManager.players.get(peer, {})
		var wanted: int = int(info.get("color_id", -1))
		if wanted >= 0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = int(GameManager.map_seed * 313 + peer_id * 197)
		var start_color := rng.randi_range(0, 3)
		var assigned := false
		for offset in range(4):
			var candidate := (start_color + offset) % 4
			if not used_colors.has(candidate):
				color_map[peer_id] = candidate
				used_colors[candidate] = true
				assigned = true
				break
		if not assigned:
			color_map[peer_id] = start_color
	return color_map

func _spawn_base_for_player(peer_id: int, team_id: int, faction_id: int, color_id: int, cc_pos: Vector2) -> void:
	var worker_key := "sa_worker"
	if faction_id == GameConstants.Faction.SHADOW_TECH:
		worker_key = "st_worker"

	_create_building("command_center", team_id, cc_pos, true, peer_id, color_id)
	# 工人出生在基地占地外，避免与建筑碰撞体重叠导致难以选中
	var cc_half_size := Vector2(4, 4) * GameConstants.TILE_SIZE * 0.5
	var spawn_y := cc_half_size.y + 60.0
	var worker_offsets := [
		Vector2(-90, spawn_y),
		Vector2(-30, spawn_y),
		Vector2(30, spawn_y),
		Vector2(90, spawn_y),
	]
	for offset in worker_offsets:
		_create_unit(worker_key, team_id, cc_pos + offset, peer_id, color_id)

	# 每个出生点附近资源
	var res_sign_x := -1.0 if cc_pos.x > (GameConstants.MAP_WIDTH * GameConstants.TILE_SIZE / 2.0) else 1.0
	var res_sign_y := -1.0 if cc_pos.y > (GameConstants.MAP_HEIGHT * GameConstants.TILE_SIZE / 2.0) else 1.0
	_create_resource(GameConstants.ResourceType.MINERAL, cc_pos + Vector2(3 * GameConstants.TILE_SIZE * res_sign_x, 2 * GameConstants.TILE_SIZE * res_sign_y), 1500)
	_create_resource(GameConstants.ResourceType.MINERAL, cc_pos + Vector2(4 * GameConstants.TILE_SIZE * res_sign_x, 2 * GameConstants.TILE_SIZE * res_sign_y), 1500)
	_create_resource(GameConstants.ResourceType.MINERAL, cc_pos + Vector2(5 * GameConstants.TILE_SIZE * res_sign_x, 2 * GameConstants.TILE_SIZE * res_sign_y), 1500)
	_create_resource(GameConstants.ResourceType.ENERGY, cc_pos + Vector2(2 * GameConstants.TILE_SIZE * res_sign_x, 4 * GameConstants.TILE_SIZE * res_sign_y), 2000)

## 公共生成逻辑 (普通游戏和回放共用)
func _spawn_initial_entities_common() -> void:
	var spawn_positions := _get_spawn_positions()

	# 统一走同一条路径 (单机模式下 NetworkManager.players 也包含 AI)
	var peer_ids := NetworkManager.players.keys()
	# 按数值排序 (兼容 int/string key)
	peer_ids.sort_custom(func(a, b): return int(a) < int(b))
	var slot_count := mini(peer_ids.size(), spawn_positions.size())
	var slot_map := _resolve_spawn_slot_map(peer_ids, spawn_positions.size())
	var color_map := _resolve_color_id_map(peer_ids)
	for i in range(slot_count):
		var peer_id: int = int(peer_ids[i])
		var info: Dictionary = NetworkManager.players.get(peer_ids[i], {})
		var team_id: int = int(info.get("team_id", i % 2))
		var faction_id: int = int(info.get("faction", team_id % 2))
		var color_id: int = int(color_map.get(peer_id, i % 4))
		var spawn_slot: int = int(slot_map.get(peer_id, i))
		_spawn_base_for_player(peer_id, team_id, faction_id, color_id, spawn_positions[spawn_slot])
	
	# 中央及各象限散射争夺矿（8 人地图，资源分布均匀）
	var ts := GameConstants.TILE_SIZE
	var mw := GameConstants.MAP_WIDTH
	var mh := GameConstants.MAP_HEIGHT
	# 中心簇
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/2) * ts, (mh/2 - 3) * ts), 2000)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/2) * ts, (mh/2 + 3) * ts), 2000)
	_create_resource(GameConstants.ResourceType.ENERGY,  Vector2((mw/2 - 3) * ts, (mh/2) * ts), 2500)
	_create_resource(GameConstants.ResourceType.ENERGY,  Vector2((mw/2 + 3) * ts, (mh/2) * ts), 2500)
	# 四象限中心
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/4) * ts,     (mh/4) * ts),     1800)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/4 - 2) * ts, (mh/4) * ts),     1800)
	_create_resource(GameConstants.ResourceType.ENERGY,  Vector2((mw/4) * ts,     (mh/4 + 3) * ts), 2000)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((3*mw/4) * ts,     (mh/4) * ts),     1800)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((3*mw/4 + 2) * ts, (mh/4) * ts),     1800)
	_create_resource(GameConstants.ResourceType.ENERGY,  Vector2((3*mw/4) * ts,     (mh/4 + 3) * ts), 2000)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/4) * ts,     (3*mh/4) * ts),     1800)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/4 - 2) * ts, (3*mh/4) * ts),     1800)
	_create_resource(GameConstants.ResourceType.ENERGY,  Vector2((mw/4) * ts,     (3*mh/4 - 3) * ts), 2000)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((3*mw/4) * ts,     (3*mh/4) * ts),     1800)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((3*mw/4 + 2) * ts, (3*mh/4) * ts),     1800)
	_create_resource(GameConstants.ResourceType.ENERGY,  Vector2((3*mw/4) * ts,     (3*mh/4 - 3) * ts), 2000)
	# 上下左右通道中间的扩张点
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/2 - 2) * ts, (mh/4) * ts), 1800)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/2 + 2) * ts, (mh/4) * ts), 1800)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/2 - 2) * ts, (3*mh/4) * ts), 1800)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/2 + 2) * ts, (3*mh/4) * ts), 1800)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/4) * ts, (mh/2 - 2) * ts), 1800)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((mw/4) * ts, (mh/2 + 2) * ts), 1800)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((3*mw/4) * ts, (mh/2 - 2) * ts), 1800)
	_create_resource(GameConstants.ResourceType.MINERAL, Vector2((3*mw/4) * ts, (mh/2 + 2) * ts), 1800)

## ====== 工厂方法 ======

## 收集各队伍统计数据 (用于回放录制)
func _collect_team_stats() -> Dictionary:
	var stats: Dictionary = {}
	for i in range(GameManager.player_count):
		var minerals := GameManager.resource_system.get_minerals(i)
		var energy := GameManager.resource_system.get_energy(i)
		var units := GameManager.get_units_by_team(i)
		var buildings := GameManager.get_buildings_by_team(i)
		var prod_queue_size := 0
		for b in buildings:
			if is_instance_valid(b) and b is BaseBuilding:
				prod_queue_size += b.production_queue.size()
		stats[i] = {
			"minerals": minerals,
			"energy": energy,
			"unit_count": units.size(),
			"building_count": buildings.size(),
			"production_queue_size": prod_queue_size,
		}
	return stats

## 回放模式: 应用镜头跟随
func _apply_replay_camera(tick: int) -> void:
	if not is_replay_mode or camera_system == null:
		return
	if ReplaySystem.replay_camera_mode != ReplaySystem.CameraMode.FOLLOW_PLAYER:
		return
	if ReplaySystem.replay_follow_peer_id < 0:
		return
	
	var cam_data := ReplaySystem.get_camera_at_tick(tick, ReplaySystem.replay_follow_peer_id)
	if cam_data.is_empty():
		return
	
	var target_pos := Vector2(float(cam_data.get("x", 0)), float(cam_data.get("y", 0)))
	var target_zoom := float(cam_data.get("zoom", 1.0))
	camera_system.position = target_pos
	camera_system._target_zoom = Vector2(target_zoom, target_zoom)

func _create_unit(unit_key: String, team: int, pos: Vector2, owner_peer_id: int = 0, color_id: int = 0) -> BaseUnit:
	var unit := BASE_UNIT_SCRIPT.new() as BaseUnit
	unit.unit_data_key = unit_key
	unit.team_id = team
	unit.owner_peer_id = owner_peer_id
	unit.player_color_id = color_id
	unit.global_position = pos
	entity_layer.add_child(unit)
	unit.construction_started.connect(_on_unit_construction_started)
	GameManager.register_unit(unit)
	return unit

func _create_building(building_key: String, team: int, pos: Vector2, instant: bool = false, owner_peer_id: int = 0, color_id: int = 0) -> BaseBuilding:
	var building := BASE_BUILDING_SCRIPT.new() as BaseBuilding
	building.building_data_key = building_key
	building.team_id = team
	building.owner_peer_id = owner_peer_id
	building.player_color_id = color_id
	building.global_position = pos
	entity_layer.add_child(building)
	building.start_build(instant)
	building.building_completed.connect(func(_b): AudioManager.play_event_sfx("build_complete"))
	GameManager.register_building(building)
	
	# 占用地图格子
	var tile_pos := map_system.world_to_tile(pos)
	map_system.place_building(tile_pos.x, tile_pos.y, building.building_size, building.entity_id)
	
	return building

func _create_resource(type: GameConstants.ResourceType, pos: Vector2, amount: int) -> ResourceNode:
	var res := RESOURCE_NODE_SCRIPT.new() as ResourceNode
	res.resource_type = type
	res.total_amount = amount
	res.remaining_amount = amount
	res.global_position = pos
	entity_layer.add_child(res)
	GameManager.register_resource(res)
	return res

## ====== 回调 ======

func _on_selection_changed(units: Array[BaseUnit], buildings: Array[BaseBuilding]) -> void:
	hud.update_selection(units, buildings)

func _on_building_placed(building_key: String, pos: Vector2) -> void:
	var builder_id := _find_selected_builder_id()
	if builder_id < 0:
		hud.show_message("需要选中工程兵执行建造")
		return
	NetworkManager.send_command({
		"type": "build",
		"building_key": building_key,
		"team_id": local_team_id,
		"builder_id": builder_id,
		"position": pos,
	})

func _find_selected_builder_id() -> int:
	if selection_system == null:
		return -1
	for unit in selection_system.selected_units:
		if not is_instance_valid(unit):
			continue
		if unit.team_id == local_team_id and unit.can_build:
			return unit.entity_id
	return -1

func _on_unit_construction_started(builder: BaseUnit, building_key: String, pos: Vector2) -> void:
	if not is_instance_valid(builder):
		return
	if builder.current_state == GameConstants.UnitState.DEAD:
		return

	var data: Dictionary = GameConstants.BUILDING_DATA.get(building_key, {})
	if data.is_empty():
		return
	var bsize: Vector2i = data.get("size", Vector2i(3, 3))
	var tile := map_system.world_to_tile(pos)
	if not _can_place_building_world(pos, tile, bsize, builder):
		# 位置被占，退款
		var cost_m: int = data.get("cost_mineral", 0)
		var cost_e: int = data.get("cost_energy", 0)
		GameManager.resource_system.add_minerals(builder.team_id, cost_m)
		GameManager.resource_system.add_energy(builder.team_id, cost_e)
		if builder.team_id == local_team_id:
			hud.show_message("建造位置被占用，已退款")
		return

	AudioManager.play_event_sfx("build_start")
	var new_building := _create_building(building_key, builder.team_id, pos, false, builder.owner_peer_id, builder.player_color_id)
	if is_instance_valid(builder) and is_instance_valid(new_building):
		builder.assisting_building = new_building

func _can_place_building_world(center_pos: Vector2, top_left_tile: Vector2i, size: Vector2i,
		ignored_unit: BaseUnit = null) -> bool:
	if not map_system.can_place_building(top_left_tile.x, top_left_tile.y, size):
		return false

	var half: Vector2 = Vector2(size) * GameConstants.TILE_SIZE * 0.5

	for b in GameManager._all_buildings:
		if not is_instance_valid(b):
			continue
		if b.hp <= 0:
			continue
		var b_half: Vector2 = Vector2(b.building_size) * GameConstants.TILE_SIZE * 0.5
		if _aabb_overlap(center_pos, half, b.global_position, b_half):
			return false

	for r in GameManager._all_resources:
		if not is_instance_valid(r):
			continue
		if r.remaining_amount <= 0:
			continue
		if _rect_circle_overlap(center_pos, half, r.global_position, r.get_collision_radius()):
			return false

	for u in GameManager._all_units:
		if not is_instance_valid(u):
			continue
		if ignored_unit != null and u == ignored_unit:
			continue
		if u.current_state == GameConstants.UnitState.DEAD:
			continue
		if _rect_circle_overlap(center_pos, half, u.global_position, u.unit_radius):
			return false

	return true

func _aabb_overlap(a_center: Vector2, a_half: Vector2, b_center: Vector2, b_half: Vector2) -> bool:
	return absf(a_center.x - b_center.x) < (a_half.x + b_half.x) and absf(a_center.y - b_center.y) < (a_half.y + b_half.y)

func _rect_circle_overlap(rect_center: Vector2, rect_half: Vector2, circle_center: Vector2, radius: float) -> bool:
	var min_x: float = rect_center.x - rect_half.x
	var max_x: float = rect_center.x + rect_half.x
	var min_y: float = rect_center.y - rect_half.y
	var max_y: float = rect_center.y + rect_half.y
	var closest: Vector2 = Vector2(
		clampf(circle_center.x, min_x, max_x),
		clampf(circle_center.y, min_y, max_y)
	)
	return closest.distance_squared_to(circle_center) < radius * radius

func _on_game_command(tick: int, commands: Array) -> void:
	# 录制指令 (回放模式下不录制)
	if ReplaySystem.mode == ReplaySystem.Mode.RECORDING:
		ReplaySystem.record_tick(tick, commands)
		# 每 tick 录镜头 (仅单机或本地视角)
		if camera_system:
			ReplaySystem.record_camera(tick, NetworkManager.peer_id, camera_system.position, camera_system.zoom.x)
		# 每 20 tick 录一次玩家统计快照
		if tick % 20 == 0:
			var team_stats: Dictionary = _collect_team_stats()
			ReplaySystem.record_stats(tick, team_stats)
	
	for cmd in commands:
		_execute_command(cmd)
	_simulate_tick()
	
	# 回放模式: 实时更新统计 + 镜头跟随
	if is_replay_mode:
		ReplaySystem.update_live_stats()
		_apply_replay_camera(tick)

## 每个同步 tick 推进一步游戏仿真 (确定性执行)
func _simulate_tick() -> void:
	var dt := NetworkManager.DEFAULT_TICK_INTERVAL
	var produced_units: Array = []
	
	# 推进所有单位
	for child in entity_layer.get_children():
		if child is BaseUnit:
			child.simulate_tick(dt)
	
	# 推进所有建筑，收集生产完成的单位
	for child in entity_layer.get_children():
		if child is BaseBuilding:
			var produced: Array = child.simulate_tick(dt)
			produced_units.append_array(produced)
	
	# 生成已完成生产的单位 (确定性 entity_id 分配)
	for prod in produced_units:
		var building: BaseBuilding = prod["building"]
		var unit_key: String = prod["unit_key"]
		var spawn_pos := _get_production_spawn_pos(building)
		spawn_pos = _resolve_spawn_overlap(spawn_pos, 24.0)
		var unit := _create_unit(unit_key, building.team_id, spawn_pos, building.owner_peer_id, building.player_color_id)
		AudioManager.play_event_sfx("unit_produced")
		if building.has_rally_point:
			unit.command_move(building.rally_point)
	
	# 空闲单位自动索敌 (确定性列表遍历)
	for child in entity_layer.get_children():
		if child is BaseUnit and child.current_state == GameConstants.UnitState.IDLE:
			child._auto_acquire_target()

func _execute_command(cmd: Dictionary) -> void:
	var cmd_type: String = cmd.get("type", "")
	match cmd_type:
		"move":
			var entity_id: int = cmd.get("entity_id", -1)
			var target: Vector2 = cmd.get("target", Vector2.ZERO)
			var unit := _find_unit_by_id(entity_id)
			if unit:
				unit.command_move(target)
		"attack":
			var entity_id: int = cmd.get("entity_id", -1)
			var target_id: int = cmd.get("target_id", -1)
			var unit := _find_unit_by_id(entity_id)
			var target := _find_entity_by_id(target_id)
			if unit and target:
				unit.command_attack(target)
		"gather":
			var entity_id: int = cmd.get("entity_id", -1)
			var resource_id: int = cmd.get("resource_id", -1)
			var depot_id: int = cmd.get("depot_id", -1)
			var unit := _find_unit_by_id(entity_id)
			var resource := _find_entity_by_id(resource_id)
			var depot := _find_building_by_id(depot_id)
			if unit and resource and depot:
				unit.command_gather(resource, depot)
		"return_resource":
			var entity_id: int = cmd.get("entity_id", -1)
			var depot_id: int = cmd.get("depot_id", -1)
			var unit := _find_unit_by_id(entity_id)
			var depot := _find_building_by_id(depot_id)
			if unit and depot:
				unit.command_return(depot)
		"stop":
			var entity_id: int = cmd.get("entity_id", -1)
			var unit := _find_unit_by_id(entity_id)
			if unit:
				unit.command_stop()
		"build":
			var building_key: String = cmd.get("building_key", "")
			var team: int = cmd.get("team_id", 0)
			var pos: Vector2 = cmd.get("position", Vector2.ZERO)
			var builder_id: int = cmd.get("builder_id", -1)
			var builder := _find_unit_by_id(builder_id)
			if builder == null:
				return
			if builder.team_id != team or not builder.can_build:
				return
			var data: Dictionary = GameConstants.BUILDING_DATA.get(building_key, {})
			var cost_m: int = data.get("cost_mineral", 0)
			var cost_e: int = data.get("cost_energy", 0)
			if GameManager.resource_system.spend(team, cost_m, cost_e):
				builder.command_construct(building_key, pos)
		"produce":
			var building_id: int = cmd.get("building_id", -1)
			var unit_key: String = cmd.get("unit_key", "")
			var team: int = cmd.get("team_id", 0)
			var building := _find_building_by_id(building_id)
			if building:
				var data: Dictionary = GameConstants.UNIT_DATA.get(unit_key, {})
				var cost_m: int = data.get("cost_mineral", 0)
				var cost_e: int = data.get("cost_energy", 0)
				if GameManager.resource_system.spend(team, cost_m, cost_e):
					building.queue_production(unit_key)
		"chat":
			var sender_id: int = int(cmd.get("sender_id", cmd.get("peer_id", -1)))
			var sender_name: String = str(cmd.get("sender_name", "Player"))
			var channel: String = str(cmd.get("channel", "all"))
			var message: String = str(cmd.get("message", ""))
			var sender_team: int = int(cmd.get("team_id", -1))
			if message.strip_edges().is_empty():
				return
			var visible: bool = true
			if not is_replay_mode:
				if channel == "team":
					var local_team: int = int(NetworkManager.players.get(NetworkManager.peer_id, {}).get("team_id", -1))
					visible = local_team >= 0 and local_team == sender_team
				elif channel.begins_with("whisper:"):
					var target_id: int = int(channel.get_slice(":", 1))
					visible = sender_id == NetworkManager.peer_id or target_id == NetworkManager.peer_id
			if visible:
				NetworkManager.game_chat_received.emit(sender_id, sender_name, channel, message)
		"cheat_set":
			if not GameManager.is_single_player():
				return
			var enabled: bool = bool(cmd.get("enabled", false))
			GameManager.cheat_instant_build = enabled
			var state_text := "开启" if enabled else "关闭"
			NetworkManager.game_chat_received.emit(0, "系统", "all", "[作弊] 秒造模式已%s" % state_text)

## ====== 查找实体 ======

func _find_unit_by_id(id: int) -> BaseUnit:
	for child in entity_layer.get_children():
		if child is BaseUnit and child.entity_id == id:
			return child
	return null

func _find_building_by_id(id: int) -> BaseBuilding:
	for child in entity_layer.get_children():
		if child is BaseBuilding and child.entity_id == id:
			return child
	return null

func _find_entity_by_id(id: int) -> Node2D:
	for child in entity_layer.get_children():
		if child.get("entity_id") == id:
			return child
	return null

func _get_production_spawn_pos(building: BaseBuilding) -> Vector2:
	var slot: int = int(_spawn_slot_counter.get(building.entity_id, 0))
	_spawn_slot_counter[building.entity_id] = slot + 1
	var half := Vector2(building.building_size) * GameConstants.TILE_SIZE * 0.5
	var front_y := half.y + 34.0
	var offsets := [
		Vector2(0, front_y),
		Vector2(-44, front_y),
		Vector2(44, front_y),
		Vector2(-88, front_y),
		Vector2(88, front_y),
		Vector2(-22, front_y + 36),
		Vector2(22, front_y + 36),
	]
	return building.global_position + offsets[slot % offsets.size()]

func _resolve_spawn_overlap(spawn_pos: Vector2, radius: float) -> Vector2:
	var corrected := spawn_pos
	for other in GameManager._all_units:
		if not is_instance_valid(other):
			continue
		if other.current_state == GameConstants.UnitState.DEAD:
			continue
		var offset: Vector2 = corrected - other.global_position
		var dist: float = offset.length()
		var min_dist: float = radius + other.unit_radius
		if dist >= min_dist:
			continue
		if dist > 0.001:
			corrected += offset / dist * (min_dist - dist)
		else:
			corrected += Vector2(0, min_dist)
	return corrected
