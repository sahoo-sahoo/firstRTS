## 选择系统 - 框选、点选、编队
class_name SelectionSystem
extends Node2D

signal selection_changed(selected_units: Array[BaseUnit], selected_buildings: Array[BaseBuilding])

## 当前选中的单位
var selected_units: Array[BaseUnit] = []
## 当前选中的建筑
var selected_buildings: Array[BaseBuilding] = []

## 框选状态
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_end: Vector2 = Vector2.ZERO
var _min_drag_distance: float = 10.0

## 右键按下位置（用于区分点击指令与拖拽平移）
var _rclick_press_pos: Vector2 = Vector2.ZERO

## 编队 (0~9)
var _control_groups: Dictionary = {}  # {group_id: [unit_refs]}

## 引用
var _camera: Camera2D = null
var _game_world: Node2D = null
var _local_team_id: int = 0
## 回放模式: 允许选中任意队伍单位, 禁止发送指令
var replay_mode: bool = false

func setup(camera: Camera2D, game_world: Node2D, local_team: int, is_replay: bool = false) -> void:
	_camera = camera
	_game_world = game_world
	_local_team_id = local_team
	replay_mode = is_replay

func _process(_delta: float) -> void:
	if _is_dragging:
		# 直接读取当前鼠标位置，不依赖 motion 事件
		_drag_end = get_viewport().get_mouse_position()
	# 每帧重绘：路径虚线需要实时更新
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey:
		_handle_key(event)

func _draw() -> void:
	# 绘制框选矩形
	if _is_dragging:
		var rect := _get_drag_rect_screen()
		# 将屏幕坐标转为本地坐标 (通过 canvas transform)
		var canvas_transform := get_canvas_transform()
		var inv := canvas_transform.affine_inverse()
		var local_start := inv * rect.position
		var local_end := inv * rect.end
		var local_rect := Rect2(local_start, local_end - local_start)
		
		draw_rect(local_rect, Color(0.2, 0.9, 0.2, 0.15))
		draw_rect(local_rect, Color(0.2, 0.9, 0.2, 0.6), false, 1.5)

	# 绘制所有单位的路径规划虚线（玩家单位青/蓝色，AI单位红/橙色）
	for unit in GameManager._all_units:
		if not is_instance_valid(unit):
			continue
		if unit.current_state == GameConstants.UnitState.DEAD:
			continue
		var pf = unit.get("pathfinding")
		if pf == null:
			continue
		var pts: PackedVector2Array = pf.path
		var idx: int = pf.path_index
		if pts.size() < 2 or idx >= pts.size():
			continue
		# 玩家队伍：青绿色系；AI队伍：橙红色系；每个单位微调色相以便区分
		var hue_base: float = 0.5 if unit.team_id == _local_team_id else 0.05
		var hue := hue_base + float(unit.entity_id % 4) * 0.04
		var col := Color.from_hsv(hue, 0.85, 1.0, 0.75)
		# 从单位当前位置开始向后拼接剩余路径点
		var draw_pts: Array[Vector2] = []
		draw_pts.append(unit.global_position)
		for i in range(idx, pts.size()):
			draw_pts.append(pts[i])
		# 绘制虚线
		for i in range(draw_pts.size() - 1):
			_draw_dashed_line(to_local(draw_pts[i]), to_local(draw_pts[i + 1]), col, 6.0, 5.0, 1.5)
		# 终点标记圆
		if draw_pts.size() > 1:
			draw_circle(to_local(draw_pts[-1]), 4.0, col)

## ====== 公共接口 ======

## 清空选择
func clear_selection() -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.deselect()
	for building in selected_buildings:
		if is_instance_valid(building):
			building.deselect()
	selected_units.clear()
	selected_buildings.clear()
	selection_changed.emit(selected_units, selected_buildings)

## 选择指定单位
func select_units(units: Array) -> void:
	clear_selection()
	for unit in units:
		if unit is BaseUnit and (replay_mode or unit.team_id == _local_team_id):
			selected_units.append(unit)
			unit.select()
	selection_changed.emit(selected_units, selected_buildings)

## 框选指定区域内的单位
func select_in_rect(world_rect: Rect2) -> void:
	clear_selection()
	if not _game_world:
		return
	
	# 遍历所有单位
	for child in _game_world.get_children():
		if child is BaseUnit and (replay_mode or child.team_id == _local_team_id):
			if world_rect.has_point(child.global_position):
				selected_units.append(child)
				child.select()
	
	# 如果没选到单位，尝试选建筑
	if selected_units.is_empty():
		for child in _game_world.get_children():
			if child is BaseBuilding and (replay_mode or child.team_id == _local_team_id):
				if world_rect.has_point(child.global_position):
					selected_buildings.append(child)
					child.select()
					break  # 建筑一次只选一个
	
	selection_changed.emit(selected_units, selected_buildings)

## 设置编队
func set_control_group(group_id: int) -> void:
	if selected_units.size() > 0:
		_control_groups[group_id] = selected_units.duplicate()

## 召回编队
func recall_control_group(group_id: int) -> void:
	if _control_groups.has(group_id):
		var group: Array = _control_groups[group_id]
		# 移除已死亡的引用
		group = group.filter(func(u): return is_instance_valid(u))
		_control_groups[group_id] = group
		if group.size() > 0:
			select_units(group)

## ====== 指令发送 ======

## 发送右键指令 (移动/攻击/采集)
func issue_command(world_pos: Vector2) -> void:
	if selected_units.is_empty():
		return
	
	# 检查目标位置是否有敌方单位/建筑
	var target := _find_target_at(world_pos)
	
	if target:
		# 资源节点 - 工人采集 (资源没有team_id，需优先判断)
		if target is ResourceNode:
			_command_gather(target)
		elif target.get("team_id") != null and target.get("team_id") != _local_team_id:
			# 攻击敌方
			for unit in selected_units:
				if is_instance_valid(unit):
					NetworkManager.send_command({
						"type": "attack",
						"entity_id": unit.entity_id,
						"target_id": target.entity_id,
					})
		else:
			# 友方单位/建筑
			if target is BaseBuilding and target.is_resource_depot:
				# 右键友方资源收集站 - 工人交矿
				for unit in selected_units:
					if is_instance_valid(unit) and unit.can_gather:
						NetworkManager.send_command({
							"type": "return_resource",
							"entity_id": unit.entity_id,
							"depot_id": target.entity_id,
						})
					elif is_instance_valid(unit):
						NetworkManager.send_command({
							"type": "move",
							"entity_id": unit.entity_id,
							"target": world_pos,
						})
			else:
				_command_move_formation(world_pos)
	else:
		# 移动到空地
		_command_move_formation(world_pos)

## 绘制虚线辅助函数
func _draw_dashed_line(a: Vector2, b: Vector2, color: Color, dash: float, gap: float, width: float) -> void:
	var total := a.distance_to(b)
	if total < 0.001:
		return
	var dir := (b - a) / total
	var pos := 0.0
	var drawing := true
	while pos < total:
		var seg_len := dash if drawing else gap
		var end_pos := minf(pos + seg_len, total)
		if drawing:
			draw_line(a + dir * pos, a + dir * end_pos, color, width)
		pos = end_pos
		drawing = not drawing

## ====== 内部方法 ======

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start = event.position
			_drag_end = event.position
			_is_dragging = true
		else:
			_is_dragging = false
			_drag_end = event.position  # 确保结束位置正确
			var drag_dist := _drag_start.distance_to(_drag_end)
			
			if drag_dist < _min_drag_distance:
				# 点选
				_handle_click(event)
			else:
				# 框选
				_handle_box_select()
			queue_redraw()
	
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			# 记录按下位置，用于判断是否发生了拖拽平移
			_rclick_press_pos = event.position
		else:
			# 松开时：只有移动距离小于阈值才视为点击指令
			var drag_dist := _rclick_press_pos.distance_to(event.position)
			if not replay_mode and drag_dist < _min_drag_distance:
				var world_pos := _screen_to_world(event.position)
				issue_command(world_pos)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_dragging:
		_drag_end = event.position

func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	
	# Ctrl + 数字键 = 设置编队
	# 数字键 = 召回编队
	var key := event.keycode
	if key >= KEY_0 and key <= KEY_9:
		var group_id := key - KEY_0
		if event.ctrl_pressed:
			set_control_group(group_id)
		else:
			recall_control_group(group_id)
	
	# S = 停止
	if key == KEY_S and not event.ctrl_pressed:
		for unit in selected_units:
			if is_instance_valid(unit):
				NetworkManager.send_command({
					"type": "stop",
					"entity_id": unit.entity_id,
				})

func _handle_click(event: InputEventMouseButton) -> void:
	var world_pos := _screen_to_world(event.position)
	
	# 查找点击位置的实体 (左键选中: 优先己方单位, 避免被资源节点遮挡)
	var target := _find_target_at(world_pos, true)
	
	if target:
		if not event.shift_pressed:
			clear_selection()
		
		if target is BaseUnit and (replay_mode or target.team_id == _local_team_id):
			selected_units.append(target)
			target.select()
		elif target is BaseBuilding and (replay_mode or target.team_id == _local_team_id):
			selected_buildings.append(target)
			target.select()
	else:
		if not event.shift_pressed:
			clear_selection()
	
	selection_changed.emit(selected_units, selected_buildings)

func _handle_box_select() -> void:
	var world_start := _screen_to_world(_drag_start)
	var world_end := _screen_to_world(_drag_end)
	
	var rect := Rect2()
	rect.position = Vector2(minf(world_start.x, world_end.x), minf(world_start.y, world_end.y))
	rect.size = Vector2(absf(world_end.x - world_start.x), absf(world_end.y - world_start.y))
	
	select_in_rect(rect)

## prefer_unit: 左键选中时优先返回己方单位 (防止采矿工人被资源节点遮挡无法选中)
##              右键指令时为 false, 优先返回资源节点 (方便下达采集指令)
func _find_target_at(world_pos: Vector2, prefer_unit: bool = false) -> Node2D:
	var space := get_world_2d().direct_space_state
	# 先做精确点查询
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collision_mask = 2 | 4 | 8  # units, buildings, resources
	
	var results := space.intersect_point(query, 8)
	var best := _pick_best_target(results, prefer_unit)
	if best:
		return best
	
	# 点查询未命中: 用小半径圆形查询做容差
	var click_shape := CircleShape2D.new()
	click_shape.radius = 20.0
	var shape_query := PhysicsShapeQueryParameters2D.new()
	shape_query.shape = click_shape
	shape_query.transform = Transform2D(0.0, world_pos)
	shape_query.collision_mask = 2 | 4 | 8
	
	var shape_results := space.intersect_shape(shape_query, 8)
	best = _pick_best_target(shape_results, prefer_unit)
	if best:
		return best
	
	return null

## 从物理查询结果中按优先级挑选目标
func _pick_best_target(results: Array, prefer_unit: bool) -> Node2D:
	if results.is_empty():
		return null
	if prefer_unit:
		# 选中模式: 在回放中忽略队伍限制; 正常模式优先己方
		for r in results:
			var c = r["collider"]
			if c is BaseUnit and (replay_mode or c.team_id == _local_team_id):
				return c as Node2D
		for r in results:
			var c = r["collider"]
			if c is BaseBuilding and (replay_mode or c.team_id == _local_team_id):
				return c as Node2D
		if replay_mode:
			return results[0]["collider"] as Node2D
		return null
	else:
		# 指令模式: 资源 > 其他 (方便右键采集)
		for r in results:
			if r["collider"] is ResourceNode:
				return r["collider"] as Node2D
		return results[0]["collider"] as Node2D

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var canvas_transform := get_viewport().get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos

func _get_drag_rect_screen() -> Rect2:
	var pos := Vector2(minf(_drag_start.x, _drag_end.x), minf(_drag_start.y, _drag_end.y))
	var size := Vector2(absf(_drag_end.x - _drag_start.x), absf(_drag_end.y - _drag_start.y))
	return Rect2(pos, size)

func _command_move_formation(center: Vector2) -> void:
	var count := selected_units.size()
	if count == 0:
		return
	
	if count == 1:
		NetworkManager.send_command({
			"type": "move",
			"entity_id": selected_units[0].entity_id,
			"target": center,
		})
		return
	
	# 方阵排布
	var cols := ceili(sqrt(float(count)))
	var spacing := 40.0
	
	for i in range(count):
		if not is_instance_valid(selected_units[i]):
			continue
		var row := i / cols
		var col := i % cols
		var offset := Vector2(
			(col - cols / 2.0) * spacing,
			(row - cols / 2.0) * spacing
		)
		NetworkManager.send_command({
			"type": "move",
			"entity_id": selected_units[i].entity_id,
			"target": center + offset,
		})

func _command_gather(resource_node: Node2D) -> void:
	# 找最近的资源收集站
	var depot: BaseBuilding = null
	var closest_dist := INF
	
	if _game_world:
		for child in _game_world.get_children():
			if child is BaseBuilding and child.team_id == _local_team_id and child.is_resource_depot:
				var dist := resource_node.global_position.distance_to(child.global_position)
				if dist < closest_dist:
					closest_dist = dist
					depot = child
	
	if depot == null:
		# 没有资源收集站, 通知玩家
		var hud_node := get_parent().get_node_or_null("HUD")
		if hud_node and hud_node.has_method("show_message"):
			hud_node.show_message("没有资源收集站")
		return
	
	for unit in selected_units:
		if is_instance_valid(unit) and unit.can_gather:
			NetworkManager.send_command({
				"type": "gather",
				"entity_id": unit.entity_id,
				"resource_id": resource_node.entity_id,
				"depot_id": depot.entity_id,
			})
