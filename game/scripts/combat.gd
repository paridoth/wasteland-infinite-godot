extends Node
## Fallout-style turn-based combat. The player's side and the enemies' side alternate; each
## unit spends action points on moving (1 per cell) and attacking (the weapon's AP cost).

signal changed

const Unit := preload("res://scripts/unit.gd")
const SIGHT := 7.0  ## Cells within which an enemy with line of sight notices the player.
const LEASH := 14.0  ## Combat ends once no living enemy is this close.

var main: Node3D  # main.gd; untyped to avoid a preload cycle.
var active := false
var busy := false
var player_turn := false
var rng := RandomNumberGenerator.new()


func start(player_first: bool) -> void:
	if active:
		return
	active = true
	var player: Unit = main.player
	player.halt()
	if player.moving():
		await player.arrived
	main.log_line("[ Combat ]")
	if player_first:
		_begin_player_turn()
	else:
		await _enemy_phase()


func hit_chance(attacker: Unit, target: Unit) -> int:
	var distance := Vector2(attacker.cell).distance_to(Vector2(target.cell))
	return clampi(attacker.skill - target.armor_class * 2 - roundi(3 * distance), 5, 95)


func in_range(attacker: Unit, target: Unit) -> bool:
	return Vector2(attacker.cell).distance_to(Vector2(target.cell)) <= attacker.weapon.range \
			and main.sees(attacker.cell, target.cell)


func player_move(target: Vector2i) -> void:
	var player: Unit = main.player
	if not player_turn or busy:
		return
	var route: Array[Vector2i] = main.path_for(player, target, false)
	if route.is_empty():
		return
	route = route.slice(0, player.ap)
	player.ap -= route.size()
	busy = true
	player.walk(route)
	await player.arrived
	busy = false
	_after_player_action()


func player_attack(target: Unit) -> void:
	var player: Unit = main.player
	if not player_turn or busy:
		return
	if player.ap < player.weapon.ap:
		main.log_line("Not enough action points.")
	elif not in_range(player, target):
		main.log_line("%s is out of range." % target.display_name)
	else:
		await attack(player, target)
		_after_player_action()


func end_player_turn() -> void:
	if not player_turn or busy:
		return
	player_turn = false
	changed.emit()
	await _enemy_phase()


func _after_player_action() -> void:
	changed.emit()
	if _should_end():
		_finish()
	elif main.player.ap <= 0:
		end_player_turn()


func _begin_player_turn() -> void:
	main.player.ap = main.player.max_ap
	player_turn = true
	changed.emit()


func _enemy_phase() -> void:
	for enemy: Unit in main.enemies():
		if not main.player.alive():
			return
		if Vector2(enemy.cell).distance_to(Vector2(main.player.cell)) <= LEASH:
			await _enemy_turn(enemy)
	if not main.player.alive():
		active = false
		changed.emit()
	elif _should_end():
		_finish()
	else:
		_begin_player_turn()


## Simple melee brain: close the distance, then attack while AP allows.
func _enemy_turn(enemy: Unit) -> void:
	var player: Unit = main.player
	enemy.ap = enemy.max_ap
	while enemy.alive() and player.alive():
		if in_range(enemy, player):
			if enemy.ap < enemy.weapon.ap:
				break
			await attack(enemy, player)
			continue
		var route: Array[Vector2i] = main.path_for(enemy, player.cell, true)
		route = route.slice(0, enemy.ap)
		if route.is_empty():
			break
		enemy.ap -= route.size()
		enemy.walk(route)
		await enemy.arrived
	await get_tree().create_timer(0.15).timeout


func attack(attacker: Unit, target: Unit) -> void:
	busy = true
	attacker.ap -= attacker.weapon.ap
	attacker.face(target.cell)
	var chance := hit_chance(attacker, target)
	await _attack_effect(attacker, target)
	var roll := rng.randi_range(1, 100)
	if roll <= chance:
		var damage := rng.randi_range(attacker.weapon.min, attacker.weapon.max)
		var critical := roll <= 5
		if critical:
			damage *= 2
		target.take_damage(damage)
		changed.emit()
		main.float_text(target, str(damage) + ("!" if critical else ""), Color(1, 0.3, 0.2))
		var verb := "critically hit" if critical else "hit"
		main.log_line("%s %s %s for %d damage%s." % [attacker.display_name,
				verb if attacker.is_player else verb + "s", _object(target), damage,
				"" if target.alive() else (", killing " + ("you" if target.is_player else "it"))])
	else:
		main.float_text(target, "Miss", Color(0.8, 0.8, 0.8))
		main.log_line("%s %s %s." % [attacker.display_name,
				"miss" if attacker.is_player else "misses", _object(target)])
	await get_tree().create_timer(0.25).timeout
	busy = false
	changed.emit()


func _object(unit: Unit) -> String:
	return "you" if unit.is_player else "the " + unit.display_name


func _attack_effect(attacker: Unit, target: Unit) -> void:
	if attacker.weapon.range > 2.0:
		var from := attacker.position + Vector3(0, 1.1, 0) + attacker.basis.z * 0.4
		var to := target.position + Vector3(0, 1.0, 0)
		var tracer := MeshInstance3D.new()
		var beam := BoxMesh.new()
		beam.size = Vector3(0.03, 0.03, from.distance_to(to))
		tracer.mesh = beam
		tracer.material_override = main.unlit(Color(1, 0.85, 0.4, 0.9))
		main.add_child(tracer)
		tracer.look_at_from_position((from + to) / 2, to)
		var flash := OmniLight3D.new()
		flash.light_color = Color(1, 0.8, 0.4)
		flash.light_energy = 4.0
		flash.omni_range = 5.0
		flash.position = from
		main.add_child(flash)
		await get_tree().create_timer(0.08).timeout
		tracer.queue_free()
		flash.queue_free()
	else:
		var lunge := create_tween()
		var reach := (target.position - attacker.position).normalized() * 0.45
		lunge.tween_property(attacker.model, "position", attacker.basis.inverse() * reach, 0.12)
		lunge.tween_property(attacker.model, "position", Vector3.ZERO, 0.15)
		await lunge.finished


func _should_end() -> bool:
	for enemy: Unit in main.enemies():
		if Vector2(enemy.cell).distance_to(Vector2(main.player.cell)) <= LEASH:
			return false
	return true


func _finish() -> void:
	active = false
	player_turn = false
	main.log_line("[ Combat over ]")
	changed.emit()
