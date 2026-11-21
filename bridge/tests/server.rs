mod common;

use agent_workshop_bridge::server::BridgeOptions;
use common::*;
use serde_json::json;
use std::sync::{Arc, Mutex};
use std::time::Duration;

#[tokio::test]
async fn a_client_gets_hello_then_events_posted_to_event() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    assert_eq!(client.next().await, json!({"v": 1, "type": "hello"}));
    let (status, body) = post(
        &format!("{}/event", running.http),
        &json!({"v": 1, "framework": "pi", "session": "s1", "type": "thinking"}),
    )
    .await;
    assert_eq!(status, 202);
    assert_eq!(body, json!({"accepted": 1, "rejected": []}));
    let event = client.next().await;
    assert_eq!(event["type"], "thinking");
    assert_eq!(event["agent"], "main");
    assert!(event["ts"].is_number());
    running.bridge.close().await;
}

#[tokio::test]
async fn invalid_events_get_400_and_are_not_broadcast_but_valid_ones_in_the_same_batch_pass() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await; // hello
    let batch = json!([
        {"v": 1, "framework": "pi", "session": "s1", "type": "tool_start"},
        {"v": 1, "framework": "pi", "session": "s1", "type": "done"},
    ]);
    let (status, body) = post(&format!("{}/event", running.http), &batch).await;
    assert_eq!(status, 400);
    assert_eq!(body["accepted"], 1);
    assert_eq!(body["rejected"][0]["index"], 0);
    assert!(
        body["rejected"][0]["errors"]
            .as_array()
            .unwrap()
            .iter()
            .any(|m| m == "tool_start requires tool")
    );
    assert_eq!(client.next().await["type"], "done");
    assert_eq!(running.bridge.stats().rejected, 1);
    running.bridge.close().await;
}

#[tokio::test]
async fn claude_code_hook_payloads_are_mapped_and_broadcast_and_the_answer_is_empty() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let payload = json!({"hook_event_name": "PreToolUse", "session_id": "c1", "tool_name": "Bash", "tool_input": {"command": "npm test"}});
    let (status, text) = request(
        "POST",
        format!("{}/hook/claude-code", running.http),
        Some(payload.to_string()),
    )
    .await;
    assert_eq!((status, text.as_str()), (204, ""));
    let event = client.next().await;
    assert_eq!(
        (
            &event["type"],
            &event["category"],
            &event["target"],
            &event["framework"]
        ),
        (
            &json!("tool_start"),
            &json!("exec"),
            &json!("npm test"),
            &json!("claude-code")
        )
    );
    running.bridge.close().await;
}

#[tokio::test]
async fn redact_targets_drops_targets_and_errors_before_broadcast() {
    let running = start_with(BridgeOptions {
        port: 0,
        redact_targets: true,
        ..BridgeOptions::default()
    })
    .await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let payload = json!({"hook_event_name": "PreToolUse", "session_id": "c1", "tool_name": "Bash", "tool_input": {"command": "echo secret"}});
    post(&format!("{}/hook/claude-code", running.http), &payload).await;
    let event = client.next().await;
    assert!(event.get("target").is_none());
    assert_eq!(event["tool"], "Bash");
    let failed = json!({"hook_event_name": "PostToolUseFailure", "session_id": "c1", "tool_name": "Bash", "error": "secret path"});
    post(&format!("{}/hook/claude-code", running.http), &failed).await;
    assert!(client.next().await.get("error").is_none());
    let (_, _) = post(
        &format!("{}/event", running.http),
        &json!({"v": 1, "framework": "pi", "session": "s", "type": "error", "target": "t", "error": "e"}),
    )
    .await;
    let posted = client.next().await;
    assert!(posted.get("target").is_none() && posted.get("error").is_none());
    running.bridge.close().await;
}

#[tokio::test]
async fn malformed_json_gives_400_unknown_routes_404_and_health_reports_counters() {
    let running = start().await;
    let (status, text) = request("POST", format!("{}/event", running.http), Some("{nope".into())).await;
    assert_eq!(status, 400);
    assert!(serde_json::from_str::<serde_json::Value>(&text).unwrap()["error"].is_string());
    assert_eq!(
        get(&format!("{}/nowhere", running.http)).await,
        (404, json!({"error": "not found"}))
    );
    let (status, health) = get(&format!("{}/health", running.http)).await;
    assert_eq!(status, 200);
    assert_eq!(
        (
            &health["ok"],
            &health["schema"],
            &health["clients"],
            &health["events"],
            &health["rejected"]
        ),
        (&json!(true), &json!(1), &json!(0), &json!(0), &json!(0))
    );
    running.bridge.close().await;
}

#[tokio::test]
async fn routes_match_the_method_and_the_path_exactly() {
    let running = start().await;
    let h = &running.http;
    assert_eq!(get(&format!("{h}/event")).await.0, 404, "GET /event");
    assert_eq!(get(&format!("{h}/hook/pi")).await.0, 404, "GET /hook/pi");
    assert_eq!(
        get(&format!("{h}/ws")).await.0,
        404,
        "a plain GET /ws is not an upgrade"
    );
    assert_eq!(
        post(&format!("{h}/hook/unknown"), &json!({})).await.0,
        404,
        "an unknown framework"
    );
    let (status, _) = request("POST", format!("{h}/hook/unknown"), Some("{nope".into())).await;
    assert_eq!(status, 404, "an unknown framework is a 404 before the body is read");
    assert_eq!(
        post(&format!("{h}/hook/Pi"), &json!({})).await.0,
        404,
        "upper case is not a framework name"
    );
    assert_eq!(
        post(&format!("{h}/hook/pi/"), &json!({})).await.0,
        404,
        "a trailing slash"
    );
    assert_eq!(
        post(&format!("{h}/event/"), &json!({})).await.0,
        404,
        "a trailing slash on /event"
    );
    assert_eq!(
        get(&format!("{h}/health?x=1")).await.0,
        200,
        "a query string is ignored"
    );
    assert_eq!(
        post(
            &format!("{h}/event?x=1"),
            &json!({"v":1,"framework":"pi","session":"s","type":"done"})
        )
        .await
        .0,
        202
    );
    running.bridge.close().await;
}

#[tokio::test]
async fn a_value_that_is_not_an_event_is_rejected() {
    let running = start().await;
    let (status, body) = post(&format!("{}/event", running.http), &json!(null)).await;
    assert_eq!(status, 400);
    assert_eq!(body["rejected"][0]["errors"], json!(["event must be an object"]));
    let (status, body) = post(&format!("{}/event", running.http), &json!([])).await;
    assert_eq!((status, &body["accepted"]), (202, &json!(0)));
    running.bridge.close().await;
}

#[tokio::test]
async fn an_event_keeps_unknown_extra_fields() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    post(
        &format!("{}/event", running.http),
        &json!({"v": 1, "framework": "x", "session": "s", "type": "newer_type", "extra": {"a": [1, 2]}, "cost": 0.5}),
    )
    .await;
    let event = client.next().await;
    assert_eq!(
        (&event["type"], &event["extra"], &event["cost"]),
        (&json!("newer_type"), &json!({"a": [1, 2]}), &json!(0.5))
    );
    running.bridge.close().await;
}

#[tokio::test]
async fn hermes_hooks_reach_clients_including_a_payload_over_1_mb() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let big = json!({
        "hook_event_name": "post_tool_call", "tool_name": "read_file", "session_id": "s7",
        "extra": {"tool_call_id": "c", "status": "ok", "result": "x".repeat(2_000_000)},
    });
    let (status, _) = request("POST", format!("{}/hook/hermes", running.http), Some(big.to_string())).await;
    assert_eq!(status, 204);
    let event = client.next().await;
    assert_eq!(
        (&event["framework"], &event["session"], &event["type"], &event["ok"]),
        (&json!("hermes"), &json!("s7"), &json!("tool_end"), &json!(true))
    );
    running.bridge.close().await;
}

#[tokio::test]
async fn a_body_over_the_limit_gets_413() {
    let running = start().await;
    let body = format!("\"{}\"", "x".repeat(10_000_001));
    let (status, text) = request("POST", format!("{}/event", running.http), Some(body)).await;
    assert_eq!(status, 413);
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&text).unwrap(),
        json!({"error": "payload too large"})
    );
    // The bridge still works.
    assert_eq!(get(&format!("{}/health", running.http)).await.0, 200);
    running.bridge.close().await;
}

#[tokio::test]
async fn opencode_and_pi_hooks_reach_clients() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let (status, _) = post(
        &format!("{}/hook/opencode", running.http),
        &json!({"event": {"type": "session.idle", "properties": {"sessionID": "s9"}}}),
    )
    .await;
    assert_eq!(status, 204);
    let event = client.next().await;
    assert_eq!(
        (&event["framework"], &event["session"], &event["type"]),
        (&json!("opencode"), &json!("s9"), &json!("done"))
    );
    let pi = json!({"session": "s1", "event": {"type": "tool_execution_start", "toolCallId": "x", "toolName": "bash", "args": {"command": "ls"}}});
    assert_eq!(post(&format!("{}/hook/pi", running.http), &pi).await.0, 204);
    assert_eq!(summarize(&client.next().await), "tool_start:exec:ls");
    running.bridge.close().await;
}

#[tokio::test]
async fn adapters_keep_their_state_between_requests() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let hook = |extra: serde_json::Value| {
        let mut payload = json!({"session_id": "c1"});
        for (k, v) in extra.as_object().unwrap() {
            payload[k] = v.clone();
        }
        payload
    };
    let url = format!("{}/hook/claude-code", running.http);
    post(
        &url,
        &hook(json!({"hook_event_name": "PreToolUse", "tool_name": "Task", "tool_use_id": "sub1"})),
    )
    .await;
    assert_eq!(client.next().await["type"], "tool_start");
    assert_eq!(client.next().await["type"], "subagent_start");
    post(&url, &hook(json!({"hook_event_name": "SubagentStop"}))).await;
    let end = client.next().await;
    assert_eq!((&end["type"], &end["id"]), (&json!("subagent_end"), &json!("sub1")));
    running.bridge.close().await;
}

#[tokio::test]
async fn an_invalid_mapped_event_is_dropped_and_counted() {
    let lines = Arc::new(Mutex::new(Vec::<String>::new()));
    let sink = lines.clone();
    let running = start_with(BridgeOptions {
        port: 0,
        log: Arc::new(move |line| sink.lock().unwrap().push(line.to_string())),
        ..BridgeOptions::default()
    })
    .await;
    // A session id that is not a string maps to an event that fails validation.
    let (status, _) = post(
        &format!("{}/hook/claude-code", running.http),
        &json!({"hook_event_name": "Stop", "session_id": 5}),
    )
    .await;
    assert_eq!(status, 204);
    assert_eq!(running.bridge.stats().rejected, 1);
    assert_eq!(running.bridge.stats().events, 0);
    assert!(
        lines
            .lock()
            .unwrap()
            .iter()
            .any(|l| l.starts_with("dropped claude-code event: session must be a non-empty string"))
    );
    running.bridge.close().await;
}

#[tokio::test]
async fn every_client_gets_every_event_and_the_count_follows_the_connections() {
    let running = start().await;
    let mut a = connect(&running.ws).await;
    let mut b = connect(&running.ws).await;
    a.next().await;
    b.next().await;
    assert_eq!(get(&format!("{}/health", running.http)).await.1["clients"], 2);
    post(
        &format!("{}/event", running.http),
        &json!({"v": 1, "framework": "pi", "session": "s", "type": "done"}),
    )
    .await;
    assert_eq!(a.next().await["type"], "done");
    assert_eq!(b.next().await["type"], "done");
    drop(a);
    for _ in 0..50 {
        if get(&format!("{}/health", running.http)).await.1["clients"] == 1 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert_eq!(get(&format!("{}/health", running.http)).await.1["clients"], 1);
    running.bridge.close().await;
}

#[tokio::test]
async fn a_burst_of_events_arrives_in_order() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let batch: Vec<_> = (0..200)
        .map(|i| json!({"v": 1, "framework": "pi", "session": "s", "type": "tool_end", "ok": true, "id": format!("c{i}")}))
        .collect();
    post(&format!("{}/event", running.http), &json!(batch)).await;
    for i in 0..200 {
        assert_eq!(client.next().await["id"], format!("c{i}"));
    }
    running.bridge.close().await;
}

#[tokio::test]
async fn closing_ends_the_connections_and_frees_the_port() {
    let running = start().await;
    let port: u16 = running.http.rsplit(':').next().unwrap().parse().unwrap();
    let mut client = connect(&running.ws).await;
    client.next().await;
    running.bridge.close().await;
    assert!(client.closed().await, "the client sees the close");
    // The same port can be used again at once (the Godot client reconnects to it).
    let again = start_with(BridgeOptions {
        port,
        ..BridgeOptions::default()
    })
    .await;
    assert_eq!(get(&format!("{}/health", again.http)).await.0, 200);
    again.bridge.close().await;
}

#[tokio::test]
async fn a_client_without_an_origin_header_is_let_in() {
    // The Godot client sends no Origin header. The bridge must accept that.
    let running = start().await;
    let mut client = connect(&running.ws).await;
    assert_eq!(client.next().await["type"], "hello");
    running.bridge.close().await;
}

const EVENT: &str = r#"{"v":1,"framework":"pi","session":"s1","type":"thinking"}"#;

#[tokio::test]
async fn a_web_page_cannot_post_events_or_read_the_stream() {
    // A page in a browser can reach 127.0.0.1. It always sends an Origin header, and the bridge refuses a foreign one.
    let running = start().await;
    for origin in [
        "https://evil.example",
        "http://127.0.0.1.evil.example",
        "http://localhost.evil.example:8787",
        "null",
    ] {
        let (status, text) = request_with_headers(
            "POST",
            format!("{}/event", running.http),
            Some(EVENT.to_string()),
            vec![("Origin", origin), ("Content-Type", "text/plain")],
        )
        .await;
        assert_eq!(status, 403, "origin {origin}");
        assert!(text.contains("forbidden origin"), "{text}");
        let (status, _) = request_with_headers(
            "GET",
            format!("{}/health", running.http),
            None,
            vec![("Origin", origin)],
        )
        .await;
        assert_eq!(status, 403, "origin {origin} on /health");
    }
    assert_eq!(running.bridge.stats().events, 0, "no event got in");

    // The WebSocket handshake of a page is refused too, and no client is counted.
    let mut request =
        tokio_tungstenite::tungstenite::client::IntoClientRequest::into_client_request(running.ws.as_str()).unwrap();
    request
        .headers_mut()
        .insert("Origin", "https://evil.example".parse().unwrap());
    let refused = tokio_tungstenite::connect_async(request).await;
    assert!(refused.is_err(), "a foreign origin must not get a WebSocket");
    assert_eq!(running.bridge.stats().clients, 0);
    running.bridge.close().await;
}

#[tokio::test]
async fn a_local_origin_and_a_local_host_are_let_in() {
    let running = start().await;
    for origin in [
        "http://127.0.0.1:8787",
        "http://localhost:3000",
        "http://[::1]:8787",
        "https://LOCALHOST",
    ] {
        let (status, _) = request_with_headers(
            "POST",
            format!("{}/event", running.http),
            Some(EVENT.to_string()),
            vec![("Origin", origin), ("Content-Type", "text/plain")],
        )
        .await;
        assert_eq!(status, 202, "origin {origin}");
    }
    let (status, _) = request_with_headers(
        "GET",
        format!("{}/health", running.http),
        None,
        vec![("Host", "localhost:8787")],
    )
    .await;
    assert_eq!(status, 200);
    let (status, _) = request_with_headers(
        "GET",
        format!("{}/health", running.http),
        None,
        vec![("Host", "[::1]:8787")],
    )
    .await;
    assert_eq!(status, 200);
    running.bridge.close().await;
}

#[tokio::test]
async fn a_foreign_host_name_is_refused_when_the_bridge_listens_on_loopback() {
    // DNS rebinding: a page on a name that points to 127.0.0.1 sends that name as the Host.
    let running = start().await;
    let (status, text) = request_with_headers(
        "GET",
        format!("{}/health", running.http),
        None,
        vec![("Host", "evil.example:8787")],
    )
    .await;
    assert_eq!(status, 403);
    assert!(text.contains("forbidden host"), "{text}");
    let (status, _) = request_with_headers(
        "GET",
        format!("{}/health", running.http),
        None,
        vec![("Host", "127.0.0.1.evil.example")],
    )
    .await;
    assert_eq!(status, 403);
    running.bridge.close().await;
}

#[tokio::test]
async fn known_difference_json_nested_deeper_than_128_levels_gets_400() {
    // The Node bridge parses it. The JSON library of the bridge stops at 128 levels.
    let running = start().await;
    let deep = format!("{}1{}", "[".repeat(200), "]".repeat(200));
    let (status, _) = request("POST", format!("{}/event", running.http), Some(deep)).await;
    assert_eq!(status, 400);
    let fine = format!("{}1{}", "[".repeat(100), "]".repeat(100));
    let (status, text) = request("POST", format!("{}/event", running.http), Some(fine)).await;
    let answer: serde_json::Value = serde_json::from_str(&text).unwrap();
    // 100 levels are read: the answer is a list of rejected events, not a parse error.
    assert_eq!((status, &answer["accepted"]), (400, &json!(0)));
    running.bridge.close().await;
}

#[tokio::test]
async fn known_difference_integers_above_2_to_the_53_are_kept_as_sent() {
    // The Node bridge rounds them. The bridge keeps them.
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let body = r#"{"v":1,"framework":"x","session":"s","type":"t","big":1152921504606846976}"#;
    request("POST", format!("{}/event", running.http), Some(body.into())).await;
    let event = client.next().await;
    assert_eq!(event["big"].to_string(), "1152921504606846976");
    running.bridge.close().await;
}

#[tokio::test]
async fn an_unknown_framework_named_constructor_is_a_404() {
    // The Node bridge answered 500 for this one name, by a quirk of JavaScript objects.
    let running = start().await;
    assert_eq!(
        post(&format!("{}/hook/constructor", running.http), &json!({})).await.0,
        404
    );
    running.bridge.close().await;
}

#[tokio::test]
async fn a_lone_surrogate_in_a_payload_does_not_lose_the_event() {
    // JavaScript and Python write a text that was cut in the middle of an emoji with a lone surrogate escape.
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let body =
        r#"{"hook_event_name":"PostToolUse","session_id":"c","tool_name":"Bash","tool_response":{"stderr":"x\ud83d"}}"#;
    let (status, _) = request("POST", format!("{}/hook/claude-code", running.http), Some(body.into())).await;
    assert_eq!(status, 204);
    let event = client.next().await;
    assert_eq!((&event["type"], &event["ok"]), (&json!("tool_end"), &json!(true)));
    running.bridge.close().await;
}

#[tokio::test]
async fn events_of_one_session_keep_their_order_when_posts_come_together() {
    let running = start().await;
    let mut client = connect(&running.ws).await;
    client.next().await;
    let url = format!("{}/hook/claude-code", running.http);
    let mut posts = Vec::new();
    for i in 0..60 {
        let url = url.clone();
        let body = json!({"hook_event_name": "PreToolUse", "session_id": "c", "tool_name": "Read", "tool_use_id": format!("t{i}")});
        posts.push(tokio::spawn(async move { post(&url, &body).await.0 }));
    }
    for post in posts {
        assert_eq!(post.await.unwrap(), 204);
    }
    // Every event arrives once. (Posts that run together have no order among themselves, but the adapter's own pairs stay together.)
    let mut ids: Vec<String> = Vec::new();
    for _ in 0..60 {
        ids.push(client.next().await["id"].as_str().unwrap().to_string());
    }
    ids.sort();
    ids.dedup();
    assert_eq!(ids.len(), 60);
    running.bridge.close().await;
}
