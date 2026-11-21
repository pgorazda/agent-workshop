//! Framework adapters: raw payloads of each framework to canonical events.

pub mod claude_code;
pub mod hermes;
pub mod opencode;
pub mod pi;

use serde_json::Value;

/// All adapters with their state. One set serves one bridge.
#[derive(Default)]
pub struct Adapters {
    claude_code: claude_code::ClaudeCodeAdapter,
    opencode: opencode::OpenCodeAdapter,
    pi: pi::PiAdapter,
    hermes: hermes::HermesAdapter,
}

impl Adapters {
    pub fn new() -> Self {
        Self::default()
    }

    /// True when an adapter has this framework id.
    pub fn knows(framework: &str) -> bool {
        matches!(framework, "claude-code" | "opencode" | "pi" | "hermes")
    }

    /// Raw payload to canonical events, per framework id (the `:framework` part of
    /// `/hook/:framework`). `None` means that no adapter has this id.
    pub fn map(&mut self, framework: &str, payload: &Value) -> Option<Vec<Value>> {
        Some(match framework {
            "claude-code" => self.claude_code.from_hook(payload),
            "opencode" => self.opencode.from_payload(payload),
            "pi" => self.pi.from_payload(payload),
            "hermes" => self.hermes.from_hook(payload),
            _ => return None,
        })
    }
}
