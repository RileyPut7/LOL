# GameManager.gd
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

func _ready():
	print("NetworkManager exists: ", NetworkManager != null)
	print("GameManager exists: ", GameManager != null)
	print("PlayerManager exists: ", PlayerManager != null)
	set_multiplayer_authority(1)  # Server authority
	

func _process(delta):
	if not multiplayer.is_server() or not game_started:
		return
		
	phase_timer -= delta
	
	if phase_timer <= 0:
		advance_phase()

func start_game():
	if not multiplayer.is_server():
		return
		
	if NetworkManager.connected_players.size() < 3:
		print("Need at least 3 players to start")
		return
		
	game_started = true
	assign_roles()
	set_phase(GamePhase.DAY_DISCUSSION)
	print("Game started with ", NetworkManager.connected_players.size(), " players")

func assign_roles():
	var player_ids = NetworkManager.connected_players.keys()
	var roles_to_assign = []
	
	# Calculate role distribution based on player count
	var player_count = player_ids.size()
	var mafia_count = max(1, player_count / 4)  # This will be integer division automatically
	
	# Rest of the function remains the same...
	
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
		PlayerManager.assign_role(player_id, role)
		players_alive[player_id] = true

func set_phase(new_phase: GamePhase):
	current_phase = new_phase
	game_phase_changed.emit(new_phase)
	
	match new_phase:
		GamePhase.DAY_DISCUSSION:
			is_day = true
			day_count += 1
			phase_timer = day_duration
			day_night_changed.emit(true)
			clear_night_actions()
			
		GamePhase.DAY_VOTING:
			phase_timer = voting_duration
			
		GamePhase.NIGHT_ACTION:
			is_day = false
			phase_timer = night_duration
			day_night_changed.emit(false)
			clear_votes()
			
	sync_phase.rpc(new_phase, phase_timer, is_day)

@rpc("any_peer", "call_local")
func sync_phase(new_phase: GamePhase, timer: float, day: bool):
	current_phase = new_phase
	phase_timer = timer
	is_day = day
	game_phase_changed.emit(new_phase)
	day_night_changed.emit(day)

func advance_phase():
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
		return
		
	player_votes[voter_id] = target_id
	print("Player ", voter_id, " voted for ", target_id)

@rpc("any_peer", "call_local") 
func submit_night_action(player_id: int, action_type: String, target_id: int):
	if current_phase != GamePhase.NIGHT_ACTION:
		return
		
	night_actions[player_id] = {"type": action_type, "target": target_id}

func process_day_votes():
	if player_votes.is_empty():
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
		eliminate_player(eliminated_player)

func process_night_actions():
	var kills = []
	var protections = []
	var investigations = {}
	
	# Process all night actions
	for player_id in night_actions:
		var action = night_actions[player_id]
		var player_role = PlayerManager.get_player_role(player_id)
		
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
					var target_role = PlayerManager.get_player_role(action.target)
					var is_suspicious = target_role in [PlayerRole.MAFIA, PlayerRole.GODFATHER, PlayerRole.SERIAL_KILLER]
					investigations[player_id] = {"target": action.target, "suspicious": is_suspicious}
	
	# Apply kills (unless protected)
	for target in kills:
		if target not in protections and players_alive.get(target, false):
			eliminate_player(target)
	
	# Send investigation results
	for investigator in investigations:
		rpc_id(investigator, "receive_investigation_result", investigations[investigator])

@rpc("authority", "call_local")
func receive_investigation_result(_result: Dictionary):
	# Handle investigation result on client
	# Add underscore prefix to indicate intentionally unused parameter
	pass

func eliminate_player(player_id: int):
	players_alive[player_id] = false
	player_eliminated.emit(player_id)
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
		var role = PlayerManager.get_player_role(player_id)
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
	return phase_timer
