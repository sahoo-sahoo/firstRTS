## 建筑可视化 - 代码绘制各类建筑外观
class_name BuildingVisual
extends EntityVisual

var building_type: String = "command_center"
var building_size: Vector2i = Vector2i(3, 3)  # 占地瓦片数
var hp: int = 1000
var max_hp: int = 1000
var build_progress: float = 1.0  # 0~1, 1=已完成
var is_producing: bool = false
var production_progress: float = 0.0
var rally_point: Vector2 = Vector2.ZERO
var has_rally_point: bool = false

func _draw_procedural() -> void:
	var color := get_team_color()
	var data: Dictionary = GameConstants.BUILDING_DATA.get(building_type, {})
	var type: int = data.get("type", GameConstants.BuildingType.COMMAND_CENTER)
	var pixel_size := Vector2(building_size) * GameConstants.TILE_SIZE
	
	# 选中框
	if is_selected:
		draw_rect(
			Rect2(-pixel_size / 2.0 - Vector2(3, 3), pixel_size + Vector2(6, 6)),
			Color.GREEN, false, 2.0
		)
	
	# 建造中效果：半透明+网格线
	var alpha := 1.0 if build_progress >= 1.0 else 0.4 + build_progress * 0.6
	var draw_color := Color(color.r, color.g, color.b, alpha)
	
	match type:
		GameConstants.BuildingType.COMMAND_CENTER:
			_draw_command_center(draw_color, pixel_size)
		GameConstants.BuildingType.BARRACKS:
			_draw_barracks(draw_color, pixel_size)
		GameConstants.BuildingType.FACTORY:
			_draw_factory(draw_color, pixel_size)
		GameConstants.BuildingType.AIRPORT:
			_draw_airport(draw_color, pixel_size)
		GameConstants.BuildingType.DEFENSE_TOWER:
			_draw_defense_tower(draw_color, pixel_size)
		GameConstants.BuildingType.POWER_PLANT:
			_draw_power_plant(draw_color, pixel_size)
		GameConstants.BuildingType.TECH_CENTER:
			_draw_tech_center(draw_color, pixel_size)
		_:
			_draw_generic_building(draw_color, pixel_size)

	if build_progress < 1.0:
		_draw_construction_overlay(pixel_size, build_progress)
	
	# 建造进度
	if build_progress < 1.0:
		draw_build_progress(build_progress, maxf(pixel_size.x, pixel_size.y) * 0.42)
	
	# 血条
	if build_progress >= 1.0:
		draw_health_bar(hp, max_hp, -pixel_size.y / 2.0 - 12, pixel_size.x * 0.8)
	
	# 生产进度条
	if is_producing:
		var bar_w := pixel_size.x * 0.6
		var bar_pos := Vector2(-bar_w / 2.0, pixel_size.y / 2.0 + 4)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, 5)), Color(0.2, 0.2, 0.2, 0.7))
		draw_rect(Rect2(bar_pos, Vector2(bar_w * production_progress, 5)), Color(0.2, 0.8, 1.0, 0.9))
	
	# 集结点
	if has_rally_point and is_selected:
		var local_rally := rally_point - global_position
		draw_line(Vector2.ZERO, local_rally, Color(0.2, 0.9, 0.2, 0.5), 1.5)
		draw_circle(local_rally, 5, Color(0.2, 0.9, 0.2, 0.6))

## ====== 各建筑类型绘制 ======

func _draw_command_center(color: Color, size: Vector2) -> void:
	var rect := Rect2(-size / 2.0, size)
	# 主体
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.3), false, 2.0)
	# 十字标记
	var cross_size := size.x * 0.25
	draw_line(Vector2(-cross_size, 0), Vector2(cross_size, 0), Color.WHITE * Color(1,1,1, color.a), 3.0)
	draw_line(Vector2(0, -cross_size), Vector2(0, cross_size), Color.WHITE * Color(1,1,1, color.a), 3.0)
	# 角落装饰
	var corner_s := size * 0.15
	for dx in [-1, 1]:
		for dy in [-1, 1]:
			var corner_pos := Vector2(dx, dy) * (size / 2.0 - corner_s / 2.0)
			draw_rect(Rect2(corner_pos - corner_s / 2.0, corner_s), color.lightened(0.2))

func _draw_barracks(color: Color, size: Vector2) -> void:
	var rect := Rect2(-size / 2.0, size)
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.3), false, 2.0)
	# 星标 (五角星)
	var star_r := mini(size.x, size.y) * 0.2
	var star_points := PackedVector2Array()
	for i in range(10):
		var angle := i * TAU / 10.0 - PI / 2.0
		var r := star_r if i % 2 == 0 else star_r * 0.45
		star_points.append(Vector2.from_angle(angle) * r)
	draw_colored_polygon(star_points, Color(1, 1, 1, color.a * 0.8))
	# 门
	var door_w := size.x * 0.2
	var door_h := size.y * 0.3
	draw_rect(Rect2(-door_w/2, size.y/2 - door_h, door_w, door_h), color.darkened(0.4))

func _draw_factory(color: Color, size: Vector2) -> void:
	var rect := Rect2(-size / 2.0, size)
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.3), false, 2.0)
	# 齿轮
	var gear_r := mini(size.x, size.y) * 0.2
	var teeth := 8
	for i in range(teeth):
		var angle := i * TAU / teeth
		var start := Vector2.from_angle(angle) * gear_r
		var end_pos := Vector2.from_angle(angle) * (gear_r * 1.4)
		draw_line(start, end_pos, Color(0.7, 0.7, 0.7, color.a), 3.0)
	draw_arc(Vector2.ZERO, gear_r, 0, TAU, 24, Color(0.7, 0.7, 0.7, color.a), 2.0)
	draw_circle(Vector2.ZERO, gear_r * 0.4, color.darkened(0.2))
	# 烟囱
	draw_rect(Rect2(size.x * 0.25, -size.y / 2 - 15, 12, 15), Color(0.5, 0.5, 0.5, color.a))

func _draw_airport(color: Color, size: Vector2) -> void:
	var rect := Rect2(-size / 2.0, size)
	draw_rect(rect, color.darkened(0.1))
	draw_rect(rect, color.darkened(0.3), false, 2.0)
	# 跑道标记
	draw_line(Vector2(-size.x * 0.35, 0), Vector2(size.x * 0.35, 0), Color(1, 1, 1, color.a * 0.6), 2.0)
	# H 字停机坪
	var h_s := mini(size.x, size.y) * 0.15
	draw_line(Vector2(-h_s, -h_s), Vector2(-h_s, h_s), Color.WHITE * Color(1,1,1,color.a), 2.0)
	draw_line(Vector2(h_s, -h_s), Vector2(h_s, h_s), Color.WHITE * Color(1,1,1,color.a), 2.0)
	draw_line(Vector2(-h_s, 0), Vector2(h_s, 0), Color.WHITE * Color(1,1,1,color.a), 2.0)

func _draw_defense_tower(color: Color, size: Vector2) -> void:
	# 底座
	draw_circle(Vector2.ZERO, size.x * 0.4, color.darkened(0.1))
	draw_arc(Vector2.ZERO, size.x * 0.4, 0, TAU, 24, color.darkened(0.4), 2.0)
	# 中央炮塔
	draw_circle(Vector2.ZERO, size.x * 0.2, color.lightened(0.1))
	# 炮管 (朝向最近敌人or默认右方)
	var barrel_end := Vector2(size.x * 0.55, 0).rotated(facing_angle)
	draw_line(Vector2.ZERO, barrel_end, color.darkened(0.2), 3.0)
	draw_circle(barrel_end, 3, color.lightened(0.2))
	# 射程圈 (选中时显示)
	if is_selected:
		var data: Dictionary = GameConstants.BUILDING_DATA.get(building_type, {})
		var atk_range: float = data.get("attack_range", 200.0)
		draw_arc(Vector2.ZERO, atk_range, 0, TAU, 64, Color(1, 0.3, 0.3, 0.15), 1.0)

func _draw_power_plant(color: Color, size: Vector2) -> void:
	var rect := Rect2(-size / 2.0, size)
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.3), false, 2.0)
	# 闪电符号
	var bolt := PackedVector2Array([
		Vector2(2, -size.y * 0.25),
		Vector2(-6, 2),
		Vector2(2, 2),
		Vector2(-2, size.y * 0.25),
		Vector2(6, -2),
		Vector2(-2, -2),
	])
	draw_colored_polygon(bolt, Color(1, 0.9, 0.2, color.a))

func _draw_tech_center(color: Color, size: Vector2) -> void:
	var rect := Rect2(-size / 2.0, size)
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.3), false, 2.0)
	# 原子/科技符号 - 三个椭圆轨道
	var orbit_r := mini(size.x, size.y) * 0.22
	for i in range(3):
		var angle := i * TAU / 3.0
		draw_arc(Vector2.ZERO, orbit_r, angle, angle + TAU, 20, Color(0.5, 0.9, 1.0, color.a * 0.7), 1.5)
	# 核心
	draw_circle(Vector2.ZERO, 5, Color(0.5, 0.9, 1.0, color.a))

func _draw_generic_building(color: Color, size: Vector2) -> void:
	var rect := Rect2(-size / 2.0, size)
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.3), false, 2.0)

func _draw_construction_overlay(size: Vector2, progress: float) -> void:
	var rect := Rect2(-size / 2.0, size)
	# 施工中的深色遮罩
	draw_rect(rect, Color(0.05, 0.05, 0.08, 0.32))
	# 黄色警示边框
	draw_rect(rect, Color(1.0, 0.82, 0.2, 0.75), false, 2.0)
	# 斜向脚手架条纹
	var stripe_color := Color(1.0, 0.82, 0.2, 0.38)
	var stripe_gap := 26.0
	var x := rect.position.x - 10.0
	while x < rect.end.x:
		var x2 := minf(x + 16.0, rect.end.x)
		draw_line(Vector2(maxf(x, rect.position.x), rect.position.y), Vector2(x2, rect.end.y), stripe_color, 1.5)
		x += stripe_gap
	# 文字提示
	var pct := int(progress * 100.0)
	var txt := "施工中 %d%%" % pct
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var pos := Vector2(-text_size.x * 0.5, rect.position.y + 18)
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.92, 0.35, 0.95))
