extends Node3D
## Builds a seeded ruin, the player, enemy packs and the isometric camera, and routes input
## to real-time exploration or turn-based combat. Everything is generated in code for now so
## the map can later be driven by the director's world data.

const Unit := preload("res://scripts/unit.gd")
const Combat := preload("res://scripts/combat.gd")
const Hud := preload("res://scripts/hud.gd")
const IsoCamera := preload("res://scripts/iso_camera.gd")
const Flicker := preload("res://scripts/flicker.gd")
const SIZE := 48
const KIT := "res://assets/kenney/"
const DEBRIS := ["survival/rock-a", "survival/rock-b", "survival/rock-c", "survival/rock-sand-a",
		"survival/resource-stone", "survival/resource-stone-large", "survival/box-large",
		"survival/box-large-open", "survival/tree-trunk", "survival/tree-log", "survival/bucket",
		"survival/metal-panel-screws", "survival/signpost", "survival/chest"]
const CAMP := ["survival/tent-canvas", "survival/fence-fortified", "survival/fence",
		"survival/workbench", "survival/structure-metal"]
const LANDMARKS := ["industrial/water-tower", "industrial/shipping-container-a",
		"industrial/shipping-container-b", "industrial/shipping-container-c",
		"industrial/detail-tank", "industrial/detail-tank-large", "industrial/chimney-large"]

@export var map_seed := 42

var grid := AStarGrid2D.new()
var player: Unit
var units: Array[Unit] = []
var combat := Combat.new()
var hud := Hud.new()
var demo_combat := "--demo-combat" in OS.get_cmdline_user_args()
var camera: IsoCamera
var cursor: MeshInstance3D
var concrete := ShaderMaterial.new()
var landmarks: Array[Node3D] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	grid.region = Rect2i(0, 0, SIZE, SIZE)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	_build_environment()
	_build_ground()
	_build_ruins(rng)
	player = _spawn({"display_name": "You", "is_player": true},
			_open_cell_near(Vector2i(SIZE / 2, SIZE / 2)))
	_spawn_packs(rng)
	camera = IsoCamera.new()
	camera.target = player
	add_child(camera)
	cursor = MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.9, 0.9)
	cursor.mesh = quad
	cursor.material_override = unlit(Color(0.3, 1.0, 0.4, 0.35))
	add_child(cursor)
	combat.main = self
	combat.rng.seed = map_seed
	combat.changed.connect(func() -> void: hud.refresh())
	add_child(combat)
	hud.main = self
	add_child(hud)
	hud.log_line("You wake among the ruins. Something shuffles in the dark.")
	if "--demo" in OS.get_cmdline_user_args():
		# Scripted walk for frame captures (godot --write-movie ... -- --demo).
		player.move_to(_demo_target())


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.4)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.09, 0.08)
	env.fog_density = 0.015
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, 30, 0)
	moon.light_color = Color(0.6, 0.7, 0.9)
	moon.light_energy = 0.55
	moon.shadow_enabled = true
	add_child(moon)


func _build_ground() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.seamless = true
	texture.color_ramp = Gradient.new()
	texture.color_ramp.set_color(0, Color(0.16, 0.13, 0.1))
	texture.color_ramp.set_color(1, Color(0.32, 0.28, 0.2))
	var dirt := StandardMaterial3D.new()
	dirt.albedo_texture = texture
	dirt.uv1_scale = Vector3(6, 6, 6)
	dirt.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = dirt
	ground.position = Vector3(SIZE / 2.0, 0, SIZE / 2.0)
	add_child(ground)
	concrete.shader = preload("res://shaders/wall.gdshader")
	var grime := NoiseTexture2D.new()
	grime.noise = FastNoiseLite.new()
	grime.noise.frequency = 0.05
	grime.seamless = true
	concrete.set_shader_parameter("grime", grime)


func _build_ruins(rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(6, 10):
		var w := rng.randi_range(5, 10)
		var h := rng.randi_range(5, 9)
		var origin := Vector2i(rng.randi_range(2, SIZE - w - 2), rng.randi_range(2, SIZE - h - 2))
		var edge: Array[Vector2i] = []
		for x in w:
			edge.append(origin + Vector2i(x, 0))
			edge.append(origin + Vector2i(x, h - 1))
		for z in range(1, h - 1):
			edge.append(origin + Vector2i(0, z))
			edge.append(origin + Vector2i(w - 1, z))
		var door := rng.randi_range(0, edge.size() - 1)
		for j in edge.size():
			if j != door and rng.randf() > 0.18:
				_wall(edge[j], rng.randf_range(0.5, 2.6))
	for i in rng.randi_range(3, 5):
		var cell := _open_cell_near(Vector2i(rng.randi_range(6, SIZE - 6), rng.randi_range(6, SIZE - 6)))
		var landmark := _prop(LANDMARKS[rng.randi() % LANDMARKS.size()], cell, 2.0, rng.randi() % 4)
		if landmark:
			landmarks.append(landmark)
	for i in 80:
		var cell := Vector2i(rng.randi_range(1, SIZE - 2), rng.randi_range(1, SIZE - 2))
		_prop(DEBRIS[rng.randi() % DEBRIS.size()], cell, rng.randf_range(1.8, 2.8), rng.randi() % 4)
	for i in 3:
		var camp := _open_cell_near(Vector2i(rng.randi_range(6, SIZE - 6), rng.randi_range(6, SIZE - 6)))
		_fire(camp, "survival/campfire-pit", 0.5)
		for j in 3:
			var spot := camp + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
			_prop(CAMP[rng.randi() % CAMP.size()], spot, 2.5, rng.randi() % 4)
	for i in 6:
		_fire(_open_cell_near(Vector2i(rng.randi_range(4, SIZE - 4), rng.randi_range(4, SIZE - 4))),
				"survival/barrel", 1.4)


func _wall(cell: Vector2i, height: float) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1, height, 1)
	var wall := MeshInstance3D.new()
	wall.mesh = box
	wall.material_override = concrete
	wall.position = Unit.to_world(cell) + Vector3(0, height / 2, 0)
	add_child(wall)
	grid.set_point_solid(cell, true)


## Places a kit model on a cell, rotated by quarter turns. Every cell its footprint covers
## must be free; tall props make those cells solid. Returns null when the spot is blocked.
func _prop(model: String, cell: Vector2i, size: float, quarter: int) -> Node3D:
	if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell):
		return null
	var prop: Node3D = load(KIT + model + ".glb").instantiate()
	prop.scale = Vector3.ONE * size
	prop.rotation.y = quarter * PI / 2
	prop.position = Unit.to_world(cell)
	var box := AABB()
	for mesh: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
		box = box.merge(mesh.transform * mesh.get_aabb())
	box = prop.transform * box
	var cells: Array[Vector2i] = [cell]
	for x in range(floori(box.position.x + 0.2), ceili(box.end.x - 0.2)):
		for z in range(floori(box.position.z + 0.2), ceili(box.end.z - 0.2)):
			var covered := Vector2i(x, z)
			if not grid.is_in_boundsv(covered) or grid.is_point_solid(covered):
				prop.free()
				return null
			cells.append(covered)
	add_child(prop)
	if box.size.y > 0.5:
		for covered in cells:
			grid.set_point_solid(covered, true)
	return prop


func _fire(cell: Vector2i, model: String, height: float) -> void:
	if _prop(model, cell, 2.5, 0) == null:
		return
	var fire := Flicker.new()
	fire.light_color = Color(1.0, 0.55, 0.2)
	fire.omni_range = 6.0
	fire.base_energy = 2.2
	fire.shadow_enabled = true
	fire.position = Unit.to_world(cell) + Vector3(0, height, 0)
	add_child(fire)
	grid.set_point_solid(cell, true)


func _open_cell_near(start: Vector2i) -> Vector2i:
	for radius in SIZE:
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var cell := start + Vector2i(x, z)
				if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell):
					return cell
	return start


## Nearest reachable cell with a wall between it and the camera (camera sits at +x, +z).
func _demo_target() -> Vector2i:
	for radius in range(3, SIZE):
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var cell := player.cell + Vector2i(x, z)
				var behind := cell + Vector2i(1, 1)
				if grid.is_in_boundsv(behind) and not grid.is_point_solid(cell) \
						and grid.is_point_solid(behind) and grid.is_point_solid(cell + Vector2i(1, 0)) \
						and not grid.get_id_path(player.cell, cell).is_empty():
					return cell
	return player.cell


const ZOMBIE := {"display_name": "Shambler", "hostile": true, "speed": 2.2, "max_hp": 14,
		"max_ap": 5, "skill": 70, "armor_class": 2,
		"weapon": {"name": "Claws", "ap": 3, "min": 2, "max": 5, "range": 1.5}}


func _spawn(stats: Dictionary, cell: Vector2i) -> Unit:
	var unit := Unit.new()
	for key: String in stats:
		unit.set(key, stats[key])
	unit.grid = grid
	add_child(unit)
	unit.place(cell)
	units.append(unit)
	return unit


## Diablo-style packs: a few shamblers around a reachable point away from the player.
func _spawn_packs(rng: RandomNumberGenerator) -> void:
	var near := 5 if demo_combat else 12
	for pack in 2 if demo_combat else 3:
		var center := player.cell
		for attempt in 100:
			var angle := rng.randf() * TAU
			var guess := player.cell + Vector2i(Vector2(cos(angle), sin(angle)) * (near + rng.randi_range(0, 8)))
			if grid.is_in_boundsv(guess) and not grid.is_point_solid(guess) \
					and not grid.get_id_path(player.cell, guess).is_empty():
				center = guess
				break
		for i in rng.randi_range(2, 3):
			var stats := ZOMBIE.duplicate()
			stats.skin = "zombieA" if rng.randf() < 0.5 else "zombieC"
			var spot := _open_cell_near(center + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2)))
			if unit_at(spot) == null and spot != player.cell:
				_spawn(stats, spot).rotation.y = rng.randf() * TAU


func enemies() -> Array[Unit]:
	return units.filter(func(u: Unit) -> bool: return u.hostile and u.alive())


func unit_at(cell: Vector2i) -> Unit:
	for unit in units:
		if unit.alive() and unit.cell == cell:
			return unit
	return null


## Path for one unit with every other living unit treated as an obstacle. The unit's own
## cell is dropped from the front. `partial` walks as close as possible to a blocked target.
func path_for(unit: Unit, target: Vector2i, partial: bool) -> Array[Vector2i]:
	var blocked: Array[Vector2i] = []
	for other in units:
		if other != unit and other.alive() and not grid.is_point_solid(other.cell):
			grid.set_point_solid(other.cell, true)
			blocked.append(other.cell)
	var route := grid.get_id_path(unit.cell, target, partial)
	for cell in blocked:
		grid.set_point_solid(cell, false)
	if not route.is_empty() and route[0] == unit.cell:
		route.remove_at(0)
	return route


## Grid line of sight: no solid cell strictly between the two cells.
func sees(from: Vector2i, to: Vector2i) -> bool:
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i in range(1, steps):
		var point := Vector2(from).lerp(Vector2(to), float(i) / steps).round()
		if grid.is_point_solid(Vector2i(point)):
			return false
	return true


func log_line(text: String) -> void:
	hud.log_line(text)


func float_text(unit: Unit, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = 72
	label.outline_size = 12
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = unit.position + Vector3(0, 2.1, 0)
	add_child(label)
	var rise := create_tween()
	rise.tween_property(label, "position:y", label.position.y + 0.9, 0.9)
	rise.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	rise.tween_callback(label.queue_free)


func unlit(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	return material


func _mouse_cell(screen: Vector2) -> Variant:
	var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(
		camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	return null if hit == null else Vector2i(floori(hit.x), floori(hit.z))


func _process(_delta: float) -> void:
	# Large props keep their own materials, so they fade as a whole instead of dissolving.
	var eye := camera.global_position
	var seg := player.position + Vector3(0, 0.9, 0) - eye
	for landmark in landmarks:
		var t := clampf((landmark.position - eye).dot(seg) / seg.length_squared(), 0, 1)
		var near := (eye + seg * t).distance_to(landmark.position + Vector3(0, 1, 0)) < 3.0
		var fade := 0.75 if near and t < 0.97 else 0.0
		for mesh: GeometryInstance3D in landmark.find_children("*", "GeometryInstance3D", true, false):
			mesh.transparency = lerpf(mesh.transparency, fade, 0.2)
	if not combat.active and player.alive():
		for enemy in enemies():
			if Vector2(enemy.cell).distance_to(Vector2(player.cell)) <= Combat.SIGHT \
					and sees(enemy.cell, player.cell):
				log_line("%s notices you!" % enemy.display_name)
				combat.start(false)
				break
	if demo_combat and combat.player_turn and not combat.busy:
		_demo_turn()


## Auto-pilot for frame captures: shoot the nearest visible enemy, otherwise end the turn.
func _demo_turn() -> void:
	var targets := enemies().filter(func(e: Unit) -> bool: return combat.in_range(player, e))
	if targets.is_empty() or player.ap < player.weapon.ap:
		combat.end_player_turn()
	else:
		combat.player_attack(targets[0])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			combat.end_player_turn()
		elif event.keycode == KEY_R:
			get_tree().reload_current_scene()
	if not event is InputEventMouse or not player.alive():
		return
	var cell: Variant = _mouse_cell(event.position)
	if cell == null or not grid.is_in_boundsv(cell):
		cursor.visible = false
		hud.show_tooltip("", Vector2.ZERO)
		return
	var target := unit_at(cell)
	var enemy := target if target and target.hostile else null
	var open: bool = not grid.is_point_solid(cell) and target == null
	cursor.visible = true
	cursor.position = Unit.to_world(cell) + Vector3(0, 0.02, 0)
	cursor.material_override.albedo_color = Color(0.3, 1, 0.4, 0.35) if open \
			else Color(1, 0.3, 0.3, 0.35)
	if enemy:
		hud.show_tooltip("%s  %d/%d HP\n%d%% to hit  (%d AP)" % [enemy.display_name, enemy.hp,
				enemy.max_hp, combat.hit_chance(player, enemy), player.weapon.ap], event.position)
	elif combat.active and open:
		hud.show_tooltip("%d AP" % path_for(player, cell, false).size(), event.position)
	else:
		hud.show_tooltip("", Vector2.ZERO)
	var click: bool = event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT
	if combat.active:
		if click and enemy:
			combat.player_attack(enemy)
		elif click and open:
			combat.player_move(cell)
	elif click and enemy:
		await combat.start(true)
		combat.player_attack(enemy)
	elif open and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		# Diablo-style: click or hold the left button to keep walking toward the cursor.
		player.move_to(cell)
