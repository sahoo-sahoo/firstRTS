## 相机系统 - WASD/鼠标边缘滚动/缩放
class_name CameraSystem
extends Camera2D

## 移动速度 (像素/秒)
@export var move_speed: float = 600.0

## 鼠标边缘滚动触发区域 (像素)
@export var edge_margin: float = 20.0

## 缩放范围
@export var zoom_min: float = 0.3
@export var zoom_max: float = 2.0
@export var zoom_step: float = 0.1
@export var zoom_smooth: float = 10.0

## 地图边界限制
var map_bounds: Rect2 = Rect2(0, 0, 10240, 7680)

## 底部 HUD 高度 (像素), 用于扩展相机下边界使地图底部不被 HUD 遮挡
var hud_bottom_height: float = 0.0

## 目标缩放
var _target_zoom: Vector2 = Vector2.ONE

## 右键拖拽平移状态
var _rclick_dragging: bool = false
var _rclick_last_mouse: Vector2 = Vector2.ZERO
## 右键拖拽产生的惯性速度（世界坐标像素/秒）
var _pan_velocity: Vector2 = Vector2.ZERO
## 惯性衰减系数（每秒剩余比例）
const PAN_FRICTION: float = 8.0

## 是否启用鼠标边缘滚动
@export var edge_scroll_enabled: bool = true

func _ready() -> void:
	_target_zoom = zoom
	# 启用平滑
	position_smoothing_enabled = true
	position_smoothing_speed = 15.0

func setup(map_pixel_size: Vector2) -> void:
	map_bounds = Rect2(Vector2.ZERO, map_pixel_size)

func _process(delta: float) -> void:
	var move_dir := Vector2.ZERO
	
	# WASD 键盘移动
	if Input.is_action_pressed("camera_up"):
		move_dir.y -= 1
	if Input.is_action_pressed("camera_down"):
		move_dir.y += 1
	if Input.is_action_pressed("camera_left"):
		move_dir.x -= 1
	if Input.is_action_pressed("camera_right"):
		move_dir.x += 1
	
	# 鼠标边缘滚动
	if edge_scroll_enabled:
		var mouse_pos := get_viewport().get_mouse_position()
		var viewport_size := get_viewport_rect().size
		
		if mouse_pos.x < edge_margin:
			move_dir.x -= 1
		elif mouse_pos.x > viewport_size.x - edge_margin:
			move_dir.x += 1
		if mouse_pos.y < edge_margin:
			move_dir.y -= 1
		elif mouse_pos.y > viewport_size.y - edge_margin:
			move_dir.y += 1
	
	# 应用移动
	if move_dir != Vector2.ZERO:
		move_dir = move_dir.normalized()
		var speed_adjusted := move_speed / zoom.x  # 缩放适配速度
		position += move_dir * speed_adjusted * delta
		# 键盘/边缘滚动时清除拖拽惯性，避免叠加
		_pan_velocity = Vector2.ZERO

	# 右键拖拽惯性衰减
	if not _rclick_dragging and _pan_velocity.length_squared() > 0.1:
		position += _pan_velocity * delta
		_pan_velocity = _pan_velocity.lerp(Vector2.ZERO, PAN_FRICTION * delta)
	
	# 平滑缩放
	zoom = zoom.lerp(_target_zoom, zoom_smooth * delta)
	
	# 限制相机在地图边界内
	_clamp_to_bounds()

func _unhandled_input(event: InputEvent) -> void:
	# 右键按下/松开：控制拖拽平移
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_rclick_dragging = true
				_rclick_last_mouse = event.position
				_pan_velocity = Vector2.ZERO
			else:
				_rclick_dragging = false
		# 鼠标滚轮缩放
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_zoom += Vector2(zoom_step, zoom_step)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom -= Vector2(zoom_step, zoom_step)
			_target_zoom = _target_zoom.clamp(
				Vector2(zoom_min, zoom_min),
				Vector2(zoom_max, zoom_max)
			)

	# 右键拖拽平移：鼠标移动时按鼠标位移反向平移相机
	if event is InputEventMouseMotion and _rclick_dragging:
		var mouse_delta: Vector2 = event.position - _rclick_last_mouse
		_rclick_last_mouse = event.position
		# 世界坐标偏移 = 屏幕偏移 / 缩放（鼠标向右 → 场景向左 → 相机向右补偿）
		var world_delta: Vector2 = -mouse_delta / zoom.x
		position += world_delta
		# 记录拖拽速度供惯性使用（速度 = 本帧偏移 / 物理帧时长）
		var engine_delta := 1.0 / Engine.get_frames_per_second() if Engine.get_frames_per_second() > 0 else 0.016
		_pan_velocity = world_delta / engine_delta
		_clamp_to_bounds()

## 跳转到指定世界坐标
func jump_to(world_pos: Vector2) -> void:
	position = world_pos
	_clamp_to_bounds()

## 平滑移动到指定坐标
func move_to(world_pos: Vector2) -> void:
	# 使用 Tween
	var tween := create_tween()
	tween.tween_property(self, "position", world_pos, 0.3).set_ease(Tween.EASE_OUT)

func _clamp_to_bounds() -> void:
	var viewport_size := get_viewport_rect().size / zoom
	var half_vp := viewport_size / 2.0
	# 底部额外偏移: 将 HUD 遮挡高度换算为世界坐标, 使地图底部可完整显示
	var hud_offset_y := hud_bottom_height / zoom.y
	position.x = clampf(position.x, map_bounds.position.x + half_vp.x, map_bounds.end.x - half_vp.x)
	position.y = clampf(position.y, map_bounds.position.y + half_vp.y, map_bounds.end.y - half_vp.y + hud_offset_y)
