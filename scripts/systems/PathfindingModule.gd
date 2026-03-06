## 寻路模块 - 将自动寻路、碰撞回避、路径跟随解耦到独立组件
##
## 用法:
##   var pathfinding := PathfindingModule.new(owner_unit)
##   pathfinding.request_path_to(target_pos)               # 请求路径（含绕角规划）
##   pathfinding.follow_path_toward(target, delta, speed)  # 路径跟随 (含 ORCA + 障碍推开)
##   pathfinding.move_step(direction, distance)            # 单次位移 + 碰撞解算
##   pathfinding.has_clear_line(from, to)                  # 视线检测
##
## 所有方法均在 BaseUnit 的 simulate_tick 里调用，完全确定性，支持录像回放。
class_name PathfindingModule
extends RefCounted

# ──────────────────────────────────────────────────────────
#  常量
# ──────────────────────────────────────────────────────────

## 近距离直线移动阈值：低于此距离时跳过规划直接走直线
const DIRECT_MOVE_THRESHOLD: float = 96.0   # 1.5 格

## 到达路径节点的容差
const WAYPOINT_REACH_DIST: float = 8.0

## 到达最终目标的容差
const GOAL_REACH_DIST: float = 10.0

## 卡住检测
const STUCK_FRAME_THRESHOLD: int = 8
const STUCK_MOVE_EPSILON: float = 0.35
const FORCED_SIDE_DURATION_FRAMES: int = 30

## 贴墙行走：每帧探测目标方向局部畅通性，一旦发现前方无障碍立即切回目标
## 探测距离：向目标方向看多远（像素）来判断局部畅通
const WALL_FOLLOW_PROBE_DIST: float = 80.0
## 退出宽容：连续 N 帧目标方向畅通后才真正切回，避免凹角瞬间抖动
const WALL_FOLLOW_EXIT_FRAMES: int = 2

# ──────────────────────────────────────────────────────────
#  公有状态（由 BaseUnit 读写）
# ──────────────────────────────────────────────────────────

## 当前路径（规划好的绕角拐点列表）
var path: PackedVector2Array = PackedVector2Array()

## 当前跟踪的路径点下标
var path_index: int = 0

## 当前速度向量（ORCA 计算结果，供动画朝向使用）
var current_velocity: Vector2 = Vector2.ZERO

# ──────────────────────────────────────────────────────────
#  内部状态
# ──────────────────────────────────────────────────────────

var _unit: CharacterBody2D              # 持有单位引用
var _stuck_frames: int = 0
var _forced_side_sign: int = 0          # -1=左绕, 1=右绕
var _forced_side_frames_left: int = 0
## 上一次建筑碰撞解算产生的推力法线（用于贴墙滑行）
var _last_push_normal: Vector2 = Vector2.ZERO
## 当前寻路目标（供贴墙方向选边使用）
var _current_goal: Vector2 = Vector2.ZERO

## 采集时忽略碰撞的资源节点（避免工人被矿点推开无法进入采集状态）
var ignore_resource: Node2D = null

## ── 贴墙状态机 ──────────────────────────────────────────
## NONE=自由行走  FOLLOWING=贴墙中  EXITING=视线重开宽容期
enum WallState { NONE, FOLLOWING, EXITING }
var _wall_state: WallState = WallState.NONE
## 贴墙方向（固定切线，单位向量）；一旦确定不再重选直到退出
var _wall_tangent: Vector2 = Vector2.ZERO
## 宽容期计数
var _wall_exit_frames: int = 0

# ──────────────────────────────────────────────────────────
#  初始化
# ──────────────────────────────────────────────────────────

func _init(owner_unit: CharacterBody2D) -> void:
	_unit = owner_unit

# ──────────────────────────────────────────────────────────
#  公有接口
# ──────────────────────────────────────────────────────────

## 重置路径状态（切换目标时调用）
func clear_path() -> void:
	path = PackedVector2Array()
	path_index = 0
	current_velocity = Vector2.ZERO
	_wall_state = WallState.NONE
	_wall_tangent = Vector2.ZERO
	_wall_exit_frames = 0

## 请求到 target 的路径，先做绕角可见性规划再存入 path
func request_path_to(target: Vector2) -> void:
	_current_goal = target
	# 出发前重置贴墙状态，让新规划路径接管
	_wall_state = WallState.NONE
	_wall_tangent = Vector2.ZERO
	_wall_exit_frames = 0
	var from := _unit.global_position
	var planned := _plan_path(from, target)
	path = planned
	path_index = 0

## 检查当前路径是否仍有效（路径非空且下标未越界）
func has_active_path() -> bool:
	return path.size() > 0 and path_index < path.size()

## 通用路径跟随：采集/回矿/建造/攻击追敌均统一调用此方法
## 返回 true 表示已到达目标
func follow_path_toward(target: Vector2, delta: float, speed: float) -> bool:
	_current_goal = target
	var dist_to_target := _unit.global_position.distance_to(target)

	# 近距离 + 视线通畅 → 直接走直线
	if dist_to_target < DIRECT_MOVE_THRESHOLD and has_clear_line(_unit.global_position, target):
		var dir := (target - _unit.global_position).normalized()
		_set_facing(dir.angle())
		var preferred_vel := dir * speed
		current_velocity = _apply_orca(preferred_vel, delta)
		var step_dist := minf(current_velocity.length() * delta, dist_to_target)
		move_step(current_velocity.normalized(), step_dist)
		return _unit.global_position.distance_to(target) < GOAL_REACH_DIST

	# 路径无效则重新请求
	if not has_active_path():
		request_path_to(target)

	if not has_active_path():
		# 寻路失败 → 直线强行走
		var dir := (target - _unit.global_position).normalized()
		_set_facing(dir.angle())
		var preferred_vel := dir * speed
		current_velocity = _apply_orca(preferred_vel, delta)
		move_step(current_velocity.normalized(), current_velocity.length() * delta)
		return false

	# 沿路径点推进
	var remaining := speed * delta
	while remaining > 0.0 and path_index < path.size():
		var waypoint := path[path_index]
		var to_wp := waypoint - _unit.global_position
		var wp_dist := to_wp.length()

		if wp_dist < WAYPOINT_REACH_DIST:
			path_index += 1
			continue

		var dir := to_wp.normalized()
		_set_facing(dir.angle())
		var preferred_vel := dir * speed
		current_velocity = _apply_orca(preferred_vel, delta)

		if wp_dist <= remaining:
			remaining -= wp_dist
			path_index += 1
			move_step(current_velocity.normalized(), wp_dist)
		else:
			move_step(current_velocity.normalized(), remaining)
			remaining = 0.0

	return _unit.global_position.distance_to(target) < GOAL_REACH_DIST

## 沿路径点推进用于 MOVING 状态（移动命令）
## 返回 true 表示已到达 move_target
func advance_on_path(move_target: Vector2, delta: float, speed: float) -> bool:
	_current_goal = move_target
	if not has_active_path():
		# 无路径 → 直线走
		var dir := (move_target - _unit.global_position)
		var dist := dir.length()
		if dist < GOAL_REACH_DIST:
			return true
		dir = dir.normalized()
		var preferred_vel := dir * speed
		current_velocity = _apply_orca(preferred_vel, delta)
		_set_facing(current_velocity.angle() if current_velocity.length_squared() > 0.1 else dir.angle())
		move_step(current_velocity.normalized(), current_velocity.length() * delta)
		return false

	var remaining := speed * delta
	while remaining > 0.0 and path_index < path.size():
		var waypoint := path[path_index]
		var to_wp := waypoint - _unit.global_position
		var wp_dist := to_wp.length()

		if wp_dist < WAYPOINT_REACH_DIST:
			path_index += 1
			continue

		var dir := to_wp.normalized()
		_set_facing(dir.angle())

		if wp_dist <= remaining:
			remaining -= wp_dist
			path_index += 1
			var preferred_vel := dir * speed
			current_velocity = _apply_orca(preferred_vel, delta)
			move_step(current_velocity.normalized(), wp_dist)
		else:
			var preferred_vel := dir * speed
			current_velocity = _apply_orca(preferred_vel, delta)
			move_step(current_velocity.normalized(), remaining)
			remaining = 0.0

	if path_index >= path.size():
		if _unit.global_position.distance_to(move_target) < GOAL_REACH_DIST:
			return true
	return false

## 单次位移 + 完整碰撞解算
## 策略：直线通畅直接走；遇障时进入贴墙状态机，沿固定切线行走直到视线重开
func move_step(direction: Vector2, distance: float) -> void:
	if distance <= 0.0:
		return
	if direction.length_squared() < 0.0001:
		return

	var start: Vector2 = _unit.global_position
	var move_dir: Vector2 = direction.normalized()

	# ── 贴墙状态机：处于 FOLLOWING/EXITING 时，优先沿固定切线走 ────
	if _wall_state != WallState.NONE:
		_wall_follow_step(start, move_dir, distance)
		return

	# ── 自由状态：尝试直线 ──────────────────────────────────────────
	_last_push_normal = Vector2.ZERO
	var desired: Vector2 = start + move_dir * distance
	var direct_pos: Vector2 = _resolve_building_collisions(desired)
	if ((_unit.collision_mask & 8) != 0):
		direct_pos = _resolve_resource_collisions(direct_pos)
	if ((_unit.collision_mask & 2) != 0):
		direct_pos = _resolve_unit_collisions(direct_pos)

	var direct_step: Vector2 = direct_pos - start
	var direct_forward: float = direct_step.dot(move_dir)
	var direct_ok: bool = direct_forward >= distance * 0.65

	if direct_ok:
		_unit.global_position = direct_pos
		_update_unstuck_state(start, direct_pos)
		return

	# ── 直线受阻：进入贴墙状态 ──────────────────────────────────────
	# 从推力法线计算墙面切线，一次性固定下来
	var wall_normal: Vector2 = _last_push_normal
	if wall_normal.length_squared() < 0.0001:
		# 没有明确法线（单位碰撞等）：尝试贴墙滑行后放弃
		_unit.global_position = direct_pos
		_update_unstuck_state(start, direct_pos)
		return

	# 切线 = 法线旋转 90°，选择朝向目标的那侧
	var tan_a: Vector2 = Vector2(-wall_normal.y, wall_normal.x)
	var tan_b: Vector2 = -tan_a
	var to_goal: Vector2 = (_current_goal - start).normalized() if (_current_goal - start).length_squared() > 1.0 else move_dir
	var tangent: Vector2 = tan_a if tan_a.dot(to_goal) >= tan_b.dot(to_goal) else tan_b

	_wall_state = WallState.FOLLOWING
	_wall_tangent = tangent
	_wall_exit_frames = 0
	_wall_follow_step(start, move_dir, distance)

## 贴墙状态机步进：沿固定切线方向行走，直到视线重开
func _wall_follow_step(start: Vector2, original_dir: Vector2, distance: float) -> void:
	# 每帧向目标方向做近端探测：检测前方 WALL_FOLLOW_PROBE_DIST 像素是否畅通
	var to_goal_dir: Vector2 = Vector2.ZERO
	if (_current_goal - start).length_squared() > 1.0:
		to_goal_dir = (_current_goal - start).normalized()
	else:
		to_goal_dir = original_dir

	var probe_end: Vector2 = start + to_goal_dir * WALL_FOLLOW_PROBE_DIST
	# 探测用静态障碍检查（不含单位），避免友军路过导致永远无法离开贴墙
	var goal_dir_clear: bool = has_clear_line_static(start, probe_end)

	if goal_dir_clear:
		_wall_exit_frames += 1
	else:
		_wall_exit_frames = 0  # 目标方向又出现障碍，重置宽容期

	if _wall_exit_frames >= WALL_FOLLOW_EXIT_FRAMES:
		# 连续确认目标方向畅通 → 立刻退出贴墙，转向目标
		_wall_state = WallState.NONE
		_wall_tangent = Vector2.ZERO
		_wall_exit_frames = 0
		var goal_desired: Vector2 = start + to_goal_dir * distance
		_last_push_normal = Vector2.ZERO
		var goal_pos: Vector2 = _resolve_building_collisions(goal_desired)
		if ((_unit.collision_mask & 8) != 0):
			goal_pos = _resolve_resource_collisions(goal_pos)
		if ((_unit.collision_mask & 2) != 0):
			goal_pos = _resolve_unit_collisions(goal_pos)
		_set_facing(to_goal_dir.angle())
		_unit.global_position = goal_pos
		_update_unstuck_state(start, goal_pos)
		return

	# 沿固定切线方向行走
	var tangent: Vector2 = _wall_tangent
	_set_facing(tangent.angle())
	var tan_desired: Vector2 = start + tangent * distance
	_last_push_normal = Vector2.ZERO
	var tan_pos: Vector2 = _resolve_building_collisions(tan_desired)
	if ((_unit.collision_mask & 8) != 0):
		tan_pos = _resolve_resource_collisions(tan_pos)
	if ((_unit.collision_mask & 2) != 0):
		tan_pos = _resolve_unit_collisions(tan_pos)

	var tan_step: Vector2 = tan_pos - start
	var tan_moved: float = tan_step.length()

	# 贴墙方向也被完全堵死（凹角、门槛等）→ 翻转切线方向一次
	if tan_moved < distance * 0.25:
		_wall_tangent = -_wall_tangent
		tangent = _wall_tangent
		_set_facing(tangent.angle())
		var flip_desired: Vector2 = start + tangent * distance
		_last_push_normal = Vector2.ZERO
		var flip_pos: Vector2 = _resolve_building_collisions(flip_desired)
		if ((_unit.collision_mask & 8) != 0):
			flip_pos = _resolve_resource_collisions(flip_pos)
		if ((_unit.collision_mask & 2) != 0):
			flip_pos = _resolve_unit_collisions(flip_pos)
		_unit.global_position = flip_pos
		_update_unstuck_state(start, flip_pos)
		return

	# 检测到新的推力法线说明到达拐角，更新切线方向
	if _last_push_normal.length_squared() > 0.0001:
		var new_tan_a: Vector2 = Vector2(-_last_push_normal.y, _last_push_normal.x)
		var new_tan_b: Vector2 = -new_tan_a
		var to_goal: Vector2 = (_current_goal - tan_pos).normalized() if (_current_goal - tan_pos).length_squared() > 1.0 else tangent
		var new_tangent: Vector2 = new_tan_a if new_tan_a.dot(to_goal) >= new_tan_b.dot(to_goal) else new_tan_b
		# 仅当新切线与旧切线差异明显时才更新（避免同一面墙抖动）
		if new_tangent.dot(_wall_tangent) < 0.85:
			_wall_tangent = new_tangent

	_unit.global_position = tan_pos
	_update_unstuck_state(start, tan_pos)

## 视线检测：true = 两点之间无建筑/资源/其他单位阻挡
func has_clear_line(from: Vector2, to: Vector2) -> bool:
	return _has_clear_line_impl(from, to, true)

## 视线检测（仅静态障碍：建筑+资源，不包含单位）
## 用于贴墙退出探测，避免友军阻碍永远无法离开贴墙状态
func has_clear_line_static(from: Vector2, to: Vector2) -> bool:
	return _has_clear_line_impl(from, to, false)

func _has_clear_line_impl(from: Vector2, to: Vector2, check_units: bool) -> bool:
	var unit_r: float = _unit.unit_radius if _unit.get("unit_radius") != null else 10.0
	# 线段 AABB 粗过滤：只检测包围盒范围内的障碍
	var seg_min: Vector2 = Vector2(minf(from.x, to.x), minf(from.y, to.y))
	var seg_max: Vector2 = Vector2(maxf(from.x, to.x), maxf(from.y, to.y))

	for building in GameManager._all_buildings:
		if not is_instance_valid(building):
			continue
		if building.hp <= 0:
			continue
		var half := Vector2(building.building_size) * GameConstants.TILE_SIZE * 0.5 + Vector2(unit_r, unit_r)
		var bc: Vector2 = building.global_position
		if bc.x + half.x < seg_min.x or bc.x - half.x > seg_max.x:
			continue
		if bc.y + half.y < seg_min.y or bc.y - half.y > seg_max.y:
			continue
		if _segment_intersects_aabb(from, to, bc, half):
			return false

	for res in GameManager._all_resources:
		if not is_instance_valid(res):
			continue
		if res.remaining_amount <= 0:
			continue
		# 采集目标矿点不计入视线過滤，允许工人辺寻路直达其中心
		if ignore_resource != null and res == ignore_resource:
			continue
		var node := res as ResourceNode
		var radius := node.get_collision_radius() + unit_r
		var rc: Vector2 = node.global_position
		if rc.x + radius < seg_min.x or rc.x - radius > seg_max.x:
			continue
		if rc.y + radius < seg_min.y or rc.y - radius > seg_max.y:
			continue
		if _segment_point_distance_sq(from, to, rc) < radius * radius:
			return false

	# 其他单位也纳入视线遮挡（单位有碰撞体积时不认为路径畅通）
	if check_units:
		for other in GameManager._all_units:
			if not is_instance_valid(other) or other == _unit:
				continue
			if other.current_state == GameConstants.UnitState.DEAD:
				continue
			var other_r: float = other.unit_radius if other.get("unit_radius") != null else 10.0
			var radius := other_r + unit_r
			var oc: Vector2 = other.global_position
			if oc.x + radius < seg_min.x or oc.x - radius > seg_max.x:
				continue
			if oc.y + radius < seg_min.y or oc.y - radius > seg_max.y:
				continue
			if _segment_point_distance_sq(from, to, oc) < radius * radius:
				return false

	return true

# ──────────────────────────────────────────────────────────
#  内部：ORCA（预留扩展接口，当前直接透传）
# ──────────────────────────────────────────────────────────

func _apply_orca(preferred_vel: Vector2, _dt: float) -> Vector2:
	return preferred_vel

# ──────────────────────────────────────────────────────────
#  内部：碰撞解算
# ──────────────────────────────────────────────────────────

func _apply_all_collisions(candidate_pos: Vector2) -> Vector2:
	var mask: int = _unit.collision_mask
	var corrected := candidate_pos
	if (mask & 4) != 0:
		corrected = _resolve_building_collisions(corrected)
	if (mask & 8) != 0:
		corrected = _resolve_resource_collisions(corrected)
	if (mask & 2) != 0:
		corrected = _resolve_unit_collisions(corrected)
	return corrected

func _resolve_building_collisions(candidate_pos: Vector2) -> Vector2:
	var unit_r: float = _unit.unit_radius
	var corrected := candidate_pos
	var total_push := Vector2.ZERO
	for building in GameManager._all_buildings:
		if not is_instance_valid(building):
			continue
		if building.hp <= 0:
			continue
		var half := Vector2(building.building_size) * GameConstants.TILE_SIZE * 0.5
		var expanded := half + Vector2(unit_r, unit_r)
		# 粗过滤：包围盒外直接跳过
		var bc: Vector2 = building.global_position
		if absf(corrected.x - bc.x) >= expanded.x + unit_r or absf(corrected.y - bc.y) >= expanded.y + unit_r:
			continue
		var offset: Vector2 = corrected - bc
		if absf(offset.x) >= expanded.x or absf(offset.y) >= expanded.y:
			continue
		var push_x := expanded.x - absf(offset.x)
		var push_y := expanded.y - absf(offset.y)
		var push_vec: Vector2
		if push_x < push_y:
			push_vec = Vector2(push_x if offset.x >= 0.0 else -push_x, 0.0)
		else:
			push_vec = Vector2(0.0, push_y if offset.y >= 0.0 else -push_y)
		corrected += push_vec
		total_push += push_vec
	# 记录推力法线供贴墙滑行使用
	if total_push.length_squared() > 0.0001:
		_last_push_normal = total_push.normalized()
	return corrected

func _resolve_unit_collisions(candidate_pos: Vector2) -> Vector2:
	var unit_r: float = _unit.unit_radius
	var eid: int = _unit.entity_id
	var corrected := candidate_pos
	var total_push := Vector2.ZERO
	for other in GameManager._all_units:
		if not is_instance_valid(other) or other == _unit:
			continue
		if other.current_state == GameConstants.UnitState.DEAD:
			continue
		var min_dist: float = unit_r + other.unit_radius
		var offset: Vector2 = corrected - other.global_position
		# 粗过滤：曼哈顿距离快速排除
		if absf(offset.x) >= min_dist or absf(offset.y) >= min_dist:
			continue
		var dist: float = offset.length()
		if dist >= min_dist:
			continue
		var push_vec: Vector2
		if dist > 0.001:
			push_vec = offset / dist * (min_dist - dist)
		else:
			push_vec = (Vector2(1, 0) if eid >= other.entity_id else Vector2(-1, 0)) * (min_dist * 0.5)
		corrected += push_vec
		total_push += push_vec
	# 仅当建筑没有设置推力法线时，单位碰撞才贡献（单位是动态障碍，优先级较低）
	if total_push.length_squared() > 0.0001 and _last_push_normal.length_squared() < 0.0001:
		_last_push_normal = total_push.normalized()
	return corrected

func _resolve_resource_collisions(candidate_pos: Vector2) -> Vector2:
	var unit_r: float = _unit.unit_radius
	var corrected := candidate_pos
	var total_push := Vector2.ZERO
	for res in GameManager._all_resources:
		if not is_instance_valid(res):
			continue
		if res.remaining_amount <= 0:
			continue
		# 跳过当前正在采集的目标矿点，允许工人进入其碰撞半径完成占用
		if ignore_resource != null and res == ignore_resource:
			continue
		var node := res as ResourceNode
		var min_dist: float = unit_r + node.get_collision_radius()
		var offset: Vector2 = corrected - node.global_position
		# 粗过滤：曼哈顿距离快速排除
		if absf(offset.x) >= min_dist or absf(offset.y) >= min_dist:
			continue
		var dist: float = offset.length()
		if dist >= min_dist:
			continue
		var push_vec: Vector2
		if dist > 0.001:
			push_vec = offset / dist * (min_dist - dist)
		else:
			push_vec = Vector2(0, min_dist)
		corrected += push_vec
		total_push += push_vec
	# 资源碰撞贡献推力法线（优先级介于建筑和单位之间）
	if total_push.length_squared() > 0.0001:
		_last_push_normal = (total_push + _last_push_normal).normalized()
	return corrected

# ──────────────────────────────────────────────────────────
#  内部：转向选边 & 卡角兜底
# ──────────────────────────────────────────────────────────

func _infer_side_from_blocker(start: Vector2, move_dir: Vector2) -> int:
	var unit_r: float = _unit.unit_radius
	var blocker: BaseBuilding = _find_blocking_building(start + move_dir * (unit_r + 12.0))
	if blocker == null:
		return -1
	var to_center: Vector2 = blocker.global_position - start
	var cross_val: float = move_dir.cross(to_center)
	if cross_val < -0.001:
		return -1
	if cross_val > 0.001:
		return 1
	return -1

func _update_unstuck_state(from_pos: Vector2, to_pos: Vector2) -> void:
	var moved: float = to_pos.distance_to(from_pos)
	if moved <= STUCK_MOVE_EPSILON:
		_stuck_frames += 1
	else:
		_stuck_frames = 0
		_forced_side_sign = 0
		_forced_side_frames_left = 0
		return

	if _forced_side_frames_left > 0:
		_forced_side_frames_left -= 1
		if _forced_side_frames_left <= 0:
			_forced_side_frames_left = 0

func _find_blocking_building(candidate_pos: Vector2) -> BaseBuilding:
	var unit_r: float = _unit.unit_radius
	for building in GameManager._all_buildings:
		if not is_instance_valid(building):
			continue
		var b := building as BaseBuilding
		if b == null or b.hp <= 0:
			continue
		var half: Vector2 = Vector2(b.building_size) * GameConstants.TILE_SIZE * 0.5
		var expanded: Vector2 = half + Vector2(unit_r, unit_r)
		var offset: Vector2 = candidate_pos - b.global_position
		if absf(offset.x) < expanded.x and absf(offset.y) < expanded.y:
			return b
	return null

# ──────────────────────────────────────────────────────────
#  内部：几何工具
# ──────────────────────────────────────────────────────────

func _segment_intersects_aabb(a: Vector2, b: Vector2, center: Vector2, half: Vector2) -> bool:
	var min_b := center - half
	var max_b := center + half
	var d := b - a
	var t_min := 0.0
	var t_max := 1.0

	if absf(d.x) < 0.000001:
		if a.x < min_b.x or a.x > max_b.x:
			return false
	else:
		var inv_dx := 1.0 / d.x
		var tx1 := (min_b.x - a.x) * inv_dx
		var tx2 := (max_b.x - a.x) * inv_dx
		var tx_min := minf(tx1, tx2)
		var tx_max := maxf(tx1, tx2)
		t_min = maxf(t_min, tx_min)
		t_max = minf(t_max, tx_max)
		if t_min > t_max:
			return false

	if absf(d.y) < 0.000001:
		if a.y < min_b.y or a.y > max_b.y:
			return false
	else:
		var inv_dy := 1.0 / d.y
		var ty1 := (min_b.y - a.y) * inv_dy
		var ty2 := (max_b.y - a.y) * inv_dy
		var ty_min := minf(ty1, ty2)
		var ty_max := maxf(ty1, ty2)
		t_min = maxf(t_min, ty_min)
		t_max = minf(t_max, ty_max)
		if t_min > t_max:
			return false

	return true

func _segment_point_distance_sq(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.000001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest := a + ab * t
	return p.distance_squared_to(closest)

# ──────────────────────────────────────────────────────────
#  路径规划：可见性图绕角规划（出发前一次性计算）
# ──────────────────────────────────────────────────────────

## 从 from 到 to 的可见性图最短路径规划
## 算法：贪心可见性图 —— 若直达则返回直线；否则枚举所有 AABB 拐角
## 依次插入能减少总路径长度且两端均可视的拐角，迭代直到稳定
## 复杂度 O(C²)，C = 总拐角数（建筑数 × 4），适合几十栋建筑量级
func _plan_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	# 直线可达直接返回（规划阶段只考虑静态障碍，不含动态单位）
	if has_clear_line_static(from, to):
		return PackedVector2Array([from, to])

	var unit_r: float = _unit.unit_radius if _unit.get("unit_radius") != null else 10.0
	var margin: float = unit_r + 2.0

	# 规划范围：起点与终点包围盒，向外扩展一定余量，只考虑范围内的障碍
	# 余量 = 最大建筑尺寸 + 2个单位半径，保证边缘障碍不被漏掉
	const PLAN_PADDING: float = 160.0  # 约 2.5 格，覆盖最大建筑半宽
	var plan_min: Vector2 = Vector2(minf(from.x, to.x), minf(from.y, to.y)) - Vector2(PLAN_PADDING, PLAN_PADDING)
	var plan_max: Vector2 = Vector2(maxf(from.x, to.x), maxf(from.y, to.y)) + Vector2(PLAN_PADDING, PLAN_PADDING)

	# 收集范围内的绕行候选拐点：建筑 AABB 四角 + 资源节点四个切点
	var corners: Array[Vector2] = []
	for building in GameManager._all_buildings:
		if not is_instance_valid(building):
			continue
		if building.hp <= 0:
			continue
		var c: Vector2 = building.global_position
		if c.x < plan_min.x or c.x > plan_max.x or c.y < plan_min.y or c.y > plan_max.y:
			continue
		var half: Vector2 = Vector2(building.building_size) * GameConstants.TILE_SIZE * 0.5
		var ex: Vector2 = half + Vector2(margin, margin)
		corners.append(c + Vector2(-ex.x, -ex.y))
		corners.append(c + Vector2( ex.x, -ex.y))
		corners.append(c + Vector2(-ex.x,  ex.y))
		corners.append(c + Vector2( ex.x,  ex.y))
	# 资源节点当作圆形障碍，生成左/右/上/下四个切线绕行点
	for res in GameManager._all_resources:
		if not is_instance_valid(res):
			continue
		if res.remaining_amount <= 0:
			continue
		# 采集目标矿点不需要绕行，直接功需寻路
		if ignore_resource != null and res == ignore_resource:
			continue
		var rc: Vector2 = (res as ResourceNode).global_position
		if rc.x < plan_min.x or rc.x > plan_max.x or rc.y < plan_min.y or rc.y > plan_max.y:
			continue
		var node := res as ResourceNode
		var r: float = node.get_collision_radius() + margin
		corners.append(rc + Vector2(-r,  0.0))
		corners.append(rc + Vector2( r,  0.0))
		corners.append(rc + Vector2( 0.0, -r))
		corners.append(rc + Vector2( 0.0,  r))

	# 初始路径只有起点和终点
	var result: Array[Vector2] = [from, to]

	# 贪心插入：寻找能改善路径且可见的拐角
	var improved: bool = true
	var max_iter: int = corners.size() + 2  # 最多迭代次数防死循环
	var iter: int = 0
	while improved and iter < max_iter:
		improved = false
		iter += 1
		# 对 result 的每段线段，寻找可插入的最佳拐角
		var i: int = 0
		while i < result.size() - 1:
			var seg_a: Vector2 = result[i]
			var seg_b: Vector2 = result[i + 1]
			if has_clear_line_static(seg_a, seg_b):
				i += 1
				continue
			# 这段视线不通畅，从拐角中找最短绕路
			var best_extra: float = INF
			var best_corner: Vector2 = Vector2.INF
			for corner in corners:
				if not has_clear_line_static(seg_a, corner):
					continue
				if not has_clear_line_static(corner, seg_b):
					continue
				var extra: float = seg_a.distance_to(corner) + corner.distance_to(seg_b) - seg_a.distance_to(seg_b)
				if extra < best_extra:
					best_extra = extra
					best_corner = corner
			if best_corner != Vector2.INF:
				result.insert(i + 1, best_corner)
				improved = true
				# 不推进 i，让新段再检测一次
			else:
				i += 1

	# 路径平滑：从起点开始，贪心跳过能直视的中间点，得到无冗余的最短路径
	var smoothed: Array[Vector2] = [result[0]]
	var si: int = 0
	while si < result.size() - 1:
		# 向后扫描，找到能从 result[si] 直视的最远点
		var farthest: int = si + 1
		for fj in range(si + 2, result.size()):
			if has_clear_line_static(result[si], result[fj]):
				farthest = fj
		smoothed.append(result[farthest])
		si = farthest

	var packed := PackedVector2Array()
	for p in smoothed:
		packed.append(p)
	return packed

# ──────────────────────────────────────────────────────────
#  内部：朝向辅助
# ──────────────────────────────────────────────────────────

func _set_facing(angle: float) -> void:
	var visual = _unit.get("visual")
	if visual != null and is_instance_valid(visual):
		visual.facing_angle = angle
