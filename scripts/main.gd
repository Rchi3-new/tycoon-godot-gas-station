extends Node2D
## Game root. World is Y-sorted so characters and city props overlap correctly.

@onready var _city: EndlessCity = $World/EndlessCity
@onready var _player: Node2D = $World/Player


func _ready() -> void:
	_player.global_position = _city.to_global(_city.get_spawn_position())
