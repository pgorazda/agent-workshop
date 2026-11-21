//! The Agent Workshop bridge: adapters turn the events of coding agents into canonical events,
//! and the server streams them to the clients.

pub mod adapters;
pub mod categories;
pub mod cli;
pub mod event;
pub mod js;
pub mod schema;
pub mod server;
pub mod targets;
