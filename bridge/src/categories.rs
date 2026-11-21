//! Maps native tool names to the canonical category set. The game only ever sees categories.

/// Lower-cased tool name to category. Shared by all frameworks.
const DEFAULT_MAP: &[(&str, &str)] = &[
    // read
    ("read", "read"),
    ("read_file", "read"),
    ("readfile", "read"),
    ("view", "read"),
    ("cat", "read"),
    ("notebookread", "read"),
    // search
    ("glob", "search"),
    ("grep", "search"),
    ("find", "search"),
    ("ls", "search"),
    ("list", "search"),
    ("search", "search"),
    ("codesearch", "search"),
    // write
    ("edit", "write"),
    ("multiedit", "write"),
    ("write", "write"),
    ("write_file", "write"),
    ("patch", "write"),
    ("apply_patch", "write"),
    ("notebookedit", "write"),
    // exec
    ("bash", "exec"),
    ("bashoutput", "exec"),
    ("killshell", "exec"),
    ("shell", "exec"),
    ("exec", "exec"),
    ("run", "exec"),
    // web
    ("websearch", "web"),
    ("webfetch", "web"),
    ("fetch", "web"),
    ("browse", "web"),
    // delegate
    ("task", "delegate"),
    ("agent", "delegate"),
    ("subagent", "delegate"),
    // think
    ("todowrite", "think"),
    ("todoread", "think"),
    ("exitplanmode", "think"),
    // ask
    ("askuserquestion", "ask_permission"),
    ("question", "ask_permission"),
];

/// Hermes Agent tool names (tools/*.py in hermes-agent). Names shared with other frameworks
/// (read_file, write_file, patch) come from the default map.
const HERMES_OVERRIDES: &[(&str, &str)] = &[
    ("terminal", "exec"),
    ("process", "exec"),
    ("execute_code", "exec"),
    ("read_terminal", "exec"),
    ("close_terminal", "exec"),
    ("search_files", "search"),
    ("session_search", "search"),
    ("skill_view", "read"),
    ("skills_list", "read"),
    ("web_search", "web"),
    ("web_extract", "web"),
    ("x_search", "web"),
    ("delegate_task", "delegate"),
    ("todo", "think"),
    ("memory", "think"),
    ("skill_manage", "think"),
    ("clarify", "ask_permission"),
];

/// Per-framework overrides. Add entries when a framework's names differ.
fn overrides(framework: &str) -> &'static [(&'static str, &'static str)] {
    match framework {
        "hermes" => HERMES_OVERRIDES,
        _ => &[],
    }
}

/// Name prefixes per framework, tried after exact names. Hermes has many `browser_*` tools.
fn prefixes(framework: &str) -> &'static [(&'static str, &'static str)] {
    match framework {
        "hermes" => &[("browser_", "web")],
        _ => &[],
    }
}

fn lookup(table: &[(&str, &'static str)], key: &str) -> Option<&'static str> {
    table
        .iter()
        .find(|(name, _)| *name == key)
        .map(|(_, category)| *category)
}

/// The category of a tool. An empty or missing name gives `other`.
pub fn category_for(framework: &str, tool_name: Option<&str>) -> &'static str {
    let Some(name) = tool_name.filter(|n| !n.is_empty()) else {
        return "other";
    };
    let key = name.to_lowercase();
    if let Some(found) = lookup(overrides(framework), &key).or_else(|| lookup(DEFAULT_MAP, &key)) {
        return found;
    }
    prefixes(framework)
        .iter()
        .find(|(prefix, _)| key.starts_with(prefix))
        .map_or("other", |(_, category)| category)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::schema::CATEGORIES;

    #[test]
    fn known_tools_map_across_frameworks_and_the_rest_is_other() {
        assert_eq!(category_for("claude-code", Some("Bash")), "exec");
        assert_eq!(category_for("opencode", Some("bash")), "exec");
        assert_eq!(category_for("pi", Some("read")), "read");
        assert_eq!(category_for("claude-code", Some("WebFetch")), "web");
        assert_eq!(category_for("claude-code", Some("Task")), "delegate");
        assert_eq!(category_for("claude-code", Some("mcp__server__tool")), "other");
        assert_eq!(category_for("claude-code", None), "other");
        assert_eq!(category_for("claude-code", Some("")), "other");
        for tool in [
            "Read",
            "Grep",
            "Edit",
            "Bash",
            "WebSearch",
            "Task",
            "TodoWrite",
            "AskUserQuestion",
        ] {
            assert!(CATEGORIES.contains(&category_for("claude-code", Some(tool))));
        }
    }

    #[test]
    fn hermes_tool_names_map_to_categories() {
        let cases = [
            ("terminal", "exec"),
            ("execute_code", "exec"),
            ("read_file", "read"),
            ("write_file", "write"),
            ("patch", "write"),
            ("search_files", "search"),
            ("web_search", "web"),
            ("web_extract", "web"),
            ("browser_click", "web"),
            ("delegate_task", "delegate"),
            ("todo", "think"),
            ("clarify", "ask_permission"),
            ("image_generate", "other"),
        ];
        for (tool, category) in cases {
            assert_eq!(category_for("hermes", Some(tool)), category, "{tool}");
        }
        assert_eq!(
            category_for("claude-code", Some("browser_click")),
            "other",
            "prefix rules are per framework"
        );
    }

    #[test]
    fn every_target_is_a_known_category() {
        for (_, category) in DEFAULT_MAP.iter().chain(HERMES_OVERRIDES) {
            assert!(CATEGORIES.contains(category));
        }
    }
}
