//! Helpers for the integration tests: a bridge on a free port, a WebSocket client and HTTP posts.
#![allow(dead_code)]

use agent_workshop_bridge::server::{Bridge, BridgeOptions};
use futures_util::StreamExt;
use serde_json::Value;
use std::time::Duration;
use tokio_tungstenite::tungstenite::Message;

pub struct Running {
    pub bridge: Bridge,
    pub http: String,
    pub ws: String,
}

pub async fn start() -> Running {
    start_with(BridgeOptions {
        port: 0,
        ..BridgeOptions::default()
    })
    .await
}

pub async fn start_with(options: BridgeOptions) -> Running {
    let mut bridge = Bridge::new(options);
    let addr = bridge.listen().await.expect("the bridge listens");
    Running {
        bridge,
        http: format!("http://127.0.0.1:{}", addr.port()),
        ws: format!("ws://127.0.0.1:{}/ws", addr.port()),
    }
}

pub struct Client {
    socket: tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>,
}

pub async fn connect(url: &str) -> Client {
    let (socket, _) = tokio_tungstenite::connect_async(url)
        .await
        .expect("the client connects");
    Client { socket }
}

impl Client {
    /// The next JSON message, or a panic after 3 seconds.
    pub async fn next(&mut self) -> Value {
        self.try_next(Duration::from_secs(3))
            .await
            .expect("a message arrives in time")
    }

    pub async fn try_next(&mut self, wait: Duration) -> Option<Value> {
        loop {
            match tokio::time::timeout(wait, self.socket.next()).await.ok()?? {
                Ok(Message::Text(text)) => return Some(serde_json::from_str(text.as_str()).expect("JSON text")),
                Ok(Message::Close(_)) | Err(_) => return None,
                Ok(_) => continue,
            }
        }
    }

    /// True when the server closed the connection.
    pub async fn closed(&mut self) -> bool {
        loop {
            match tokio::time::timeout(Duration::from_secs(3), self.socket.next()).await {
                Err(_) => return false,
                Ok(None) | Ok(Some(Err(_))) | Ok(Some(Ok(Message::Close(_)))) => return true,
                Ok(Some(Ok(_))) => continue,
            }
        }
    }
}

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .http_status_as_error(false)
        .proxy(None)
        .build()
        .into()
}

/// A blocking request, run off the async threads. Returns the status and the body text.
pub async fn request(method: &'static str, url: String, body: Option<String>) -> (u16, String) {
    tokio::task::spawn_blocking(move || {
        let agent = agent();
        let mut response = match (method, body) {
            ("POST", body) => agent.post(&url).send(body.unwrap_or_default()),
            (_, _) => agent.get(&url).call(),
        }
        .expect("the request is sent");
        let status = response.status().as_u16();
        (status, response.body_mut().read_to_string().unwrap_or_default())
    })
    .await
    .expect("the request task ends")
}

/// A blocking request with extra headers (for example `Origin` or `Host`). Returns the status and the body text.
pub async fn request_with_headers(
    method: &'static str,
    url: String,
    body: Option<String>,
    headers: Vec<(&'static str, &'static str)>,
) -> (u16, String) {
    tokio::task::spawn_blocking(move || {
        let agent = agent();
        let mut response = if method == "POST" {
            let mut req = agent.post(&url);
            for (name, value) in &headers {
                req = req.header(*name, *value);
            }
            req.send(body.unwrap_or_default())
        } else {
            let mut req = agent.get(&url);
            for (name, value) in &headers {
                req = req.header(*name, *value);
            }
            req.call()
        }
        .expect("the request is sent");
        let status = response.status().as_u16();
        (status, response.body_mut().read_to_string().unwrap_or_default())
    })
    .await
    .expect("the request task ends")
}

pub async fn post(url: &str, body: &Value) -> (u16, Value) {
    let (status, text) = request("POST", url.to_string(), Some(body.to_string())).await;
    (status, serde_json::from_str(&text).unwrap_or(Value::Null))
}

pub async fn get(url: &str) -> (u16, Value) {
    let (status, text) = request("GET", url.to_string(), None).await;
    (status, serde_json::from_str(&text).unwrap_or(Value::Null))
}

/// One-line description of an event, used to compare streams in tests.
pub fn summarize(e: &Value) -> String {
    match e["type"].as_str().unwrap_or("") {
        "tool_start" => format!(
            "tool_start:{}:{}",
            e["category"].as_str().unwrap_or(""),
            e.get("target").and_then(Value::as_str).unwrap_or("")
        ),
        "tool_end" => {
            if e["ok"] == false {
                "tool_end(fail)".to_string()
            } else {
                "tool_end".to_string()
            }
        }
        other => other.to_string(),
    }
}
