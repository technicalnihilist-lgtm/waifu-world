extends TestCase
## Integration test: boots the real main scene and drives the real UI paths.

var _main: Node3D


func run(tree: SceneTree) -> void:
	await tree.process_frame

	var packed: PackedScene = load("res://scenes/main.tscn")
	not_null(packed, "main scene loads")
	if packed == null:
		return

	_main = packed.instantiate() as Node3D
	not_null(_main, "main scene instantiates")
	if _main == null:
		return

	tree.root.add_child(_main)
	await tree.process_frame
	await tree.process_frame

	# --- scene wiring -----------------------------------------------------
	not_null(_main.room_builder, "room builder is wired")
	not_null(_main.lighting, "lighting controller is wired")
	not_null(_main.camera_rig, "camera rig is wired")
	not_null(_main.avatar_loader, "avatar loader is wired")
	not_null(_main.hud, "HUD is created")
	not_null(_main.screens, "screen manager is created")

	# --- room -------------------------------------------------------------
	check(_main.room_builder.item_count >= 15, "room built a full set of furniture")
	check(_main.room_builder.get_child_count() >= 10, "room nodes are in the tree")
	var solid_bodies := _count_type(_main.room_builder, "StaticBody3D")
	check(solid_bodies >= 10, "solid furniture has collision bodies")
	var shapes := _count_type(_main.room_builder, "CollisionShape3D")
	equal(shapes, solid_bodies, "every collision body has a shape")

	# --- lighting ---------------------------------------------------------
	not_null(_main.lighting.world_environment, "world environment exists")
	not_null(_main.lighting.sun, "directional light exists")
	check(_main.lighting.sun is DirectionalLight3D, "sun is a directional light")
	not_null(_main.lighting.environment, "environment resource exists")
	check(_main.lighting.hours >= 0.0 and _main.lighting.hours <= 24.0, "time of day is in range")

	# --- camera -----------------------------------------------------------
	not_null(_main.camera_rig.camera, "camera exists")
	check(_main.camera_rig.camera.current, "camera is the active one")
	check(_main.camera_rig.camera.global_position.z > 0.5, "camera sits in front of the companion")
	check(_main.camera_rig.camera.global_position.y > 0.3, "camera stays above the floor")

	# --- companion --------------------------------------------------------
	not_null(_main.avatar_loader.current, "an avatar is loaded")
	check(_main.avatar is ProceduralAvatar, "the built-in placeholder is used when no GLB is installed")
	check(_main.avatar_loader.used_fallback, "fallback is reported to the UI")
	equal(_main.avatar_loader.capabilities.get("kind", ""), "procedural", "capabilities reach the settings screen")

	# --- framing (this environment has no display server, so the camera
	# composition is verified geometrically instead of by pixels) -----------
	var head_position: Vector3 = _main.avatar.head_global_position()
	check(
		_main.camera_rig.camera.is_position_in_frustum(head_position),
		"the companion's head is inside the camera frustum"
	)
	var avatar_bounds := _avatar_bounds(_main.avatar)
	check(
		avatar_bounds.size.y > 1.3 and avatar_bounds.size.y < 2.2,
		"avatar is human scale (%.2f m tall)" % avatar_bounds.size.y
	)
	check(avatar_bounds.size.y > avatar_bounds.size.x * 1.5, "avatar is clearly taller than wide")
	check(
		avatar_bounds.position.y > -0.2 and avatar_bounds.position.y < 0.2,
		"avatar feet rest on the floor (lowest point %.2f m)" % avatar_bounds.position.y
	)
	check(
		absf(_main.avatar.global_position.x) < 1.5 and absf(_main.avatar.global_position.z) < 1.5,
		"companion stands inside the room, not in a wall"
	)

	# --- HUD actions ------------------------------------------------------
	_main._on_wave_pressed()
	await tree.process_frame
	_main._on_talk_pressed()
	await tree.process_frame

	# --- graphics presets -------------------------------------------------
	_main._on_quality_changed(0)
	await tree.process_frame
	check(not _main.lighting.sun.shadow_enabled, "low quality disables shadows")
	check(_main.room_builder.item_count >= 15, "room survives a quality change")

	_main._on_quality_changed(2)
	await tree.process_frame
	check(_main.lighting.sun.shadow_enabled, "high quality enables shadows")
	equal(AppSettings.quality_level(), 2, "quality choice is persisted")

	# --- time of day ------------------------------------------------------
	_main._on_time_changed(12.0)
	await tree.process_frame
	approx(_main.lighting.get_time_of_day(), 12.0, 0.01, "time of day applied to lighting")
	approx(AppSettings.time_of_day(), 12.0, 0.01, "time of day persisted")

	# --- rooms ------------------------------------------------------------
	_main._on_room_changed("living_room")
	await tree.process_frame
	equal(_main.room_builder.current_room_id, "living_room", "room switched")
	check(_main.room_builder.item_count >= 15, "living room built")
	_main._on_room_changed("bedroom")
	await tree.process_frame
	equal(_main.room_builder.current_room_id, "bedroom", "room switched back")

	# --- camera controls --------------------------------------------------
	_main._on_camera_distance_changed(4.0)
	await tree.process_frame
	approx(AppSettings.camera_distance(), 4.0, 0.01, "camera distance persisted")
	_main._on_reset_view()
	await tree.process_frame

	# --- screens ----------------------------------------------------------
	var characters_screen: Control = _main.screens.open("characters")
	not_null(characters_screen, "character select opens")
	equal(_main.screens.current_id(), "characters", "character select is on top")
	await tree.process_frame
	_main.screens.close_top()
	await tree.process_frame
	check(not _main.screens.is_open(), "character select closes")

	var settings_screen: Control = _main.screens.open("settings", {
		"quality_level": AppSettings.quality_level(),
		"time_of_day": 12.0,
		"auto_cycle": false,
		"room_id": "bedroom",
		"camera_distance": 4.0,
		"capabilities": _main.avatar_loader.capabilities,
		"avatar_notice": "",
	})
	not_null(settings_screen, "settings opens")
	check(settings_screen.has_signal("quality_changed"), "settings exposes its signals")
	await tree.process_frame
	_main.screens.close_top()
	await tree.process_frame

	# --- companion management through the real repository -----------------
	var before_count := Companions.count()
	var created := Companions.create_profile("Integration Test")
	not_null(created, "a companion can be created from the running app")
	await tree.process_frame
	equal(Companions.count(), before_count + 1, "companion count grew")
	check(_main.avatar_loader.current != null, "avatar reloaded for the new active companion")

	var editor_screen: Control = _main.screens.open("editor", {"profile_id": created.id})
	not_null(editor_screen, "editor opens for an existing profile")
	await tree.process_frame
	_main.screens.close_top()
	await tree.process_frame

	check(Companions.delete_profile(created.id), "the test companion can be deleted")
	await tree.process_frame
	check(_main.avatar_loader.current != null or Companions.count() == 0, "avatar state is consistent after deletion")

	# --- shutdown ---------------------------------------------------------
	_main.queue_free()
	await tree.process_frame
	await tree.process_frame


func _avatar_bounds(node: Node3D) -> AABB:
	var combined := AABB()
	var first := true
	for mesh_instance in _find_meshes(node):
		var box: AABB = mesh_instance.get_aabb()
		box = mesh_instance.global_transform * box
		if first:
			combined = box
			first = false
		else:
			combined = combined.merge(box)
	return combined


func _find_meshes(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_meshes(child))
	return found


func _count_type(node: Node, class_name_to_find: String) -> int:
	var total := 0
	if node.is_class(class_name_to_find):
		total += 1
	for child in node.get_children():
		total += _count_type(child, class_name_to_find)
	return total
