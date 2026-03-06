## 资源节点 - 矿点/能源点
class_name ResourceNode
extends StaticBody2D

signal resource_depleted(node: ResourceNode)

@export var resource_type: GameConstants.ResourceType = GameConstants.ResourceType.MINERAL
@export var total_amount: int = 1500
var remaining_amount: int = 1500
var entity_id: int = -1
var collision_radius: float = 24.0

## 当前正在采集的工人 (null 表示空闲)
var occupied_by: Node2D = null

var visual: Node2D = null

func _ready() -> void:
	remaining_amount = total_amount
	_setup_visual()
	_setup_collision()

func _setup_visual() -> void:
	visual = Node2D.new()
	visual.name = "Visual"
	add_child(visual)
	visual.set_script(preload("res://scripts/entities/ResourceVisual.gd"))
	visual.resource_type = resource_type

func _process(_delta: float) -> void:
	if visual and total_amount > 0:
		visual.remaining_ratio = float(remaining_amount) / float(total_amount)

func _setup_collision() -> void:
	var shape := CircleShape2D.new()
	# 碰撞半径与实际绘制大小匹配
	if resource_type == GameConstants.ResourceType.MINERAL:
		shape.radius = 28.0  # 矿石晶体簇 (宽约 40px, 高约 38px)
	else:
		shape.radius = 22.0  # 能源球 (含发光光晕)
	collision_radius = shape.radius
	var col := CollisionShape2D.new()
	col.shape = shape
	col.name = "CollisionShape"
	add_child(col)
	collision_layer = 8  # resources layer (layer 4, bit index)
	collision_mask = 0

func get_collision_radius() -> float:
	return collision_radius

## 采集资源
func gather(amount: int) -> int:
	var actual := mini(amount, remaining_amount)
	remaining_amount -= actual
	if remaining_amount <= 0:
		occupied_by = null
		resource_depleted.emit(self)
		# 淡出
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.5)
		tween.tween_callback(queue_free)
	return actual

## 尝试占用矿点 (返回是否成功)
func try_occupy(worker: Node2D) -> bool:
	if occupied_by == null or not is_instance_valid(occupied_by) or occupied_by == worker:
		occupied_by = worker
		return true
	return false

## 释放占用
func release(worker: Node2D) -> void:
	if occupied_by == worker:
		occupied_by = null

## 美术素材接口
func set_resource_sprite(texture: Texture2D) -> void:
	if visual and visual.has_method("set_sprite"):
		visual.set_sprite(texture)
