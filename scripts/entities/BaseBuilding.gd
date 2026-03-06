## 基础建筑 - 所有建筑的基类
class_name BaseBuilding
extends StaticBody2D

signal building_selected(building: BaseBuilding)
signal building_deselected(building: BaseBuilding)
signal building_destroyed(building: BaseBuilding)
signal building_completed(building: BaseBuilding)
signal unit_produced(building: BaseBuilding, unit_key: String)

## 建筑数据键
@export var building_data_key: String = "command_center"

## 网络唯一ID
var entity_id: int = -1
var owner_peer_id: int = 0
var player_color_id: int = 0

## 阵营
var team_id: int = 0

## 属性
var max_hp: int = 1000
var hp: int = 1000
var building_size: Vector2i = Vector2i(3, 3)
var vision_range: float = 250.0

## 建造
var is_built: bool = false
var build_progress: float = 0.0  # 0~1
var build_time: float = 30.0
var build_worker_range: float = 72.0

## 生产
var can_produce: Array = []  # 可以生产的单位类型键列表
var is_producing: bool = false
var production_queue: Array = []  # [{unit_key, progress, total_time}]

## 资源收集站
var is_resource_depot: bool = false

## 防御塔
var has_attack: bool = false
var attack_power: int = 0
var attack_range_val: float = 0.0
var _attack_timer: float = 0.0
var attack_target: Node2D = null

## 能源产出
var energy_output: int = 0

## 集结点
var rally_point: Vector2 = Vector2.ZERO
var has_rally_point: bool = false

## 状态
var is_selected: bool = false

## 组件
var visual: BuildingVisual = null

func _ready() -> void:
	_init_from_data()
	_setup_visual()
	_setup_collision()

func _init_from_data() -> void:
	var data: Dictionary = GameConstants.BUILDING_DATA.get(building_data_key, {})
	if data.is_empty():
		return
	
	max_hp = data.get("hp", 1000)
	hp = max_hp
	building_size = data.get("size", Vector2i(3, 3))
	vision_range = data.get("vision_range", 250.0)
	build_time = data.get("build_time", 30.0)
	is_resource_depot = data.get("is_resource_depot", false)
	energy_output = data.get("energy_output", 0)
	
	# 生产列表
	var produces: Array = data.get("produces", [])
	can_produce = produces
	
	# 攻击 (防御塔)
	attack_power = data.get("attack", 0)
	attack_range_val = data.get("attack_range", 0.0)
	has_attack = attack_power > 0

func _setup_visual() -> void:
	visual = BuildingVisual.new()
	visual.building_type = building_data_key
	visual.building_size = building_size
	visual.team_id = player_color_id
	visual.hp = hp
	visual.max_hp = max_hp
	visual.build_progress = build_progress
	visual.name = "Visual"
	add_child(visual)

func _setup_collision() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(building_size) * GameConstants.TILE_SIZE
	var col := CollisionShape2D.new()
	col.shape = shape
	col.name = "CollisionShape"
	add_child(col)
	collision_layer = 4  # buildings layer
	collision_mask = 0

func _process(_delta: float) -> void:
	_update_visual()

## 由 GameWorld 在每个同步 tick 调用，返回本 tick 完成生产的单位列表
func simulate_tick(dt: float) -> Array:
	var produced: Array = []
	var instant := GameManager.cheat_instant_build
	# 建造进度
	if not is_built:
		if instant or _has_builder_in_range():
			if instant:
				build_progress = 1.0
			else:
				build_progress += dt / build_time
			if build_progress >= 1.0:
				build_progress = 1.0
				is_built = true
				building_completed.emit(self)
	# 生产队列
	if is_built and production_queue.size() > 0:
		var current: Dictionary = production_queue[0]
		if instant:
			current["progress"] = 1.0
		else:
			current["progress"] += dt / current["total_time"]
		if current["progress"] >= 1.0:
			var unit_key: String = current["unit_key"]
			production_queue.pop_front()
			is_producing = production_queue.size() > 0
			produced.append({"building": self, "unit_key": unit_key})
	# 防御塔攻击
	if is_built and has_attack:
		_update_defense(dt)
	return produced

func _update_visual() -> void:
	z_index = 10
	if visual:
		visual.team_id = player_color_id
		visual.hp = hp
		visual.build_progress = build_progress
		visual.is_selected = is_selected
		visual.is_producing = production_queue.size() > 0
		visual.has_rally_point = has_rally_point
		visual.rally_point = rally_point
		if production_queue.size() > 0:
			visual.production_progress = production_queue[0].get("progress", 0.0)

## ====== 公共接口 ======

## 开始建造 (出生时调用)
func start_build(instant: bool = false) -> void:
	if instant:
		build_progress = 1.0
		is_built = true
		building_completed.emit(self)
	else:
		build_progress = 0.0
		is_built = false

## 生产单位 (加入队列)
func queue_production(unit_key: String) -> bool:
	if not is_built:
		return false
	# 检查是否能生产该类型
	var unit_data: Dictionary = GameConstants.UNIT_DATA.get(unit_key, {})
	if unit_data.is_empty():
		return false
	
	production_queue.append({
		"unit_key": unit_key,
		"progress": 0.0,
		"total_time": unit_data.get("build_time", 15.0),
	})
	is_producing = true
	return true

## 取消生产 (取消最后一个)
func cancel_production() -> Dictionary:
	if production_queue.size() > 0:
		var cancelled: Dictionary = production_queue.pop_back()
		if production_queue.size() == 0:
			is_producing = false
		return cancelled
	return {}

## 设置集结点
func set_rally_point(world_pos: Vector2) -> void:
	rally_point = world_pos
	has_rally_point = true

## 受伤
func take_damage(damage: int) -> void:
	AudioManager.play_event_sfx("hit")
	hp -= damage
	# 受击特效
	var fx := _get_combat_effects()
	if fx:
		fx.spawn_damage_number(global_position, damage)
		fx.flash_entity(self, Color(1, 0.5, 0.5), 0.12)
		fx.spawn_hit_spark(global_position, Color.ORANGE)
	if hp <= 0:
		hp = 0
		_destroy()

## 选中
func select() -> void:
	is_selected = true
	building_selected.emit(self)

func deselect() -> void:
	is_selected = false
	building_deselected.emit(self)

## 美术素材替换接口
func set_building_sprite(texture: Texture2D) -> void:
	if visual:
		visual.set_sprite(texture)

func set_building_animation(frames: SpriteFrames, default_anim: String = "idle") -> void:
	if visual:
		visual.set_animation(frames, default_anim)

## ====== 内部 ======

func _update_production(delta: float) -> void:
	var current: Dictionary = production_queue[0]
	current["progress"] += delta / current["total_time"]
	
	if current["progress"] >= 1.0:
		# 生产完成
		var unit_key: String = current["unit_key"]
		production_queue.pop_front()
		is_producing = production_queue.size() > 0
		unit_produced.emit(self, unit_key)

func _has_builder_in_range() -> bool:
	for unit in GameManager._all_units:
		if not is_instance_valid(unit):
			continue
		if unit.current_state == GameConstants.UnitState.DEAD:
			continue
		if unit.team_id != team_id:
			continue
		if not unit.can_build:
			continue
		var dist: float = unit.global_position.distance_to(global_position)
		var half: Vector2 = Vector2(building_size) * GameConstants.TILE_SIZE * 0.5
		var reach: float = maxf(half.x, half.y) + build_worker_range
		if dist <= reach:
			return true
	return false

func _update_defense(delta: float) -> void:
	_attack_timer -= delta
	if _attack_timer > 0:
		return
	
	# 扫描范围内敌人 (含确定性死亡检查，避免联机 desync)
	var need_retarget := attack_target == null or not is_instance_valid(attack_target)
	if not need_retarget:
		if attack_target is BaseUnit and attack_target.current_state == GameConstants.UnitState.DEAD:
			need_retarget = true
		elif attack_target is BaseBuilding and attack_target.hp <= 0:
			need_retarget = true
	if need_retarget:
		attack_target = _find_enemy_in_range()
	
	if attack_target:
		var dist := global_position.distance_to(attack_target.global_position)
		if dist <= attack_range_val:
			# 攻击
			if attack_target.has_method("take_damage"):
				attack_target.take_damage(attack_power)
			_attack_timer = 1.0  # 1秒攻击间隔
			# 更新炮塔朝向
			if visual:
				visual.facing_angle = (attack_target.global_position - global_position).angle()
			# 防御塔弹道特效
			var fx := _get_combat_effects()
			if fx:
				fx.spawn_projectile(global_position, attack_target.global_position, Color(1, 0.4, 0.2), 500.0, 4.0)
		else:
			attack_target = null

func _find_enemy_in_range() -> Node2D:
	var closest_dist := INF
	var closest_enemy: Node2D = null
	# 确定性遍历单位列表 (不使用物理查询)
	for unit in GameManager._all_units:
		if not is_instance_valid(unit):
			continue
		if unit.team_id == team_id:
			continue
		if unit.current_state == GameConstants.UnitState.DEAD:
			continue
		var dist := global_position.distance_to(unit.global_position)
		if dist <= attack_range_val and dist < closest_dist:
			closest_dist = dist
			closest_enemy = unit
	return closest_enemy

func _destroy() -> void:
	AudioManager.play_event_sfx("explosion")
	building_destroyed.emit(self)
	# 建筑爆炸特效
	var fx := _get_combat_effects()
	if fx:
		var bsize := Vector2(building_size) * GameConstants.TILE_SIZE
		var radius := maxf(bsize.x, bsize.y) / 2.0
		fx.spawn_death_effect(global_position, radius, true, Color(1, 0.4, 0.1))
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)

## 获取战斗特效系统
func _get_combat_effects() -> CombatEffects:
	var parent := get_parent()
	if parent:
		var effect_layer := parent.get_parent()
		if effect_layer:
			var fx := effect_layer.get_node_or_null("EffectLayer/CombatEffects")
			if fx:
				return fx as CombatEffects
	var tree_root := get_tree().root
	var game_world := tree_root.get_node_or_null("GameWorld")
	if game_world:
		var fx := game_world.get_node_or_null("EffectLayer/CombatEffects")
		if fx:
			return fx as CombatEffects
	return null
