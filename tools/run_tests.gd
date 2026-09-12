extends SceneTree

## Headless test runner for Aetherfold engine suites.
## Usage (from the project root, Godot 4.7 on PATH as `godot`):
##   godot --headless --path . -s res://tools/run_tests.gd
##   godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_stack
##   godot --headless --path . -s res://tools/run_tests.gd -- --suite=engine_stack --test=test_creature


func _initialize() -> void:
	var suite_filter := ""
	var test_filter := ""
	var verbose := false
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--suite="):
			suite_filter = str(arg).substr(8)
		elif str(arg).begins_with("--test="):
			test_filter = str(arg).substr(7)
		elif str(arg) == "--verbose" or str(arg) == "-v":
			verbose = true
	var suites: Array = []
	var errors: PackedStringArray = PackedStringArray()
	_discover("res://tests", suites, errors)
	suites.sort_custom(func(a, b) -> bool:
		return a.suite_name() < b.suite_name()
	)
	if not errors.is_empty():
		print("Discovery errors:")
		for e in errors:
			print("  ", e)
	if suite_filter != "":
		var names := PackedStringArray()
		for s in suites:
			names.append(s.suite_name())
		if not names.has(suite_filter):
			print("No suite named '%s'. Available: %s" % [suite_filter, ", ".join(names)])
			quit(2)
			return
	var runner := McpTestRunner.new()
	var results: Dictionary = runner.run_suites(suites, suite_filter, test_filter, {}, verbose)
	var passed := int(results.get("passed", 0))
	var failed := int(results.get("failed", 0))
	var skipped := int(results.get("skipped", 0))
	var total := int(results.get("total", 0))
	print("Ran %d tests in %d suite(s) (%d ms)" % [
		total,
		int(results.get("suite_count", 0)),
		int(results.get("duration_ms", 0)),
	])
	print("  passed: %d" % passed)
	print("  failed: %d" % failed)
	print("  skipped: %d" % skipped)
	if verbose and results.has("results"):
		for row in results.get("results", []):
			var mark := "ok"
			if bool(row.get("skipped", false)):
				mark = "skip"
			elif not bool(row.get("passed", false)):
				mark = "FAIL"
			print("  [%s] %s.%s" % [mark, str(row.get("suite", "")), str(row.get("test", ""))])
			if mark == "FAIL" and str(row.get("message", "")) != "":
				print("         %s" % str(row.get("message", "")))
	if results.has("failures"):
		print("Failures:")
		for row2 in results.get("failures", []):
			print("  %s.%s: %s" % [
				str(row2.get("suite", "")),
				str(row2.get("test", "")),
				str(row2.get("message", "")),
			])
	quit(1 if failed > 0 else 0)


func _discover(dir_path: String, suites: Array, errors: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		errors.append("cannot open %s" % dir_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == ".." or file_name == "addons":
			file_name = dir.get_next()
			continue
		var path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			_discover(path, suites, errors)
		elif file_name.begins_with("test_") and file_name.ends_with(".gd"):
			var script = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if script == null:
				errors.append("%s failed to load" % path)
			elif script.can_instantiate():
				var instance = script.new()
				if instance is McpTestSuite:
					suites.append(instance)
				else:
					errors.append("%s is not an McpTestSuite" % path)
		file_name = dir.get_next()
