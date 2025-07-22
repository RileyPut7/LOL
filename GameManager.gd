# GameManager.gd - Fixed Version
extends Node

signal game_phase_changed(phase: GamePhase)
signal day_night_changed(is_day: bool)
signal player_eliminated(player_id: int)

enum GamePhase {
	LOBBY,
	DAY_DISCUSSION,
	DAY_VOTING,
	NIGHT_ACTION,
	GAME_OVER
}

enum PlayerRole {
	INNOCENT,
	SHERIFF,
	DOCTOR,
	INVESTIGATOR,
	MAFIA,
	GODFATHER,
	SERIAL_KILLER,
	JESTER
}

@export var day_duration: float = 120.0  # 2 minutes
@export var night_duration: float = 60.0  # 1 minute
@export var voting_duration: float = 30.0

var current_phase: GamePhase = GamePhase.LOBBY
var is_day: bool = true
var day_count: int = 0
var phase_timer: float = 0.0
var game_started: bool = false

var players_alive: Dictionary = {}
var player_votes: Dictionary = {}
var night_actions: Dictionary = {}

# World Environment reference for day/night cycle
var world_environment: WorldEnvironment
var day_sky_color = Color(0.54, 0.81, 0.94)  # Light blue
var night_sky_color = Color(0.05, 0.05, 0.2)  # Dark blue

func _ready():
	print("GameManager ready - NetworkManager exists: ", NetworkManager != null)
	print("GameManager exists: ", GameManager != null)
	print("PlayerManager exists: ", PlayerManager != null)
	set_multiplayer_authority(1)  # Server authority
	
	# Find world environment for day/night cycle
	find_world_environment()
	
	# Auto-start game for testing (remove this later)
	if multiplayer.is_server():
		call_deferred("test_auto_start")

func find_world_environment():
	# Try to find WorldEnvironment in the scene
	var scene_tree = get_tree()
	if scene_tree and scene_tree.current_scene:
		world_environment = find_node_recursive(scene_tree.current_scene, "WorldEnvironment")
		if world_environment:
			print("Found WorldEnvironment for day/night cycle")
		else:
			print("WorldEnvironment not found - day/night visual changes disabled")

func find_node_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var result = find_node_recursive(child, target_name)
		if result:
			return result
	return null

func test_auto_start():
	# Auto-start for testing - remove in production
	await get_tree().create_timer(2.0).timeout
	if NetworkManager and NetworkManager.connected_players.size() >= 1:
		print("Auto-starting game for testing...")
		start_game()

func _process(delta):
	if not multiplayer.is_server() or not game_started:
		return
		
	if phase_timer > 0:
		phase_timer -= delta
		
		# Sync timer to all clients every second
		if int(phase_timer) != int(phase_timer + delta):
			sync_timer.rpc(phase_timer)
	
	if phase_timer <= 0:
		advance_phase()

@rpc("authority", "call_local")
func sync_timer(time_remaining: float):
	phase_timer = time_remaining

func start_game():
	if not multiplayer.is_server():
		return
		
	print("Starting game...")
	game_started = true
	assign_roles()
	set_phase(GamePhase.DAY_DISCUSSION)
	print("Game started with ", NetworkManager.connected_players.size() if NetworkManager else 0, " players")

func assign_roles():
	if not NetworkManager:
		print("ERROR: NetworkManager not found!")
		return
		
	var player_ids = NetworkManager.connected_players.keys()
	var roles_to_assign = []
	
	# Calculate role distribution based on player count
	var player_count = player_ids.size()
	var mafia_count = max(1, player_count / 4)
	
	print("Assigning roles for ", player_count, " players")
	
	# Add mafia roles
	for i in range(mafia_count):
		if i == 0:
			roles_to_assign.append(PlayerRole.GODFATHER)
		else:
			roles_to_assign.append(PlayerRole.MAFIA)
	
	# Add special roles
	if player_count >= 5:
		roles_to_assign.append(PlayerRole.SHERIFF)
	if player_count >= 6:
		roles_to_assign.append(PlayerRole.DOCTOR)
	if player_count >= 7:
		roles_to_assign.append(PlayerRole.INVESTIGATOR)
	if player_count >= 8:
		roles_to_assign.append(PlayerRole.SERIAL_KILLER)
	
	# Fill remaining with innocents
	while roles_to_assign.size() < player_count:
		roles_to_assign.append(PlayerRole.INNOCENT)
	
	# Shuffle and assign
	roles_to_assign.shuffle()
	
	for i in range(player_ids.size()):
		var player_id = player_ids[i]
		var role = roles_to_assign[i]
		if PlayerManager:
			PlayerManager.assign_role(player_id, role)
		players_alive[player_id] = true
		print("Assigned ", PlayerRole.keys()[role], " to player ", player_id)

func set_phase(new_phase: GamePhase):
	print("Setting phase to: ", GamePhase.keys()[new_phase])
	current_phase = new_phase
	
	# Update day/night and timer based on phase
	match new_phase:
		GamePhase.DAY_DISCUSSION:
			is_day = true
			day_count += 1
			phase_timer = day_duration
			update_sky_color(true)
			clear_night_actions()
			print("Day ", day_count, " discussion started")
			
		GamePhase.DAY_VOTING:
			phase_timer = voting_duration
			print("Voting phase started")
			
		GamePhase.NIGHT_ACTION:
			is_day = false
			phase_timer = night_duration
			update_sky_color(false)
			clear_votes()
			print("Night phase started")
			
		GamePhase.GAME_OVER:
			print("Game over")
	
	# Emit signals locally first
	game_phase_changed.emit(new_phase)
	day_night_changed.emit(is_day)
	
	# Then sync to clients
	sync_phase.rpc(new_phase, phase_timer, is_day, day_count)

func update_sky_color(day: bool):
	if not world_environment or not world_environment.environment:
		return
		
	var env = world_environment.environment
	if day:
		env.ambient_light_color = day_sky_color
		env.ambient_light_energy = 1.0
	else:
		env.ambient_light_color = night_sky_color
		env.ambient_light_energy = 0.3

@rpc("authority", "call_local")
func sync_phase(new_phase: GamePhase, timer: float, day: bool, new_day_count: int):
	print("Received phase sync: ", GamePhase.keys()[new_phase])
	current_phase = new_phase
	phase_timer = timer
	is_day = day
	day_count = new_day_count
	
	# Update sky on clients too
	update_sky_color(day)
	
	# Emit signals
	game_phase_changed.emit(new_phase)
	day_night_changed.emit(day)

func advance_phase():
	print("Advancing phase from: ", GamePhase.keys()[current_phase])
	match current_phase:
		GamePhase.DAY_DISCUSSION:
			set_phase(GamePhase.DAY_VOTING)
			
		GamePhase.DAY_VOTING:
			process_day_votes()
			if check_win_condition():
				set_phase(GamePhase.GAME_OVER)
			else:
				set_phase(GamePhase.NIGHT_ACTION)
				
		GamePhase.NIGHT_ACTION:
			process_night_actions()
			if check_win_condition():
				set_phase(GamePhase.GAME_OVER)
			else:
				set_phase(GamePhase.DAY_DISCUSSION)

@rpc("any_peer", "call_local")
func submit_vote(voter_id: int, target_id: int):
	if current_phase != GamePhase.DAY_VOTING:
		print("Vote rejected - wrong phase")
		return
		
	player_votes[voter_id] = target_id
	print("Player ", voter_id, " voted for ", target_id)

@rpc("any_peer", "call_local") 
func submit_night_action(player_id: int, action_type: String, target_id: int):
	if current_phase != GamePhase.NIGHT_ACTION:
		print("Night action rejected - wrong phase")
		return
		
	night_actions[player_id] = {"type": action_type, "target": target_id}
	print("Player ", player_id, " submitted night action: ", action_type, " on ", target_id)

func process_day_votes():
	print("Processing day votes...")
	if player_votes.is_empty():
		print("No votes cast")
		return
		
	var vote_counts = {}
	for target_id in player_votes.values():
		vote_counts[target_id] = vote_counts.get(target_id, 0) + 1
	
	# Find player with most votes
	var max_votes = 0
	var eliminated_player = -1
	for player_id in vote_counts:
		if vote_counts[player_id] > max_votes:
			max_votes = vote_counts[player_id]
			eliminated_player = player_id
	
	if eliminated_player != -1:
		print("Player ", eliminated_player, " eliminated by vote")
		eliminate_player(eliminated_player)

func process_night_actions():
	print("Processing night actions...")
	var kills = []
	var protections = []
	var investigations = {}
	
	# Process all night actions
	for player_id in night_actions:
		var action = night_actions[player_id]
		var player_role = PlayerManager.get_player_role(player_id) if PlayerManager else PlayerRole.INNOCENT
		
		match player_role:
			PlayerRole.MAFIA, PlayerRole.GODFATHER:
				if action.type == "kill":
					kills.append(action.target)
					
			PlayerRole.SERIAL_KILLER:
				if action.type == "kill":
					kills.append(action.target)
					
			PlayerRole.DOCTOR:
				if action.type == "protect":
					protections.append(action.target)
					
			PlayerRole.SHERIFF:
				if action.type == "investigate":
					var target_role = PlayerManager.get_player_role(action.target) if PlayerManager else PlayerRole.INNOCENT
					var is_suspicious = target_role in [PlayerRole.MAFIA, PlayerRole.GODFATHER, PlayerRole.SERIAL_KILLER]
					investigations[player_id] = {"target": action.target, "suspicious": is_suspicious}
	
	# Apply kills (unless protected)
	for target in kills:
		if target not in protections and players_alive.get(target, false):
			print("Player ", target, " killed at night")
			eliminate_player(target)
	
	# Send investigation results
	for investigator in investigations:
		receive_investigation_result.rpc_id(investigator, investigations[investigator])

@rpc("authority", "call_local")
func receive_investigation_result(result: Dictionary):
	print("Received investigation result: ", result)
	# Forward to UI if it exists
	var game_ui = get_tree().get_first_node_in_group("game_ui")
	if game_ui and game_ui.has_method("_on_investigation_result"):
		game_ui._on_investigation_result(result)

func eliminate_player(player_id: int):
	players_alive[player_id] = false
	player_eliminated.emit(player_id)
	if PlayerManager:
		PlayerManager.eliminate_player(player_id)
	sync_player_elimination.rpc(player_id)

@rpc("authority", "call_local")
func sync_player_elimination(player_id: int):
	players_alive[player_id] = false
	player_eliminated.emit(player_id)

func check_win_condition() -> bool:
	var alive_players = []
	for player_id in players_alive:
		if players_alive[player_id]:
			alive_players.append(player_id)
	
	if alive_players.size() <= 1:
		return true
	
	var mafia_count = 0
	var innocent_count = 0
	
	for player_id in alive_players:
		var role = PlayerManager.get_player_role(player_id) if PlayerManager else PlayerRole.INNOCENT
		if role in [PlayerRole.MAFIA, PlayerRole.GODFATHER]:
			mafia_count += 1
		else:
			innocent_count += 1
	
	# Mafia wins if they equal or outnumber innocents
	if mafia_count >= innocent_count:
		return true
		
	# Innocents win if no mafia left
	if mafia_count == 0:
		return true
		
	return false

func clear_votes():
	player_votes.clear()

func clear_night_actions():
	night_actions.clear()

func get_time_remaining() -> float:
	return max(0, phase_timer)
