extends Node
## Local save/load. JSON with a version and a checksum, written atomically with a rolling backup.
## Corrupt, truncated or hand-edited files are rejected (falling back to the backup) instead of crashing.

const PATH := "user://savegame.json"
const BACKUP := "user://savegame.bak.json"
const TMP := "user://savegame.tmp.json"
const META := "user://progress_meta.json"

func has_save() -> bool:
	return not _read_valid(PATH).is_empty() or not _read_valid(BACKUP).is_empty()

## Writes the current GameState. Returns true on success.
func save_game() -> bool:
	if not GameState.in_game:
		return false
	var data: Dictionary = GameState.to_save_dict()
	var body := JSON.stringify(data)
	var wrapper := {
		"version": Cfg.SAVE_VERSION,
		"checksum": body.sha256_text(),
		"body": body,
	}
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	if f == null:
		push_warning("SaveSys: cannot open temp file (%s)" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(wrapper))
	f.close()
	# Keep the previous good save as a backup, then promote the new file.
	if FileAccess.file_exists(PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(BACKUP))
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(TMP), ProjectSettings.globalize_path(PATH))
	if err != OK:
		# rename onto an existing file can fail on some platforms: remove then retry
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
		err = DirAccess.rename_absolute(ProjectSettings.globalize_path(TMP), ProjectSettings.globalize_path(PATH))
	return err == OK

## Loads the newest valid save into GameState. Returns false if none is usable.
func load_game() -> bool:
	for p in [PATH, BACKUP]:
		var d := _read_valid(p)
		if not d.is_empty() and GameState.apply_save_dict(d):
			return true
	return false

func delete_save() -> void:
	for p in [PATH, BACKUP, TMP]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	return parse_save_text(text)

## Parses + verifies a save file's text. Public so tests can feed it corrupt data.
func parse_save_text(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var w: Dictionary = parsed
	if int(w.get("version", -1)) != Cfg.SAVE_VERSION:
		return {}
	var body := str(w.get("body", ""))
	if body.sha256_text() != str(w.get("checksum", "")):
		return {}
	var inner: Variant = JSON.parse_string(body)
	if not (inner is Dictionary) or not validate(inner):
		return {}
	return inner

## Structural + range validation of the decoded save body.
func validate(d: Dictionary) -> bool:
	for key in ["snap", "chapter_snap"]:
		if not (d.get(key) is Dictionary):
			return false
		var s: Dictionary = d[key]
		var ch := int(s.get("chapter", 0))
		if ch < 1 or ch > Cfg.CHAPTERS.size():
			return false
		if not (s.get("flags", {}) is Dictionary) or not (s.get("logs", []) is Array) or not (s.get("upgrades", {}) is Dictionary):
			return false
		if not (s.get("checkpoint", "") is String):
			return false
		var frag: Variant = s.get("fragments", 0)
		if not (frag is float or frag is int) or float(frag) < 0.0 or float(frag) > 100000.0:
			return false
		for id in s["upgrades"]:
			if not Cfg.UPGRADES.has(id):
				return false
			var lvl: Variant = s["upgrades"][id]
			if not (lvl is float or lvl is int) or int(lvl) < 0 or int(lvl) > int(Cfg.UPGRADES[id]["max"]):
				return false
	return true

# --- Cross-run metadata (which endings were seen) ---------------------------------------------

func save_meta_only() -> void:
	var f := FileAccess.open(META, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"endings_seen": GameState.endings_seen}))
		f.close()
	if GameState.in_game:
		save_game()

func load_meta() -> void:
	if not FileAccess.file_exists(META):
		return
	var f := FileAccess.open(META, FileAccess.READ)
	if f == null:
		return
	var p: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if p is Dictionary and p.get("endings_seen") is Array:
		for e in p["endings_seen"]:
			if str(e) in ["shutdown", "containment", "reactivation"] and not GameState.endings_seen.has(str(e)):
				GameState.endings_seen.append(str(e))
