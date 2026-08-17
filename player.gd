class_name Player
extends CharacterBody2D

## HighlandRun - player controller.
## A 2D precision platformer character: run, variable-height jump, coyote time,
## jump buffering, wall slide / wall jump, and a dash with a cooldown.
##
## Controls (configured in Project Settings -> Input Map, actions:
## move_left/move_right, jump, dash):
##   - A / D or Left/Right arrows: move
##   - Space: jump (hold for a higher jump, tap for a short hop)
##   - Shift: dash
##
## Every gameplay-tunable number is an @export so it can be adjusted in the
## Inspector (even live, while the game is paused/running) without touching code.
##
## All timers are in seconds and are advanced with the physics delta inside
## _physics_process(), which runs on Godot's fixed 60 Hz physics step. Every
## acceleration/gravity value is multiplied by delta, so behavior is identical
## regardless of the physics tick rate.

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
## Emitted the frame a dash starts - hook up trail/particle effects here.
signal dash_started
## Emitted the frame a dash ends - stop trail/particle effects here.
signal dash_ended

# ---------------------------------------------------------------------------
# Movement (tune in the Inspector)
# ---------------------------------------------------------------------------
## Max horizontal speed while running, px/s.
@export var move_speed: float = 220.0
## Acceleration toward move_speed while grounded, px/s^2.
@export var ground_acceleration: float = 1800.0
## Deceleration when no horizontal input while grounded, px/s^2.
@export var ground_friction: float = 1600.0
## Acceleration while airborne, px/s^2. Lower than ground_acceleration = the
## player has less grip in the air while actively steering with input.
@export var air_acceleration: float = 1000.0
## Deceleration while airborne with no horizontal input, px/s^2. Much lower
## than air_acceleration so wall-jump momentum carries further even if input
## isn't held perfectly the whole time.
@export var air_drag: float = 300.0

## Downward gravity, px/s^2. Jump velocity is derived from this (see below).
@export var gravity: float = 1800.0:
	set(value):
		gravity = value
		_update_jump_velocity()
## Gravity multiplier applied while falling (velocity.y > 0) - a snappier,
## less floaty arc.
@export var fall_gravity_multiplier: float = 1.5
## Gravity multiplier applied while still rising if the jump button is released
## early - this is what makes a tap jump a short hop and a held jump a full one.
@export var jump_cut_gravity_multiplier: float = 2.5
## Terminal fall speed, px/s.
@export var max_fall_speed: float = 900.0

## Jump height in px. Jump velocity is *computed* from this with the kinematic
## formula v = sqrt(2 * g * h) instead of being a hardcoded guess, so the jump
## apex lands on jump_height for any gravity/height combination.
@export var jump_height: float = 64.0:
	set(value):
		jump_height = value
		_update_jump_velocity()
## Coyote time (s): how long after walking off a ledge the player can still jump.
@export var coyote_time: float = 0.1
## Jump buffer (s): how long a jump press is kept in memory. Pressing jump up to
## this long before landing still executes the jump the instant you touch down.
@export var jump_buffer_time: float = 0.12

# ---------------------------------------------------------------------------
# Wall interaction (tune in the Inspector)
# ---------------------------------------------------------------------------
## Max fall speed while wall sliding, px/s.
@export var wall_slide_speed: float = 120.0
## Horizontal push away from the wall on a wall jump, px/s. The launch alone
## covers most of a typical gap; a brief hold toward the target wall finishes
## the crossing (air_acceleration does the rest).
@export var wall_jump_push: float = 260.0
## Vertical lift of a wall jump, px/s (upward).
@export var wall_jump_velocity: float = 440.0

# ---------------------------------------------------------------------------
# Dash (tune in the Inspector)
# ---------------------------------------------------------------------------
## Horizontal speed of a dash, px/s.
@export var dash_speed: float = 600.0
## How long the dash lasts (s). Gravity is ignored during this window.
@export var dash_duration: float = 0.15
## Cooldown (s) after a dash ends before it can be used again.
@export var dash_cooldown: float = 0.5

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var _left_wall_ray: RayCast2D = $WallRayLeft
@onready var _right_wall_ray: RayCast2D = $WallRayRight

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _jump_velocity: float = 0.0            # computed from jump_height + gravity
var _coyote_timer: float = 0.0             # counts down while airborne
var _jump_buffer_timer: float = 0.0        # stores a recent jump press
var _locked_wall_side: int = 0             # wall jumped from; ungrabbable until the
                                           # opposite wall is touched or the player lands
var _dash_timer: float = 0.0               # > 0 while a dash is active
var _dash_cooldown_timer: float = 0.0      # counts down after a dash ends
var _dash_direction: float = 1.0           # horizontal direction of the active dash
var _facing: float = 1.0                   # 1 = right, -1 = left (dash fallback)


func _ready() -> void:
	_update_jump_velocity()
	# The wall raycasts are children of this body; RayCast2D excludes the parent
	# body's own collision shape by default, so they only detect external walls.
	_left_wall_ray.enabled = true
	_right_wall_ray.enabled = true
	# NOTE (RayCast2D flush-contact quirk): with hit_from_inside = false (the
	# default), a ray whose origin sits EXACTLY on a wall face (0.000px gap) can
	# miss. The physics solver's sub-pixel margin normally prevents this, but if
	# wall-slide/wall-jump detection ever starts missing intermittently after a
	# level-geometry change, nudge the ray origins inward ~0.5-1px (or enable
	# hit_from_inside) instead of relying on solver behavior staying favorable.


## Recomputes jump velocity from the target height using the kinematic formula
##   v = sqrt(2 * g * h)
## This gives the exact upward speed needed to reach `jump_height` under
## `gravity`, independent of the fixed physics step.
func _update_jump_velocity() -> void:
	_jump_velocity = sqrt(2.0 * gravity * jump_height)


func _physics_process(delta: float) -> void:
	var input_dir := Input.get_axis("move_left", "move_right")

	# Track facing from input so a dash with no directional input goes the way
	# the player currently faces.
	if input_dir != 0.0 and not _is_dashing():
		_facing = signf(input_dir)

	# --- Timers ----------------------------------------------------------
	# Coyote time: refreshed every frame we're grounded, then counts down while
	# airborne. Jumping is allowed while it's above zero.
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	# Jump buffer: remember a jump press for a few frames. If it expires unused
	# the input is dropped; if the player lands first, the buffered jump fires.
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)

	# --- Dash ------------------------------------------------------------
	if _is_dashing():
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_dash_timer = 0.0
			dash_ended.emit()
			# Cooldown starts once the dash finishes (dash 0.15s, then wait 0.5s).
			_dash_cooldown_timer = dash_cooldown
	elif Input.is_action_just_pressed("dash") and _dash_cooldown_timer <= 0.0:
		_start_dash(input_dir)

	# --- Wall detection --------------------------------------------------
	# wall_side: -1 = wall on the left, 1 = wall on the right, 0 = none.
	var wall_side := _get_wall_side()

	# The wall-jump lock is state-based, not timed: the wall jumped from stays
	# ungrabbable until the player touches the OPPOSITE wall or lands.
	if _locked_wall_side != 0:
		if is_on_floor() or wall_side == -_locked_wall_side:
			_locked_wall_side = 0

	var wall_sliding := _is_wall_sliding(wall_side)

	# --- Jumping ---------------------------------------------------------
	if Input.is_action_just_pressed("jump") and wall_sliding:
		_do_wall_jump(wall_side)
		wall_sliding = false  # we're jumping away from the wall now
	elif _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_do_jump()

	# --- Movement --------------------------------------------------------
	if _is_dashing():
		# Dash overrides normal movement: constant horizontal burst, gravity off.
		velocity.x = _dash_direction * dash_speed
		velocity.y = 0.0
	else:
		_apply_horizontal_movement(input_dir, delta)
		_apply_vertical_movement(delta, wall_sliding)

	move_and_slide()


## True while a dash is in its active window.
func _is_dashing() -> bool:
	return _dash_timer > 0.0


## Returns which side has a wall in contact via the side raycasts.
## -1 = wall on the left, 1 = wall on the right, 0 = none.
func _get_wall_side() -> int:
	if _left_wall_ray.is_colliding():
		return -1
	if _right_wall_ray.is_colliding():
		return 1
	return 0


## Wall sliding requires only: airborne (not grounded) and not currently
## locked out of that wall. Touching a wall is enough to grab it, whether
## rising or falling and with or without directional input toward it. After a
## wall jump the wall jumped from stays locked until the player touches the
## OPPOSITE wall or lands - so climbing a gap structurally requires
## alternating between the two walls, not waiting out a cooldown.
func _is_wall_sliding(wall_side: int) -> bool:
	if wall_side == 0 or is_on_floor():
		return false
	if wall_side == _locked_wall_side:
		return false  # still locked from the wall jump off this wall
	return true


## Ground / coyote jump.
func _do_jump() -> void:
	velocity.y = -_jump_velocity
	# Consume both timers so the jump can't fire twice.
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0


## Wall jump: push away from the wall with horizontal force plus vertical lift.
func _do_wall_jump(wall_side: int) -> void:
	# Negating wall_side points away from the wall (-1 -> right, 1 -> left).
	velocity.x = -float(wall_side) * wall_jump_push
	velocity.y = -wall_jump_velocity
	_facing = -float(wall_side)
	# Lock THIS wall: it stays ungrabbable until the opposite wall is touched
	# or the player lands (see _is_wall_sliding), structurally requiring
	# alternating wall jumps to climb a gap.
	_locked_wall_side = wall_side
	_jump_buffer_timer = 0.0


func _apply_horizontal_movement(input_dir: float, delta: float) -> void:
	if input_dir != 0.0:
		# Accelerate toward max speed; grip is lower in the air than on the ground.
		var accel := ground_acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, input_dir * move_speed, accel * delta)
	else:
		# Friction when no input: ground_friction on the ground, air_drag in the
		# air (kept low so wall-jump momentum carries without holding input).
		var friction := ground_friction if is_on_floor() else air_drag
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _apply_vertical_movement(delta: float, wall_sliding: bool) -> void:
	# Pick the gravity multiplier for the current phase of the jump arc:
	var mult := 1.0
	if velocity.y > 0.0:
		# Falling: stronger gravity = snappier, less floaty fall.
		mult = fall_gravity_multiplier
	elif velocity.y < 0.0 and not Input.is_action_pressed("jump"):
		# Rising but the jump button was released: cut the jump short by
		# slamming on extra gravity for the rest of the ascent.
		mult = jump_cut_gravity_multiplier

	velocity.y += gravity * mult * delta
	if wall_sliding:
		# Wall slide caps fall speed well below terminal velocity.
		velocity.y = minf(velocity.y, wall_slide_speed)
	else:
		velocity.y = minf(velocity.y, max_fall_speed)


func _start_dash(input_dir: float) -> void:
	# Dash along horizontal input, or along the facing direction if no input.
	_dash_direction = input_dir if input_dir != 0.0 else _facing
	_facing = _dash_direction
	_dash_timer = dash_duration
	velocity.y = 0.0  # gravity is ignored during the dash window
	dash_started.emit()
