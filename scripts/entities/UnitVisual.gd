## 单位可视化 - 代码绘制各类单位的外观
## 后期替换美术资源时，只需调用 set_sprite() 或 set_animation()
class_name UnitVisual
extends EntityVisual

var unit_type: String = "sa_worker"
var unit_radius: float = 10.0
var turret_angle: float = 0.0  # 炮塔朝向 (坦克用)
var is_air: bool = false

var hp: int = 100
var max_hp: int = 100
var shield: int = 0
var max_shield: int = 0

## 携带资源的视觉提示
var carrying_resource: bool = false
var carrying_type: int = 0  # 0=mineral, 1=energy
var is_gathering: bool = false  # 正在采集中
var carried_amount: int = 0     # 当前携带数量
var carry_capacity: int = 10    # 最大携带量

func _draw_procedural() -> void:
	var color := get_team_color()
	var data: Dictionary = GameConstants.UNIT_DATA.get(unit_type, {})
	var type: int = data.get("type", GameConstants.UnitType.WORKER)
	
	# 选中圈
	draw_selection_circle(unit_radius)
	
	# 根据单位类型绘制
	match type:
		GameConstants.UnitType.WORKER:
			_draw_worker(color)
		GameConstants.UnitType.INFANTRY:
			_draw_infantry(color)
		GameConstants.UnitType.TANK:
			_draw_tank(color)
		GameConstants.UnitType.HELICOPTER:
			_draw_helicopter(color)
		GameConstants.UnitType.SUPER_UNIT:
			_draw_super_unit(color)
		_:
			_draw_worker(color)
	
	# 血条
	var bar_width := unit_radius * 2.5
	draw_health_bar(hp, max_hp, -unit_radius - 14, bar_width)
	draw_shield_bar(shield, max_shield, -unit_radius - 20, bar_width)

## ====== 各单位类型的绘制 ======

func _draw_worker(color: Color) -> void:
	# 小圆身体
	draw_circle(Vector2.ZERO, unit_radius, color)
	draw_arc(Vector2.ZERO, unit_radius, 0, TAU, 24, color.darkened(0.3), 1.5)
	
	# 锤子 / 工具标记
	var tool_start := Vector2(0, -unit_radius * 0.3).rotated(facing_angle)
	var tool_end := tool_start + Vector2(unit_radius * 0.8, 0).rotated(facing_angle)
	draw_line(tool_start, tool_end, Color.GRAY, 2.0)
	
	# 头部/核心亮色点
	draw_circle(Vector2.ZERO, unit_radius * 0.4, color.lightened(0.3))
	
	# 采集中动画效果（锤子摆动 + 火花）
	if is_gathering and not carrying_resource:
		var t := fmod(Time.get_ticks_msec() * 0.006, TAU)
		var swing := sin(t) * 0.8
		var hammer_base := Vector2(unit_radius * 0.3, 0).rotated(facing_angle + swing)
		var hammer_end := hammer_base + Vector2(unit_radius * 0.9, 0).rotated(facing_angle + swing)
		draw_line(hammer_base, hammer_end, Color.LIGHT_GRAY, 2.5)
		# 锤头
		var head_dir := (hammer_end - hammer_base).normalized()
		var head_perp := head_dir.rotated(PI / 2)
		draw_line(hammer_end - head_perp * 3, hammer_end + head_perp * 3, Color(0.6, 0.6, 0.6), 3.0)
		# 火花粒子
		var spark_t := fmod(Time.get_ticks_msec() * 0.01, 1.0)
		if spark_t < 0.3:
			var spark_offset := Vector2(randf_range(-6, 6), randf_range(-8, -2))
			draw_circle(hammer_end + spark_offset, 1.5, Color(1.0, 0.9, 0.3, 1.0 - spark_t * 3))
	
	# 携带资源指示（大圆 + 数量标签，画在工人身体外侧上方）
	if carrying_resource:
		var res_color := Color(0.3, 0.55, 0.9) if carrying_type == GameConstants.ResourceType.MINERAL else Color(0.95, 0.8, 0.1)
		var indicator_pos := Vector2(unit_radius * 0.8, -unit_radius * 0.8)
		var indicator_r := 6.0
		# 背景圆
		draw_circle(indicator_pos, indicator_r + 1.5, Color(0, 0, 0, 0.5))
		draw_circle(indicator_pos, indicator_r, res_color)
		draw_arc(indicator_pos, indicator_r, 0, TAU, 12, res_color.lightened(0.4), 1.5)
		# 数量文字
		var font := ThemeDB.fallback_font
		var amount_text := str(carried_amount)
		var text_size := font.get_string_size(amount_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
		draw_string(font, indicator_pos - Vector2(text_size.x / 2, -3), amount_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.WHITE)

func _draw_infantry(color: Color) -> void:
	# 身体 - 圆形
	draw_circle(Vector2.ZERO, unit_radius, color)
	draw_arc(Vector2.ZERO, unit_radius, 0, TAU, 24, color.darkened(0.3), 1.5)
	
	# 枪管
	var gun_start := Vector2.ZERO
	var gun_end := Vector2(unit_radius * 1.5, 0).rotated(facing_angle)
	draw_line(gun_start, gun_end, Color(0.3, 0.3, 0.3), 2.5)
	
	# 头盔/头部 - 小三角标记朝向
	var dir := Vector2.RIGHT.rotated(facing_angle)
	var tri_size := unit_radius * 0.5
	var tri := PackedVector2Array([
		dir * tri_size,
		dir.rotated(2.3) * tri_size * 0.6,
		dir.rotated(-2.3) * tri_size * 0.6,
	])
	draw_colored_polygon(tri, color.lightened(0.2))

func _draw_tank(color: Color) -> void:
	# 车身 - 矩形
	var body_size := Vector2(unit_radius * 2.0, unit_radius * 1.3)
	var body_rect := Rect2(-body_size / 2.0, body_size)
	
	# 旋转车身
	draw_set_transform(Vector2.ZERO, facing_angle)
	draw_rect(body_rect, color)
	draw_rect(body_rect, color.darkened(0.3), false, 2.0)
	
	# 履带
	var track_h := body_size.y * 0.2
	draw_rect(Rect2(-body_size.x / 2, -body_size.y / 2 - track_h, body_size.x, track_h), color.darkened(0.5))
	draw_rect(Rect2(-body_size.x / 2, body_size.y / 2, body_size.x, track_h), color.darkened(0.5))
	draw_set_transform(Vector2.ZERO, 0)
	
	# 炮塔 - 圆形 (独立旋转)
	draw_circle(Vector2.ZERO, unit_radius * 0.55, color.lightened(0.15))
	draw_arc(Vector2.ZERO, unit_radius * 0.55, 0, TAU, 20, color.darkened(0.2), 1.5)
	
	# 炮管 (跟随炮塔角度)
	var barrel_start := Vector2.ZERO
	var barrel_end := Vector2(unit_radius * 1.8, 0).rotated(turret_angle)
	draw_line(barrel_start, barrel_end, color.darkened(0.1), 3.5)
	# 炮口
	draw_circle(barrel_end, 2.5, color.lightened(0.3))

func _draw_helicopter(color: Color) -> void:
	# 阴影 (表示空中)
	draw_circle(Vector2(4, 6), unit_radius * 0.7, Color(0, 0, 0, 0.2))
	
	# 机身 - 菱形
	var size := unit_radius
	var body := PackedVector2Array([
		Vector2(size * 1.4, 0).rotated(facing_angle),
		Vector2(0, size * 0.7).rotated(facing_angle),
		Vector2(-size * 0.8, 0).rotated(facing_angle),
		Vector2(0, -size * 0.7).rotated(facing_angle),
	])
	draw_colored_polygon(body, color)
	draw_polyline(body + PackedVector2Array([body[0]]), color.darkened(0.3), 1.5)
	
	# 旋翼 (旋转动画)
	var rotor_angle := fmod(Time.get_ticks_msec() * 0.01, TAU)
	var rotor_len := unit_radius * 1.2
	draw_line(
		Vector2(-rotor_len, 0).rotated(rotor_angle),
		Vector2(rotor_len, 0).rotated(rotor_angle),
		Color(0.7, 0.7, 0.7, 0.5), 1.5
	)
	draw_line(
		Vector2(0, -rotor_len).rotated(rotor_angle),
		Vector2(0, rotor_len).rotated(rotor_angle),
		Color(0.7, 0.7, 0.7, 0.5), 1.5
	)
	
	# 中心点
	draw_circle(Vector2.ZERO, 3, color.lightened(0.3))

func _draw_super_unit(color: Color) -> void:
	# 大型单位 - 六边形 + 发光
	var points := PackedVector2Array()
	for i in range(6):
		var angle := i * TAU / 6.0 - PI / 6.0
		points.append(Vector2.from_angle(angle) * unit_radius)
	
	# 外发光
	var glow_points := PackedVector2Array()
	for i in range(6):
		var angle := i * TAU / 6.0 - PI / 6.0
		glow_points.append(Vector2.from_angle(angle) * (unit_radius + 4))
	draw_colored_polygon(glow_points, Color(color.r, color.g, color.b, 0.3))
	
	# 主体
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), color.lightened(0.3), 2.0)
	
	# 核心
	draw_circle(Vector2.ZERO, unit_radius * 0.35, color.lightened(0.4))
