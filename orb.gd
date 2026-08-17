extends Polygon2D
## Summit goal orb. Builds a circle polygon and gently pulses its scale and
## color so it reads as a glowing goal marker without needing real art.

const RADIUS := 22.0
const SEGMENTS := 24

var _t := 0.0


func _ready() -> void:
	var pts := PackedVector2Array()
	for i in SEGMENTS:
		var a := TAU * float(i) / SEGMENTS
		pts.append(Vector2(cos(a), sin(a)) * RADIUS)
	polygon = pts
	color = Color(1.0, 0.82, 0.35, 0.9)


func _process(delta: float) -> void:
	_t += delta
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	scale = Vector2.ONE * (1.0 + 0.2 * pulse)
	color = Color(1.0, 0.82 + 0.12 * pulse, 0.35, 0.85 + 0.15 * pulse)
