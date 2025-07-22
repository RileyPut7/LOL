# NightManager.gd - Handles complex night phase mechanics
extends Node

signal night_phase_started()
signal killer_selection_phase(time_remaining: float)
signal kill_action_phase(killer_id: int, target_house: int)
signal townfolk_moon_phase()
signal night_phase_ended()

const KILLER_HOUSE_SELECTION_TIME = 15.0
const KILL_ACTION_TIME = 15.0
const TOWNFOLK_MOON_TIME = 15.0

var current_night_phase: String = "none"
var active_killers: Array = []
var killer_house_selections: Dictionary = {}

func _ready():
	# Connect to GameManager signals
	if GameManager:
		GameManager.game_phase_changed.connect(_on_phase_changed)

func _on_phase_changed(phase: GameManager.GamePhase):
	if phase == GameManager.GamePhase.NIGHT_ACTION:
		start_night_sequence()

func start_night_sequence():
	print("Starting enhanced night sequence")
	night_phase_started.emit()
	
	# Get all killers (mafia, serial killer, etc.)
	if PlayerManager:
		active_killers = PlayerManager.get_players_by_role(GameManager.PlayerRole.MAFIA)
		active_killers.append_array(PlayerManager.get_players_by_role(GameManager.PlayerRole.GODFATHER))
		active_killers.append_array(PlayerManager.get_players_by_role(GameManager.PlayerRole.SERIAL_KILLER))
	
	# Phase 1: Killers select houses (10-15 seconds)
	current_night_phase = "house_selection"
	start_house_selection_phase()

func start_house_selection_phase():
	print("Night Phase 1: Killers selecting houses")
	killer_selection_phase.emit(KILLER_HOUSE_SELECTION_TIME)
	
	# Show house selection UI for killers
	for killer_id in active_killers:
		show_house_selection_ui.rpc_id(killer_id, KILLER_HOUSE_SELECTION_TIME)
	
	# Start townfolk moon watching
	start_townfolk_moon_phase()
	
	# Wait for selection time
	await get_tree().create_timer(KILLER_HOUSE_SELECTION_TIME).timeout
	start_kill_action_phase()

func start_townfolk_moon_phase():
	print("Townfolk can look at moon and walk around houses")
	townfolk_moon_phase.emit()
	
	# Allow townfolk to move around their houses for first 10-15 seconds
	var alive_players = PlayerManager.get_alive_players() if PlayerManager else []
	for player_id in alive_players:
		if player_id not in active_killers:
			enable_house_movement.rpc_id(player_id, true)
			start_sheep_minigame.rpc_id(player_id)

func start_kill_action_phase():
	print("Night Phase 2: Kill actions")
	current_night_phase = "kill_actions"
	
	# Process each killer's house selection
	for killer_id in killer_house_selections:
		var target_house_id = killer_house_selections[killer_id]
		kill_action_phase.emit(killer_id, target_house_id)
		execute_house_entry(killer_id, target_house_id)
	
	# Disable townfolk movement, start sheep minigame
	var alive_players = PlayerManager.get_alive_players() if PlayerManager else []
	for player_id in alive_players:
		if player_id not in active_killers:
			enable_house_movement.rpc_id(player_id, false)
			force_sheep_minigame.rpc_id(player_id)
	
	# Wait for kill actions to complete
	await get_tree().create_timer(KILL_ACTION_TIME).timeout
	end_night_sequence()

func execute_house_entry(killer_id: int, house_id: int):
	# Find the house and execute entry
	var house = get_house_by_id(house_id)
	if house:
		house.enter_house_as_killer(killer_id)

func get_house_by_id(house_id: int) -> Node:
	# Find house in scene
	var houses = get_tree().get_nodes_in_group("houses")
	for house in houses:
		if house.house_id == house_id:
			return house
	return null

func end_night_sequence():
	print("Night sequence complete")
	current_night_phase = "complete"
	night_phase_ended.emit()
	
	# Clear selections for next night
	killer_house_selections.clear()

@rpc("authority", "call_local")
func show_house_selection_ui(time_limit: float):
	# Client-side: Show UI for killers to select houses
	var ui = get_tree().get_first_node_in_group("game_ui")
	if ui and ui.has_method("show_house_selection"):
		ui.show_house_selection(time_limit)

@rpc("authority", "call_local") 
func enable_house_movement(enabled: bool):
	# Client-side: Enable/disable movement within house
	var player = get_tree().get_first_node_in_group("local_player")
	if player and player.has_method("set_house_movement"):
		player.set_house_movement(enabled)

@rpc("authority", "call_local")
func start_sheep_minigame():
	# Client-side: Start sheep jumping minigame option
	var ui = get_tree().get_first_node_in_group("game_ui")
	if ui and ui.has_method("show_sheep_minigame"):
		ui.show_sheep_minigame()

@rpc("authority", "call_local")
func force_sheep_minigame():
	# Client-side: Force sheep minigame during second phase
	var ui = get_tree().get_first_node_in_group("game_ui")
	if ui and ui.has_method("force_sheep_minigame"):
		ui.force_sheep_minigame()

@rpc("any_peer", "call_local")
func submit_house_selection(killer_id: int, house_id: int):
	if current_night_phase == "house_selection" and killer_id in active_killers:
		killer_house_selections[killer_id] = house_id
		print("Killer ", killer_id, " selected house ", house_id)

# Enhanced role-specific actions based on design doc
func handle_sheriff_night_action(sheriff_id: int, target_house: int):
	# Sheriff can shoot killers who enter their house
	var sheriff_house = PlayerManager.get_player_house(sheriff_id)
	if sheriff_house and sheriff_house.get("index") == target_house:
		# Mark any killer who enters as shot/wounded
		var house = get_house_by_id(target_house)
		if house:
			house.house_entered.connect(_on_sheriff_house_entered.bind(sheriff_id))

func _on_sheriff_house_entered(sheriff_id: int, killer_id: int, victim_id: int):
	if victim_id == sheriff_id:
		# Sheriff defends their house
		mark_player_shot.rpc(killer_id)
		print("Sheriff ", sheriff_id, " shot killer ", killer_id)

@rpc("authority", "call_local")
func mark_player_shot(player_id: int):
	# Visual indicator that player was shot by sheriff
	var player = PlayerManager.get_player_by_id(player_id)
	if player and player.has_method("mark_as_shot"):
		player.mark_as_shot()

func handle_investigator_window_peek(investigator_id: int, target_house: int):
	# Investigator can see into windows during kills
	var house = get_house_by_id(target_house)
	if house:
		var window_view = house.get_window_view()
		send_window_view.rpc_id(investigator_id, window_view)

@rpc("authority", "call_local")
func send_window_view(visible_info: Array):
	# Client-side: Show what investigator saw through window
	var ui = get_tree().get_first_node_in_group("game_ui")
	if ui and ui.has_method("show_window_investigation"):
		ui.show_window_investigation(visible_info)
