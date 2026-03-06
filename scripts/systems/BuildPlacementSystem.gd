## 建筑放置系统 - 幽灵图预览 + 放置确认
class_name BuildPlacementSystem
extends Node2D

signal building_placed(building_key: String, position: Vector2)
signal placement_cancelled

## 状态
var is_placing: bool = false
var current_building_key: String = ""
var current_building_size: Vector2i = Vector2i(3, 3)
var _ghost_position: Vector2 = Vector2.ZERO
var _can_place: bool = false

## 引用
var map_system: MapSystem = null
var team_id: int = 0

func setup(map: MapSystem, team: int) -> void:
	map_system = map
	team_id = team

## 开始放置建筑
func start_placement(building_key: String) -> void:
	var data: Dictionary = GameConstants.BUILDING_DATA.get(building_key, {})
	if data.is_empty():
		return
	
	current_building_key = building_key
	current_building_size = data.get("size", Vector2i(3, 3))
	is_placing = true
	
	# 检查资源是否够
	var cost_m: int = data.get("cost_mineral", 0)
	var cost_e: int = data.get("cost_energy", 0)
	if not GameManager.resource_system.can_afford(team_id, cost_m, cost_e):
		cancel_placement()

## 取消放置
func cancel_placement() -> void:
	is_placing = false
	current_building_key = ""
	placement_cancelled.emit()
	queue_redraw()

func _process(_delta: float) -> void:
	if is_placing:
		# 获取鼠标世界坐标
		var mouse_world := _get_mouse_world_pos()
		# 对齐到瓦片网格
		if map_system:
			var tile := map_system.world_to_tile(mouse_world)
			_ghost_position = map_system.tile_to_world(tile)
			_can_place = _can_place_here(_ghost_position, tile)
		queue_redraw()

func _can_place_here(center_pos: Vector2, top_left_tile: Vector2i) -> bool:
	if map_system == null:
		return false
	if not map_system.can_place_building(top_left_tile.x, top_left_tile.y, current_building_size):
		return false

	var half: Vector2 = Vector2(current_building_size) * GameConstants.TILE_SIZE * 0.5

	# 不能与已有建筑重叠
	for b in GameManager._all_buildings:
		if not is_instance_valid(b):
			continue
		if b.hp <= 0:
			continue
		var b_half: Vector2 = Vector2(b.building_size) * GameConstants.TILE_SIZE * 0.5
		if _aabb_overlap(center_pos, half, b.global_position, b_half):
			return false

	# 不能与资源节点重叠
	for r in GameManager._all_resources:
		if not is_instance_valid(r):
			continue
		if r.remaining_amount <= 0:
			continue
		if _rect_circle_overlap(center_pos, half, r.global_position, r.get_collision_radius()):
			return false

	# 不能与单位重叠
	for u in GameManager._all_units:
		if not is_instance_valid(u):
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

func _unhandled_input(event: InputEvent) -> void:
	if not is_placing:
		return
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _can_place:
				_confirm_placement()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_placement()
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not is_placing:
		return
	
	var pixel_size := Vector2(current_building_size) * GameConstants.TILE_SIZE
	var rect := Rect2(_ghost_position - pixel_size / 2.0, pixel_size)
	
	var color := Color(0.2, 0.9, 0.2, 0.3) if _can_place else Color(0.9, 0.2, 0.2, 0.3)
	var border_color := Color(0.2, 0.9, 0.2, 0.7) if _can_place else Color(0.9, 0.2, 0.2, 0.7)
	
	draw_rect(rect, color)
	draw_rect(rect, border_color, false, 2.0)
	
	# 格子线
	for dy in range(current_building_size.y + 1):
		var y := rect.position.y + dy * GameConstants.TILE_SIZE
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(1, 1, 1, 0.2), 1.0)
	for dx in range(current_building_size.x + 1):
		var x := rect.position.x + dx * GameConstants.TILE_SIZE
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(1, 1, 1, 0.2), 1.0)

func _confirm_placement() -> void:
	var data: Dictionary = GameConstants.BUILDING_DATA.get(current_building_key, {})
	var cost_m: int = data.get("cost_mineral", 0)
	var cost_e: int = data.get("cost_energy", 0)
	
	# 只检查资源是否足够，不扣费 (扣费在 _execute_command 中统一处理)
	if GameManager.resource_system.can_afford(team_id, cost_m, cost_e):
		building_placed.emit(current_building_key, _ghost_position)
		is_placing = false
		current_building_key = ""
		queue_redraw()
	else:
		# 资源不够了
		cancel_placement()

func _get_mouse_world_pos() -> Vector2:
	var canvas_transform := get_viewport().get_canvas_transform()
	return canvas_transform.affine_inverse() * get_viewport().get_mouse_position()
