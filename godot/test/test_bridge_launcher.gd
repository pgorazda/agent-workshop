extends GutTest
## The helpers of the bridge launcher and the saved setting. The process itself is checked by tools/launcher.test.mjs.

const BridgeLauncher := preload("res://src/net/bridge_launcher.gd")
const BridgeSettings := preload("res://src/net/bridge_settings.gd")
const Options := preload("res://src/core/options.gd")


func test_an_address_on_this_computer_is_local() -> void:
	for url: String in ["ws://127.0.0.1:8787/ws", "ws://localhost:9000/ws", "ws://[::1]:8787/ws", "ws://127.0.0.1/ws"]:
		assert_true(BridgeLauncher.parse_address(url)["local"], url)
	var plain: Dictionary = BridgeLauncher.parse_address("ws://127.0.0.1:8787/ws")
	assert_eq([plain["host"], plain["port"]], ["127.0.0.1", 8787])
	assert_eq(BridgeLauncher.parse_address("ws://localhost/ws")["port"], 80)
	assert_eq(BridgeLauncher.parse_address("ws://[::1]:9001/ws")["port"], 9001)
	assert_eq(BridgeLauncher.parse_address("ws://[::1]:9001/ws")["host"], "::1")


func test_other_addresses_are_not_local() -> void:
	for url: String in ["ws://example.test:8787/ws", "ws://192.168.1.5:8787/ws", "ws://0.0.0.0:8787/ws", "wss://127.0.0.1:8787/ws", "wss://localhost/ws", "ws://127.0.0.1.example.test/ws", "ws://127.0.0.1:99999/ws", "ws://127.0.0.1:abc/ws"]:
		assert_false(BridgeLauncher.parse_address(url)["local"], url)


func test_the_program_name_follows_the_system() -> void:
	assert_eq(BridgeLauncher.program_name("Windows"), "agent-workshop-bridge.exe")
	assert_eq(BridgeLauncher.program_name("Linux"), "agent-workshop-bridge")
	assert_eq(BridgeLauncher.program_name("macOS"), "agent-workshop-bridge")


func test_a_configured_path_is_the_only_candidate() -> void:
	assert_eq(BridgeLauncher.candidate_paths("/opt/bridge", "/app", "/usr/bin", "Linux"), PackedStringArray(["/opt/bridge"]))


func test_candidates_are_next_to_the_app_then_on_the_path() -> void:
	assert_eq(
		BridgeLauncher.candidate_paths("", "/app", "/usr/bin:/opt/bin", "Linux"),
		PackedStringArray(["/app/agent-workshop-bridge", "/usr/bin/agent-workshop-bridge", "/opt/bin/agent-workshop-bridge"]),
	)
	assert_eq(
		BridgeLauncher.candidate_paths("", "C:/app", "C:/tools;D:/more", "Windows"),
		PackedStringArray(["C:/app/agent-workshop-bridge.exe", "C:/tools/agent-workshop-bridge.exe", "D:/more/agent-workshop-bridge.exe"]),
	)
	var mac: PackedStringArray = BridgeLauncher.candidate_paths("", "/Apps/Agent Workshop.app/Contents/MacOS", "", "macOS")
	assert_eq(mac, PackedStringArray(["/Apps/Agent Workshop.app/Contents/MacOS/agent-workshop-bridge", "/Apps/agent-workshop-bridge"]))


func test_the_first_existing_candidate_is_found() -> void:
	var dir: String = ProjectSettings.globalize_path("user://launcher_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var file: String = dir.path_join("a-program")
	var handle := FileAccess.open(file, FileAccess.WRITE)
	handle.store_string("x")
	handle.close()
	assert_eq(BridgeLauncher.find_program(PackedStringArray([dir.path_join("missing"), file, "/also/missing"])), file)
	assert_eq(BridgeLauncher.find_program(PackedStringArray([dir.path_join("missing")])), "")
	assert_eq(BridgeLauncher.find_program(PackedStringArray()), "")
	DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(dir)


func test_the_arguments_keep_the_bridge_on_the_loopback_address() -> void:
	assert_eq(
		BridgeLauncher.serve_arguments("127.0.0.1", 9000),
		PackedStringArray(["serve", "--host", "127.0.0.1", "--port", "9000", "--exit-when-stdin-closes"]),
	)
	assert_eq(BridgeLauncher.serve_arguments("::1", 9000)[2], "::1")


func test_the_loopback_host_follows_the_address_and_the_health_address_matches() -> void:
	assert_eq(BridgeLauncher.loopback_host("::1"), "::1")
	assert_eq(BridgeLauncher.loopback_host("127.0.0.1"), "127.0.0.1")
	assert_eq(BridgeLauncher.loopback_host("localhost"), "127.0.0.1")
	assert_eq(BridgeLauncher.health_url("127.0.0.1", 8787), "http://127.0.0.1:8787/health")
	assert_eq(BridgeLauncher.health_url("::1", 8787), "http://[::1]:8787/health")


func test_a_note_is_short_and_has_no_error_prefix() -> void:
	assert_eq(BridgeLauncher.short_message("error: could not listen on 127.0.0.1:8787: Address already in use"), "Bridge: could not listen on 127.0.0.1:8787: Address already in use")
	var long: String = BridgeLauncher.short_message("error: " + "x".repeat(500))
	assert_lte(long.length(), BridgeLauncher.MAX_NOTE_CHARACTERS + "Bridge: ".length())
	assert_true(long.ends_with("…"))


func test_the_options_for_starting_the_bridge() -> void:
	var defaults: RefCounted = Options.parse(PackedStringArray())
	assert_eq([defaults.start_bridge, defaults.start_bridge_set, defaults.bridge_path], [false, false, ""])
	var on: RefCounted = Options.parse(PackedStringArray(["--start-bridge"]))
	assert_eq([on.start_bridge, on.start_bridge_set, on.bridge_path, on.warnings.size()], [true, true, "", 0])
	var with_path: RefCounted = Options.parse(PackedStringArray(["--start-bridge=/opt/agent-workshop-bridge"]))
	assert_eq([with_path.start_bridge, with_path.bridge_path], [true, "/opt/agent-workshop-bridge"])
	var off: RefCounted = Options.parse(PackedStringArray(["--no-start-bridge"]))
	assert_eq([off.start_bridge, off.start_bridge_set, off.warnings.size()], [false, true, 0])


func test_the_setting_is_off_when_there_is_no_file() -> void:
	assert_eq(BridgeSettings.read("user://no_such_settings.cfg"), { "start": false, "path": "" })


func test_the_setting_is_saved_and_read_back() -> void:
	var file := "user://launcher_settings_test.cfg"
	assert_true(BridgeSettings.write(true, "/opt/agent-workshop-bridge", file))
	assert_eq(BridgeSettings.read(file), { "start": true, "path": "/opt/agent-workshop-bridge" })
	assert_true(BridgeSettings.write(false, "", file))
	assert_eq(BridgeSettings.read(file), { "start": false, "path": "" })
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))


func test_the_saved_setting_applies_unless_the_command_line_decided() -> void:
	var file := "user://launcher_settings_apply.cfg"
	BridgeSettings.write(true, "/saved/path", file)
	var from_file: RefCounted = Options.parse(PackedStringArray())
	BridgeSettings.apply(from_file, file)
	assert_eq([from_file.start_bridge, from_file.bridge_path], [true, "/saved/path"])
	var off: RefCounted = Options.parse(PackedStringArray(["--no-start-bridge"]))
	BridgeSettings.apply(off, file)
	assert_false(off.start_bridge, "the command line wins")
	var own_path: RefCounted = Options.parse(PackedStringArray(["--start-bridge=/cli/path"]))
	BridgeSettings.apply(own_path, file)
	assert_eq(own_path.bridge_path, "/cli/path")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
