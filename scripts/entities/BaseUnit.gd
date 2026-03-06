## 基础单位 - 所有可移动单位的基类
class_name BaseUnit
extends CharacterBody2D

const PathfindingModule = preload("res://scripts/systems/PathfindingModule.gd")

signal unit_selected(unit: BaseUnit)
signal unit_deselected(unit: BaseUnit)
signal unit_died(unit: BaseUnit)
signal unit_attacked(unit: BaseUnit, target: Node2D)
signal resource_delivered(unit: BaseUnit, amount: int)
signal construction_started(unit: BaseUnit, building_key: String, build_pos: Vector2)

## 单位数据键 (对应 GameConstants.UNIT_DATA)
@export var unit_data_key: String = "sa_worker"

## 网络唯一ID
var entity_id: int = -1
var owner_peer_id: int = 0
var player_color_id: int = 0

## 阵营
var team_id: int = 0
var faction: GameConstants.Faction = GameConstants.Faction.STEEL_ALLIANCE

## 属性
var max_hp: int = 40
var hp: int = 40
var max_shield: int = 0
var shield: int = 0
var attack_power: int = 5
var attack_range: float = 30.0
var attack_cooldown: float = 1.0
var move_speed: float = 120.0
var vision_range: float = 200.0
var unit_radius: float = 10.0

## 能力标记
var can_gather: bool = false
var can_build: bool = false
var is_air: bool = false

## 状态
var is_selected: bool = false
var current_state: int = GameConstants.UnitState.IDLE

## 移动目标
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false

## 当前速度向量（从 pathfinding 模块同步，供外部读取）
var current_velocity: Vector2 = Vector2.ZERO

## 寻路模块（负责路径计算、路径跟随、碰撞回避、卡角脱困）
var pathfinding: PathfindingModule = null

## 攻击目标
var attack_target: Node2D = null
var _attack_timer: float = 0.0

## 采集
var gather_target: Node2D = null  # 矿点
var return_target: Node2D = null  # 基地
var carried_resource: int = 0
var carried_resource_type: int = GameConstants.ResourceType.MINERAL
var _gather_timer: float = 0.0
var _gather_retry_timer: float = 0.0   ## 矿点被占时的等待计时器（已锁定状态才计时）
var _gather_success_count: int = 0     ## 当前目标点采集成功次数；>=3 次后锁定该点位

## 建造
var _build_target_pos: Vector2 = Vector2.ZERO
var _build_target_key: String = ""
var _has_build_order: bool = false
var _construction_emitted: bool = false
## 正在辅助建造的建筑 (工人留在旁边直到建成)
var assisting_building: Node2D = null

## 组件引用
var visual: UnitVisual = null
var state_machine: StateMachine = null

const COLLISION_MASK_FULL: int = 1 | 2 | 4 | 8

## ====== 初始化 ======

func _ready() -> void:
	_init_from_data()
	_setup_visual()
	_setup_collision()
	_setup_pathfinding()
	_setup_state_machine()

func _init_from_data() -> void:
	var data: Dictionary = GameConstants.UNIT_DATA.get(unit_data_key, {})
	if data.is_empty():
		push_warning("BaseUnit: Unknown unit data key '%s'" % unit_data_key)
		return
	
	max_hp = data.get("hp", 40)
	hp = max_hp
	max_shield = data.get("shield", 0)
	shield = max_shield
	attack_power = data.get("attack", 5)
	attack_range = data.get("attack_range", 30.0)
	move_speed = data.get("speed", 120.0)
	vision_range = data.get("vision_range", 200.0)
	unit_radius = data.get("radius", 10.0)
	can_gather = data.get("can_gather", false)
	can_build = data.get("can_build", false)
	is_air = data.get("is_air", false)
	faction = data.get("faction", GameConstants.Faction.STEEL_ALLIANCE)

func _setup_visual() -> void:
	visual = UnitVisual.new()
	visual.unit_type = unit_data_key
	visual.unit_radius = unit_radius
	visual.team_id = player_color_id
	visual.hp = hp
	visual.max_hp = max_hp
	visual.shield = shield
	visual.max_shield = max_shield
	visual.name = "Visual"
	add_child(visual)

func _setup_collision() -> void:
	var shape := CircleShape2D.new()
	shape.radius = unit_radius
	var col := CollisionShape2D.new()
	col.shape = shape
	col.name = "CollisionShape"
	add_child(col)
	# 设置碰撞层
	collision_layer = 2  # units layer
	collision_mask = COLLISION_MASK_FULL  # terrain, units, buildings, resources

func _setup_pathfinding() -> void:
	pathfinding = PathfindingModule.new(self)

func _setup_state_machine() -> void:
	state_machine = StateMachine.new()
	state_machine.name = "StateMachine"
	add_child(state_machine)
	
	state_machine.add_state("idle", _on_enter_idle, _on_update_idle)
	state_machine.add_state("moving", _on_enter_moving, _on_update_moving)
	state_machine.add_state("attacking", _on_enter_attacking, _on_update_attacking)
	state_machine.add_state("gathering", _on_enter_gathering, _on_update_gathering)
	state_machine.add_state("returning", _on_enter_returning, _on_update_returning)
	state_machine.add_state("building", _on_enter_building, _on_update_building)
	state_machine.add_state("dead", _on_enter_dead)
	
	state_machine.setup(self, "idle")

## ====== 游戏循环 ======

func _physics_process(_delta: float) -> void:
	if current_state == GameConstants.UnitState.DEAD:
		return
	_update_visual()

## 由 GameWorld 在每个同步 tick 调用
func simulate_tick(dt: float) -> void:
	if current_state == GameConstants.UnitState.DEAD:
		return
	state_machine.update(dt)
	# 将寻路模块的速度向量同步回 BaseUnit（供外部读取）
	current_velocity = pathfinding.current_velocity
	_update_attack_cooldown(dt)

func _update_visual() -> void:
	z_index = 20
	if visual:
		visual.team_id = player_color_id
		visual.hp = hp
		visual.shield = shield
		visual.is_selected = is_selected
		visual.carrying_resource = carried_resource > 0
		visual.carrying_type = carried_resource_type
		visual.is_gathering = current_state == GameConstants.UnitState.GATHERING
		visual.carried_amount = carried_resource
		visual.carry_capacity = GameConstants.WORKER_CARRY_AMOUNT

func _update_attack_cooldown(delta: float) -> void:
	if _attack_timer > 0:
		_attack_timer -= delta

## ====== 公共指令接口 ======

## 移动到指定位置
func command_move(target_pos: Vector2) -> void:
	_clear_build_order()
	_release_gather_target()  # 释放矿点占用 (必须在 gather_target=null 之前)
	move_target = target_pos
	has_move_target = true
	attack_target = null
	gather_target = null
	# 委托寻路模块计算路径
	pathfinding.request_path_to(target_pos)
	state_machine.change_state("moving")
	current_state = GameConstants.UnitState.MOVING

## 攻击目标
func command_attack(target: Node2D) -> void:
	_clear_build_order()
	attack_target = target
	has_move_target = false
	state_machine.change_state("attacking")
	current_state = GameConstants.UnitState.ATTACKING

## 采集资源
func command_gather(resource_node: Node2D, base: Node2D) -> void:
	if not can_gather:
		return
	_clear_build_order()
	
	# 如果工人已满载正在回矿，仅更新目标，不打断回矿路径
	if carried_resource >= GameConstants.WORKER_CARRY_AMOUNT and current_state == GameConstants.UnitState.RETURNING:
		gather_target = resource_node
		return_target = base
		return
	
	# 释放旧矿点占用
	_release_gather_target()
	gather_target = resource_node
	return_target = base
	# 如果已经在 gathering 状态，强制重新进入
	if current_state == GameConstants.UnitState.GATHERING:
		collision_mask = COLLISION_MASK_FULL
		_gather_timer = 0.0
		_gather_retry_timer = 0.0
		_gather_success_count = 0  # 新目标，重置计数
		pathfinding.ignore_resource = gather_target
		pathfinding.request_path_to(gather_target.global_position)
	else:
		state_machine.change_state("gathering")
	current_state = GameConstants.UnitState.GATHERING

## 手动交矿 (右键点击资源收集站)
func command_return(base: Node2D) -> void:
	if not can_gather:
		return
	_clear_build_order()
	return_target = base
	if carried_resource > 0:
		state_machine.change_state("returning")
		current_state = GameConstants.UnitState.RETURNING
	else:
		# 没有资源，移动到基地附近
		command_move(base.global_position)

## 停止
func command_stop() -> void:
	_clear_build_order()
	_release_gather_target()  # 释放矿点占用 (必须在 gather_target=null 之前)
	has_move_target = false
	attack_target = null
	gather_target = null
	state_machine.change_state("idle")
	current_state = GameConstants.UnitState.IDLE

## 建造建筑 (工人移动到建造点后开工)
func command_construct(building_key: String, target_pos: Vector2) -> void:
	if not can_build:
		return
	_clear_build_order()
	_release_gather_target()  # 释放矿点占用 (必须在 gather_target=null 之前)
	_build_target_key = building_key
	_build_target_pos = target_pos
	_has_build_order = true
	_construction_emitted = false
	has_move_target = false
	attack_target = null
	gather_target = null
	return_target = null
	state_machine.change_state("building")
	current_state = GameConstants.UnitState.BUILDING

## 受到伤害
func take_damage(damage: int) -> void:
	AudioManager.play_event_sfx("hit")
	var original_damage := damage
	var had_shield := shield > 0
	# 先扣护盾
	if shield > 0:
		var shield_dmg := mini(damage, shield)
		shield -= shield_dmg
		damage -= shield_dmg
	
	hp -= damage
	
	# === 受击特效 ===
	var fx := _get_combat_effects()
	if fx:
		fx.spawn_damage_number(global_position, original_damage)
		if had_shield and original_damage > damage:
			fx.spawn_shield_hit(global_position, unit_radius * 1.5)
		else:
			fx.flash_entity(self, Color(1, 0.5, 0.5), 0.12)
			fx.spawn_hit_spark(global_position, Color.ORANGE)
	
	if hp <= 0:
		hp = 0
		_die()

## 选中/取消选中
func select() -> void:
	is_selected = true
	if visual:
		visual.is_selected = true
	unit_selected.emit(self)

func deselect() -> void:
	is_selected = false
	if visual:
		visual.is_selected = false
	unit_deselected.emit(self)

## ====== 状态机回调 ======

func _on_enter_idle() -> void:
	velocity = Vector2.ZERO
	current_velocity = Vector2.ZERO
	pathfinding.clear_path()
	_release_gather_target()
	collision_mask = COLLISION_MASK_FULL  # 恢复与其他单位碰撞
	if visual:
		visual.play_animation("idle")

func _on_update_idle(_delta: float) -> void:
	pass  # 自动索敌由 GameWorld._simulate_tick 统一处理

func _on_enter_moving() -> void:
	collision_mask = COLLISION_MASK_FULL  # 恢复完整碰撞 (从 gathering/returning 过来时 mask=1|4|8)
	if visual:
		visual.play_animation("move")

func _on_update_moving(delta: float) -> void:
	if not has_move_target:
		state_machine.change_state("idle")
		current_state = GameConstants.UnitState.IDLE
		return

	var arrived: bool = pathfinding.advance_on_path(move_target, delta, move_speed)
	if arrived:
		has_move_target = false
		pathfinding.clear_path()
		state_machine.change_state("idle")
		current_state = GameConstants.UnitState.IDLE

func _on_enter_attacking() -> void:
	collision_mask = COLLISION_MASK_FULL  # 恢复完整碰撞
	if visual:
		visual.play_animation("attack")

func _on_update_attacking(delta: float) -> void:
	if attack_target == null or not is_instance_valid(attack_target):
		attack_target = null
		state_machine.change_state("idle")
		current_state = GameConstants.UnitState.IDLE
		return
	
	# 确定性检查: 目标是否已死亡 (不依赖 queue_free 时机，避免联机 desync)
	var target_dead := false
	if attack_target is BaseUnit and attack_target.current_state == GameConstants.UnitState.DEAD:
		target_dead = true
	elif attack_target is BaseBuilding and attack_target.hp <= 0:
		target_dead = true
	if target_dead:
		attack_target = null
		state_machine.change_state("idle")
		current_state = GameConstants.UnitState.IDLE
		return
	
	# 建筑使用边缘距离, 单位使用中心距离
	var dist := _distance_to_target_edge(attack_target)
	
	if dist > attack_range:
		# 移动接近目标 (建筑用边缘接近点, 单位用中心)
		var approach := _get_attack_approach_target(attack_target)
		pathfinding.follow_path_toward(approach, delta, move_speed)
	else:
		# 在攻击范围内，开火
		velocity = Vector2.ZERO
		if visual:
			visual.facing_angle = (attack_target.global_position - global_position).angle()
		
		if _attack_timer <= 0:
			_perform_attack()
			_attack_timer = attack_cooldown

func _on_enter_gathering() -> void:
	collision_mask = COLLISION_MASK_FULL  # 采集时也保留与其他单位碰撞
	_gather_retry_timer = 0.0
	_gather_success_count = 0  # 新目标，重置采集计数
	# 告知寻路模块忽略目标矿点的碰撞，避免被矿点推开而陷入贴墙循环
	pathfinding.ignore_resource = gather_target
	if visual:
		visual.play_animation("gather")
	# 委托寻路模块计算到矿点的路径
	if gather_target and is_instance_valid(gather_target):
		pathfinding.request_path_to(gather_target.global_position)

func _on_update_gathering(delta: float) -> void:
	if gather_target == null or not is_instance_valid(gather_target):
		state_machine.change_state("idle")
		current_state = GameConstants.UnitState.IDLE
		return
	
	# 如果已经满载，回基地
	if carried_resource >= GameConstants.WORKER_CARRY_AMOUNT:
		state_machine.change_state("returning")
		current_state = GameConstants.UnitState.RETURNING
		return
	
	var dist := global_position.distance_to(gather_target.global_position)
	var gather_range := 35.0
	if gather_target is ResourceNode:
		var res := gather_target as ResourceNode
		gather_range = maxf(gather_range, unit_radius + res.get_collision_radius() + 2.0)
	
	if dist > gather_range:
		# 走向矿点 (使用寻路模块)
		pathfinding.follow_path_toward(gather_target.global_position, delta, move_speed)
	else:
		# 到达矿点，尝试占用
		if gather_target.has_method("try_occupy") and not gather_target.try_occupy(self):
			# 矿点被占用：
			#   未锁定（采集 <3 次）→ 立刻寻找附近空闲矿/能，找不到则原地等待 1.5s 再试
			#   已锁定（采集 >=3 次）→ 最多等待 10 秒再考虑切换
			var locked: bool = _gather_success_count >= 3
			var wait_limit: float = 10.0 if locked else 1.5
			_gather_retry_timer += delta
			if _gather_retry_timer >= wait_limit:
				_gather_retry_timer = 0.0
				# 未锁定：优先寻找空闲点；已锁定：只有超时才切换
				var retry_node := _find_free_resource_nearby()
				if retry_node:
					gather_target = retry_node
					_gather_success_count = 0  # 切换目标，重置计数
					pathfinding.ignore_resource = gather_target  # 必须在 request_path_to 之前更新
					pathfinding.request_path_to(gather_target.global_position)
			# 同步当前目标（无论是否切换）
			pathfinding.ignore_resource = gather_target
			velocity = Vector2.ZERO
			return
		# 成功占用矿点，重置等待计时器
		_gather_retry_timer = 0.0
		# 采集
		velocity = Vector2.ZERO
		_gather_timer += delta
		if _gather_timer >= GameConstants.WORKER_GATHER_TIME:
			_gather_timer = 0.0
			# 记录采集资源类型
			if gather_target.has_method("gather"):
				carried_resource_type = gather_target.resource_type
				var gathered: int = gather_target.gather(1)
				carried_resource = mini(carried_resource + gathered, GameConstants.WORKER_CARRY_AMOUNT)
			else:
				carried_resource = mini(carried_resource + 1, GameConstants.WORKER_CARRY_AMOUNT)
			# 每次采集成功累计计数，达到 3 次即锁定该点位
			_gather_success_count += 1

func _on_enter_returning() -> void:
	# 离开采集状态，释放矿点占用（同时清除 ignore_resource）
	_release_gather_target()
	collision_mask = COLLISION_MASK_FULL  # 回矿时也保留与其他单位碰撞
	if visual:
		visual.play_animation("move")
	# 委托寻路模块计算到基地的路径 (目标为建筑边缘而非中心, 避免寻路到不可达目标)
	if return_target and is_instance_valid(return_target):
		pathfinding.request_path_to(_get_depot_approach_target())

func _on_enter_building() -> void:
	collision_mask = COLLISION_MASK_FULL
	if visual:
		visual.play_animation("gather")
	# 委托寻路模块计算到建造目标的路径
	if _has_build_order:
		pathfinding.request_path_to(_build_target_pos)

func _on_update_building(delta: float) -> void:
	# 辅助建造模式: 工人留在旁边直到建筑完工
	if assisting_building != null:
		if not is_instance_valid(assisting_building) or assisting_building.hp <= 0:
			# 建筑被摧毁
			assisting_building = null
			state_machine.change_state("idle")
			current_state = GameConstants.UnitState.IDLE
			return
		if assisting_building.is_built:
			# 建筑完工
			assisting_building = null
			state_machine.change_state("idle")
			current_state = GameConstants.UnitState.IDLE
			return
		# 留在旁边等待 (不移动)
		velocity = Vector2.ZERO
		return

	if not _has_build_order:
		state_machine.change_state("idle")
		current_state = GameConstants.UnitState.IDLE
		return

	var dist := global_position.distance_to(_build_target_pos)
	var reach_dist := unit_radius + 16.0
	if dist > reach_dist:
		pathfinding.follow_path_toward(_build_target_pos, delta, move_speed)
		return

	velocity = Vector2.ZERO
	if not _construction_emitted:
		_construction_emitted = true
		construction_started.emit(self, _build_target_key, _build_target_pos)
	# 不立即回到 idle, 由 GameWorld 设置 assisting_building 后继续留在 building 状态
	# 如果 assisting_building 没被设置 (放置失败/退款), 下一帧 _has_build_order=false 会回 idle
	_clear_build_order()

func _on_update_returning(delta: float) -> void:
	if return_target == null or not is_instance_valid(return_target):
		state_machine.change_state("idle")
		current_state = GameConstants.UnitState.IDLE
		return
	
	# 计算到资源站的有效距离 (矩形建筑使用到碰撞边缘的距离)
	var deliver_dist := global_position.distance_to(return_target.global_position)
	var deliver_threshold := unit_radius + 12.0
	if return_target is BaseBuilding:
		var bsize := Vector2(return_target.building_size) * GameConstants.TILE_SIZE
		var half := bsize * 0.5
		var offset := global_position - return_target.global_position
		var dx := maxf(0.0, absf(offset.x) - half.x)
		var dy := maxf(0.0, absf(offset.y) - half.y)
		deliver_dist = sqrt(dx * dx + dy * dy)
	
	if deliver_dist > deliver_threshold:
		pathfinding.follow_path_toward(_get_depot_approach_target(), delta, move_speed)
	else:
		# 交付资源
		resource_delivered.emit(self, carried_resource)
		carried_resource = 0
		# 继续回去采
		if gather_target and is_instance_valid(gather_target):
			state_machine.change_state("gathering")
			current_state = GameConstants.UnitState.GATHERING
		else:
			state_machine.change_state("idle")
			current_state = GameConstants.UnitState.IDLE

## 计算返回资源站的移动目标 (建筑碰撞体外侧最近点, 保证寻路可达)
func _get_depot_approach_target() -> Vector2:
	if return_target is BaseBuilding:
		var half := Vector2(return_target.building_size) * GameConstants.TILE_SIZE * 0.5
		var offset := global_position - return_target.global_position
		# 投影到建筑 AABB 表面外侧 (偏移 unit_radius + 4 保证寻路目标不在建筑内部)
		var clamped := Vector2(
			clampf(offset.x, -half.x, half.x),
			clampf(offset.y, -half.y, half.y)
		)
		# 计算法线方向并偏移到碰撞体外侧
		var outward := offset - clamped
		if outward.length_squared() > 0.01:
			outward = outward.normalized() * (unit_radius + 4.0)
		else:
			# 工人在建筑内部 (罕见), 往下方推出
			outward = Vector2(0, half.y + unit_radius + 4.0) - clamped
		return return_target.global_position + clamped + outward
	return return_target.global_position

func _on_enter_dead() -> void:
	current_state = GameConstants.UnitState.DEAD
	if visual:
		visual.play_animation("death")
	velocity = Vector2.ZERO
	current_velocity = Vector2.ZERO
	pathfinding.clear_path()
	collision_layer = 0
	collision_mask = 0
	# 死亡爆炸特效
	var fx := _get_combat_effects()
	if fx:
		var team_color: Color = GameConstants.TEAM_COLORS.get(team_id, Color.ORANGE_RED)
		fx.spawn_death_effect(global_position, unit_radius, false, team_color)
	# 淡出动画后移除
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	tween.tween_callback(queue_free)

## ====== 内部方法 ======

## 计算到建筑边缘的距离 (基于 AABB)
func _distance_to_building_edge(building: BaseBuilding) -> float:
	var half := Vector2(building.building_size) * GameConstants.TILE_SIZE * 0.5
	var offset := global_position - building.global_position
	var dx := maxf(0.0, absf(offset.x) - half.x)
	var dy := maxf(0.0, absf(offset.y) - half.y)
	return sqrt(dx * dx + dy * dy)

## 计算到攻击目标的有效距离 (建筑用边缘, 单位用中心)
func _distance_to_target_edge(target: Node2D) -> float:
	if target is BaseBuilding:
		return _distance_to_building_edge(target as BaseBuilding)
	return global_position.distance_to(target.global_position)

## 获取攻击时的接近目标点 (建筑取边缘最近可达点, 单位取中心)
func _get_attack_approach_target(target: Node2D) -> Vector2:
	if target is BaseBuilding:
		var building := target as BaseBuilding
		var half := Vector2(building.building_size) * GameConstants.TILE_SIZE * 0.5
		var offset := global_position - building.global_position
		# 投影到建筑 AABB 表面最近点 (保证寻路目标在建筑边缘附近)
		return building.global_position + Vector2(
			clampf(offset.x, -half.x, half.x),
			clampf(offset.y, -half.y, half.y)
		)
	return target.global_position

## 释放矿点占用
func _release_gather_target() -> void:
	if gather_target and is_instance_valid(gather_target) and gather_target.has_method("release"):
		gather_target.release(self)
	pathfinding.ignore_resource = null  # 恢复对所有资源的碰撞检测

## 全图搜索半径：仅用于首次指派目标时，5 × 指挥中心格数 × 瓦片大小
## 防止工人跑到敌方基地采矿
const GATHER_SEARCH_RADIUS: float = 5.0 * 4.0 * GameConstants.TILE_SIZE

## 矿点被占时附近搜索半径：以原矿点为圆心的搜索范围
## 设为 10 格，覆盖附近同一片矿区内的所有矿/能
const GATHER_NEARBY_RADIUS: float = 10.0 * GameConstants.TILE_SIZE

func _find_free_resource_nearby() -> ResourceNode:
	if not gather_target or not is_instance_valid(gather_target):
		return null
	# 以原矿点为圆心，在 GATHER_NEARBY_RADIUS 范围内搜索任意类型的空闲矿/能
	# 传入 -1 表示不限类型，不要求与原矿点相同
	return _find_free_resource_of_type(-1, gather_target.global_position, GATHER_NEARBY_RADIUS)

func _is_resource_occupied_by_other(res: ResourceNode) -> bool:
	return res.occupied_by != null and is_instance_valid(res.occupied_by) and res.occupied_by != self

## 在 search_center 圆心、max_dist 半径内搜索空闲矿点
## res_type = -1 时不限资源类型，直接选附近最近的空闲矿/能
func _find_free_resource_of_type(res_type: int, search_center: Vector2, max_dist: float) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist := INF
	for res in GameManager._all_resources:
		if not is_instance_valid(res):
			continue
		var rnode := res as ResourceNode
		if res_type != -1 and rnode.resource_type != res_type:
			continue
		if rnode == gather_target:
			continue
		if rnode.remaining_amount <= 0:
			continue
		# 空闲或被自己占用
		if _is_resource_occupied_by_other(rnode):
			continue
		# 必须在搜索圆内
		if search_center.distance_to(rnode.global_position) > max_dist:
			continue
		# 选最近的（以工人当前位置排序，走最少路）
		var dist := global_position.distance_to(rnode.global_position)
		if dist < best_dist:
			best_dist = dist
			best = rnode
	return best

func _perform_attack() -> void:
	if attack_target and is_instance_valid(attack_target) and attack_target.has_method("take_damage"):
		attack_target.take_damage(attack_power)
		unit_attacked.emit(self, attack_target)
		
		# === 战斗特效 ===
		var fx := _get_combat_effects()
		if fx:
			var data: Dictionary = GameConstants.UNIT_DATA.get(unit_data_key, {})
			var unit_type: int = data.get("type", GameConstants.UnitType.WORKER)
			var team_color: Color = GameConstants.TEAM_COLORS.get(team_id, Color.WHITE)
			
			if unit_type == GameConstants.UnitType.TANK:
				# 坦克：大型弹道 + 炮口火焰
				var dir_to := (attack_target.global_position - global_position).normalized()
				var muzzle := global_position + dir_to * unit_radius * 1.5
				fx.spawn_projectile(muzzle, attack_target.global_position, Color(1, 0.7, 0.2), 500.0, 5.0)
				fx.spawn_hit_spark(muzzle, Color(1, 0.8, 0.3))
			elif unit_type == GameConstants.UnitType.HELICOPTER:
				# 飞机：连续弹
				var dir_to := (attack_target.global_position - global_position).normalized()
				var muzzle := global_position + dir_to * unit_radius
				fx.spawn_projectile(muzzle, attack_target.global_position, Color.RED, 700.0, 3.0)
			elif faction == GameConstants.Faction.SHADOW_TECH and unit_type == GameConstants.UnitType.INFANTRY:
				# 暗影步兵：能量刀光
				fx.spawn_attack_line(global_position, attack_target.global_position, Color(0.5, 0.2, 1.0), 3.0, 0.2)
			else:
				# 默认：枪弹
				var dir_to := (attack_target.global_position - global_position).normalized()
				var muzzle := global_position + dir_to * unit_radius
				fx.spawn_projectile(muzzle, attack_target.global_position, Color.YELLOW, 600.0, 2.5)

func _auto_acquire_target() -> void:
	var closest_dist := INF
	var closest_enemy: Node2D = null
	# 确定性遍历单位列表 (不使用物理查询)
	for other in GameManager._all_units:
		if not is_instance_valid(other) or other == self:
			continue
		if other.team_id == team_id:
			continue
		if other.current_state == GameConstants.UnitState.DEAD:
			continue
		var dist := global_position.distance_to(other.global_position)
		if dist <= vision_range and dist < closest_dist:
			closest_dist = dist
			closest_enemy = other
	# 确定性遍历建筑列表 (使用边缘距离)
	for other in GameManager._all_buildings:
		if not is_instance_valid(other) or other.team_id == team_id:
			continue
		if other.hp <= 0:
			continue
		var dist := _distance_to_building_edge(other)
		if dist <= vision_range and dist < closest_dist:
			closest_dist = dist
			closest_enemy = other
	if closest_enemy:
		command_attack(closest_enemy)

func _die() -> void:
	AudioManager.play_event_sfx("explosion")
	unit_died.emit(self)
	state_machine.change_state("dead")

func _clear_build_order() -> void:
	_build_target_key = ""
	_build_target_pos = Vector2.ZERO
	_has_build_order = false
	_construction_emitted = false
	# 注意: 不清除 assisting_building, 那是在建筑完工后才清的

## 获取战斗特效系统
func _get_combat_effects() -> CombatEffects:
	var parent := get_parent()
	if parent:
		var effect_layer := parent.get_parent()
		if effect_layer:
			var fx := effect_layer.get_node_or_null("EffectLayer/CombatEffects")
			if fx:
				return fx as CombatEffects
	# 备选：直接从场景树查找
	var tree_root := get_tree().root
	var game_world := tree_root.get_node_or_null("GameWorld")
	if game_world:
		var fx := game_world.get_node_or_null("EffectLayer/CombatEffects")
		if fx:
			return fx as CombatEffects
	return null
