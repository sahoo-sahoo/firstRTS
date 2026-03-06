## AI 系统 - 简单电脑对手
## 所有 AI 行为通过 NetworkManager.send_command() 发出, 保证录像完整可回放
class_name AISystem
extends Node

## AI 控制的阵营
var team_id: int = 1
var faction: GameConstants.Faction = GameConstants.Faction.SHADOW_TECH

## AI 难度
enum Difficulty { EASY, MEDIUM, HARD }
var difficulty: Difficulty = Difficulty.MEDIUM

## 计时器
var _think_interval: float = 2.0  # AI 每2秒决策一次
var _think_timer: float = 0.0
var _attack_timer: float = 0.0
var _attack_interval: float = 120.0  # 2分钟后开始进攻

## 建造冷却 (防止反复下同一建造单)
const BUILD_ORDER_COOLDOWN: float = 8.0
var _build_cooldowns: Dictionary = {}

## 状态
var _has_barracks: bool = false
var _has_factory: bool = false
var _army_count: int = 0

## 工人无任务冷却（避免无法分配时反复下指令）
## key = entity_id, value = 剩余冷却时间
## 工人找到新任务后清除其记录
const WORKER_IDLE_COOLDOWN: float = 10.0
var _worker_idle_cooldowns: Dictionary = {}

## 引用
var _entity_layer: Node2D = null

func setup(entity_layer: Node2D, ai_team: int, ai_faction: GameConstants.Faction, ai_difficulty: Difficulty = Difficulty.MEDIUM) -> void:
	_entity_layer = entity_layer
	team_id = ai_team
	faction = ai_faction
	difficulty = ai_difficulty
	
	match difficulty:
		Difficulty.EASY:
			_think_interval = 3.0
			_attack_interval = 180.0
		Difficulty.MEDIUM:
			_think_interval = 2.0
			_attack_interval = 120.0
		Difficulty.HARD:
			_think_interval = 1.0
			_attack_interval = 60.0

func _process(delta: float) -> void:
	_think_timer += delta
	_attack_timer += delta
	_update_build_cooldowns(delta)
	# 递减工人空闲冷却
	for key in _worker_idle_cooldowns.keys():
		var left: float = float(_worker_idle_cooldowns[key]) - delta
		if left <= 0.0:
			_worker_idle_cooldowns.erase(key)
		else:
			_worker_idle_cooldowns[key] = left
	
	if _think_timer >= _think_interval:
		_think_timer = 0.0
		_think()

func _think() -> void:
	var buildings := GameManager.get_buildings_by_team(team_id)
	var units := GameManager.get_units_by_team(team_id)
	var minerals := GameManager.resource_system.get_minerals(team_id)
	var energy := GameManager.resource_system.get_energy(team_id)
	
	_has_barracks = false
	_has_factory = false
	var has_cc := false
	var has_power_plant := false
	var worker_count := 0
	var army_units: Array = []
	var barracks_count := 0
	var factory_count := 0
	var cc_list: Array = []
	var built_barracks: Array = []
	var built_factory: Array = []
	
	for b in buildings:
		if not is_instance_valid(b):
			continue
		match b.building_data_key:
			"command_center":
				has_cc = true
				cc_list.append(b)
			"barracks":
				_has_barracks = true
				barracks_count += 1
				if b.is_built:
					built_barracks.append(b)
			"factory":
				_has_factory = true
				factory_count += 1
				if b.is_built:
					built_factory.append(b)
			"power_plant":
				has_power_plant = true
	
	for u in units:
		if not is_instance_valid(u):
			continue
		var data: Dictionary = GameConstants.UNIT_DATA.get(u.unit_data_key, {})
		if data.get("can_gather", false):
			worker_count += 1
			# 让閗着的工人去采矿，但如果该工人在空闲冷却中则跳过
			if u.current_state == GameConstants.UnitState.IDLE:
				if not _worker_idle_cooldowns.has(u.entity_id):
					_send_worker_to_gather(u)
		else:
			army_units.append(u)
	
	_army_count = army_units.size()
	var worker_target := _get_worker_target()
	
	# 决策优先级：
	# 1. 维持工人数量
	# 2. 经济建筑（发电厂）
	# 3. 军事建筑（兵营→工厂）
	# 4. 造兵（兵营/工厂）
	# 4. 达到一定数量后进攻
	
	if has_cc and worker_count < worker_target:
		_try_produce_worker(buildings)
	
	if has_cc and not has_power_plant and worker_count >= 4:
		_try_build_structure("power_plant", units, cc_list)

	if not _has_barracks and has_cc and worker_count >= 5:
		_try_build_structure("barracks", units, cc_list)

	if _has_barracks and not _has_factory and worker_count >= 7:
		_try_build_structure("factory", units, cc_list)

	# 困难模式且资源充足时可补第二兵营
	if difficulty == Difficulty.HARD and barracks_count < 2 and minerals >= 450 and has_cc:
		_try_build_structure("barracks", units, cc_list)

	# 中/困难在资源富余时补第二工厂
	if difficulty != Difficulty.EASY and factory_count < 2 and _has_factory and minerals >= 700 and energy >= 120 and has_cc:
		_try_build_structure("factory", units, cc_list)
	
	if built_barracks.size() > 0 or built_factory.size() > 0:
		_try_produce_army(built_barracks, built_factory, minerals, energy)
	
	# 进攻
	if _attack_timer > _attack_interval and _army_count >= _get_attack_threshold():
		_launch_attack(army_units)
		_attack_timer = 0.0

func _send_worker_to_gather(worker: BaseUnit) -> void:
	if not is_instance_valid(worker):
		return
	if _entity_layer == null or not is_instance_valid(_entity_layer):
		return
	# 查找最近矿点
	var nearest_res: Node2D = null
	var nearest_dist := INF

	for res in GameManager._all_resources:
		if not is_instance_valid(res):
			continue
		if res.remaining_amount <= 0:
			continue
		if res.occupied_by != null and is_instance_valid(res.occupied_by) and res.occupied_by != worker:
			continue
		var dist := worker.global_position.distance_to(res.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_res = res
	
	var depot := GameManager.get_nearest_depot(team_id, worker.global_position)
	if nearest_res and depot:
		# 找到任务：清除冷却并下达指令
		_worker_idle_cooldowns.erase(worker.entity_id)
		NetworkManager.send_command({
			"type": "gather",
			"entity_id": worker.entity_id,
			"resource_id": nearest_res.entity_id,
			"depot_id": depot.entity_id,
			"team_id": team_id,
		})
	else:
		# 找不到任务：设置冷却，10 秒内不再尝试
		_worker_idle_cooldowns[worker.entity_id] = WORKER_IDLE_COOLDOWN

func _try_produce_worker(buildings: Array) -> void:
	var worker_key := _get_worker_key()
	
	for b in buildings:
		if is_instance_valid(b) and b.building_data_key == "command_center" and b.is_built:
			if b.production_queue.size() < 2:
				NetworkManager.send_command({
					"type": "produce",
					"building_id": b.entity_id,
					"unit_key": worker_key,
					"team_id": team_id,
				})
			break

func _try_build_structure(building_key: String, units: Array, anchors: Array) -> void:
	if not _can_issue_build_order(building_key):
		return

	# 找到一个空闲工人作为建造者
	var builder: BaseUnit = null
	for u in units:
		if not is_instance_valid(u):
			continue
		if u.can_build and u.current_state == GameConstants.UnitState.IDLE:
			builder = u
			break
	# 没有空闲工人, 找任意工人
	if builder == null:
		for u in units:
			if not is_instance_valid(u):
				continue
			if u.can_build:
				builder = u
				break
	if builder == null:
		return

	var anchor: Node2D = null
	if anchors.size() > 0:
		anchor = anchors[0]
	if anchor == null:
		anchor = GameManager.get_nearest_depot(team_id, builder.global_position)
	if anchor == null:
		return

	var pos := _find_build_position(building_key, anchor.global_position, builder)
	NetworkManager.send_command({
		"type": "build",
		"building_key": building_key,
		"team_id": team_id,
		"builder_id": builder.entity_id,
		"position": pos,
	})
	_build_cooldowns[building_key] = BUILD_ORDER_COOLDOWN

func _try_produce_army(barracks_list: Array, factory_list: Array, minerals: int, energy: int) -> void:
	var infantry_key := _get_infantry_key()
	var tank_key := _get_tank_key()

	for b in barracks_list:
		if not is_instance_valid(b):
			continue
		if b.production_queue.size() < 2:
			NetworkManager.send_command({
				"type": "produce",
				"building_id": b.entity_id,
				"unit_key": infantry_key,
				"team_id": team_id,
			})

	var tank_data: Dictionary = GameConstants.UNIT_DATA.get(tank_key, {})
	if tank_data.is_empty():
		return
	var tank_cost_m: int = int(tank_data.get("cost_mineral", 0))
	var tank_cost_e: int = int(tank_data.get("cost_energy", 0))
	if minerals < tank_cost_m or energy < tank_cost_e:
		return

	for f in factory_list:
		if not is_instance_valid(f):
			continue
		if f.production_queue.size() < 2:
			NetworkManager.send_command({
				"type": "produce",
				"building_id": f.entity_id,
				"unit_key": tank_key,
				"team_id": team_id,
			})

func _launch_attack(army: Array) -> void:
	# 找到敌方目标并直接下达攻击指令（避免移动到建筑中心导致卡住不进攻）
	var enemy_team := 0 if team_id == 1 else 1
	var target_entity: Node2D = null

	# 优先打敌方主基地
	var enemy_buildings := GameManager.get_buildings_by_team(enemy_team)
	for b in enemy_buildings:
		if not is_instance_valid(b):
			continue
		if b.hp <= 0:
			continue
		if b.building_data_key == "command_center":
			target_entity = b
			break

	# 其次打任意敌方建筑
	if target_entity == null:
		for b in enemy_buildings:
			if not is_instance_valid(b):
				continue
			if b.hp <= 0:
				continue
			target_entity = b
			break

	# 建筑全灭后攻击敌方单位
	if target_entity == null:
		var enemy_units := GameManager.get_units_by_team(enemy_team)
		for e in enemy_units:
			if not is_instance_valid(e):
				continue
			if e.current_state == GameConstants.UnitState.DEAD:
				continue
			target_entity = e
			break

	if target_entity == null:
		return

	for unit in army:
		if not is_instance_valid(unit):
			continue
		NetworkManager.send_command({
			"type": "attack",
			"entity_id": unit.entity_id,
			"target_id": target_entity.entity_id,
			"team_id": team_id,
		})

func _get_worker_target() -> int:
	match difficulty:
		Difficulty.EASY:
			return 6
		Difficulty.HARD:
			return 12
		_:
			return 9

func _get_attack_threshold() -> int:
	match difficulty:
		Difficulty.EASY:
			return 6
		Difficulty.HARD:
			return 4
		_:
			return 5

func _get_worker_key() -> String:
	if faction == GameConstants.Faction.SHADOW_TECH:
		return "st_worker"
	return "sa_worker"

func _get_infantry_key() -> String:
	if faction == GameConstants.Faction.SHADOW_TECH:
		return "st_zealot"
	return "sa_infantry"

func _get_tank_key() -> String:
	if faction == GameConstants.Faction.SHADOW_TECH:
		return "st_phase_tank"
	return "sa_tank"

func _update_build_cooldowns(delta: float) -> void:
	var keys := _build_cooldowns.keys()
	for key in keys:
		var left: float = float(_build_cooldowns.get(key, 0.0)) - delta
		if left <= 0.0:
			_build_cooldowns.erase(key)
		else:
			_build_cooldowns[key] = left

func _can_issue_build_order(building_key: String) -> bool:
	return float(_build_cooldowns.get(building_key, 0.0)) <= 0.0

func _find_build_position(building_key: String, anchor_pos: Vector2, builder: BaseUnit) -> Vector2:
	var ring1: Array[Vector2] = [
		Vector2(220, 0), Vector2(-220, 0), Vector2(0, 220), Vector2(0, -220),
		Vector2(220, 220), Vector2(-220, 220), Vector2(220, -220), Vector2(-220, -220),
	]
	var ring2: Array[Vector2] = [
		Vector2(320, 0), Vector2(-320, 0), Vector2(0, 320), Vector2(0, -320),
		Vector2(320, 160), Vector2(-320, 160), Vector2(320, -160), Vector2(-320, -160),
		Vector2(160, 320), Vector2(-160, 320), Vector2(160, -320), Vector2(-160, -320),
	]
	var ring3: Array[Vector2] = [
		Vector2(420, 0), Vector2(-420, 0), Vector2(0, 420), Vector2(0, -420),
		Vector2(420, 220), Vector2(-420, 220), Vector2(420, -220), Vector2(-420, -220),
	]
	for off: Vector2 in ring1:
		var candidate: Vector2 = anchor_pos + off
		if _can_place_building_at(building_key, candidate, builder):
			return candidate
	for off: Vector2 in ring2:
		var candidate: Vector2 = anchor_pos + off
		if _can_place_building_at(building_key, candidate, builder):
			return candidate
	for off: Vector2 in ring3:
		var candidate: Vector2 = anchor_pos + off
		if _can_place_building_at(building_key, candidate, builder):
			return candidate

	# 兜底：在工人附近尝试一圈
	for off: Vector2 in ring2:
		var candidate: Vector2 = builder.global_position + off
		if _can_place_building_at(building_key, candidate, builder):
			return candidate

	return anchor_pos + Vector2(320, 0)

func _can_place_building_at(building_key: String, world_pos: Vector2, builder: BaseUnit) -> bool:
	var world := _entity_layer.get_parent() if _entity_layer else null
	if world == null:
		return false
	if not world.has_method("get"):
		return false
	var map_system: Variant = world.get("map_system")
	if map_system == null:
		return false
	var data: Dictionary = GameConstants.BUILDING_DATA.get(building_key, {})
	if data.is_empty():
		return false
	var size: Vector2i = data.get("size", Vector2i(3, 3))
	var tile: Vector2i = map_system.world_to_tile(world_pos)
	if not map_system.can_place_building(tile.x, tile.y, size):
		return false

	var half: Vector2 = Vector2(size) * GameConstants.TILE_SIZE * 0.5

	for b in GameManager._all_buildings:
		if not is_instance_valid(b):
			continue
		if b.hp <= 0:
			continue
		var b_half: Vector2 = Vector2(b.building_size) * GameConstants.TILE_SIZE * 0.5
		if _aabb_overlap(world_pos, half, b.global_position, b_half):
			return false

	for r in GameManager._all_resources:
		if not is_instance_valid(r):
			continue
		if r.remaining_amount <= 0:
			continue
		if _rect_circle_overlap(world_pos, half, r.global_position, r.get_collision_radius()):
			return false

	for u in GameManager._all_units:
		if not is_instance_valid(u):
			continue
		if u.current_state == GameConstants.UnitState.DEAD:
			continue
		if builder != null and u == builder:
			continue
		if _rect_circle_overlap(world_pos, half, u.global_position, u.unit_radius):
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
