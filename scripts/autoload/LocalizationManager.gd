## 多语言管理器 - 支持简体中文 / 繁体中文 / 英文
extends Node

signal language_changed(lang_code: String)

enum Lang { ZH_CN, ZH_TW, EN }

const LANG_CODES: Array[String] = ["zh_CN", "zh_TW", "en"]
const LANG_NAMES: Dictionary = {
	"zh_CN": "简体中文",
	"zh_TW": "繁體中文",
	"en": "English",
}

const SETTINGS_FILE := "game_settings.cfg"

var current_lang: String = "zh_CN"

## 翻译表: { key: { "zh_CN": ..., "zh_TW": ..., "en": ... } }
var _translations: Dictionary = {}

func _ready() -> void:
	_build_translations()
	_load_language()

## 获取翻译文本
func t(key: String, args: Array = []) -> String:
	var table: Dictionary = _translations.get(key, {})
	var text: String = table.get(current_lang, "")
	if text == "":
		text = table.get("zh_CN", key)  # fallback to zh_CN, then key
	if args.size() > 0:
		text = text % args
	return text

## 切换语言
func set_language(lang_code: String) -> void:
	if lang_code == current_lang:
		return
	if lang_code not in LANG_CODES:
		return
	current_lang = lang_code
	_save_language()
	language_changed.emit(current_lang)

## 获取语言显示名列表
func get_language_names() -> Array[String]:
	var result: Array[String] = []
	for code in LANG_CODES:
		result.append(LANG_NAMES[code])
	return result

func get_current_lang_index() -> int:
	return LANG_CODES.find(current_lang)

func set_language_by_index(index: int) -> void:
	if index >= 0 and index < LANG_CODES.size():
		set_language(LANG_CODES[index])

func get_unit_name(unit_key: String, fallback_name: String = "") -> String:
	var key := "unit.name.%s" % unit_key
	var text := t(key)
	if text == key:
		return fallback_name if fallback_name != "" else unit_key
	return text

func get_building_name(building_key: String, fallback_name: String = "") -> String:
	var key := "building.name.%s" % building_key
	var text := t(key)
	if text == key:
		return fallback_name if fallback_name != "" else building_key
	return text

func _save_language() -> void:
	var cfg := ConfigFile.new()
	var path := OS.get_user_data_dir().path_join(SETTINGS_FILE)
	cfg.load(path)
	cfg.set_value("general", "language", current_lang)
	cfg.save(path)

func _load_language() -> void:
	var cfg := ConfigFile.new()
	var path := OS.get_user_data_dir().path_join(SETTINGS_FILE)
	if cfg.load(path) == OK:
		current_lang = cfg.get_value("general", "language", "zh_CN")

## ====== 翻译数据 ======
func _build_translations() -> void:
	var T := _translations

	# ============ 主菜单 ============
	_tr(T, "menu.subtitle",
		"星际争霸 × 红色警戒 风格即时战略",
		"星際爭霸 × 紅色警戒 風格即時戰略",
		"StarCraft × Red Alert Style RTS")
	_tr(T, "menu.single_player",
		"单人对战 (vs AI)",
		"單人對戰 (vs AI)",
		"Single Player (vs AI)")
	_tr(T, "menu.multiplayer",
		"联机对战",
		"連線對戰",
		"Multiplayer")
	_tr(T, "menu.replay",
		"录像回放",
		"錄像回放",
		"Replay")
	_tr(T, "menu.settings",
		"设置",
		"設定",
		"Settings")
	_tr(T, "menu.quit",
		"退出",
		"退出",
		"Quit")

	# ============ 游戏设置面板 ============
	_tr(T, "settings.title",
		"游戏设置",
		"遊戲設定",
		"Game Settings")
	_tr(T, "settings.fog_of_war",
		"战争迷雾",
		"戰爭迷霧",
		"Fog of War")
	_tr(T, "settings.fog_none",
		"无迷雾（全图可见）",
		"無迷霧（全圖可見）",
		"None (Full Map Visible)")
	_tr(T, "settings.fog_full_black",
		"战争迷雾（未探索全黑）",
		"戰爭迷霧（未探索全黑）",
		"Fog of War (Unexplored Black)")
	_tr(T, "settings.fog_terrain_only",
		"战争迷雾（未探索显示地形）",
		"戰爭迷霧（未探索顯示地形）",
		"Fog of War (Show Terrain)")
	_tr(T, "settings.fog_explored_visible",
		"黑雾探索（探索后始终可见）",
		"黑霧探索（探索後始終可見）",
		"Black Fog (Always Visible After Explored)")
	_tr(T, "settings.game_speed",
		"游戏速度",
		"遊戲速度",
		"Game Speed")
	_tr(T, "settings.speed_unlimited",
		"∞（不限速）",
		"∞（不限速）",
		"∞ (Unlimited)")
	_tr(T, "settings.starting_resources",
		"初始资源",
		"初始資源",
		"Starting Resources")
	_tr(T, "settings.starting_minerals",
		"初始矿石",
		"初始礦石",
		"Starting Minerals")
	_tr(T, "settings.starting_energy",
		"初始能源",
		"初始能源",
		"Starting Energy")
	_tr(T, "settings.cancel",
		"取消",
		"取消",
		"Cancel")
	_tr(T, "settings.start_game",
		"开始游戏",
		"開始遊戲",
		"Start Game")
	_tr(T, "settings.language",
		"语言",
		"語言",
		"Language")

	# ============ 录像面板 ============
	_tr(T, "replay.title",
		"📼 录像回放",
		"📼 錄像回放",
		"📼 Replay")
	_tr(T, "replay.no_files",
		"暂无录像文件",
		"暫無錄像檔案",
		"No replay files")
	_tr(T, "replay.play",
		"▶ 播放",
		"▶ 播放",
		"▶ Play")
	_tr(T, "replay.delete_all",
		"🗑 删除全部录像",
		"🗑 刪除全部錄像",
		"🗑 Delete All")

	# ============ HUD - 资源栏 ============
	_tr(T, "hud.resource_format",
		"矿石: %d  |  能源: %d  |  人口: %d",
		"礦石: %d  |  能源: %d  |  人口: %d",
		"Minerals: %d  |  Energy: %d  |  Pop: %d")
	_tr(T, "hud.timer",
		"计时: %s",
		"計時: %s",
		"Time: %s")
	_tr(T, "hud.no_selection",
		"未选中任何单位",
		"未選中任何單位",
		"No unit selected")
	_tr(T, "hud.production_queue",
		"生产队列",
		"生產佇列",
		"Production Queue")
	_tr(T, "hud.replay_spectate",
		"回放观战模式",
		"回放觀戰模式",
		"Replay Spectate Mode")
	_tr(T, "hud.selected_units",
		"已选中 %d 个单位",
		"已選中 %d 個單位",
		"%d units selected")
	_tr(T, "hud.hp_format",
		"%s  HP: %d/%d  攻击: %d",
		"%s  HP: %d/%d  攻擊: %d",
		"%s  HP: %d/%d  ATK: %d")
	_tr(T, "hud.shield_format",
		"  护盾: %d/%d",
		"  護盾: %d/%d",
		"  Shield: %d/%d")
	_tr(T, "hud.carry_format",
		"  携带%s: %d/%d",
		"  攜帶%s: %d/%d",
		"  Carry %s: %d/%d")

	# 单位状态
	_tr(T, "unit.state.idle", "待命", "待命", "Idle")
	_tr(T, "unit.state.moving", "移动中", "移動中", "Moving")
	_tr(T, "unit.state.gathering", "采集中", "採集中", "Gathering")
	_tr(T, "unit.state.returning", "运送中", "運送中", "Returning")
	_tr(T, "unit.state.building", "建造中", "建造中", "Building")

	# 资源简称
	_tr(T, "resource.mineral_short", "矿", "礦", "Ore")
	_tr(T, "resource.energy_short", "能", "能", "Eng")

	# 建筑状态
	_tr(T, "building.constructing",
		"\n状态: 施工中 %d%%",
		"\n狀態: 施工中 %d%%",
		"\nStatus: Building %d%%")
	_tr(T, "building.completed",
		"\n状态: 已完工",
		"\n狀態: 已完工",
		"\nStatus: Completed")
	_tr(T, "building.queue_empty",
		"\n生产队列: 空",
		"\n生產佇列: 空",
		"\nQueue: Empty")
	_tr(T, "building.queue_prefix",
		"\n生产队列: ",
		"\n生產佇列: ",
		"\nQueue: ")
	_tr(T, "building.queue_waiting",
		"排队中",
		"排隊中",
		"Queued")
	_tr(T, "building.cost_format",
		"矿%d 能%d",
		"礦%d 能%d",
		"M%d E%d")

	# 消息
	_tr(T, "msg.insufficient_resources", "资源不足！", "資源不足！", "Insufficient resources!")
	_tr(T, "msg.insufficient_minerals", "矿石不足！", "礦石不足！", "Not enough minerals!")
	_tr(T, "msg.insufficient_energy", "能源不足！", "能源不足！", "Not enough energy!")
	_tr(T, "msg.build_not_init", "建造系统未初始化", "建造系統未初始化", "Build system not initialized")

	# ============ 单位名称 ============
	_tr(T, "unit.name.sa_worker", "工程兵", "工程兵", "Engineer")
	_tr(T, "unit.name.sa_infantry", "突击步兵", "突擊步兵", "Assault Infantry")
	_tr(T, "unit.name.sa_tank", "重型坦克", "重型坦克", "Heavy Tank")
	_tr(T, "unit.name.sa_helicopter", "武装直升机", "武裝直升機", "Attack Helicopter")
	_tr(T, "unit.name.st_worker", "探针", "探針", "Probe")
	_tr(T, "unit.name.st_zealot", "光刃战士", "光刃戰士", "Blade Warrior")
	_tr(T, "unit.name.st_phase_tank", "相位战车", "相位戰車", "Phase Tank")
	_tr(T, "unit.name.st_ghost_fighter", "幽灵战机", "幽靈戰機", "Ghost Fighter")

	# ============ 建筑名称 ============
	_tr(T, "building.name.command_center", "指挥中心", "指揮中心", "Command Center")
	_tr(T, "building.name.barracks", "兵营", "兵營", "Barracks")
	_tr(T, "building.name.factory", "车工厂", "車工廠", "Factory")
	_tr(T, "building.name.airport", "机场", "機場", "Airport")
	_tr(T, "building.name.defense_tower", "防御塔", "防禦塔", "Defense Tower")
	_tr(T, "building.name.power_plant", "发电厂", "發電廠", "Power Plant")
	_tr(T, "building.name.tech_center", "科技中心", "科技中心", "Tech Center")

	# ============ HUD - 聊天 ============
	_tr(T, "chat.channel_all", "[全体]", "[全體]", "[All]")
	_tr(T, "chat.channel_team", "[队友]", "[隊友]", "[Team]")
	_tr(T, "chat.channel_whisper", "[私聊]", "[私聊]", "[Whisper]")
	_tr(T, "chat.input_placeholder",
		"输入消息... (Tab切换频道)",
		"輸入訊息... (Tab切換頻道)",
		"Type message... (Tab to switch channel)")

	# ============ HUD - 投降对话框 ============
	_tr(T, "surrender.title", "确认投降", "確認投降", "Confirm Surrender")
	_tr(T, "surrender.desc",
		"你确定要投降吗？\n此操作不可撤销，你将输掉本局游戏。",
		"你確定要投降嗎？\n此操作不可撤銷，你將輸掉本局遊戲。",
		"Are you sure you want to surrender?\nThis cannot be undone. You will lose the game.")
	_tr(T, "surrender.confirm", "确认投降", "確認投降", "Confirm")
	_tr(T, "surrender.continue", "继续战斗", "繼續戰鬥", "Keep Fighting")
	_tr(T, "surrender.already", "你已投降，无法再次投降", "你已投降，無法再次投降", "You have already surrendered")
	_tr(T, "surrender.done", "🏳 已投降", "🏳 已投降", "🏳 Surrendered")

	# ============ HUD - ESC 菜单 ============
	_tr(T, "esc.title", "☰ 游戏菜单", "☰ 遊戲選單", "☰ Game Menu")
	_tr(T, "esc.resume", "▶ 继续游戏", "▶ 繼續遊戲", "▶ Resume")
	_tr(T, "esc.pause", "⏸ 暂停游戏", "⏸ 暫停遊戲", "⏸ Pause")
	_tr(T, "esc.resume_game", "▶ 恢复游戏", "▶ 恢復遊戲", "▶ Resume Game")
	_tr(T, "esc.history", "📜 历史消息", "📜 歷史訊息", "📜 Chat History")
	_tr(T, "esc.surrender", "🏳 投降", "🏳 投降", "🏳 Surrender")
	_tr(T, "esc.return_menu", "🚪 回到主菜单", "🚪 回到主選單", "🚪 Return to Menu")
	_tr(T, "esc.speed_format", "速度: %s", "速度: %s", "Speed: %s")
	_tr(T, "esc.speed_replay", "速度: 回放模式", "速度: 回放模式", "Speed: Replay Mode")
	_tr(T, "esc.speed_online_fixed", "速度: 联机固定", "速度: 連線固定", "Speed: Online Fixed")
	_tr(T, "esc.single_unlimited", "单人模式 - 无限暂停", "單人模式 - 無限暫停", "Single Player - Unlimited Pause")
	_tr(T, "esc.pause_remaining", "剩余暂停次数: %d / %d", "剩餘暫停次數: %d / %d", "Pause remaining: %d / %d")
	_tr(T, "esc.pause_exhausted",
		"暂停机会已用完 (最多%d次)",
		"暫停機會已用完 (最多%d次)",
		"No pauses left (max %d)")
	_tr(T, "esc.pause_exhausted_short", "暂停机会已用完", "暫停機會已用完", "No pauses left")

	# ============ HUD - 暂停覆盖 ============
	_tr(T, "pause.title", "⏸ 游戏暂停", "⏸ 遊戲暫停", "⏸ Game Paused")
	_tr(T, "pause.you_paused", "你暂停了游戏", "你暫停了遊戲", "You paused the game")
	_tr(T, "pause.player_paused",
		"玩家 %s 暂停了游戏\n点击继续可恢复游戏",
		"玩家 %s 暫停了遊戲\n點擊繼續可恢復遊戲",
		"Player %s paused the game\nClick Resume to continue")
	_tr(T, "pause.resume_btn", "▶ 继续游戏", "▶ 繼續遊戲", "▶ Resume")
	_tr(T, "pause.remaining",
		"你的剩余暂停次数: %d / %d",
		"你的剩餘暫停次數: %d / %d",
		"Your pause remaining: %d / %d")

	# ============ HUD - 游戏结束 ============
	_tr(T, "game.victory", "🏆 胜利！", "🏆 勝利！", "🏆 Victory!")
	_tr(T, "game.defeat", "💀 战败...", "💀 戰敗...", "💀 Defeat...")
	_tr(T, "game.return_menu", "回到主菜单", "回到主選單", "Return to Menu")
	_tr(T, "game.speed_format", "游戏速度: %s", "遊戲速度: %s", "Game Speed: %s")

	# ============ HUD - 回放控制 ============
	_tr(T, "replay.controls", "回放控制", "回放控制", "Replay Controls")
	_tr(T, "replay.collapse", "▼ 折叠", "▼ 摺疊", "▼ Collapse")
	_tr(T, "replay.expand", "▲ 展开", "▲ 展開", "▲ Expand")
	_tr(T, "replay.exit", "退出回放", "退出回放", "Exit Replay")
	_tr(T, "replay.restart_tip", "从头开始", "從頭開始", "Restart")
	_tr(T, "replay.finished", "回放结束", "回放結束", "Replay Finished")
	_tr(T, "replay.player_stats", "玩家统计", "玩家統計", "Player Stats")
	_tr(T, "replay.free_camera", "自由镜头", "自由鏡頭", "Free Camera")
	_tr(T, "replay.follow_format", "跟随: %s", "跟隨: %s", "Follow: %s")
	_tr(T, "replay.follow_tooltip", "跟随此玩家镜头", "跟隨此玩家鏡頭", "Follow player camera")
	_tr(T, "replay.action_log", "操作日志", "操作日誌", "Action Log")
	_tr(T, "replay.stats_format",
		"矿石: %d  能源: %d\n单位: %d  建筑: %d  生产队列: %d",
		"礦石: %d  能源: %d\n單位: %d  建築: %d  生產佇列: %d",
		"Minerals: %d  Energy: %d\nUnits: %d  Buildings: %d  Queue: %d")
	_tr(T, "replay.team_format",
		"■ 队伍%d: %s",
		"■ 隊伍%d: %s",
		"■ Team %d: %s")
	_tr(T, "replay.saved",
		"[系统] 录像已保存: %s",
		"[系統] 錄像已儲存: %s",
		"[System] Replay saved: %s")

	# ============ HUD - 系统消息 ============
	_tr(T, "sys.you_surrendered",
		"[系统] 你已投降，所有单位和建筑将自爆。",
		"[系統] 你已投降，所有單位和建築將自爆。",
		"[System] You surrendered. All units and buildings will self-destruct.")
	_tr(T, "sys.player_quit",
		"[系统] 玩家 %s 已退出，其所有单位和建筑将自爆。",
		"[系統] 玩家 %s 已退出，其所有單位和建築將自爆。",
		"[System] Player %s has quit. Their units and buildings will self-destruct.")
	_tr(T, "sys.game_paused", "[系统] 游戏已暂停", "[系統] 遊戲已暫停", "[System] Game paused")
	_tr(T, "sys.game_resumed", "[系统] 游戏已恢复", "[系統] 遊戲已恢復", "[System] Game resumed")
	_tr(T, "sys.opponent_disconnected",
		"[系统] 对方已断开连接，你获胜！",
		"[系統] 對方已斷開連線，你獲勝！",
		"[System] Opponent disconnected. You win!")

	# ============ 大厅 ============
	_tr(T, "lobby.title", "联 机 大 厅", "連 線 大 廳", "M U L T I P L A Y E R   L O B B Y")
	_tr(T, "lobby.not_connected", "未连接", "未連線", "Not Connected")
	_tr(T, "lobby.connection_settings", "连接设置", "連線設定", "Connection Settings")
	_tr(T, "lobby.nickname", "昵称:", "暱稱:", "Name:")
	_tr(T, "lobby.ip_address", "IP地址:", "IP地址:", "IP Address:")
	_tr(T, "lobby.port", "端口:", "連接埠:", "Port:")
	_tr(T, "lobby.create_room", "创建房间", "建立房間", "Create Room")
	_tr(T, "lobby.join_room", "加入房间", "加入房間", "Join Room")
	_tr(T, "lobby.faction_select", "阵营选择", "陣營選擇", "Faction Select")
	_tr(T, "lobby.steel_alliance_blue", "钢铁联盟 (蓝方)", "鋼鐵聯盟 (藍方)", "Steel Alliance (Blue)")
	_tr(T, "lobby.shadow_tech_red", "暗影科技 (红方)", "暗影科技 (紅方)", "Shadow Tech (Red)")
	_tr(T, "lobby.settings", "游戏设置", "遊戲設定", "Game Settings")
	_tr(T, "lobby.fog_label", "战争迷雾:", "戰爭迷霧:", "Fog of War:")
	_tr(T, "lobby.fog_none", "无迷雾", "無迷霧", "None")
	_tr(T, "lobby.fog_full_black", "未探索全黑", "未探索全黑", "Unexplored Black")
	_tr(T, "lobby.fog_terrain", "未探索显示地形", "未探索顯示地形", "Show Terrain")
	_tr(T, "lobby.fog_explored", "探索后始终可见", "探索後始終可見", "Always Visible After Explored")
	_tr(T, "lobby.speed_label", "游戏速度:", "遊戲速度:", "Game Speed:")
	_tr(T, "lobby.speed_unlimited", "∞ 不限速", "∞ 不限速", "∞ Unlimited")
	_tr(T, "lobby.mineral_label", "初始矿石:", "初始礦石:", "Starting Minerals:")
	_tr(T, "lobby.energy_label", "初始能源:", "初始能源:", "Starting Energy:")
	_tr(T, "lobby.player_list", "玩家列表", "玩家列表", "Players")
	_tr(T, "lobby.chat", "聊天", "聊天", "Chat")
	_tr(T, "lobby.chat_placeholder", "输入消息...", "輸入訊息...", "Type message...")
	_tr(T, "lobby.send", "发送", "傳送", "Send")
	_tr(T, "lobby.back", "返回主菜单", "返回主選單", "Back to Menu")
	_tr(T, "lobby.ready", "准备", "準備", "Ready")
	_tr(T, "lobby.cancel_ready", "取消准备", "取消準備", "Cancel Ready")
	_tr(T, "lobby.start", "开始游戏", "開始遊戲", "Start Game")
	_tr(T, "lobby.no_players", "暂无玩家", "暫無玩家", "No players")
	_tr(T, "lobby.default_name", "玩家1", "玩家1", "Player1")
	_tr(T, "lobby.team_format", "队伍 %d", "隊伍 %d", "Team %d")
	_tr(T, "lobby.steel_alliance", "钢铁联盟", "鋼鐵聯盟", "Steel Alliance")
	_tr(T, "lobby.shadow_tech", "暗影科技", "暗影科技", "Shadow Tech")
	_tr(T, "lobby.random_color", "随机颜色", "隨機顏色", "Random Color")
	_tr(T, "lobby.random_spawn", "随机位置", "隨機位置", "Random Spawn")
	_tr(T, "lobby.host_tag", "👑 房主", "👑 房主", "👑 Host")
	_tr(T, "lobby.ready_tag", "✓ 已准备", "✓ 已準備", "✓ Ready")
	_tr(T, "lobby.not_ready_tag", "未准备", "未準備", "Not Ready")
	_tr(T, "lobby.steel_short", "钢铁", "鋼鐵", "Steel")
	_tr(T, "lobby.shadow_short", "暗影", "暗影", "Shadow")
	_tr(T, "lobby.random_short", "随机", "隨機", "Random")

	# 颜色名
	_tr(T, "color.blue", "蓝色", "藍色", "Blue")
	_tr(T, "color.red", "红色", "紅色", "Red")
	_tr(T, "color.green", "绿色", "綠色", "Green")
	_tr(T, "color.yellow", "黄色", "黃色", "Yellow")
	_tr(T, "color.cyan", "青色", "青色", "Cyan")
	_tr(T, "color.purple", "紫色", "紫色", "Purple")
	_tr(T, "color.orange", "橙色", "橙色", "Orange")
	_tr(T, "color.white", "白色", "白色", "White")
	# 颜色简称
	_tr(T, "color.blue_s", "蓝", "藍", "Blue")
	_tr(T, "color.red_s", "红", "紅", "Red")
	_tr(T, "color.green_s", "绿", "綠", "Green")
	_tr(T, "color.yellow_s", "黄", "黃", "Yellow")
	_tr(T, "color.cyan_s", "青", "青", "Cyan")
	_tr(T, "color.purple_s", "紫", "紫", "Purple")
	_tr(T, "color.orange_s", "橙", "橙", "Orange")
	_tr(T, "color.white_s", "白", "白", "White")

	# 出生点名称
	_tr(T, "spawn.0", "1-左上角", "1-左上角", "1-Top Left")
	_tr(T, "spawn.1", "2-上中", "2-上中", "2-Top Center")
	_tr(T, "spawn.2", "3-右上角", "3-右上角", "3-Top Right")
	_tr(T, "spawn.3", "4-左中", "4-左中", "4-Mid Left")
	_tr(T, "spawn.4", "5-右中", "5-右中", "5-Mid Right")
	_tr(T, "spawn.5", "6-左下角", "6-左下角", "6-Bottom Left")
	_tr(T, "spawn.6", "7-下中", "7-下中", "7-Bottom Center")
	_tr(T, "spawn.7", "8-右下角", "8-右下角", "8-Bottom Right")

	# 大厅系统消息
	_tr(T, "lobby.room_created",
		"你创建了房间，等待其他玩家加入...",
		"你建立了房間，等待其他玩家加入...",
		"Room created, waiting for players...")
	_tr(T, "lobby.create_failed", "创建失败!", "建立失敗!", "Create failed!")
	_tr(T, "lobby.connecting",
		"正在连接 %s:%d...",
		"正在連線 %s:%d...",
		"Connecting to %s:%d...")
	_tr(T, "lobby.connect_failed", "连接失败!", "連線失敗!", "Connection failed!")
	_tr(T, "lobby.connected", "已连接到服务器", "已連線到伺服器", "Connected to server")
	_tr(T, "lobby.connected_msg", "成功连接到服务器!", "成功連線到伺服器!", "Connected to server!")
	_tr(T, "lobby.disconnected", "已断开连接", "已斷開連線", "Disconnected")
	_tr(T, "lobby.disconnected_msg", "与服务器断开连接", "與伺服器斷開連線", "Disconnected from server")
	_tr(T, "lobby.connect_failed_msg",
		"无法连接到服务器，请检查 IP 和端口",
		"無法連線到伺服器，請檢查 IP 和連接埠",
		"Cannot connect to server. Check IP and port.")
	_tr(T, "lobby.player_joined", "%s 加入了房间", "%s 加入了房間", "%s joined the room")
	_tr(T, "lobby.player_left", "%s 离开了房间", "%s 離開了房間", "%s left the room")
	_tr(T, "lobby.all_ready", "所有玩家已准备就绪！", "所有玩家已準備就緒！", "All players are ready!")
	_tr(T, "lobby.game_starting", "游戏即将开始...", "遊戲即將開始...", "Game starting...")
	_tr(T, "lobby.need_2_players",
		"至少需要2名玩家才能开始!",
		"至少需要2名玩家才能開始!",
		"Need at least 2 players to start!")
	_tr(T, "lobby.not_all_ready", "还有玩家未准备!", "還有玩家未準備!", "Some players are not ready!")
	_tr(T, "lobby.duplicate_spawn",
		"存在重复出生位置，请先调整后再开始!",
		"存在重複出生位置，請先調整後再開始!",
		"Duplicate spawn positions! Adjust before starting!")
	_tr(T, "lobby.you_ready", "你已准备就绪", "你已準備就緒", "You are ready")
	_tr(T, "lobby.you_cancel_ready", "你取消了准备", "你取消了準備", "You cancelled ready")
	_tr(T, "lobby.connecting_server", "正在连接服务器...", "正在連線伺服器...", "Connecting to server...")
	_tr(T, "lobby.room_created_ip",
		"房间已创建 | 其他玩家请连接: %s:%d",
		"房間已建立 | 其他玩家請連線: %s:%d",
		"Room created | Others connect to: %s:%d")
	_tr(T, "lobby.fog_updated",
		"[大厅设置] 迷雾模式已更新为: %s",
		"[大廳設定] 迷霧模式已更新為: %s",
		"[Lobby] Fog mode updated to: %s")

	# ============ 设置面板 ============
	_tr(T, "settings_panel.title",
		"设置",
		"設定",
		"Settings")
	_tr(T, "settings_panel.language",
		"语言 / Language",
		"語言 / Language",
		"Language")
	_tr(T, "settings_panel.close",
		"关闭",
		"關閉",
		"Close")

## 辅助方法: 添加一条翻译
func _tr(table: Dictionary, key: String, zh_cn: String, zh_tw: String, en: String) -> void:
	table[key] = { "zh_CN": zh_cn, "zh_TW": zh_tw, "en": en }
