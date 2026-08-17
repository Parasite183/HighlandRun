# HighlandRun

A 2D precision platformer built with Godot 4. Run, jump, wall-jump, and dash
across the highlands.

## Controls

| Action          | Key                     | Notes                                   |
| --------------- | ----------------------- | --------------------------------------- |
| Move left       | A / Left arrow          |                                         |
| Move right      | D / Right arrow         |                                         |
| Jump            | Space                   | Hold for a higher jump, tap for a short hop |
| Dash            | Shift                   | Has a short cooldown; works mid-air     |

The input actions (`move_left`, `move_right`, `jump`, `dash`) are defined in
Project Settings -> Input Map. They are not hardcoded in scripts — the player
controller reads them by action name.

## Running

Open the project in Godot 4.x and press Play, or run the main scene
(`res://main.tscn`) directly.

## Player mechanics

- Variable-height jump (jump height derived from gravity, so a tap is a short
  hop and a held jump reaches full height)
- Coyote time and jump buffering for forgiving platforming
- Wall slide and wall jump (after a wall jump the wall is locked until the
  player touches the opposite wall or lands, so climbing a gap requires
  alternating between the two walls)
- Dash with a cooldown, along input direction or facing direction

All gameplay-tunable values are `@export`ed on `player.gd` and can be adjusted
in the Inspector without touching code.

## Scene layout

`main.tscn` contains a floor and a wall as `StaticBody2D` nodes, each with a
`Polygon2D` child that exactly matches its `RectangleShape2D` collision shape,
plus a large gradient `Polygon2D` background far behind the play area so camera
movement is visible.
