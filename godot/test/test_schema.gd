extends GutTest
## The category list in event.gd must equal the enum in schema/event.schema.json.
## The test reads the schema from the source tree, not from an export.

const Event := preload("res://src/core/event.gd")


func _schema() -> Dictionary:
	var path: String = ProjectSettings.globalize_path("res://").path_join("../schema/event.schema.json").simplify_path()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "the schema file exists: %s" % path)
	if file == null:
		return { }
	var data: Variant = JSON.parse_string(file.get_as_text())
	assert_typeof(data, TYPE_DICTIONARY)
	return data if typeof(data) == TYPE_DICTIONARY else { }


func test_category_list_equals_the_schema_enum() -> void:
	var properties: Dictionary = _schema()["properties"]
	var from_schema: Array = (properties["category"] as Dictionary)["enum"]
	assert_eq(Event.CATEGORIES.size(), from_schema.size(), "same number of categories")
	assert_eq(Array(Event.CATEGORIES), from_schema, "same categories in the same order")


func test_schema_version_matches() -> void:
	var properties: Dictionary = _schema()["properties"]
	var version: Dictionary = properties["v"]
	assert_eq(int(version["const"]), Event.SCHEMA_VERSION)


func test_required_fields_are_the_ones_the_parser_checks() -> void:
	var required: Array = _schema()["required"]
	var checked: Array = ["v", "framework", "session", "agent", "type", "ts"]
	for field: Variant in required:
		assert_true(checked.has(field), "parser checks %s" % field)
	assert_eq(required.size(), checked.size())
