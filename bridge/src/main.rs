fn main() {
    // `args_os` and a lossy text: a path with odd bytes must not make the program panic.
    let args = std::env::args_os()
        .skip(1)
        .map(|arg| arg.to_string_lossy().into_owned())
        .collect();
    std::process::exit(agent_workshop_bridge::cli::run(args));
}
