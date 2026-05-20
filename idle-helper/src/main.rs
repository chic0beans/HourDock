use std::env;
use std::fs;
use std::io::{self, Write};
use std::process;
use std::thread;
use std::time::Duration;

use serde_json::json;

fn write_json_line<W: Write>(mut out: W, value: serde_json::Value) {
    if let Ok(s) = serde_json::to_string(&value) {
        let _ = writeln!(out, "{}", s);
        let _ = out.flush();
    }
}

fn print_json_error(message: &str) {
    write_json_line(io::stderr(), json!({ "error": message }));
}

fn cmd_idle(args: &[String]) {
    if args.len() < 2 {
        print_json_error("Usage: idle-helper idle <app_id> [display_name]");
        process::exit(1);
    }

    let app_id: u32 = match args[1].parse() {
        Ok(id) => id,
        Err(_) => {
            print_json_error("Invalid app_id");
            process::exit(1);
        }
    };

    env::set_var("SteamAppId", app_id.to_string());
    env::set_var("SteamGameId", app_id.to_string());

    if let Ok(cwd) = env::current_dir() {
        let appid_file = cwd.join("steam_appid.txt");
        let _ = fs::write(&appid_file, app_id.to_string());
    }

    let client = match steamworks::Client::init_app(app_id) {
        Ok(client) => client,
        Err(_) => {
            print_json_error(
                "Failed to initialize Steam API. Ensure Steam is running, signed in, and steamclient.dylib is reachable.",
            );
            process::exit(1);
        }
    };

    write_json_line(io::stdout(), json!({ "success": "Steam API initialized" }));

    loop {
        client.run_callbacks();
        thread::sleep(Duration::from_secs(1));
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        print_json_error("Usage: idle-helper idle <app_id> [display_name]");
        process::exit(1);
    }

    match args[1].as_str() {
        "idle" => cmd_idle(&args[1..]),
        other => {
            print_json_error(&format!("Unknown command: {}", other));
            process::exit(1);
        }
    }
}
