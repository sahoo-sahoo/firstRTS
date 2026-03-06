## 战斗特效系统 - 弹道、伤害数字、受击闪烁、爆炸、死亡特效
class_name CombatEffects
extends Node2D

## ====== 弹道 (Projectile) ======

## 发射子弹 / 能量弹
func spawn_projectile(from: Vector2, to: Vector2, color: Color = Color.YELLOW,
		speed: float = 600.0, size: float = 3.0, is_energy: bool = false) -> void:
	var proj := FxProjectile.new()
	proj.start_pos = from
	proj.end_pos = to
	proj.color = color
	proj.speed = speed
	proj.size = size
	proj.is_energy = is_energy
	add_child(proj)

## 发射追踪弹
func spawn_homing_projectile(from: Vector2, target: Node2D, color: Color = Color.YELLOW,
		speed: float = 400.0, size: float = 4.0, damage: int = 0) -> void:
	var proj := FxHomingProjectile.new()
	proj.global_position = from
	proj.target_node = target
	proj.color = color
	proj.speed = speed
	proj.size = size
	proj.damage = damage
	add_child(proj)

## ====== 伤害数字 ======

func spawn_damage_number(pos: Vector2, amount: int, is_crit: bool = false) -> void:
	var dmg_num := DamageNumber.new()
	dmg_num.global_position = pos + Vector2(randf_range(-10, 10), -20)
	dmg_num.amount = amount
	dmg_num.is_crit = is_crit
	add_child(dmg_num)

## ====== 受击闪烁 ======

func flash_entity(entity: Node2D, flash_color: Color = Color.WHITE,
		duration: float = 0.1) -> void:
	if not is_instance_valid(entity):
		return
	var original_modulate := entity.modulate
	entity.modulate = flash_color
	var tween := create_tween()
	tween.tween_property(entity, "modulate", original_modulate, duration)

## ====== 爆炸特效 ======

func spawn_explosion(pos: Vector2, radius: float = 30.0, color: Color = Color(1, 0.6, 0.1)) -> void:
	var exp := ExplosionEffect.new()
	exp.global_position = pos
	exp.max_radius = radius
	exp.base_color = color
	add_child(exp)

## 小型命中特效
func spawn_hit_spark(pos: Vector2, color: Color = Color.YELLOW) -> void:
	var spark := HitSpark.new()
	spark.global_position = pos
	spark.color = color
	add_child(spark)

## ====== 死亡特效 ======

func spawn_death_effect(pos: Vector2, unit_radius: float = 10.0,
		is_building: bool = false, color: Color = Color.ORANGE_RED) -> void:
	if is_building:
		# 建筑爆炸更大
		spawn_explosion(pos, unit_radius * 3, color)
		# 多爆几次
		for i in range(3):
			var offset := Vector2(randf_range(-unit_radius, unit_radius),
				randf_range(-unit_radius, unit_radius))
			var t := create_tween()
			t.tween_callback(spawn_explosion.bind(pos + offset, unit_radius * 2, color)).set_delay(0.2 * (i + 1))
	else:
		spawn_explosion(pos, unit_radius * 2, color)

## ====== 护盾受击 ======

func spawn_shield_hit(pos: Vector2, radius: float = 15.0) -> void:
	var shield := ShieldHitEffect.new()
	shield.global_position = pos
	shield.shield_radius = radius
	add_child(shield)

## ====== 攻击线 (即时命中武器) ======

func spawn_attack_line(from: Vector2, to: Vector2, color: Color = Color.RED,
		width: float = 2.0, duration: float = 0.15) -> void:
	var line := AttackLine.new()
	line.from_pos = from
	line.to_pos = to
	line.color = color
	line.line_width = width
	line.duration = duration
	add_child(line)


## ================================================================
## 内部特效类
## ================================================================

## ----- 直线弹道 -----
class FxProjectile extends Node2D:
	var start_pos: Vector2
	var end_pos: Vector2
	var color: Color = Color.YELLOW
	var speed: float = 600.0
	var size: float = 3.0
	var is_energy: bool = false
	var _progress: float = 0.0
	var _total_dist: float = 0.0
	var _trail: PackedVector2Array = PackedVector2Array()
	
	func _ready() -> void:
		global_position = start_pos
		_total_dist = start_pos.distance_to(end_pos)
		if _total_dist < 1.0:
			queue_free()
	
	func _process(delta: float) -> void:
		_progress += speed * delta
		var t := clampf(_progress / _total_dist, 0.0, 1.0)
		global_position = start_pos.lerp(end_pos, t)
		# 轨迹
		_trail.append(global_position)
		if _trail.size() > 8:
			_trail = _trail.slice(1)
		queue_redraw()
		if t >= 1.0:
			queue_free()
	
	func _draw() -> void:
		# 弹体
		if is_energy:
			draw_circle(Vector2.ZERO, size * 1.5, Color(color.r, color.g, color.b, 0.3))
		draw_circle(Vector2.ZERO, size, color)
		# 尾迹
		if _trail.size() >= 2:
			for i in range(_trail.size() - 1):
				var alpha := float(i) / _trail.size() * 0.6
				var w := size * float(i) / _trail.size()
				var local_from := _trail[i] - global_position
				var local_to := _trail[i + 1] - global_position
				draw_line(local_from, local_to, Color(color.r, color.g, color.b, alpha), maxf(w, 0.5))

## ----- 追踪弹 -----
class FxHomingProjectile extends Node2D:
	var target_node: Node2D = null
	var color: Color = Color.YELLOW
	var speed: float = 400.0
	var size: float = 4.0
	var damage: int = 0
	var _lifetime: float = 0.0
	var _max_lifetime: float = 5.0
	
	func _process(delta: float) -> void:
		_lifetime += delta
		if _lifetime > _max_lifetime:
			queue_free()
			return
		if target_node == null or not is_instance_valid(target_node):
			queue_free()
			return
		var dir := (target_node.global_position - global_position)
		var dist := dir.length()
		if dist < 10.0:
			# 命中
			queue_free()
			return
		dir = dir.normalized()
		global_position += dir * speed * delta
		queue_redraw()
	
	func _draw() -> void:
		draw_circle(Vector2.ZERO, size, color)
		draw_circle(Vector2.ZERO, size * 1.8, Color(color.r, color.g, color.b, 0.2))

## ----- 伤害数字 -----
class DamageNumber extends Node2D:
	var amount: int = 0
	var is_crit: bool = false
	var _life: float = 0.0
	var _duration: float = 0.8
	
	func _process(delta: float) -> void:
		_life += delta
		global_position.y -= 40.0 * delta  # 上浮
		queue_redraw()
		if _life >= _duration:
			queue_free()
	
	func _draw() -> void:
		var alpha := clampf(1.0 - _life / _duration, 0.0, 1.0)
		var font := ThemeDB.fallback_font
		var text := "-%d" % amount
		var font_size := 14 if not is_crit else 20
		var color := Color(1, 0.3, 0.2, alpha) if not is_crit else Color(1.0, 0.9, 0.1, alpha)
		# 阴影
		draw_string(font, Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0, 0, 0, alpha * 0.5))
		draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)

## ----- 爆炸特效 -----
class ExplosionEffect extends Node2D:
	var max_radius: float = 30.0
	var base_color: Color = Color(1, 0.6, 0.1)
	var _life: float = 0.0
	var _duration: float = 0.4
	
	func _process(delta: float) -> void:
		_life += delta
		queue_redraw()
		if _life >= _duration:
			queue_free()
	
	func _draw() -> void:
		var t := _life / _duration
		var alpha := clampf(1.0 - t, 0.0, 1.0)
		var radius := max_radius * (0.3 + t * 0.7)
		# 外圈
		draw_circle(Vector2.ZERO, radius, Color(base_color.r, base_color.g, base_color.b, alpha * 0.3))
		# 中圈
		draw_circle(Vector2.ZERO, radius * 0.6, Color(1.0, 0.9, 0.4, alpha * 0.6))
		# 核心白
		draw_circle(Vector2.ZERO, radius * 0.25, Color(1, 1, 1, alpha * 0.8))
		# 边缘光
		draw_arc(Vector2.ZERO, radius, 0, TAU, 24, Color(base_color.r, base_color.g * 0.5, 0, alpha * 0.5), 2.0)

## ----- 命中火花 -----
class HitSpark extends Node2D:
	var color: Color = Color.YELLOW
	var _life: float = 0.0
	var _duration: float = 0.2
	var _sparks: Array = []
	
	func _ready() -> void:
		for i in range(6):
			var angle := randf() * TAU
			var spd := randf_range(40, 100)
			_sparks.append({"angle": angle, "speed": spd})
	
	func _process(delta: float) -> void:
		_life += delta
		queue_redraw()
		if _life >= _duration:
			queue_free()
	
	func _draw() -> void:
		var alpha := clampf(1.0 - _life / _duration, 0.0, 1.0)
		for s in _sparks:
			var dist: float = s["speed"] * _life
			var pos := Vector2.from_angle(s["angle"]) * dist
			draw_circle(pos, 1.5, Color(color.r, color.g, color.b, alpha))

## ----- 护盾受击 -----
class ShieldHitEffect extends Node2D:
	var shield_radius: float = 15.0
	var _life: float = 0.0
	var _duration: float = 0.3
	
	func _process(delta: float) -> void:
		_life += delta
		queue_redraw()
		if _life >= _duration:
			queue_free()
	
	func _draw() -> void:
		var alpha := clampf(1.0 - _life / _duration, 0.0, 1.0)
		# 蓝色护盾闪光弧
		draw_arc(Vector2.ZERO, shield_radius, -PI * 0.4, PI * 0.4, 16,
			Color(0.3, 0.6, 1.0, alpha * 0.8), 2.5)
		draw_arc(Vector2.ZERO, shield_radius * 0.8, -PI * 0.3, PI * 0.3, 12,
			Color(0.5, 0.8, 1.0, alpha * 0.5), 1.5)

## ----- 攻击线 -----
class AttackLine extends Node2D:
	var from_pos: Vector2
	var to_pos: Vector2
	var color: Color = Color.RED
	var line_width: float = 2.0
	var duration: float = 0.15
	var _life: float = 0.0
	
	func _process(delta: float) -> void:
		_life += delta
		queue_redraw()
		if _life >= duration:
			queue_free()
	
	func _draw() -> void:
		var alpha := clampf(1.0 - _life / duration, 0.0, 1.0)
		var local_from := from_pos - global_position
		var local_to := to_pos - global_position
		draw_line(local_from, local_to, Color(color.r, color.g, color.b, alpha), line_width)
		# 明亮核心线
		draw_line(local_from, local_to, Color(1, 1, 1, alpha * 0.5), line_width * 0.4)
