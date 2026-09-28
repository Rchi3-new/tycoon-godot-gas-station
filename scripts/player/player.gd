extends CharacterBody2D
## Placeholder survivor: eight-way movement with a locked-on camera, enough to
## walk the endless city. Collides with the environment on physics layer 1.

@export var speed: float = 200.0


func _physics_process(_delta: float) -> void:
	velocity = Input.get_vector("move_left", "move_right", "move_up", "move_down") * speed
	move_and_slide()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 12.0, Color("4a5731"))
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 32, Color("5fe0ff"), 2.0)
