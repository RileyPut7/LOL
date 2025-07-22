# VotingManager.gd - Enhanced voting system per design doc
extends Node

signal voting_initiated(accuser_id: int, accused_id: int)
signal accuser_statement_phase(time_remaining: float)
signal accused_defense_phase(time_remaining: float) 
signal group_discussion_phase(time_remaining: float)
signal voting_complete(eliminated_player: int)

const ACCUSER_STATEMENT_TIME = 15.0
const ACCUSED_DEFENSE_TIME = 20.0
const GROUP_DISCUSSION_TIME = 15.0

var current_accuser: int = -1
var current_accused: int = -1
var votes_for_elimination: Dictionary = {}
var total_voters: int = 0

func start_voting_sequence(accuser_id: int, accused_id: int):
	print("Starting voting sequence: ", accuser_id, " accusing ", accused_id)
	
	current_accuser = accuser_id
	current_accused = accused_id
	votes_for_elimination.clear()
	
	# Get total alive players for majority calculation
	if PlayerManager:
		total_voters = PlayerManager.get_alive_players().size()
	
	voting_initiated.emit(accuser_id, accused_id)
	start_accuser_statement()

func start_accuser_statement():
	print("Accuser statement phase")
	accuser_statement_phase.emit(ACCUSER_STATEMENT_TIME)
	
	# Enable voice/text for accuser only
	enable_speaking.rpc(current_accuser, true, ACCUSER_STATEMENT_TIME)
	disable_speaking_for_others.rpc(current_accuser)
	
	await get_tree().create_timer(ACCUSER_STATEMENT_TIME).timeout
	start_accused_defense()

func start_accused_defense():
	print("Accused defense phase") 
	accused_defense_phase.emit(ACCUSED_DEFENSE_TIME)
	
	# Enable voice/text for accused only
	enable_speaking.rpc(current_accused, true, ACCUSED_DEFENSE_TIME)
	disable_speaking_for_others.rpc(current_accused)
	
	await get_tree().create_timer(ACCUSED_DEFENSE_TIME).timeout
	start_group_discussion()

func start_group_discussion():
	print("Group discussion and voting phase")
	group_discussion_phase.emit(GROUP_DISCUSSION_TIME)
	
	# Enable speaking for everyone and show voting UI
	enable_speaking_for_all.rpc(GROUP_DISCUSSION_TIME)
	show_elimination_voting_ui.rpc(current_accused, GROUP_DISCUSSION_TIME)
	
	await get_tree().create_timer(GROUP_DISCUSSION_TIME).timeout
	process_elimination_votes()

func process_elimination_votes():
	var yes_votes = 0
	var no_votes = 0
	
	for voter_id in votes_for_elimination:
		if votes_for_elimination[voter_id]:
			yes_votes += 1
		else:
			no_votes += 1
	
	print("Elimination votes - Yes: ", yes_votes, " No: ", no_votes)
	
	# Majority needs to vote yes to eliminate
	if yes_votes > total_voters / 2:
		eliminate_player(current_accused)
		voting_complete.emit(current_accused)
	else:
		print("Not enough votes to eliminate ", current_accused)
		voting_complete.emit(-1)  # No elimination
	
	# Reset voting state
	current_accuser = -1
	current_accused = -1
	votes_for_elimination.clear()

func eliminate_player(player_id: int):
	print("Player ", player_id, " eliminated by vote")
	if PlayerManager:
		PlayerManager.eliminate_player(player_id)
	
	# Reveal role publicly as per design
	var role = PlayerManager.get_player_role(player_id) if PlayerManager else GameManager.PlayerRole.INNOCENT
	var role_name = GameManager.PlayerRole.keys()[role]
	reveal_eliminated_role.rpc(player_id, role_name)

@rpc("authority", "call_local")
func enable_speaking(player_id: int, enabled: bool, time_limit: float):
	if multiplayer.get_unique_id() == player_id:
		var ui = get_tree().get_first_node_in_group("game_ui")
		if ui and ui.has_method("set_speaking_enabled"):
			ui.set_speaking_enabled(enabled, time_limit)

@rpc("authority", "call_local")
func disable_speaking_for_others(speaking_player_id: int):
	if multiplayer.get_unique_id() != speaking_player_id:
		var ui = get_tree().get_first_node_in_group("game_ui")
		if ui and ui.has_method("set_speaking_enabled"):
			ui.set_speaking_enabled(false, 0)

@rpc("authority", "call_local")
func enable_speaking_for_all(time_limit: float):
	var ui = get_tree().get_first_node_in_group("game_ui")
	if ui and ui.has_method("set_speaking_enabled"):
		ui.set_speaking_enabled(true, time_limit)

@rpc("authority", "call_local")
func show_elimination_voting_ui(accused_id: int, time_limit: float):
	var ui = get_tree().get_first_node_in_group("game_ui")
	if ui and ui.has_method("show_elimination_vote"):
		ui.show_elimination_vote(accused_id, time_limit)

@rpc("authority", "call_local")
func reveal_eliminated_role(player_id: int, role_name: String):
	var ui = get_tree().get_first_node_in_group("game_ui")
	if ui and ui.has_method("show_role_reveal"):
		var player_name = NetworkManager.get_player_name_by_id(player_id) if NetworkManager else "Unknown"
		ui.show_role_reveal(player_name, role_name)

@rpc("any_peer", "call_local")
func submit_elimination_vote(voter_id: int, vote_yes: bool):
	votes_for_elimination[voter_id] = vote_yes
	print("Player ", voter_id, " voted ", "YES" if vote_yes else "NO", " for elimination")

# Player.gd additions for whispering and communication
func _input(event):
	# ... existing input code ...
	
	if event.is_action_pressed("whisper"):
		start_whisper_mode()
	
	if event.is_action_released("whisper"):
		end_whisper_mode()

func start_whisper_mode():
	# Find nearby players for whispering
	var nearby_players = get_nearby_players(3.0)  # 3 meter whisper range
	if nearby_players.size() > 0:
		show_whisper_targets(nearby_players)

func show_whisper_targets(targets: Array):
	var ui = get_tree().get_first_node_in_group("game_ui")
	if ui and ui.has_method("show_whisper_UI"):
		ui.show_whisper_UI(targets)

@rpc("any_peer", "call_local")
func send_whisper(sender_id: int, target_id: int, message: String):
	# Only sender and target can hear whisper
	var my_id = multiplayer.get_unique_id()
	if my_id == sender_id or my_id == target_id:
		var ui = get_tree().get_first_node_in_group("game_ui")
		if ui and ui.has_method("receive_whisper"):
			ui.receive_whisper(sender_id, message, my_id == target_id)
	
	# Show whisper emote to nearby players (but not the message)
	var nearby = get_nearby_players(5.0)
	for player in nearby:
		if player.get_multiplayer_authority() != sender_id and player.get_multiplayer_authority() != target_id:
			show_whisper_emote.rpc_id(player.get_multiplayer_authority(), sender_id, target_id)

@rpc("authority", "call_local")
func show_whisper_emote(whisperer_id: int, target_id: int):
	# Visual indicator that two players are whispering
	var ui = get_tree().get_first_node_in_group("game_ui")
	if ui and ui.has_method("show_whisper_emote"):
		ui.show_whisper_emote(whisperer_id, target_id)
