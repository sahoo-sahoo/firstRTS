## 投射物 - 弹道可视化
class_name Projectile
extends Node2D

var start_pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var target_node: Node2D = null
var speed: float = 400.0
var damage: int = 10
var team_id: int = 0
var _progress: float = 0.0
var color: Color = Color.YELLOW

## 美术素材接口
var use_sprite: bool = false
var sprite_texture: Texture2D = null

func setup(from: Vector2, to_node: Node2D, dmg: int, spd: float, clr: Color, tid: int) -> void:
	start_pos = from
	global_position = from
	target_node = to_node
	target_pos = to_node.global_position if to_node else to_node
	damage = dmg
	speed = spd
	color = clr
	team_id = tid

func _process(delta: float) -> void:
	if target_node and is_instance_valid(target_node):
		target_pos = target_node.global_position
	
	var dir := (target_pos - global_position)
	var dist := dir.length()
	
	if dist < 10:
		_on_hit()
		return
	
	global_position += dir.normalized() * speed * delta
	queue_redraw()

func _draw() -> void:
	if use_sprite and sprite_texture:
		draw_texture(sprite_texture, -sprite_texture.get_size() / 2.0)
		return
	
	# 代码绘制弹道
	draw_circle(Vector2.ZERO, 3, color)
	draw_circle(Vector2.ZERO, 5, Color(color.r, color.g, color.b, 0.3))
	
	# 拖尾
	var trail_dir := (start_pos - global_position).normalized()
	draw_line(Vector2.ZERO, trail_dir * 10, Color(color.r, color.g, color.b, 0.4), 1.5)

func _on_hit() -> void:
	if target_node and is_instance_valid(target_node) and target_node.has_method("take_damage"):
		target_node.take_damage(damage)
	
	# 爆炸效果
	_spawn_hit_effect()
	queue_free()

func _spawn_hit_effect() -> void:
	var effect := HitEffect.new()
	effect.global_position = global_position
	effect.color = color
	get_parent().add_child(effect)

## 设置弹道美术素材
func set_projectile_sprite(texture: Texture2D) -> void:
	sprite_texture = texture
	use_sprite = true
