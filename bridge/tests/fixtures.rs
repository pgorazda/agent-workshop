//! The Godot tests read `godot/test/fixtures/*.events.jsonl`. These tests check that those files
//! are still what the adapters make from `schema/examples/`. If one fails, run:
//! `cargo run --example fixtures`

#[path = "common/fixtures.rs"]
mod fixtures;

#[test]
fn the_fixtures_are_up_to_date() {
    for name in fixtures::NAMES {
        let expected = fixtures::fixture_text(&fixtures::example_events(name));
        let path = fixtures::fixture_path(name);
        let actual = std::fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("{}: {err}", path.display()))
            .replace("\r\n", "\n");
        assert_eq!(
            actual, expected,
            "the fixture for the {name} example is out of date (run: cargo run --example fixtures)"
        );
    }
}

#[test]
fn each_example_gives_a_stream_with_tools_a_failure_and_a_finish() {
    for name in fixtures::NAMES {
        let events = fixtures::example_events(name);
        let types: Vec<&str> = events.iter().map(|e| e["type"].as_str().unwrap()).collect();
        assert!(types.contains(&"tool_start"), "{name}: tool_start");
        assert!(
            events.iter().any(|e| e["type"] == "tool_end" && e["ok"] == false),
            "{name}: a failed tool"
        );
        assert!(types.contains(&"done") || types.contains(&"error"), "{name}: a finish");
    }
}
