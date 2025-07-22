# Lobby.gd - Fixed version
extends Control

@onready var player_list: ItemList = get_node_or_null("VBox/PlayerList")
@onready var start_button: Button = get_node_or_null("VBox/StartButton")
@onready var leave_button: Button = get_node_or_null("VBox/LeaveButton")
@onready var chat_log: RichTextLabel = get_node_or_null("VBox/HBox/ChatLog")
@onready var chat_input: LineEdit = get_node_or_null("VBox/HBox/VBoxContainer/ChatInput")
@onready var send_button: Button = get_node_or_null("VBox/HBox/VBoxContainer/SendButton")

func _ready():
	print("=== LOBBY DEBUG ===")
	print("PlayerList found: ", player_list != null)
	print("StartButton found: ", start_button != null)
	print("LeaveButton found: ", leave_button != null)
	print("ChatLog found: ", chat_log != null)
	print("ChatInput found: ", chat_input != null)
	print("SendButton found: ", send_button != null)
	
	setup_ui()
	connect_signals()
	update_player_list()

func setup_ui():
	# Only show start button for host
	if start_button:
		start_button.visible = NetworkManager.is_server_host() if NetworkManager else false
		start_button.disabled = true  # Disabled until enough players
		print("Start button configured for host: ", start_button.visible)
	
	if chat_log:
		chat_log.bbcode_enabled = true
		# Make chat log bigger
		chat_log.custom_minimum_size = Vector2(400, 200)
		print("Chat log configured")
	
	if chat_input:
		chat_input.placeholder_text = "Type message..."
		print("Chat input configured")

func connect_signals():
	print("=== CONNECTING LOBBY SIGNALS ===")
	
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
		print("Connected start button")
	
	if leave_button:
		leave_button.pressed.connect(_on_leave_pressed)
		print("Connected leave button")
	
	if send_button:
		send_button.pressed.connect(_on_send_pressed)
		print("Connected send button")
	
	if chat_input:
		chat_input.text_submitted.connect(_on_chat_submitted)
		print("Connected chat input")
	
	# Network signals
	if NetworkManager:
		if NetworkManager.has_signal("player_connected"):
			NetworkManager.player_connected.connect(_on_player_connected)
			print("Connected to player_connected signal")
		if NetworkManager.has_signal("player_disconnected"):
			NetworkManager.player_disconnected.connect(_on_player_disconnected)
			print("Connected to player_disconnected signal")
		if NetworkManager.has_signal("server_disconnected"):
			NetworkManager.server_disconnected.connect(_on_server_disconnected)
			print("Connected to server_disconnected signal")
		
		print("Connected players: ", NetworkManager.connected_players.size())
		for player_id in NetworkManager.connected_players:
			var player_info = NetworkManager.connected_players[player_id]
			print("  Player ", player_id, ": ", player_info["name"])
	else:
		print("ERROR: NetworkManager not found!")

func _on_start_pressed():
	print("Start button pressed!")
	if NetworkManager and NetworkManager.get_player_count() >= 1:  # Changed from 3 to 1 for testing
		print("Starting game...")
		start_game.rpc()
	else:
		print("Need at least 1 player to start (testing mode)")

@rpc("authority", "call_local")
func start_game():
	print("Starting game...")
	# Start the game in GameManager
	if GameManager:
		GameManager.start_game()
	get_tree().change_scene_to_file("res://Game.tscn")

func _on_leave_pressed():
	print("Leave button pressed!")
	if NetworkManager:
		NetworkManager.disconnect_from_server()
	get_tree().change_scene_to_file("res://MainMenu.tscn")

func _on_send_pressed():
	send_chat_message()

func _on_chat_submitted(text: String):
	send_chat_message()

func send_chat_message():
	if not chat_input:
		return
		
	var message = chat_input.text.strip_edges()
	if message.length() == 0:
		return
		
	var player_name = NetworkManager.player_name if NetworkManager else "Unknown"
	receive_chat_message.rpc(player_name, message)
	chat_input.clear()

@rpc("any_peer", "call_local")
func receive_chat_message(player_name: String, message: String):
	if not chat_log:
		return
		
	# Remove timestamp for cleaner look
	chat_log.append_text("%s: %s\n" % [player_name, message])
	chat_log.scroll_to_line(chat_log.get_line_count())

func _on_player_connected(id: int, player_name: String):
	print("Player connected: ", id, " - ", player_name)
	update_player_list()
	receive_chat_message("System", player_name + " joined the lobby")
	
	# Update start button availability
	if NetworkManager and start_button and NetworkManager.is_server_host():
		start_button.disabled = NetworkManager.get_player_count() < 1  # Changed from 3 to 1 for testing

func _on_player_disconnected(id: int):
	print("Player disconnected: ", id)
	var player_name = NetworkManager.get_player_name_by_id(id) if NetworkManager else "Unknown"
	update_player_list()
	receive_chat_message("System", player_name + " left the lobby")
	
	# Update start button availability
	if NetworkManager and start_button and NetworkManager.is_server_host():
		start_button.disabled = NetworkManager.get_player_count() < 1  # Changed from 3 to 1 for testing

func _on_server_disconnected():
	print("Server disconnected!")
	get_tree().change_scene_to_file("res://MainMenu.tscn")

func update_player_list():
	print("Updating player list...")
	
	if not player_list:
		print("ERROR: Player list not found!")
		return
	
	if not NetworkManager:
		print("ERROR: NetworkManager not found!")
		return
	
	player_list.clear()
	
	print("Connected players count: ", NetworkManager.connected_players.size())
	
	for player_id in NetworkManager.connected_players:
		var player_info = NetworkManager.connected_players[player_id]
		var display_name = player_info["name"]
		
		# Mark host
		if player_id == 1:
			display_name += " (Host)"
			
		player_list.add_item(display_name)
		print("Added player to list: ", display_name)
	
	print("Player list updated with ", player_list.get_item_count(), " items")
