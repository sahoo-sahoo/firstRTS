## 资源系统 - 管理各玩家的资源
class_name ResourceSystem
extends Node

signal resources_changed(team_id: int, minerals: int, energy: int)
signal insufficient_resources(team_id: int, type: String)

## 每个玩家的资源 {team_id: {mineral: int, energy: int}}
var _resources: Dictionary = {}

## 初始化玩家资源
func init_player(team_id: int, starting_minerals: int = GameConstants.STARTING_MINERALS, starting_energy: int = GameConstants.STARTING_ENERGY) -> void:
	_resources[team_id] = {
		"mineral": starting_minerals,
		"energy": starting_energy,
	}

## 获取资源
func get_minerals(team_id: int) -> int:
	if _resources.has(team_id):
		return _resources[team_id]["mineral"]
	return 0

func get_energy(team_id: int) -> int:
	if _resources.has(team_id):
		return _resources[team_id]["energy"]
	return 0

## 增加资源
func add_minerals(team_id: int, amount: int) -> void:
	if _resources.has(team_id):
		_resources[team_id]["mineral"] += amount
		_emit_changed(team_id)

func add_energy(team_id: int, amount: int) -> void:
	if _resources.has(team_id):
		_resources[team_id]["energy"] += amount
		_emit_changed(team_id)

## 消耗资源 (返回是否成功)
func spend(team_id: int, mineral_cost: int, energy_cost: int) -> bool:
	if not _resources.has(team_id):
		return false
	
	var res: Dictionary = _resources[team_id]
	if res["mineral"] < mineral_cost:
		insufficient_resources.emit(team_id, "mineral")
		return false
	if res["energy"] < energy_cost:
		insufficient_resources.emit(team_id, "energy")
		return false
	
	res["mineral"] -= mineral_cost
	res["energy"] -= energy_cost
	_emit_changed(team_id)
	return true

## 检查是否够
func can_afford(team_id: int, mineral_cost: int, energy_cost: int) -> bool:
	if not _resources.has(team_id):
		return false
	return _resources[team_id]["mineral"] >= mineral_cost and _resources[team_id]["energy"] >= energy_cost

func _emit_changed(team_id: int) -> void:
	resources_changed.emit(
		team_id,
		_resources[team_id]["mineral"],
		_resources[team_id]["energy"]
	)
