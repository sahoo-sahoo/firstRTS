## 命中特效 - 简单粒子爆炸
class_name HitEffect
extends Node2D

var color: Color = Color.YELLOW
var lifetime: float = 0.3
var _timer: float = 0.0
var _max_radius: float = 15.0

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= lifetime:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := _timer / lifetime
	var radius := _max_radius * progress
	var alpha := 1.0 - progress
	
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, alpha * 0.3))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 16, Color(color.r, color.g, color.b, alpha * 0.6), 2.0)
	draw_circle(Vector2.ZERO, radius * 0.3, Color(1, 1, 1, alpha * 0.5))
