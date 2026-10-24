extends OmniLight3D
## Firelight: layered sines give an irregular flicker without per-frame randomness.

var base_energy := 1.5
var phase := randf() * TAU


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0 + phase
	light_energy = base_energy * (0.85 + 0.1 * sin(t * 7.3) + 0.05 * sin(t * 17.1))
