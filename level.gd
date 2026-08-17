extends Node2D
## HighlandRun level controller.
##
## Tracks the respawn point at the last platform the player stood on (no
## hazards in this level, so grounded = safe), respawns the player when they
## fall below the level, and completes the level when the player reaches the
## summit goal orb - freezing the player and showing the completion message.

@onready var player: CharacterBody2D = $Player
@onready var goal_label: Label = $GoalUI/GoalLabel

## Anything below this y is a fall - teleport back to the last platform.
const KILL_Y := 480.0

var respawn_point: Vector2 = Vector2(-400, 0)
var completed := false


func _ready() -> void:
	$GoalArea.body_entered.connect(_on_goal_body_entered)


func _physics_process(_delta: float) -> void:
	if completed:
		return
	# No fail states - falling off just puts the player back on the last platform.
	# Check the kill line FIRST: is_on_floor() can still be true on the frame a
	# fall starts, so it must never overwrite the respawn point with a fall spot.
	if player.global_position.y > KILL_Y:
		_respawn()
		return
	# Remember the last platform stood on so falls can respawn there.
	if player.is_on_floor():
		respawn_point = player.global_position


func _respawn() -> void:
	player.global_position = respawn_point
	player.velocity = Vector2.ZERO


func _on_goal_body_entered(body: Node) -> void:
	if body == player and not completed:
		_complete()


func _complete() -> void:
	completed = true
	player.disable_controls()
	goal_label.visible = true
