# GameUI.gd
extends Control

@onready var phase_label: Label = $TopPanel/PhaseLabel
@onready var timer_label: Label = $TopPanel/TimerLabel
@onready var role_label: Label = $TopPanel/RoleLabel
@onready var player_list: ItemList = $RightPanel/PlayerList
@onready var chat_log: RichTextLabel = $BottomPanel/ChatLog
@onready var chat_input: LineEdit = $BottomPanel/ChatInput
@onready var vote_panel: Panel = $VotePanel
@onready var vote_list: ItemList = $VotePanel/VBox/VoteList
@onready var vote_button: Button = $VotePanel/VBox/VoteButton
@onready var night_action_panel: Panel = $NightActionPanel
@onready var action_list: ItemList = $NightActionPanel/VBox/ActionList
@onready var action_button: Button = $NightActionPanel/VBox/ActionButton
@onready var crosshair: Control = $Crosshair

var selected_vote_target: int = -1
var selected_action_target: int = -1
var current_player_role: GameManager.PlayerRole

func _ready():
	setup_ui()
	connect_signals()

func setup_ui():
	# Initially hide voting and night action panels
	vote_panel.visible = false
	night_action_panel.visible = false
	
	# Setup crosshair
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	
	# Setup lists
	player_list.select_mode = ItemList.SELECT_SINGLE
	vote_list.select_mode = ItemList.SELECT_SINGLE
	action_list.select_mode = ItemList.SELECT_SINGLE
	
	chat_log.bbcode_enabled = true

func connect_signals():
	GameManager.game_phase_changed.connect(_on_phase_changed)
	GameManager.day_night_changed.connect(_on_day_night_changed)
	GameManager.player_eliminated.connect(_on_player_eliminated)
	
	PlayerManager.player_role_assigned.connect(_on_role_assigned)
	NetworkManager.player_connected.connect(update_player_list)
	NetworkManager.player_disconnected.connect(update_player_list)
	
	vote_button.pressed.connect(_on_vote_pressed)
	action_button.pressed.connect(_on_action_pressed)
	vote_list.item_selected.connect(_on_vote_target_selected)
	action_list.item_selected.connect(_on_action_target_selected)
	
	chat_input.text_submitted.connect(_on_chat_submitted)

func _process(_delta):
	# Update timer
	var time_remaining = GameManager.get_time_remaining()
	var minutes = int(time_remaining) / 60
	var seconds = int(time_remaining) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]

func _on_phase_changed(phase: GameManager.GamePhase):
	match phase:
		GameManager.GamePhase.LOBBY:
			phase_label.text = "Lobby"
			
		GameManager.GamePhase.DAY_DISCUSSION:
			phase_label.text = "Day " + str(GameManager.day_count) + " - Discussion"
			vote_panel.visible = false
			night_action_panel.visible = false
			
		GameManager.GamePhase.DAY_VOTING:
			phase_label.text = "Day " + str(GameManager.day_count) + " - Voting"
			show_voting_panel()
			
		GameManager.GamePhase.NIGHT_ACTION:
			phase_label.text = "Night " + str(GameManager.day_count)
			vote_panel.visible = false
			show_night_action_panel()
			
		GameManager.GamePhase.GAME_OVER:
			phase_label.text = "Game Over"
			vote_panel.visible = false
			night_action_panel.visible = false

func _on_day_night_changed(is_day: bool):
	# You could change UI theme/colors here
	if is_day:
		modulate = Color.WHITE
	else:
		modulate = Color(0.7, 0.7, 1.0)  # Slightly blue tint for night

func _on_role_assigned(player_id: int, role: GameManager.PlayerRole):
	if player_id == multiplayer.get_unique_id():
		current_player_role = role
		role_label.text = "Role: " + GameManager.PlayerRole.keys()[role]
		var description = PlayerManager.get_role_description(role)
		add_chat_message("System", description)

func show_voting_panel():
	vote_panel.visible = true
	vote_list.clear()
	selected_vote_target = -1
	vote_button.disabled = true
	
	# Add all alive players except self
	var my_id = multiplayer.get_unique_id()
	for player_id in PlayerManager.get_alive_players():
		if player_id != my_id:
			var player_name = NetworkManager.get_player_name_by_id(player_id)
			vote_list.add_item(player_name)
			vote_list.set_item_metadata(vote_list.get_item_count() - 1, player_id)

func show_night_action_panel():
	if not PlayerManager.can_perform_night_action(multiplayer.get_unique_id()):
		night_action_panel.visible = false
		return
		
	night_action_panel.visible = true
	action_list.clear()
	selected_action_target = -1
	action_button.disabled = true
	
	# Add valid targets based on role
	var my_id = multiplayer.get_unique_id()
	for player_id in PlayerManager.get_alive_players():
		if player_id != my_id:
			var player_name = NetworkManager.get_player_name_by_id(player_id)
			action_list.add_item(player_name)
			action_list.set_item_metadata(action_list.get_item_count() - 1, player_id)
	
	# Update button text based on role
	match current_player_role:
		GameManager.PlayerRole.MAFIA, GameManager.PlayerRole.GODFATHER:
			action_button.text = "Kill"
		GameManager.PlayerRole.DOCTOR:
			action_button.text = "Protect"
		GameManager.PlayerRole.SHERIFF:
			action_button.text = "Investigate"
		GameManager.PlayerRole.SERIAL_KILLER:
			action_button.text = "Kill"
		_:
			action_button.text = "Action"

func _on_vote_target_selected(index: int):
	selected_vote_target = vote_list.get_item_metadata(index)
	vote_button.disabled = false

func _on_action_target_selected(index: int):
	selected_action_target = action_list.get_item_metadata(index)
	action_button.disabled = false

func _on_vote_pressed():
	if selected_vote_target != -1:
		GameManager.submit_vote(multiplayer.get_unique_id(), selected_vote_target)
		vote_panel.visible = false
		add_chat_message("System", "Vote submitted!")

func _on_action_pressed():
	if selected_action_target != -1:
		var action_type = ""
		match current_player_role:
			GameManager.PlayerRole.MAFIA, GameManager.PlayerRole.GODFATHER, GameManager.PlayerRole.SERIAL_KILLER:
				action_type = "kill"
			GameManager.PlayerRole.DOCTOR:
				action_type = "protect"
			GameManager.PlayerRole.SHERIFF:
				action_type = "investigate"
		
		if action_type != "":
			GameManager.submit_night_action(multiplayer.get_unique_id(), action_type, selected_action_target)
			night_action_panel.visible = false
			add_chat_message("System", "Night action submitted!")

func _on_player_eliminated(player_id: int):
	var player_name = NetworkManager.get_player_name_by_id(player_id)
	add_chat_message("System", player_name + " has been eliminated!")
	update_player_list()

func _on_chat_submitted(text: String):
	var message = text.strip_edges()
	if message.length() == 0:
		return
		
	# Check if player can speak (alive during day, or dead anytime)
	var my_id = multiplayer.get_unique_id()
	var is_alive = PlayerManager.get_alive_players().has(my_id)
	var is_day = GameManager.is_day
	
	if is_alive and not is_day:
		# Living players can't talk at night (except mafia to each other)
		if not PlayerManager.is_mafia(my_id):
			add_chat_message("System", "You cannot speak at night!")
			chat_input.clear()
			return
	
	var player_name = NetworkManager.get_player_name_by_id(my_id)
	if not is_alive:
		player_name += " (Dead)"
		
	receive_chat_message.rpc(player_name, message, is_alive, PlayerManager.is_mafia(my_id))
	chat_input.clear()

@rpc("any_peer", "call_local")
func receive_chat_message(player_name: String, message: String, sender_alive: bool = true, sender_is_mafia: bool = false):
	var my_id = multiplayer.get_unique_id()
	var i_am_alive = PlayerManager.get_alive_players().has(my_id)
	var i_am_mafia = PlayerManager.is_mafia(my_id)
	var is_night = not GameManager.is_day
	
	# Message filtering rules
	var can_see_message = true
	
	if is_night and sender_alive:
		# At night, only mafia can see other mafia messages, and dead can see everything
		if sender_is_mafia:
			can_see_message = i_am_mafia or not i_am_alive
		else:
			can_see_message = false  # Living non-mafia can't speak at night
	
	if can_see_message:
		add_chat_message(player_name, message)

func add_chat_message(sender: String, message: String):
	var time_str = Time.get_time_string_from_system()
	var color = "white"
	
	# Color code messages
	if sender == "System":
		color = "yellow"
	elif sender.contains("(Dead)"):
		color = "gray"
	
	chat_log.append_text("[color=%s][%s] %s: %s[/color]\n" % [color, time_str, sender, message])
	chat_log.scroll_to_line(chat_log.get_line_count())

func update_player_list(_player_id: int = -1, _player_name: String = ""):
	player_list.clear()
	
	var alive_players = PlayerManager.get_alive_players()
	
	for player_id in NetworkManager.connected_players:
		var player_info = NetworkManager.connected_players[player_id]
		var display_name = player_info["name"]
		
		# Mark dead players
		if not alive_players.has(player_id):
			display_name += " (Dead)"
		
		# Mark host
		if player_id == 1:
			display_name += " (Host)"
		
		player_list.add_item(display_name)

func _input(event):
	# Toggle chat focus
	if event.is_action_pressed("chat"):
		if chat_input.has_focus():
			chat_input.release_focus()
		else:
			chat_input.grab_focus()
	
	# Quick voting with number keys during voting phase
	if GameManager.current_phase == GameManager.GamePhase.DAY_VOTING and vote_panel.visible:
		for i in range(1, 9):  # Numbers 1-8
			if event.is_action_pressed("vote_" + str(i)) and i <= vote_list.get_item_count():
				selected_vote_target = vote_list.get_item_metadata(i - 1)
				_on_vote_pressed()
				break

func show_investigation_result(target_name: String, is_suspicious: bool):
	var result_text = target_name + " appears "
	if is_suspicious:
		result_text += "SUSPICIOUS!"
	else:
		result_text += "innocent."
	
	add_chat_message("Investigation", result_text)

func show_win_condition(winning_team: String):
	phase_label.text = "Game Over - " + winning_team + " Wins!"
	vote_panel.visible = false
	night_action_panel.visible = false
	
	# Show all roles
	add_chat_message("System", "=== FINAL ROLES ===")
	for player_id in NetworkManager.connected_players:
		var player_name = NetworkManager.get_player_name_by_id(player_id)
		var role = PlayerManager.get_player_role(player_id)
		var role_name = GameManager.PlayerRole.keys()[role]
		add_chat_message("System", player_name + " was " + role_name)

# Called by PlayerManager when receiving investigation results
func _on_investigation_result(result: Dictionary):
	var target_name = NetworkManager.get_player_name_by_id(result["target"])
	show_investigation_result(target_name, result["suspicious"])
