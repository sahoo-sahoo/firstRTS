## AudioManager - 全局音频管理 (Autoload)
## 预留接口，后期添加音效文件即可
extends Node

var _sfx_players: Dictionary = {}  # {name: AudioStreamPlayer}
var _bgm_player: AudioStreamPlayer = null
var _last_event_time_ms: Dictionary = {}

## 主音量
var master_volume: float = 1.0
var sfx_volume: float = 0.8
var bgm_volume: float = 0.5

const TONE_SAMPLE_RATE: int = 44100

enum WaveShape {
	SINE,
	SQUARE,
	TRIANGLE,
}

func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGM"
	_bgm_player.bus = "Master"
	add_child(_bgm_player)

## 播放音效 (提供音效路径或预加载的 AudioStream)
func play_sfx(sfx_name: String, stream: AudioStream = null) -> void:
	if stream == null:
		# 尝试从缓存中获取
		if not _sfx_players.has(sfx_name):
			return
		_sfx_players[sfx_name].play()
		return
	
	var player: AudioStreamPlayer
	if _sfx_players.has(sfx_name):
		player = _sfx_players[sfx_name]
	else:
		player = AudioStreamPlayer.new()
		player.name = "SFX_" + sfx_name
		player.bus = "Master"
		add_child(player)
		_sfx_players[sfx_name] = player
	
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume * master_volume)
	player.play()

## 注册音效 (预加载)
func register_sfx(sfx_name: String, stream: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	player.name = "SFX_" + sfx_name
	player.stream = stream
	player.bus = "Master"
	add_child(player)
	_sfx_players[sfx_name] = player

## 播放背景音乐
func play_bgm(stream: AudioStream, fade_in: float = 1.0) -> void:
	_bgm_player.stream = stream
	_bgm_player.volume_db = linear_to_db(0.001)
	_bgm_player.play()
	
	var tween := create_tween()
	tween.tween_property(_bgm_player, "volume_db", linear_to_db(bgm_volume * master_volume), fade_in)

## 停止背景音乐
func stop_bgm(fade_out: float = 1.0) -> void:
	var tween := create_tween()
	tween.tween_property(_bgm_player, "volume_db", linear_to_db(0.001), fade_out)
	tween.tween_callback(_bgm_player.stop)

## 设置音量
func set_master_volume(vol: float) -> void:
	master_volume = clampf(vol, 0.0, 1.0)

func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)

func set_bgm_volume(vol: float) -> void:
	bgm_volume = clampf(vol, 0.0, 1.0)
	if _bgm_player.playing:
		_bgm_player.volume_db = linear_to_db(bgm_volume * master_volume)

## ====== 事件音效（无外部资源） ======

func play_ui_click() -> void:
	play_event_sfx("ui_click")

func play_event_sfx(event_name: String) -> void:
	if not _can_trigger_event(event_name):
		return

	match event_name:
		"ui_click":
			_play_tone_stack([
				{"freq": 880.0, "dur": 0.04, "vol": 0.20, "shape": WaveShape.SINE},
				{"freq": 1320.0, "dur": 0.03, "vol": 0.16, "shape": WaveShape.SINE},
			])
		"ui_error":
			_play_tone_stack([
				{"freq": 300.0, "dur": 0.10, "vol": 0.24, "shape": WaveShape.SQUARE},
				{"freq": 220.0, "dur": 0.10, "vol": 0.20, "shape": WaveShape.SQUARE},
			])
		"build_start":
			_play_tone_stack([
				{"freq": 440.0, "dur": 0.06, "vol": 0.20, "shape": WaveShape.TRIANGLE},
				{"freq": 520.0, "dur": 0.06, "vol": 0.20, "shape": WaveShape.TRIANGLE},
			])
		"build_complete":
			_play_tone_stack([
				{"freq": 520.0, "dur": 0.08, "vol": 0.22, "shape": WaveShape.SINE},
				{"freq": 660.0, "dur": 0.08, "vol": 0.24, "shape": WaveShape.SINE},
				{"freq": 880.0, "dur": 0.10, "vol": 0.24, "shape": WaveShape.SINE},
			])
		"queue_add":
			_play_tone_stack([
				{"freq": 700.0, "dur": 0.05, "vol": 0.18, "shape": WaveShape.SINE},
			])
		"unit_produced":
			_play_tone_stack([
				{"freq": 620.0, "dur": 0.05, "vol": 0.20, "shape": WaveShape.TRIANGLE},
				{"freq": 760.0, "dur": 0.07, "vol": 0.20, "shape": WaveShape.TRIANGLE},
			])
		"hit":
			_play_tone_stack([
				{"freq": 210.0, "dur": 0.035, "vol": 0.14, "shape": WaveShape.SQUARE},
			])
		"explosion":
			_play_tone_stack([
				{"freq": 140.0, "dur": 0.11, "vol": 0.24, "shape": WaveShape.SQUARE},
				{"freq": 95.0, "dur": 0.15, "vol": 0.24, "shape": WaveShape.TRIANGLE},
			])
		_:
			_play_tone_stack([
				{"freq": 520.0, "dur": 0.05, "vol": 0.18, "shape": WaveShape.SINE},
			])

func _can_trigger_event(event_name: String) -> bool:
	var now_ms: int = Time.get_ticks_msec()
	var min_interval_ms: int = 0
	match event_name:
		"hit":
			min_interval_ms = 60
		"explosion":
			min_interval_ms = 120
		"unit_produced":
			min_interval_ms = 80
		_:
			min_interval_ms = 0

	if min_interval_ms <= 0:
		return true
	var last_ms: int = int(_last_event_time_ms.get(event_name, 0))
	if now_ms - last_ms < min_interval_ms:
		return false
	_last_event_time_ms[event_name] = now_ms
	return true

func _play_tone_stack(notes: Array) -> void:
	for note in notes:
		var freq: float = float(note.get("freq", 440.0))
		var duration: float = float(note.get("dur", 0.08))
		var volume: float = float(note.get("vol", 0.20))
		var shape: int = int(note.get("shape", WaveShape.SINE))
		var stream := _generate_tone_stream(freq, duration, volume, shape)
		play_sfx("evt_%s_%d" % [str(freq), shape], stream)

func _generate_tone_stream(freq_hz: float, duration_sec: float, volume: float, shape: int = WaveShape.SINE) -> AudioStreamWAV:
	var sample_count := maxi(1, int(TONE_SAMPLE_RATE * duration_sec))
	var pcm_data := PackedByteArray()
	pcm_data.resize(sample_count * 2)
	var amp: float = clampf(volume * sfx_volume * master_volume, 0.0, 1.0)

	for i in range(sample_count):
		var t := float(i) / float(TONE_SAMPLE_RATE)
		var phase := TAU * freq_hz * t
		var env := _adsr_envelope(float(i) / float(sample_count))
		var wave_value := 0.0
		match shape:
			WaveShape.SQUARE:
				wave_value = 1.0 if sin(phase) >= 0.0 else -1.0
			WaveShape.TRIANGLE:
				wave_value = asin(sin(phase)) * (2.0 / PI)
			_:
				wave_value = sin(phase)

		var value := int(clampi(int(wave_value * env * amp * 32767.0), -32767, 32767))
		var u16 := value & 0xFFFF
		pcm_data[i * 2] = u16 & 0xFF
		pcm_data[i * 2 + 1] = (u16 >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = TONE_SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = pcm_data
	return wav

func _adsr_envelope(normalized_t: float) -> float:
	if normalized_t < 0.06:
		return normalized_t / 0.06
	if normalized_t < 0.18:
		return lerpf(1.0, 0.75, (normalized_t - 0.06) / 0.12)
	if normalized_t < 0.78:
		return 0.72
	return lerpf(0.72, 0.0, (normalized_t - 0.78) / 0.22)
