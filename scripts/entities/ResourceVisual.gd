## 资源节点可视化 - 矿石/能源的代码绘制
class_name ResourceVisual
extends EntityVisual

var resource_type: int = GameConstants.ResourceType.MINERAL
var remaining_ratio: float = 1.0

func _draw_procedural() -> void:
	match resource_type:
		GameConstants.ResourceType.MINERAL:
			_draw_mineral()
		GameConstants.ResourceType.ENERGY:
			_draw_energy()

func _draw_mineral() -> void:
	# 矿石 - 蓝色晶体簇，大而醒目
	var size_factor := 0.5 + remaining_ratio * 0.5
	
	# 底座阴影
	draw_circle(Vector2(0, 8), 22 * size_factor, Color(0, 0, 0, 0.25))
	
	# 多块蓝色晶体
	var crystals := [
		{"pos": Vector2(-10, 5), "h": 30, "w": 14, "color": Color(0.3, 0.55, 0.9)},
		{"pos": Vector2(4, 0), "h": 38, "w": 16, "color": Color(0.35, 0.6, 0.95)},
		{"pos": Vector2(16, 6), "h": 24, "w": 12, "color": Color(0.4, 0.65, 0.85)},
		{"pos": Vector2(-4, 8), "h": 20, "w": 14, "color": Color(0.25, 0.5, 0.85)},
	]
	
	for crystal in crystals:
		var p: Vector2 = crystal["pos"]
		var h: float = crystal["h"] * size_factor
		var w: float = crystal["w"] * size_factor
		var c: Color = crystal["color"]
		# 六边形晶体
		var points := PackedVector2Array([
			p + Vector2(0, -h),
			p + Vector2(w * 0.5, -h * 0.6),
			p + Vector2(w * 0.5, -h * 0.15),
			p + Vector2(0, 0),
			p + Vector2(-w * 0.5, -h * 0.15),
			p + Vector2(-w * 0.5, -h * 0.6),
		])
		draw_colored_polygon(points, c)
		# 右侧高光面
		var highlight := PackedVector2Array([
			p + Vector2(0, -h),
			p + Vector2(w * 0.5, -h * 0.6),
			p + Vector2(w * 0.5, -h * 0.15),
			p + Vector2(0, -h * 0.4),
		])
		draw_colored_polygon(highlight, c.lightened(0.25))
		# 边框
		draw_polyline(points + PackedVector2Array([points[0]]), c.darkened(0.3), 1.5)
	
	# “矿”标记文字
	draw_string(ThemeDB.fallback_font, Vector2(-8, -38 * size_factor), "矿", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.7, 0.85, 1.0))

func _draw_energy() -> void:
	# 能源 - 黄绿色发光球体，与矿石明显区分
	var size_factor := 0.5 + remaining_ratio * 0.5
	var radius := 18.0 * size_factor
	var base_color := Color(0.95, 0.8, 0.1)  # 金黄色
	
	# 底座阴影
	draw_circle(Vector2(0, 8), radius + 2, Color(0, 0, 0, 0.2))
	
	# 外层光晕 (脉动)
	var pulse := sin(Time.get_ticks_msec() * 0.004) * 4
	draw_circle(Vector2.ZERO, radius + 8 + pulse, Color(base_color.r, base_color.g, base_color.b, 0.1))
	draw_circle(Vector2.ZERO, radius + 4 + pulse * 0.5, Color(base_color.r, base_color.g, base_color.b, 0.2))
	
	# 主体圆球
	draw_circle(Vector2.ZERO, radius, base_color)
	# 内圈 - 橙色渐变
	draw_circle(Vector2.ZERO, radius * 0.65, Color(1.0, 0.6, 0.1))
	# 核心亮点
	draw_circle(Vector2(-3, -3), radius * 0.3, Color(1.0, 1.0, 0.8, 0.8))
	
	# 边缘光环
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, base_color.lightened(0.3), 2.0)
	
	# 小闪电线条 (能量感)
	var ang := fmod(Time.get_ticks_msec() * 0.002, TAU)
	for i in range(3):
		var a := ang + i * TAU / 3.0
		var p1 := Vector2(cos(a), sin(a)) * radius
		var p2 := Vector2(cos(a + 0.3), sin(a + 0.3)) * (radius + 6 + pulse)
		draw_line(p1, p2, Color(1.0, 0.9, 0.3, 0.5), 1.5)
	
	# "能"标记文字
	draw_string(ThemeDB.fallback_font, Vector2(-8, -radius - 8), "能", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1.0, 0.9, 0.4))
