class_name RoomBuilder
extends Node3D
## Turns a RoomPresets dictionary into real 3D geometry.
##
## Everything solid gets a StaticBody3D + CollisionShape3D (the Stage 1 code
## created collision bodies without shapes, which did nothing). Decorative
## pieces stay as plain MeshInstance3D nodes so they cost nothing physically.
## Materials are cached by appearance, so 27 items share a handful of resources.

signal room_built(room_id: String, item_count: int)

var current_room_id: String = ""
var window_anchor: Dictionary = {}
var lamp_points: Array = []
var item_count: int = 0

var _materials: Dictionary = {}
var _light_budget: int = 2
var _shadows_enabled: bool = false
var _lights_used: int = 0


## Rebuilds the room from its preset. Returns false for an unknown room id.
func build(room_id: String, quality_level: int = 1) -> bool:
	if not RoomPresets.has_room(room_id):
		push_warning("RoomBuilder: unknown room '%s', falling back to bedroom." % room_id)
		room_id = "bedroom"

	clear_room()

	var preset := QualityPresets.for_level(quality_level)
	_shadows_enabled = bool(preset.get("shadows", false))
	_light_budget = int(preset.get("realtime_lights", 2))
	_lights_used = 0

	var room := RoomPresets.get_room(room_id)
	current_room_id = room_id
	item_count = 0

	var items: Array = room.get("items", [])
	for item in items:
		if item is Dictionary:
			_add_item(item)
			item_count += 1

	room_built.emit(room_id, item_count)
	return true


func clear_room() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	current_room_id = ""
	window_anchor = {}
	lamp_points = []
	item_count = 0


## World position the companion should stand at for the current room.
func companion_position() -> Vector3:
	var room := RoomPresets.get_room(current_room_id if current_room_id != "" else "bedroom")
	var value: Variant = room.get("companion_position", Vector3.ZERO)
	return value if value is Vector3 else Vector3.ZERO


func camera_defaults() -> Dictionary:
	var room := RoomPresets.get_room(current_room_id if current_room_id != "" else "bedroom")
	return {
		"height": float(room.get("camera_height", 1.55)),
		"distance": float(room.get("camera_distance", 3.1)),
	}


# --------------------------------------------------------------------------
# Item construction
# --------------------------------------------------------------------------

func _add_item(item: Dictionary) -> void:
	var node_name := str(item.get("name", "Item"))
	var pos: Vector3 = item.get("pos", Vector3.ZERO) if item.get("pos") is Vector3 else Vector3.ZERO
	var size: Vector3 = item.get("size", Vector3.ONE) if item.get("size") is Vector3 else Vector3.ONE
	var color := Color.from_string(str(item.get("color", "#808080")), Color.GRAY)
	var roughness := float(item.get("roughness", 0.8))
	var metallic := float(item.get("metallic", 0.0))
	var emission := float(item.get("emission", 0.0))
	var collide := bool(item.get("collide", true))

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _make_mesh(str(item.get("shape", "box")), size)
	mesh_instance.material_override = _get_material(color, roughness, metallic, emission)
	mesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _shadows_enabled
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)

	if collide:
		var body := StaticBody3D.new()
		body.name = node_name
		body.position = pos
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		body.add_child(mesh_instance)
		add_child(body)
	else:
		mesh_instance.name = node_name
		mesh_instance.position = pos
		add_child(mesh_instance)

	if bool(item.get("window", false)):
		window_anchor = {"position": pos, "size": size}

	if bool(item.get("lamp", false)):
		lamp_points.append(pos)
		_add_lamp(pos)


func _add_lamp(pos: Vector3) -> void:
	if _lights_used >= _light_budget:
		# The lamp shade still glows via its emissive material; we simply skip
		# the real-time light to stay inside the preset's light budget.
		return
	_lights_used += 1
	var light := OmniLight3D.new()
	light.name = "LampLight%d" % _lights_used
	light.position = pos + Vector3(0, -0.05, 0)
	light.light_color = Color(1.0, 0.86, 0.68)
	light.light_energy = 2.1
	light.omni_range = 5.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = _shadows_enabled and _lights_used <= 1
	add_child(light)


func _make_mesh(shape: String, size: Vector3) -> Mesh:
	match shape:
		"sphere":
			# SphereMesh has no size property, so the scale is baked in.
			return _scaled_sphere(size)
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size.x * 0.5
			cylinder.bottom_radius = size.x * 0.5
			cylinder.height = size.y
			cylinder.radial_segments = 16
			cylinder.rings = 1
			return cylinder
		_:
			var box := BoxMesh.new()
			box.size = size
			return box


func _scaled_sphere(size: Vector3) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 14
	sphere.rings = 7
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		vertices[index] = vertices[index] * size
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in normals.size():
		normals[index] = (normals[index] / size).normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _get_material(color: Color, roughness: float, metallic: float, emission: float) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(false), roughness, metallic, emission]
	if _materials.has(key):
		return _materials[key]

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = clampf(roughness, 0.0, 1.0)
	material.metallic = clampf(metallic, 0.0, 1.0)
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX if _shadows_enabled else BaseMaterial3D.SPECULAR_DISABLED
	if emission > 0.01:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	_materials[key] = material
	return material
