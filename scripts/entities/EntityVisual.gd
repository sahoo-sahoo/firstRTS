## 可视化组件基类 - 所有实体的绘制/渲染逻辑
## 预留了从代码绘制切换到 Sprite/AnimatedSprite 的接口
class_name EntityVisual
extends Node2D

## 渲染模式枚举
enum VisualMode {
	PROCEDURAL,    ## 代码绘制（几何图形）
	SPRITE,        ## 静态图片
	ANIMATED,      ## 帧动画
}

## 当前渲染模式
@export var visual_mode: VisualMode = VisualMode.PROCEDURAL

## Sprite 纹理 (当 visual_mode = SPRITE 时使用)
@export var sprite_texture: Texture2D = null

## 动画帧集 (当 visual_mode = ANIMATED 时使用)
@export var sprite_frames: SpriteFrames = null

## 颜色调制 (对所有模式生效)
@export var modulate_color: Color = Color.WHITE

## 朝向角度 (弧度)
var facing_angle: float = 0.0

## 是否被选中
var is_selected: bool = false

## 阵营ID
var team_id: int = 0

## 内部引用
var _sprite: Sprite2D = null
var _animated_sprite: AnimatedSprite2D = null

## ====== 生命周期 ======

func _ready() -> void:
	# 预创建 Sprite 节点（隐藏），方便后期切换
	_sprite = Sprite2D.new()
	_sprite.visible = false
	_sprite.name = "SpriteVisual"
	add_child(_sprite)
	
	_animated_sprite = AnimatedSprite2D.new()
	_animated_sprite.visible = false
	_animated_sprite.name = "AnimatedVisual"
	add_child(_animated_sprite)
	
	_apply_visual_mode()

func _process(_delta: float) -> void:
	if visual_mode == VisualMode.PROCEDURAL:
		queue_redraw()

func _draw() -> void:
	if visual_mode == VisualMode.PROCEDURAL:
		_draw_procedural()

## ====== 公共接口 ======

## 切换渲染模式
func switch_visual_mode(new_mode: VisualMode) -> void:
	visual_mode = new_mode
	_apply_visual_mode()

## 设置 Sprite 纹理 (切换到图片模式)
func set_sprite(texture: Texture2D) -> void:
	sprite_texture = texture
	_sprite.texture = texture
	switch_visual_mode(VisualMode.SPRITE)

## 设置动画帧集 (切换到动画模式)
func set_animation(frames: SpriteFrames, default_anim: String = "idle") -> void:
	sprite_frames = frames
	_animated_sprite.sprite_frames = frames
	_animated_sprite.play(default_anim)
	switch_visual_mode(VisualMode.ANIMATED)

## 播放动画 (仅 ANIMATED 模式)
func play_animation(anim_name: String) -> void:
	if visual_mode == VisualMode.ANIMATED and _animated_sprite.sprite_frames:
		if _animated_sprite.sprite_frames.has_animation(anim_name):
			_animated_sprite.play(anim_name)

## 设置朝向
func set_facing(angle: float) -> void:
	facing_angle = angle
	if visual_mode != VisualMode.PROCEDURAL:
		_sprite.rotation = angle
		_animated_sprite.rotation = angle

## 设置选中状态
func set_selected(selected: bool) -> void:
	is_selected = selected

## ====== 子类必须重写 ======

## 代码绘制逻辑 - 子类重写此方法实现不同的绘制
func _draw_procedural() -> void:
	pass  # 子类实现

## ====== 内部方法 ======

func _apply_visual_mode() -> void:
	_sprite.visible = (visual_mode == VisualMode.SPRITE)
	_animated_sprite.visible = (visual_mode == VisualMode.ANIMATED)
	
	match visual_mode:
		VisualMode.SPRITE:
			if sprite_texture:
				_sprite.texture = sprite_texture
			_sprite.modulate = modulate_color
		VisualMode.ANIMATED:
			if sprite_frames:
				_animated_sprite.sprite_frames = sprite_frames
			_animated_sprite.modulate = modulate_color
		VisualMode.PROCEDURAL:
			pass  # _draw() 会处理

## 获取阵营颜色
func get_team_color() -> Color:
	return GameConstants.TEAM_COLORS.get(team_id, Color.WHITE)

## 绘制选中圈
func draw_selection_circle(radius: float) -> void:
	if is_selected:
		draw_arc(Vector2.ZERO, radius + 4, 0, TAU, 32, Color.GREEN, 2.0)

## 绘制血条 (通用)
func draw_health_bar(current: int, maximum: int, offset_y: float, bar_width: float, bar_height: float = 4.0) -> void:
	if current >= maximum:
		return
	var ratio := clampf(float(current) / float(maximum), 0.0, 1.0)
	var bar_pos := Vector2(-bar_width / 2.0, offset_y)
	# 背景
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(0.2, 0.2, 0.2, 0.8))
	# 血量
	var hp_color := Color.GREEN if ratio > 0.5 else (Color.YELLOW if ratio > 0.25 else Color.RED)
	draw_rect(Rect2(bar_pos, Vector2(bar_width * ratio, bar_height)), hp_color)
	# 边框
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(0.1, 0.1, 0.1), false, 1.0)

## 绘制护盾条
func draw_shield_bar(current: int, maximum: int, offset_y: float, bar_width: float, bar_height: float = 3.0) -> void:
	if maximum <= 0:
		return
	var ratio := clampf(float(current) / float(maximum), 0.0, 1.0)
	var bar_pos := Vector2(-bar_width / 2.0, offset_y)
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(0.1, 0.1, 0.3, 0.6))
	draw_rect(Rect2(bar_pos, Vector2(bar_width * ratio, bar_height)), Color(0.3, 0.7, 1.0, 0.9))

## 绘制建造进度
func draw_build_progress(progress: float, radius: float) -> void:
	if progress >= 1.0:
		return
	var angle := progress * TAU - PI / 2.0
	draw_arc(Vector2.ZERO, radius + 6, -PI / 2.0, angle, 32, Color(0.2, 0.9, 0.2, 0.7), 3.0)
