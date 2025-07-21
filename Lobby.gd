# Lobby.gd
extends Control

@onready var player_list: ItemList = $VBox/PlayerList
@onready var start_button: Button = $VBox/StartButton
@onready var leave_button: Button = $VBox/LeaveButton
@onready var chat_log: RichTextLabel = $VBox/HBox/ChatLog
@onready var chat_input: LineEdit = $VBox/HBox/ChatInput
@onready var send_button: Button = $VBox/HBox/SendButton

func _ready():
	setup_ui()
	connect_signals()
	update_player_list()

func setup_ui():
	# Only show start button for host
	start_button.visible = NetworkManager.is_server_host()
	start_button.disabled = true
	
	chat_log.bbcode_enabled = true
	chat_input.placeholder_text = "Type message..."

func connect_signals():
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	send_button.pressed.connect(_on_send_pressed)
	chat_input.text_submitted.connect(_on_chat_submitted)
	
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

func _on_start_pressed():
	if NetworkManager.get_player_count() >= 3:
		start_game.rpc()

@rpc("authority", "call_local")
func start_game():
	get_tree().change_scene_to_file("res://Game.tscn")

func _on_leave_pressed():
	NetworkManager.disconnect_from_server()
	get_tree().change_scene_to_file("res://MainMenu.tscn")

func _on_send_pressed():
	send_chat_message()

func _on_chat_submitted(text: String):
	send_chat_message()

func send_chat_message():
	var message = chat_input.text.strip_edges()
	if message.length() == 0:
		return
		
	var player_name = NetworkManager.player_name
	receive_chat_message.rpc(player_name, message)
	chat_input.clear()

@rpc("any_peer", "call_local")
func receive_chat_message(player_name: String, message: String):
	var time_str = Time.get_time_string_from_system()
	chat_log.append_text("[%s] %s: %s\n" % [time_str, player_name, message])
	chat_log.scroll_to_line(chat_log.get_line_count())

func _on_player_connected(id: int, player_name: String):
	update_player_list()
	receive_chat_message("System", player_name + " joined the lobby")
	
	# Update start button availability
	if NetworkManager.is_server_host():
		start_button.disabled = NetworkManager.get_player_count() < 3

func _on_player_disconnected(id: int):
	var player_name = NetworkManager.get_player_name_by_id(id)
	update_player_list()
	receive_chat_message("System", player_name + " left the lobby")
	
	# Update start button availability
	if NetworkManager.is_server_host():
		start_button.disabled = NetworkManager.get_player_count() < 3

func _on_server_disconnected():
	get_tree().change_scene_to_file("res://MainMenu.tscn")

func update_player_list():
	player_list.clear()
	
	for player_id in NetworkManager.connected_players:
		var player_info = NetworkManager.connected_players[player_id]
		var display_name = player_info["name"]
		
		# Mark host
		if player_id == 1:
			display_name += " (Host)"
			
		player_list.add_item(display_name)
