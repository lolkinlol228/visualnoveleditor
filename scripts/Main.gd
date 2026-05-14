extends Control

func _ready() -> void:
	$VBox/PlayButton.pressed.connect(_on_play)

func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
