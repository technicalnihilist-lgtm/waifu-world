extends TestCase
## Avatar system: procedural face rig, catalog discovery, loader fallback.

var _avatar: ProceduralAvatar
var _loader: AvatarLoader
var _avatar_dir: String = ""


func before() -> void:
	_avatar_dir = TestCase.temp_dir("avatars")


func after() -> void:
	TestCase.purge_dir(_avatar_dir)


func run(tree: SceneTree) -> void:
	await tree.process_frame

	# --- procedural avatar builds ----------------------------------------
	_avatar = ProceduralAvatar.new()
	tree.root.add_child(_avatar)
	await tree.process_frame

	check(_avatar.get_child_count() > 0, "avatar builds a node hierarchy")
	var default_caps := _avatar.get_capabilities()
	equal(str(default_caps["kind"]), "procedural", "capabilities report a procedural model")
	check(not bool(default_caps["rigged"]), "procedural avatar honestly reports no skeleton")
	check(not bool(default_caps["blendshapes"]), "procedural avatar honestly reports no blendshapes")
	check((default_caps["expressions"] as Array).has("smile"), "smile expression is available")
	check((default_caps["gestures"] as Array).has("wave"), "wave gesture is available")
	equal(str(default_caps["lip_sync"]), "amplitude", "lip sync is amplitude driven")

	# --- appearance -------------------------------------------------------
	var profile := CompanionProfile.create_new("Test")
	profile.apply_patch({
		"appearance": {"hair_style": "twin_tails", "skin_tone": "#7a4c33", "hair_color": "#c8a35b"},
		"clothing": {"outfit": "gown", "primary_color": "#3f9b7a"},
	})
	_avatar.apply_profile(profile)
	await tree.process_frame
	check(_avatar.get_child_count() > 0, "avatar rebuilds for a new profile")
	approx(_avatar._skin_mat.albedo_color.r, Color.from_string("#7a4c33", Color.BLACK).r, 0.01, "skin colour applied to material")
	approx(_avatar._hair_mat.albedo_color.g, Color.from_string("#c8a35b", Color.BLACK).g, 0.01, "hair colour applied to material")
	approx(_avatar._outfit_mat.albedo_color.g, Color.from_string("#3f9b7a", Color.BLACK).g, 0.01, "outfit colour applied to material")

	var hair_nodes := _count_named(_avatar, "Tail")
	check(hair_nodes >= 2, "twin tails add their own geometry")

	# --- height scale -----------------------------------------------------
	var tall := CompanionProfile.create_new("Tall")
	tall.apply_patch({"appearance": {"height_scale": 1.1}})
	_avatar.apply_profile(tall)
	await tree.process_frame
	approx(_avatar._body.scale.y, 1.1, 0.001, "height scale is applied to the body")

	# --- expressions ------------------------------------------------------
	_avatar.set_expression("smile")
	equal(_avatar.current_expression(), "smile", "smile expression is selected")
	_avatar.set_expression("not_a_real_expression")
	equal(_avatar.current_expression(), "neutral", "unknown expressions fall back to neutral")

	# --- blink regression (the Stage 1 build scaled eyes to a fixed value) --
	_avatar.set_expression("neutral")
	_avatar._blink_progress = -1.0
	_avatar._blink_timer = 0.0
	_avatar._update_blink(0.016)
	check(_avatar._blink_progress >= 0.0, "blink starts when the timer expires")
	_avatar._update_blink(0.10)
	check(_avatar._blink_amount() > 0.9, "blink reaches a closed state")
	_avatar._apply_face(1.0)
	check(_avatar._eye_l.scale.y < 0.25, "blinking squashes the eye instead of growing it")
	check(_avatar._eye_l.scale.y > 0.0, "blinking keeps the eye above zero scale")
	check(_avatar._lid_l.position.y < 0.030, "the eyelid slides down when blinking")

	# --- mouth / lip sync -------------------------------------------------
	_avatar._face["open"] = 0.0
	_avatar._face["curve"] = 0.0
	_avatar._apply_face(1.0)
	var closed_height: float = _avatar._mouth.scale.y
	_avatar.set_talking(1.0)
	_avatar._face["open"] = 1.0
	_avatar._apply_face(1.0)
	check(_avatar._mouth.scale.y > closed_height * 1.5, "talking opens the mouth mesh")
	_avatar.set_talking(0.0)
	_avatar._update_face(1.0)
	check(not _avatar.is_talking(), "talking stops when the amplitude returns to zero")

	# --- gestures ---------------------------------------------------------
	check(_avatar.play_gesture("wave"), "wave gesture is accepted")
	check(_avatar.play_gesture("nod"), "nod gesture is accepted")
	check(not _avatar.play_gesture("backflip"), "unknown gestures are rejected")

	# --- look at ----------------------------------------------------------
	_avatar.set_look_at(Vector3(2.0, 1.6, 3.0))
	await tree.process_frame
	check(_avatar.head_global_position().y > 1.0, "head sits above the floor")

	# --- quality / LOD ----------------------------------------------------
	var nodes_low := 0
	_avatar.set_quality(0)
	await tree.process_frame
	nodes_low = _count_meshes(_avatar)
	_avatar.set_quality(3)
	await tree.process_frame
	var nodes_ultra := _count_meshes(_avatar)
	equal(nodes_low, nodes_ultra, "LOD keeps the same node count, only mesh density changes")

	_avatar.queue_free()
	await tree.process_frame

	# --- catalog: file detection -----------------------------------------
	check(AvatarCatalog.is_supported_file("mira.glb"), "glb is a supported extension")
	check(AvatarCatalog.is_supported_file("MIRA.GLB"), "extension matching is case insensitive")
	check(AvatarCatalog.is_supported_file("mira.gltf"), "gltf is a supported extension")
	check(not AvatarCatalog.is_supported_file("mira.png"), "png is not an avatar file")

	# --- catalog: bundled manifest (ships empty) --------------------------
	var bundled := AvatarCatalog.list_bundled()
	equal(bundled.size(), 0, "the bundled manifest ships with no third-party avatars")
	equal(AvatarCatalog.find_by_id("").size(), 0, "empty avatar id finds nothing")
	equal(AvatarCatalog.find_by_id("nope").size(), 0, "unknown avatar id finds nothing")

	# --- catalog: missing file -------------------------------------------
	var missing := AvatarCatalog.descriptor_for(_avatar_dir.path_join("ghost.glb"))
	check(not bool(missing["valid"]), "missing avatar files are marked invalid")
	check(not str(missing["problem"]).is_empty(), "invalid avatars explain the problem")

	# --- catalog: user installed file + sidecar ---------------------------
	var user_avatar := _avatar_dir.path_join("nova.glb")
	TestCase.write_text(user_avatar, "not really a glb")
	var plain := AvatarCatalog.descriptor_for(user_avatar)
	check(bool(plain["valid"]), "an existing .glb is listed as valid")
	check(not bool(plain["has_manifest"]), "a file without a sidecar has no manifest")
	equal(str(plain["id"]), "nova", "avatar id comes from the file name")

	TestCase.write_text(_avatar_dir.path_join("nova.json"), JSON.stringify({
		"display_name": "Nova",
		"author": "Test Artist",
		"license": "CC0",
		"height_meters": 1.72,
		"idle_animation": "Idle",
	}))
	var with_sidecar := AvatarCatalog.descriptor_for(user_avatar)
	check(bool(with_sidecar["has_manifest"]), "sidecar manifest is detected")
	equal(str(with_sidecar["display_name"]), "Nova", "sidecar display name is used")
	equal(str(with_sidecar["author"]), "Test Artist", "sidecar author is used")
	approx(float(with_sidecar["height_meters"]), 1.72, 0.001, "sidecar height is used")

	var listed := AvatarCatalog.list_user_installed(_avatar_dir)
	equal(listed.size(), 1, "user avatar directory is scanned")

	# --- loader fallback --------------------------------------------------
	_loader = AvatarLoader.new()
	tree.root.add_child(_loader)
	await tree.process_frame

	var placeholder_profile := CompanionProfile.create_new("Fallback")
	var avatar_node := _loader.load_for_profile(placeholder_profile, 1)
	not_null(avatar_node, "loader always returns an avatar node")
	check(_loader.used_fallback, "loader reports the fallback when no GLB is selected")
	check(avatar_node is ProceduralAvatar, "fallback avatar is the procedural model")
	check(avatar_node.has_method("set_expression") and avatar_node.has_method("play_gesture"), "avatar API is complete")
	equal(str(_loader.capabilities["kind"]), "procedural", "loader reports procedural capabilities")

	var missing_profile := CompanionProfile.create_new("Missing Avatar")
	missing_profile.apply_patch({"appearance": {"avatar_id": "does_not_exist"}})
	avatar_node = _loader.load_for_profile(missing_profile, 1)
	check(_loader.used_fallback, "loader falls back for an unknown avatar id")
	check(_loader.fallback_reason.contains("not installed"), "fallback reason names the missing avatar")
	not_null(avatar_node, "a fallback avatar is still returned")

	var broken_profile := CompanionProfile.create_new("Broken Avatar")
	broken_profile.apply_patch({"appearance": {"avatar_id": "nova"}})
	# 'nova' only exists in the temp directory, not in user://avatars, so the
	# loader must report it as not installed rather than crash.
	avatar_node = _loader.load_for_profile(broken_profile, 1)
	check(_loader.used_fallback, "uninstalled avatars fall back safely")
	not_null(avatar_node, "fallback still yields a usable avatar")

	_loader.queue_free()
	await tree.process_frame


func _count_named(node: Node, fragment: String) -> int:
	var total := 0
	if node.name.to_lower().contains(fragment.to_lower()):
		total += 1
	for child in node.get_children():
		total += _count_named(child, fragment)
	return total


func _count_meshes(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		total += 1
	for child in node.get_children():
		total += _count_meshes(child)
	return total
