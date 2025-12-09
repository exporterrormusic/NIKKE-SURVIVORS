@tool
extends SceneTree

func _init():
	var enemy = CharacterBody2D.new()
	enemy.name = "ModularRapture"
	enemy.set_script(load("res://scripts/enemies/modular/ModularEnemy.gd"))
	
	# Components
	var health = Node.new()
	health.name = "HealthComponent"
	health.set_script(load("res://scripts/components/HealthComponent.gd"))
	enemy.add_child(health)
	health.owner = enemy
	
	var movement = Node.new()
	movement.name = "MovementComponent"
	movement.set_script(load("res://scripts/components/MovementComponent.gd"))
	enemy.add_child(movement)
	movement.owner = enemy
	
	var hitbox = Area2D.new()
	hitbox.name = "HitboxComponent"
	hitbox.set_script(load("res://scripts/components/HitboxComponent.gd"))
	enemy.add_child(hitbox)
	hitbox.owner = enemy
	
	var col = CollisionShape2D.new()
	col.name = "CollisionShape2D"
	col.shape = CircleShape2D.new()
	col.shape.radius = 20
	hitbox.add_child(col)
	col.owner = enemy
	
	# Visuals
	var visuals = Node2D.new()
	visuals.name = "Visuals"
	enemy.add_child(visuals)
	visuals.owner = enemy
	
	var sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	# Using generic icon or existing enemy sprite
	sprite.texture = load("res://assets/enemies/rapture-basic/sprite.png")
	visuals.add_child(sprite)
	sprite.owner = enemy
	
	var scene = PackedScene.new()
	scene.pack(enemy)
	ResourceSaver.save(scene, "res://scenes/enemies/ModularRapture.tscn")
	print("ModularRapture.tscn created.")
	quit()
