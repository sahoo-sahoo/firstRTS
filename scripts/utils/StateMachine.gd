## 有限状态机 - 控制单位行为
class_name StateMachine
extends Node

signal state_changed(old_state: String, new_state: String)

var current_state: String = ""
var previous_state: String = ""
var states: Dictionary = {}  # {state_name: Callable}
var _owner_node: Node = null

func _ready() -> void:
	_owner_node = get_parent()

func setup(owner: Node, initial_state: String) -> void:
	_owner_node = owner
	current_state = initial_state

func add_state(state_name: String, on_enter: Callable = Callable(), on_update: Callable = Callable(), on_exit: Callable = Callable()) -> void:
	states[state_name] = {
		"enter": on_enter,
		"update": on_update,
		"exit": on_exit,
	}

func change_state(new_state: String) -> void:
	if new_state == current_state:
		return
	if not states.has(new_state):
		push_warning("StateMachine: Unknown state '%s'" % new_state)
		return
	
	# Exit old state
	if states.has(current_state):
		var exit_fn: Callable = states[current_state]["exit"]
		if exit_fn.is_valid():
			exit_fn.call()
	
	previous_state = current_state
	current_state = new_state
	
	# Enter new state
	var enter_fn: Callable = states[new_state]["enter"]
	if enter_fn.is_valid():
		enter_fn.call()
	
	state_changed.emit(previous_state, current_state)

func update(delta: float) -> void:
	if states.has(current_state):
		var update_fn: Callable = states[current_state]["update"]
		if update_fn.is_valid():
			update_fn.call(delta)
