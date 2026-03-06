## 游戏常量定义
class_name GameConstants

# ============ 地图 ============
const TILE_SIZE := 64
const MAP_WIDTH := 160   # 瓦片数（8 玩家地图）
const MAP_HEIGHT := 120

# ============ 战争迷雾模式 ============
enum FogMode {
	NONE,             ## 无迷雾，全图可见
	FULL_BLACK,       ## 未探索全黑，视野外变暗
	TERRAIN_ONLY,     ## 未探索只显示地形，隐藏单位
	EXPLORED_VISIBLE, ## 未探索全黑，探索后始终可见（无战争迷雾）
}

# ============ 阵营 ============
enum Faction { STEEL_ALLIANCE, SHADOW_TECH }

# 阵营颜色
const FACTION_COLORS := {
	Faction.STEEL_ALLIANCE: Color(0.2, 0.5, 0.9),   # 蓝
	Faction.SHADOW_TECH: Color(0.9, 0.2, 0.3),       # 红
}

const TEAM_COLORS := {
	0: Color(0.2, 0.5, 0.9),
	1: Color(0.9, 0.2, 0.3),
	2: Color(0.2, 0.8, 0.3),
	3: Color(0.9, 0.7, 0.1),
	4: Color(0.1, 0.85, 0.9),
	5: Color(0.7, 0.2, 0.9),
	6: Color(0.95, 0.5, 0.1),
	7: Color(0.9, 0.9, 0.9),
}

# ============ 资源 ============
enum ResourceType { MINERAL, ENERGY }

const STARTING_MINERALS := 400
const STARTING_ENERGY := 200
const WORKER_CARRY_AMOUNT := 8
const WORKER_GATHER_TIME := 2.0  # 秒

# ============ 单位类型 ============
enum UnitType { WORKER, INFANTRY, TANK, HELICOPTER, SUPER_UNIT }

# ============ 建筑类型 ============
enum BuildingType { COMMAND_CENTER, BARRACKS, FACTORY, AIRPORT, DEFENSE_TOWER, POWER_PLANT, TECH_CENTER }

# ============ 单位状态 ============
enum UnitState { IDLE, MOVING, ATTACKING, GATHERING, RETURNING, BUILDING, DEAD }

# ============ 单位数据 ============
# {type: {hp, attack, attack_range, speed, cost_mineral, cost_energy, build_time, radius}}
const UNIT_DATA := {
	# ---- 钢铁联盟 ----
	"sa_worker": {
		"name": "工程兵",
		"faction": Faction.STEEL_ALLIANCE,
		"type": UnitType.WORKER,
		"hp": 40, "attack": 5, "attack_range": 30.0, "speed": 120.0,
		"cost_mineral": 50, "cost_energy": 0, "build_time": 12.0,
		"radius": 10.0, "vision_range": 200.0,
		"can_gather": true, "can_build": true,
	},
	"sa_infantry": {
		"name": "突击步兵",
		"faction": Faction.STEEL_ALLIANCE,
		"type": UnitType.INFANTRY,
		"hp": 80, "attack": 10, "attack_range": 150.0, "speed": 100.0,
		"cost_mineral": 100, "cost_energy": 0, "build_time": 15.0,
		"radius": 10.0, "vision_range": 250.0,
		"can_gather": false, "can_build": false,
	},
	"sa_tank": {
		"name": "重型坦克",
		"faction": Faction.STEEL_ALLIANCE,
		"type": UnitType.TANK,
		"hp": 300, "attack": 30, "attack_range": 250.0, "speed": 60.0,
		"cost_mineral": 300, "cost_energy": 80, "build_time": 30.0,
		"radius": 18.0, "vision_range": 300.0,
		"can_gather": false, "can_build": false,
	},
	"sa_helicopter": {
		"name": "武装直升机",
		"faction": Faction.STEEL_ALLIANCE,
		"type": UnitType.HELICOPTER,
		"hp": 120, "attack": 18, "attack_range": 200.0, "speed": 160.0,
		"cost_mineral": 250, "cost_energy": 100, "build_time": 25.0,
		"radius": 14.0, "vision_range": 350.0, "is_air": true,
		"can_gather": false, "can_build": false,
	},
	# ---- 暗影科技 ----
	"st_worker": {
		"name": "探针",
		"faction": Faction.SHADOW_TECH,
		"type": UnitType.WORKER,
		"hp": 30, "shield": 20, "attack": 5, "attack_range": 30.0, "speed": 120.0,
		"cost_mineral": 50, "cost_energy": 0, "build_time": 12.0,
		"radius": 10.0, "vision_range": 200.0,
		"can_gather": true, "can_build": true,
	},
	"st_zealot": {
		"name": "光刃战士",
		"faction": Faction.SHADOW_TECH,
		"type": UnitType.INFANTRY,
		"hp": 50, "shield": 40, "attack": 12, "attack_range": 40.0, "speed": 130.0,
		"cost_mineral": 120, "cost_energy": 0, "build_time": 18.0,
		"radius": 11.0, "vision_range": 250.0,
		"can_gather": false, "can_build": false,
	},
	"st_phase_tank": {
		"name": "相位战车",
		"faction": Faction.SHADOW_TECH,
		"type": UnitType.TANK,
		"hp": 150, "shield": 100, "attack": 22, "attack_range": 230.0, "speed": 80.0,
		"cost_mineral": 280, "cost_energy": 100, "build_time": 28.0,
		"radius": 16.0, "vision_range": 280.0,
		"can_gather": false, "can_build": false,
	},
	"st_ghost_fighter": {
		"name": "幽灵战机",
		"faction": Faction.SHADOW_TECH,
		"type": UnitType.HELICOPTER,
		"hp": 80, "shield": 60, "attack": 20, "attack_range": 220.0, "speed": 170.0,
		"cost_mineral": 250, "cost_energy": 120, "build_time": 24.0,
		"radius": 14.0, "vision_range": 350.0, "is_air": true,
		"can_gather": false, "can_build": false,
	},
}

# ============ 建筑数据 ============
const BUILDING_DATA := {
	"command_center": {
		"name": "指挥中心",
		"type": BuildingType.COMMAND_CENTER,
		"hp": 1500, "size": Vector2i(4, 4),
		"cost_mineral": 400, "cost_energy": 0, "build_time": 60.0,
		"produces": ["worker"], "is_resource_depot": true,
		"vision_range": 300.0,
	},
	"barracks": {
		"name": "兵营",
		"type": BuildingType.BARRACKS,
		"hp": 800, "size": Vector2i(3, 3),
		"cost_mineral": 150, "cost_energy": 0, "build_time": 30.0,
		"produces": ["infantry"], "requires": ["command_center"],
		"vision_range": 250.0,
	},
	"factory": {
		"name": "车工厂",
		"type": BuildingType.FACTORY,
		"hp": 1000, "size": Vector2i(4, 3),
		"cost_mineral": 250, "cost_energy": 50, "build_time": 40.0,
		"produces": ["tank"], "requires": ["barracks"],
		"vision_range": 250.0,
	},
	"airport": {
		"name": "机场",
		"type": BuildingType.AIRPORT,
		"hp": 800, "size": Vector2i(4, 3),
		"cost_mineral": 300, "cost_energy": 100, "build_time": 45.0,
		"produces": ["helicopter"], "requires": ["factory"],
		"vision_range": 250.0,
	},
	"defense_tower": {
		"name": "防御塔",
		"type": BuildingType.DEFENSE_TOWER,
		"hp": 500, "size": Vector2i(2, 2),
		"cost_mineral": 100, "cost_energy": 25, "build_time": 20.0,
		"attack": 15, "attack_range": 250.0,
		"requires": ["barracks"],
		"vision_range": 300.0,
	},
	"power_plant": {
		"name": "发电厂",
		"type": BuildingType.POWER_PLANT,
		"hp": 600, "size": Vector2i(3, 2),
		"cost_mineral": 100, "cost_energy": 0, "build_time": 25.0,
		"energy_output": 50,
		"requires": ["command_center"],
		"vision_range": 200.0,
	},
	"tech_center": {
		"name": "科技中心",
		"type": BuildingType.TECH_CENTER,
		"hp": 700, "size": Vector2i(3, 3),
		"cost_mineral": 300, "cost_energy": 150, "build_time": 50.0,
		"requires": ["factory"],
		"vision_range": 200.0,
	},
}
