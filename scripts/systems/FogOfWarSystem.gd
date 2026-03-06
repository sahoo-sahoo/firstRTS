## 战争迷雾系统
class_name FogOfWarSystem
extends Node2D

## 迷雾状态
enum FogState { UNEXPLORED, EXPLORED, VISIBLE }

## 迷雾模式（与 GameConstants.FogMode 对应）
var fog_mode: int = 1  ## 默认 FULL_BLACK

## 迷雾网格 (比地图瓦片更粗粒度)
var _fog_grid: Array = []  # [y][x] = FogState
var _fog_cell_size: int = 32  # 每 32 像素一个迷雾格子
var _fog_width: int = 0
var _fog_height: int = 0
var _map_pixel_size: Vector2 = Vector2.ZERO

var _game_world: Node2D = null
var _local_team_id: int = 0

## 性能：使用 Image + ImageTexture 渲染迷雾
var _fog_image: Image = null
var _fog_texture: ImageTexture = null

func setup(map_pixel_size: Vector2, game_world: Node2D, local_team: int, mode: int = 1) -> void:
	_map_pixel_size = map_pixel_size
	_game_world = game_world
	_local_team_id = local_team
	fog_mode = mode
	
	_fog_width = ceili(map_pixel_size.x / _fog_cell_size)
	_fog_height = ceili(map_pixel_size.y / _fog_cell_size)
	
	# 初始化全黑
	_fog_grid.resize(_fog_height)
	for y in range(_fog_height):
		_fog_grid[y] = []
		_fog_grid[y].resize(_fog_width)
		for x in range(_fog_width):
			_fog_grid[y][x] = FogState.UNEXPLORED
	
	# 创建迷雾图像
	_fog_image = Image.create(_fog_width, _fog_height, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color(0, 0, 0, 0.85))  # 初始全黑
	_fog_texture = ImageTexture.create_from_image(_fog_image)

func _process(_delta: float) -> void:
	_update_visibility()
	queue_redraw()

func _draw() -> void:
	if _fog_texture:
		var scale_vec := Vector2(_fog_cell_size, _fog_cell_size)
		draw_texture_rect(_fog_texture, Rect2(Vector2.ZERO, _map_pixel_size), false)

## ====== 公共接口 ======

## 检查某世界坐标是否可见
func is_visible_at(world_pos: Vector2) -> bool:
	var fx := int(world_pos.x / _fog_cell_size)
	var fy := int(world_pos.y / _fog_cell_size)
	if fx < 0 or fx >= _fog_width or fy < 0 or fy >= _fog_height:
		return false
	return _fog_grid[fy][fx] == FogState.VISIBLE

## 检查某世界坐标是否已探索
func is_explored_at(world_pos: Vector2) -> bool:
	var fx := int(world_pos.x / _fog_cell_size)
	var fy := int(world_pos.y / _fog_cell_size)
	if fx < 0 or fx >= _fog_width or fy < 0 or fy >= _fog_height:
		return false
	return _fog_grid[fy][fx] != FogState.UNEXPLORED

## ====== 内部 ======

func _update_visibility() -> void:
	if not _game_world or not _fog_image:
		return
	
	# 重置可见→已探索
	for y in range(_fog_height):
		for x in range(_fog_width):
			if _fog_grid[y][x] == FogState.VISIBLE:
				_fog_grid[y][x] = FogState.EXPLORED
	
	# 根据己方单位/建筑视野揭开迷雾
	for child in _game_world.get_children():
		if not is_instance_valid(child):
			continue
		if child.get("team_id") != _local_team_id:
			continue
		
		var vision: float = child.get("vision_range") if child.get("vision_range") != null else 0.0
		if vision <= 0:
			continue
		
		var pos: Vector2 = child.global_position
		_reveal_circle(pos, vision)
	
	# 更新迷雾贴图
	_update_fog_texture()

func _reveal_circle(center: Vector2, radius: float) -> void:
	var cx := int(center.x / _fog_cell_size)
	var cy := int(center.y / _fog_cell_size)
	var r := ceili(radius / _fog_cell_size)
	
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var fx := cx + dx
			var fy := cy + dy
			if fx < 0 or fx >= _fog_width or fy < 0 or fy >= _fog_height:
				continue
			if Vector2(dx, dy).length() * _fog_cell_size <= radius:
				_fog_grid[fy][fx] = FogState.VISIBLE

func _update_fog_texture() -> void:
	## FULL_BLACK  : 未探索=纯黑不透明, 已探索=深灰半透明, 可见=透明
	## TERRAIN_ONLY: 未探索=半透黑(只挡单位,地形透过来), 已探索=淡暗罩, 可见=透明
	for y in range(_fog_height):
		for x in range(_fog_width):
			var state: FogState = _fog_grid[y][x]
			var col: Color
			match fog_mode:
				1:  ## FULL_BLACK — 未探索真黑
					match state:
						FogState.UNEXPLORED: col = Color(0, 0, 0, 1.0)   # 纯黑
						FogState.EXPLORED:   col = Color(0, 0, 0, 0.55)  # 深灰半透
						FogState.VISIBLE:    col = Color(0, 0, 0, 0.0)
				2:  ## TERRAIN_ONLY — 地形可见，单位被遮
					match state:
						FogState.UNEXPLORED: col = Color(0, 0, 0, 0.5)   # 半透黑罩住单位但透出地形色
						FogState.EXPLORED:   col = Color(0, 0, 0, 0.3)   # 轻度变暗
						FogState.VISIBLE:    col = Color(0, 0, 0, 0.0)
				3:  ## EXPLORED_VISIBLE — 未探索全黑，探索后始终透明
					match state:
						FogState.UNEXPLORED: col = Color(0, 0, 0, 1.0)   # 纯黑
						FogState.EXPLORED:   col = Color(0, 0, 0, 0.0)   # 完全透明
						FogState.VISIBLE:    col = Color(0, 0, 0, 0.0)
				_:
					col = Color(0, 0, 0, 0.0)
			_fog_image.set_pixel(x, y, col)
	
	_fog_texture.update(_fog_image)
	_update_entity_visibility()

## 根据迷雾状态控制实体的可见性
## - 己方单位/建筑：始终可见
## - 资源节点（矿/能量）：与地形同步，已探索即可见
## - 敌方单位/建筑：FULL_BLACK/TERRAIN_ONLY 仅 VISIBLE 可见；EXPLORED_VISIBLE 已探索即可见
func _update_entity_visibility() -> void:
	if not _game_world:
		return
	var explored_shows_enemy := (fog_mode == 3)  ## EXPLORED_VISIBLE 模式
	for child in _game_world.get_children():
		if not is_instance_valid(child):
			continue
		if child is ResourceNode:
			# 资源节点与地形同步：已探索就显示
			child.visible = is_explored_at(child.global_position)
			continue
		var team: int = child.get("team_id") if child.get("team_id") != null else -1
		if team == _local_team_id:
			# 己方：始终显示
			child.visible = true
		else:
			# 敌方：EXPLORED_VISIBLE 模式下已探索即可见，否则需在视野内
			if explored_shows_enemy:
				child.visible = is_explored_at(child.global_position)
			else:
				child.visible = is_visible_at(child.global_position)
