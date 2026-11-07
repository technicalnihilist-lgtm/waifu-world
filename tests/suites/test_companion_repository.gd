extends TestCase
## CompanionRepository: CRUD, persistence across restarts, recovery, isolation.

var _dir: String = ""
var _repo: CompanionRepository


func before() -> void:
	_dir = TestCase.temp_dir("repo")
	_repo = CompanionRepository.new()
	_repo.root_dir = _dir


func after() -> void:
	_repo.free()
	TestCase.purge_dir(_dir)


func run(_tree: SceneTree) -> void:
	await _tree.process_frame

	# --- first launch seeds a default companion ---------------------------
	check(_repo.load_from_disk(), "first load reports success")
	equal(_repo.count(), 1, "first launch seeds exactly one companion")
	var seeded := _repo.get_active()
	not_null(seeded, "seeded companion becomes active")
	equal(seeded.display_name, CompanionRepository.SEED_NAME, "seeded companion uses the default name")
	check(FileAccess.file_exists(_repo.storage_path()), "seeded profile is written to disk immediately")

	# --- create / select / delete ----------------------------------------
	var second := _repo.create_profile("Nova", {"personality": "witty", "language": "hi"})
	not_null(second, "create_profile returns the new profile")
	equal(_repo.count(), 2, "profile count grows")
	equal(_repo.get_active_id(), seeded.id, "creating a profile does not steal focus")
	check(_repo.set_active(second.id), "set_active accepts a known id")
	equal(_repo.get_active_id(), second.id, "active profile changed")
	check(not _repo.set_active("cmp_missing"), "set_active rejects an unknown id")

	equal(_repo.get_profile(second.id).personality, "witty", "patch applied on create")
	equal(_repo.get_profile(second.id).language, "hi", "language patch applied on create")

	# --- persistence across a simulated restart ---------------------------
	var reloaded := CompanionRepository.new()
	reloaded.root_dir = _dir
	check(reloaded.load_from_disk(), "reload reports success")
	equal(reloaded.count(), 2, "both profiles survive a restart")
	equal(reloaded.get_active_id(), second.id, "active selection survives a restart")
	equal(reloaded.get_profile(second.id).display_name, "Nova", "profile data survives a restart")
	reloaded.free()

	# --- updates persist --------------------------------------------------
	check(_repo.update_profile(second.id, {"display_name": "Nova Prime", "appearance": {"hair_style": "bob"}}), "update_profile succeeds")
	equal(_repo.get_profile(second.id).display_name, "Nova Prime", "updated name stored")
	equal(_repo.get_profile(second.id).hair_style(), "bob", "updated appearance stored")
	check(not _repo.update_profile("cmp_missing", {"display_name": "Ghost"}), "update_profile rejects unknown ids")
	check(not _repo.update_profile(second.id, {"display_name": "   "}), "update_profile rejects blank names")

	# --- unique names -----------------------------------------------------
	var twin := _repo.create_profile("Nova Prime")
	not_null(twin, "second Nova Prime is accepted")
	equal(twin.display_name, "Nova Prime (2)", "duplicate names get a numeric suffix")
	var blank := _repo.create_profile("    ")
	is_null(blank, "blank name is rejected")

	# --- deleting the active profile moves focus --------------------------
	var active_before := _repo.get_active_id()
	check(_repo.delete_profile(active_before), "delete_profile succeeds")
	check(not _repo.has_profile(active_before), "deleted profile is gone")
	check(not _repo.get_active_id().is_empty(), "another profile becomes active automatically")
	check(_repo.has_profile(_repo.get_active_id()), "the new active profile really exists")
	check(not _repo.delete_profile("cmp_missing"), "delete_profile rejects unknown ids")

	# --- profile limit ----------------------------------------------------
	var created := 0
	while _repo.can_create_more():
		if _repo.create_profile("Fill %d" % created) != null:
			created += 1
		else:
			break
	equal(_repo.count(), CompanionRepository.MAX_PROFILES, "repository fills to its limit")
	check(not _repo.can_create_more(), "can_create_more turns false at the limit")
	is_null(_repo.create_profile("Overflow"), "creating past the limit returns null")

	# --- signals ----------------------------------------------------------
	var change_count := [0]
	var listener := func() -> void: change_count[0] += 1
	_repo.profiles_changed.connect(listener)
	_repo.create_profile("Signalled")
	_repo.update_profile(_repo.get_active_id(), {"display_name": "Signalled Two"})
	check(change_count[0] >= 1, "profiles_changed fires on mutation")
	_repo.profiles_changed.disconnect(listener)

	# --- delete everything ------------------------------------------------
	check(_repo.delete_all_profiles(), "delete_all_profiles succeeds")
	equal(_repo.count(), 0, "all profiles removed")
	equal(_repo.get_active_id(), "", "no active id after deleting everything")
	is_null(_repo.get_active(), "get_active returns null on an empty store")

	var empty_reload := CompanionRepository.new()
	empty_reload.root_dir = _dir
	empty_reload.load_from_disk()
	equal(empty_reload.count(), 0, "an empty store stays empty after a restart")
	empty_reload.free()


	# --- corrupt save file recovery ---------------------------------------
	var corrupt_dir := TestCase.temp_dir("repo_corrupt")
	var corrupt_repo := CompanionRepository.new()
	corrupt_repo.root_dir = corrupt_dir
	DirAccess.make_dir_recursive_absolute(corrupt_dir)
	TestCase.write_text(corrupt_repo.storage_path(), "}{ broken json")
	corrupt_repo.load_from_disk()
	check(corrupt_repo.recovered_from_corruption, "corrupt save is flagged as recovered")
	equal(corrupt_repo.count(), 1, "corrupt save falls back to one seeded companion")
	check(not corrupt_repo.last_error.is_empty(), "recovery leaves an explanatory message")
	var backups := _find_backups(corrupt_dir)
	check(backups.size() >= 1, "the damaged file is backed up, not destroyed")
	corrupt_repo.free()
	TestCase.purge_dir(corrupt_dir)

	# --- one bad entry does not kill the rest ------------------------------
	var partial_dir := TestCase.temp_dir("repo_partial")
	var partial_repo := CompanionRepository.new()
	partial_repo.root_dir = partial_dir
	DirAccess.make_dir_recursive_absolute(partial_dir)
	var good := CompanionProfile.create_new("Good One").to_dict()
	var payload := {
		"schema": 1,
		"active_id": "cmp_good",
		"profiles": [
			"this is not a dictionary",
			good,
			{"id": "cmp_good", "display_name": "Duplicate Id"},
			{"display_name": "No Id At All"},
		],
	}
	JsonFile.write_atomic(partial_repo.storage_path(), payload)
	partial_repo.load_from_disk()
	equal(partial_repo.count(), 3, "malformed entries are skipped, valid ones load")
	var unique_ids := {}
	for profile in partial_repo.list_profiles():
		unique_ids[profile.id] = true
	equal(unique_ids.size(), 3, "duplicate ids are repaired on load")
	partial_repo.free()
	TestCase.purge_dir(partial_dir)

	# --- profile data isolation -------------------------------------------
	var isolation_dir := TestCase.temp_dir("repo_isolation")
	var isolation := CompanionRepository.new()
	isolation.root_dir = isolation_dir
	isolation.load_from_disk()
	var first := isolation.get_active()
	var other := isolation.create_profile("Other", {"appearance": {"hair_color": "#2f5a6b"}})
	isolation.update_profile(first.id, {"appearance": {"hair_color": "#c8a35b"}})
	equal(isolation.get_profile(first.id).appearance["hair_color"], "#c8a35b", "first profile keeps its own colour")
	equal(isolation.get_profile(other.id).appearance["hair_color"], "#2f5a6b", "second profile keeps its own colour")
	check(isolation.get_profile(first.id).id != isolation.get_profile(other.id).id, "profiles have distinct ids")
	isolation.free()
	TestCase.purge_dir(isolation_dir)


func _find_backups(dir_path: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.contains(".corrupt-"):
			found.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
