## 地图系统 - 管理瓦片地图的生成与渲染
## 使用代码绘制地形，预留接口换 TileMap + TileSet 美术资源
class_name MapSystem
extends Node2D

signal map_generated

## 地形类型
enum TerrainType {
	GRASS,        ## 草地 - 可通行
	DIRT,         ## 泥地 - 可通行
	SAND,         ## 沙地 - 可通行 (减速)
	WATER,        ## 水面 - 不可通行
	ROCK,         ## 岩石 - 不可通行
	MINERAL_ZONE, ## 矿区 - 可通行 (放矿)
}

## 地形数据
const TERRAIN_CONFIG := {
	TerrainType.GRASS: {"color": Color(0.28, 0.55, 0.22), "walkable": true, "speed_mod": 1.0},
	TerrainType.DIRT: {"color": Color(0.55, 0.42, 0.25), "walkable": true, "speed_mod": 1.0},
	TerrainType.SAND: {"color": Color(0.82, 0.73, 0.45), "walkable": true, "speed_mod": 0.7},
	TerrainType.WATER: {"color": Color(0.15, 0.35, 0.65), "walkable": false, "speed_mod": 0.0},
	TerrainType.ROCK: {"color": Color(0.35, 0.32, 0.30), "walkable": false, "speed_mod": 0.0},
	TerrainType.MINERAL_ZONE: {"color": Color(0.45, 0.50, 0.42), "walkable": true, "speed_mod": 1.0},
}

## 地图数据 (2D Array of TerrainType)
var terrain_data: Array = []  # [y][x]

## 占用网格 (建筑占用)
var occupation_grid: Array = []  # [y][x] = entity_id or -1

## 地图尺寸
var map_width: int = GameConstants.MAP_WIDTH
var map_height: int = GameConstants.MAP_HEIGHT
var tile_size: int = GameConstants.TILE_SIZE

## 噪声用于地形生成
var _noise: FastNoiseLite = null
var _detail_noise: FastNoiseLite = null

## ====== TileMap 模式 (美术素材切换) ======
@export var use_tilemap: bool = false
var _tilemap: TileMap = null
@export var tileset_resource: TileSet = null

func _ready() -> void:
	# 延迟生成，确保信号连接完毕后才 emit map_generated
	call_deferred("_deferred_generate")

func _deferred_generate() -> void:
	if use_tilemap and tileset_resource:
		_setup_tilemap()
	else:
		_generate_procedural_map()

func _draw() -> void:
	if use_tilemap:
		return  # TileMap 自行渲染
	if terrain_data.is_empty():
		return  # 地图还没生成
	_draw_procedural_map()

## ====== 公共接口 ======

## 获取瓦片坐标的地形类型
func get_terrain(tile_x: int, tile_y: int) -> TerrainType:
	if tile_x < 0 or tile_x >= map_width or tile_y < 0 or tile_y >= map_height:
		return TerrainType.ROCK
	return terrain_data[tile_y][tile_x]

## 世界坐标 → 瓦片坐标
func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(world_pos.x / tile_size), 0, map_width - 1),
		clampi(int(world_pos.y / tile_size), 0, map_height - 1)
	)

## 瓦片坐标 → 世界坐标 (瓦片中心)
func tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2(tile_pos.x * tile_size + tile_size / 2.0, tile_pos.y * tile_size + tile_size / 2.0)

## 检查某个瓦片是否可通行
func is_walkable(tile_x: int, tile_y: int) -> bool:
	if tile_x < 0 or tile_x >= map_width or tile_y < 0 or tile_y >= map_height:
		return false
	var terrain := terrain_data[tile_y][tile_x] as TerrainType
	if not TERRAIN_CONFIG[terrain]["walkable"]:
		return false
	if occupation_grid[tile_y][tile_x] >= 0:
		return false  # 被建筑占用
	return true

## 检查区域是否可放置建筑
func can_place_building(tile_x: int, tile_y: int, size: Vector2i) -> bool:
	for dy in range(size.y):
		for dx in range(size.x):
			if not is_walkable(tile_x + dx, tile_y + dy):
				return false
	return true

## 放置建筑占用
func place_building(tile_x: int, tile_y: int, size: Vector2i, entity_id: int) -> void:
	for dy in range(size.y):
		for dx in range(size.x):
			var tx := tile_x + dx
			var ty := tile_y + dy
			if tx >= 0 and tx < map_width and ty >= 0 and ty < map_height:
				occupation_grid[ty][tx] = entity_id

## 移除建筑占用
func remove_building(tile_x: int, tile_y: int, size: Vector2i) -> void:
	for dy in range(size.y):
		for dx in range(size.x):
			var tx := tile_x + dx
			var ty := tile_y + dy
			if tx >= 0 and tx < map_width and ty >= 0 and ty < map_height:
				occupation_grid[ty][tx] = -1

## 获取速度修正
func get_speed_modifier(world_pos: Vector2) -> float:
	var tile := world_to_tile(world_pos)
	var terrain := get_terrain(tile.x, tile.y)
	return TERRAIN_CONFIG[terrain]["speed_mod"]

## 获取地图像素尺寸
func get_map_pixel_size() -> Vector2:
	return Vector2(map_width * tile_size, map_height * tile_size)

## ====== 切换到 TileMap 美术素材 ======
func switch_to_tilemap(new_tileset: TileSet) -> void:
	tileset_resource = new_tileset
	use_tilemap = true
	_setup_tilemap()
	queue_redraw()

## ====== 内部: 过程式地图生成 ======

## 外部设置的地图种子 (联机同步用)
var map_seed: int = 0

func _generate_procedural_map() -> void:
	# 如果外部未设置种子则随机
	if map_seed == 0:
		map_seed = randi()
	
	# 初始化噪声 (使用确定性种子，保证所有客户端地图一致)
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.02
	_noise.seed = map_seed
	
	_detail_noise = FastNoiseLite.new()
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = 0.08
	_detail_noise.seed = map_seed + 1
	
	# 初始化网格
	terrain_data.resize(map_height)
	occupation_grid.resize(map_height)
	for y in range(map_height):
		terrain_data[y] = []
		terrain_data[y].resize(map_width)
		occupation_grid[y] = []
		occupation_grid[y].resize(map_width)
		for x in range(map_width):
			occupation_grid[y][x] = -1
			# 基于噪声生成地形
			var n := _noise.get_noise_2d(x, y)
			var d := _detail_noise.get_noise_2d(x, y)
			
			if n < -0.35:
				terrain_data[y][x] = TerrainType.WATER
			elif n < -0.15:
				terrain_data[y][x] = TerrainType.SAND
			elif n > 0.4:
				terrain_data[y][x] = TerrainType.ROCK
			elif n > 0.25 and d > 0.2:
				terrain_data[y][x] = TerrainType.DIRT
			else:
				terrain_data[y][x] = TerrainType.GRASS
	
	# 在对称位置放置矿区 (对称地图，公平竞技)
	_place_mineral_zones()
	
	# 确保出生点 + 资源区域可通行 (4 个出生点全覆盖)
	_ensure_spawn_and_resource_area()
	
	map_generated.emit()
	queue_redraw()

func _place_mineral_zones() -> void:
	# 8个出生点附近矿区（与 GameWorld._get_spawn_positions 和 _spawn_base_for_player 保持一致）
	# 出生点瓦片坐标
	var half_w := map_width / 2
	var half_h := map_height / 2
	var spawns: Array[Vector2i] = [
		Vector2i(8, 8),
		Vector2i(half_w, 8),
		Vector2i(map_width - 8, 8),
		Vector2i(8, half_h),
		Vector2i(map_width - 8, half_h),
		Vector2i(8, map_height - 8),
		Vector2i(half_w, map_height - 8),
		Vector2i(map_width - 8, map_height - 8),
	]
	for sp in spawns:
		var sx: int = 1 if sp.x <= half_w else -1
		var sy: int = 1 if sp.y <= half_h else -1
		# 3 个矿石 + 1 个能源
		for mi in [3, 4, 5]:
			_mark_mineral_zone(Vector2i(sp.x + mi * sx, sp.y + 2 * sy))
		_mark_mineral_zone(Vector2i(sp.x + 2 * sx, sp.y + 4 * sy))
	# 中央及各象限散射中立资源区
	var neutrals: Array[Vector2i] = [
		Vector2i(half_w, half_h - 3), Vector2i(half_w, half_h + 3),
		Vector2i(half_w - 3, half_h), Vector2i(half_w + 3, half_h),
		Vector2i(map_width / 4,     map_height / 4),
		Vector2i(3 * map_width / 4, map_height / 4),
		Vector2i(map_width / 4,     3 * map_height / 4),
		Vector2i(3 * map_width / 4, 3 * map_height / 4),
		Vector2i(half_w - 2, map_height / 4),
		Vector2i(half_w + 2, map_height / 4),
		Vector2i(half_w - 2, 3 * map_height / 4),
		Vector2i(half_w + 2, 3 * map_height / 4),
		Vector2i(map_width / 4, half_h - 2),
		Vector2i(map_width / 4, half_h + 2),
		Vector2i(3 * map_width / 4, half_h - 2),
		Vector2i(3 * map_width / 4, half_h + 2),
	]
	for pos in neutrals:
		_mark_mineral_zone(pos)

func _mark_mineral_zone(pos: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var tx := clampi(pos.x + dx, 0, map_width - 1)
			var ty := clampi(pos.y + dy, 0, map_height - 1)
			terrain_data[ty][tx] = TerrainType.MINERAL_ZONE

func _ensure_spawn_area(sx: int, sy: int, size_x: int, size_y: int = -1) -> void:
	if size_y < 0:
		size_y = size_x
	for dy in range(size_y):
		for dx in range(size_x):
			var tx := clampi(sx + dx, 0, map_width - 1)
			var ty := clampi(sy + dy, 0, map_height - 1)
			terrain_data[ty][tx] = TerrainType.GRASS

## 为所有 8 个出生点确保基地 + 资源区域可通行
func _ensure_spawn_and_resource_area() -> void:
	var half_w := map_width / 2
	var half_h := map_height / 2
	# 与 GameWorld._get_spawn_positions 保持一致
	var spawns: Array[Vector2i] = [
		Vector2i(8, 8),
		Vector2i(half_w, 8),
		Vector2i(map_width - 8, 8),
		Vector2i(8, half_h),
		Vector2i(map_width - 8, half_h),
		Vector2i(8, map_height - 8),
		Vector2i(half_w, map_height - 8),
		Vector2i(map_width - 8, map_height - 8),
	]
	for sp in spawns:
		var sx: int = 1 if sp.x <= half_w else -1
		var sy: int = 1 if sp.y <= half_h else -1
		# 覆盖范围：CC 占地 (sp-2 ~ sp+1) + 矿石 (sp+3~5, sp+2) + 能源 (sp+2, sp+4)
		var xs: Array[int] = [sp.x - 2, sp.x + 1, sp.x + 3*sx, sp.x + 5*sx, sp.x + 2*sx]
		var ys: Array[int] = [sp.y - 2, sp.y + 1, sp.y + 2*sy, sp.y + 4*sy]
		var min_x: int = xs[0]; var max_x: int = xs[0]
		for v in xs:
			min_x = mini(min_x, v); max_x = maxi(max_x, v)
		var min_y: int = ys[0]; var max_y: int = ys[0]
		for v in ys:
			min_y = mini(min_y, v); max_y = maxi(max_y, v)
		min_x = maxi(min_x - 1, 0)
		min_y = maxi(min_y - 1, 0)
		max_x = mini(max_x + 2, map_width - 1)
		max_y = mini(max_y + 2, map_height - 1)
		_ensure_spawn_area(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

## ====== 内部: 代码绘制地图 ======

func _draw_procedural_map() -> void:
	for y in range(map_height):
		for x in range(map_width):
			var terrain: TerrainType = terrain_data[y][x]
			var config: Dictionary = TERRAIN_CONFIG[terrain]
			var base_color: Color = config["color"]
			
			# 添加微小颜色变化让地图不那么死板
			var noise_val := 0.0
			if _detail_noise:
				noise_val = _detail_noise.get_noise_2d(x * 3.7, y * 3.7) * 0.05
			var color := Color(
				clampf(base_color.r + noise_val, 0, 1),
				clampf(base_color.g + noise_val, 0, 1),
				clampf(base_color.b + noise_val, 0, 1)
			)
			
			var rect := Rect2(x * tile_size, y * tile_size, tile_size, tile_size)
			draw_rect(rect, color)

## ====== 内部: TileMap 模式 ======

func _setup_tilemap() -> void:
	if _tilemap:
		_tilemap.queue_free()
	
	_tilemap = TileMap.new()
	_tilemap.tile_set = tileset_resource
	add_child(_tilemap)
	
	# 将 terrain_data 映射到 TileMap
	# 这里需要根据实际 TileSet 的 atlas 坐标来映射
	# 预留接口，美术素材就绪后在此映射
	for y in range(map_height):
		for x in range(map_width):
			var _terrain: int = terrain_data[y][x]
			# TODO: 根据 terrain 类型映射到 TileSet 中的 atlas 坐标
			# _tilemap.set_cell(0, Vector2i(x, y), 0, _get_atlas_coords(terrain))
			pass
