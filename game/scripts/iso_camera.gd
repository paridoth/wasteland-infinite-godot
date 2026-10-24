extends Camera3D
## Fixed-angle follow camera in the style of Diablo 2 Resurrected.

const OFFSET := Vector3(9, 12, 9)

var target: Node3D


func _ready() -> void:
	fov = 40.0
	position = target.position + OFFSET
	look_at(target.position)


func _process(delta: float) -> void:
	position = position.lerp(target.position + OFFSET, 1.0 - exp(-6.0 * delta))
	RenderingServer.global_shader_parameter_set("camera_pos", global_position)
