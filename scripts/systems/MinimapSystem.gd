## 小地图系统 - 代码绘制小地图
class_name MinimapSystem
extends Control

var map_system: MapSystem = null
var _game_world: Node2D = null
var _camera: Camera2D = null
var _local_team_id: int = 0
var _fog_system: FogOfWarSystem = null  ## 引用迷雾系统用于小地图遮罩

var minimap_size: Vector2 = Vector2(220, 165)  # 小地图控件尺寸
var _map_pixel_size: Vector2 = Vector2.ZERO

func setup(map: MapSystem, game_world: Node2D, camera: Camera2D, local_team: int, fog: FogOfWarSystem = null) -> void:
	map_system = map
	_game_world = game_world
	_camera = camera
	_local_team_id = local_team
	_fog_system = fog
	_map_pixel_size = map.get_map_pixel_size()
	
	custom_minimum_size = minimap_size
	size = minimap_size

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not map_system:
		return
	
	# 背景
	draw_rect(Rect2(Vector2.ZERO, minimap_size), Color(0, 0, 0, 0.8))
	
	# 地形缩略图
	var scale_x := minimap_size.x / _map_pixel_size.x
	var scale_y := minimap_size.y / _map_pixel_size.y
	
	var fog_active := _fog_system != null and _fog_system.visible
	
	# 每4x4瓦片采样一次 (性能优化)
	var sample_step := 4
	var tile_size := GameConstants.TILE_SIZE
	for y in range(0, map_system.map_height, sample_step):
		for x in range(0, map_system.map_width, sample_step):
			var world_x := x * tile_size + tile_size / 2.0
			var world_y := y * tile_size + tile_size / 2.0
			var rect := Rect2(
				x * tile_size * scale_x,
				y * tile_size * scale_y,
				sample_step * tile_size * scale_x,
				sample_step * tile_size * scale_y
			)
			if fog_active and _fog_system.fog_mode == 1:  ## FULL_BLACK: 未探索格子纯黑
				if not _fog_system.is_explored_at(Vector2(world_x, world_y)):
					draw_rect(rect, Color(0, 0, 0, 1.0))
					continue
			if fog_active and _fog_system.fog_mode == 3:  ## EXPLORED_VISIBLE: 未探索纯黑
				if not _fog_system.is_explored_at(Vector2(world_x, world_y)):
					draw_rect(rect, Color(0, 0, 0, 1.0))
					continue
			var terrain := map_system.get_terrain(x, y)
			var color: Color = MapSystem.TERRAIN_CONFIG[terrain]["color"]
			## FULL_BLACK 已探索但不可见: 地形颜色变暗
			if fog_active and _fog_system.fog_mode == 1:
				if not _fog_system.is_visible_at(Vector2(world_x, world_y)):
					color = color.darkened(0.5)
			## TERRAIN_ONLY 未探索: 地形颜色变暗
			elif fog_active and _fog_system.fog_mode == 2:
				if not _fog_system.is_explored_at(Vector2(world_x, world_y)):
					color = color.darkened(0.45)
				elif not _fog_system.is_visible_at(Vector2(world_x, world_y)):
					color = color.darkened(0.25)
			## EXPLORED_VISIBLE: 探索后地形正常显示，无变暗
			draw_rect(rect, color)
	
	# 绘制实体点（迷雾中隐藏敌方单位）
	if _game_world:
		for child in _game_world.get_children():
			var pos := Vector2.ZERO
			var dot_color := Color.WHITE
			var dot_size := 2.0
			var is_own_team := false
			
			if child is BaseUnit:
				pos = child.global_position
				dot_color = GameConstants.TEAM_COLORS.get(child.player_color_id, Color.WHITE)
				dot_size = 2.0
				is_own_team = child.team_id == _local_team_id
			elif child is BaseBuilding:
				pos = child.global_position
				dot_color = GameConstants.TEAM_COLORS.get(child.player_color_id, Color.WHITE)
				dot_size = 4.0
				is_own_team = child.team_id == _local_team_id
			elif child is ResourceNode:
				pos = child.global_position
				dot_color = Color(0.5, 0.7, 0.85)
				dot_size = 3.0
				is_own_team = true  # 资源始终显示（己方已探索）
			else:
				continue
			
			# 迷雾过滤：非己方实体只在可见区域显示（EXPLORED_VISIBLE 模式下已探索即可）
			if fog_active and not is_own_team:
				if _fog_system.fog_mode == 3:  ## EXPLORED_VISIBLE
					if not _fog_system.is_explored_at(pos):
						continue
				else:
					if not _fog_system.is_visible_at(pos):
						continue
			# FULL_BLACK 己方已探索但不可见区域：资源节点也隐藏
			if fog_active and is_own_team and child is ResourceNode:
				if not _fog_system.is_explored_at(pos):
					continue
			
			var mini_pos := Vector2(pos.x * scale_x, pos.y * scale_y)
			draw_circle(mini_pos, dot_size, dot_color)
	
	# 相机视口框
	if _camera:
		var vp_size := get_viewport_rect().size / _camera.zoom
		var cam_pos := _camera.position - vp_size / 2.0
		var cam_rect := Rect2(
			cam_pos.x * scale_x,
			cam_pos.y * scale_y,
			vp_size.x * scale_x,
			vp_size.y * scale_y
		)
		draw_rect(cam_rect, Color(1, 1, 1, 0.6), false, 1.5)
	
	# 边框
	draw_rect(Rect2(Vector2.ZERO, minimap_size), Color(0.5, 0.5, 0.5), false, 2.0)

func _gui_input(event: InputEvent) -> void:
	# 点击小地图跳转相机
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_jump_camera(event.position)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_jump_camera(event.position)

func _jump_camera(minimap_pos: Vector2) -> void:
	if not _camera or _map_pixel_size == Vector2.ZERO:
		return
	var world_pos := Vector2(
		minimap_pos.x / minimap_size.x * _map_pixel_size.x,
		minimap_pos.y / minimap_size.y * _map_pixel_size.y
	)
	_camera.jump_to(world_pos)
