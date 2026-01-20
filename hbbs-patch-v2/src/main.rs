// Enhanced main.rs with improved configuration
// https://tools.ietf.org/rfc/rfc5128.txt

use flexi_logger::*;
use hbb_common::{bail, config::RENDEZVOUS_PORT, ResultType};
use hbbs::{common::*, *};
use std::sync::Arc;

mod http_api;

const RMEM: usize = 0;
const API_PORT: u16 = 21120;  // HTTP API port (LAN accessible with X-API-Key auth)

// Enhanced configuration constants
const DEFAULT_MAX_DB_CONNECTIONS: usize = 5;  // Increased from 1
const DEFAULT_HEARTBEAT_INTERVAL: u64 = 3;    // Faster heartbeat (3s instead of 5s)
const DEFAULT_PEER_CLEANUP_INTERVAL: u64 = 60; // Clean inactive peers every minute

fn main() -> ResultType<()> {
    // Enhanced logging configuration
    let _logger = Logger::try_with_env_or_str("info")?
        .log_to_stdout()
        .format(opt_format)
        .write_mode(WriteMode::Async)
        .duplicate_to_stderr(Duplicate::Warn)  // Also send warnings/errors to stderr
        .start()?;
    
    log::info!("====================================");
    log::info!("BetterDesk Server v2 - Enhanced Edition");
    log::info!("====================================");
    
    let args = format!(
        "-c --config=[FILE] +takes_value ''Sets a custom config file''
        -p, --port=[NUMBER(default={RENDEZVOUS_PORT})] ''Sets the listening port''
        -s, --serial=[NUMBER(default=0)] ''Sets configure update serial number''
        -R, --rendezvous-servers=[HOSTS] ''Sets rendezvous servers, separated by comma''
        -u, --software-url=[URL] ''Sets download url of RustDesk software of newest version''
        -r, --relay-servers=[HOST] ''Sets the default relay servers, separated by comma''
        -M, --rmem=[NUMBER(default={RMEM})] ''Sets UDP recv buffer size, set system rmem_max first, e.g., sudo sysctl -w net.core.rmem_max=52428800. vi /etc/sysctl.conf, net.core.rmem_max=52428800, sudo sysctl p''
        --mask=[MASK] ''Determine if the connection comes from LAN, e.g. 192.168.0.0/16''
        -k, --key=[KEY] ''Only allow the client with the same key''
        -a, --api-port=[NUMBER(default={API_PORT})] ''Sets the HTTP API port''
        --max-db-connections=[NUMBER(default={DEFAULT_MAX_DB_CONNECTIONS})] ''Sets max database connection pool size''
        --heartbeat-interval=[NUMBER(default={DEFAULT_HEARTBEAT_INTERVAL})] ''Sets peer heartbeat check interval in seconds''",
    );
    
    init_args(&args, "hbbs", "RustDesk ID/Rendezvous Server - Enhanced Edition");
    
    let port = get_arg_or("port", RENDEZVOUS_PORT.to_string()).parse::<i32>()?;
    if port < 3 {
        bail!("Invalid port");
    }
    
    let rmem = get_arg("rmem").parse::<usize>().unwrap_or(RMEM);
    let serial: i32 = get_arg("serial").parse().unwrap_or(0);
    let api_port = get_arg("api-port").parse::<u16>().unwrap_or(API_PORT);
    
    // Enhanced configuration
    let max_db_conn = get_arg("max-db-connections")
        .parse::<usize>()
        .unwrap_or(DEFAULT_MAX_DB_CONNECTIONS);
    let heartbeat_interval = get_arg("heartbeat-interval")
        .parse::<u64>()
        .unwrap_or(DEFAULT_HEARTBEAT_INTERVAL);
    
    log::info!("Configuration:");
    log::info!("  Port: {}", port);
    log::info!("  API Port: {}", api_port);
    log::info!("  Max DB Connections: {}", max_db_conn);
    log::info!("  Heartbeat Interval: {}s", heartbeat_interval);
    log::info!("  Serial: {}", serial);
    
    // Store config in environment for other modules
    std::env::set_var("MAX_DATABASE_CONNECTIONS", max_db_conn.to_string());
    std::env::set_var("HEARTBEAT_INTERVAL_SECS", heartbeat_interval.to_string());
    
    // Start HTTP API server in background
    log::info!("Starting HTTP API server...");
    std::thread::spawn(move || {
        hbb_common::tokio::runtime::Runtime::new().unwrap().block_on(async {
            let db_path = get_arg_or("db", "/opt/rustdesk/db_v2.sqlite3".to_owned());
            if let Err(e) = http_api::start_api_server(db_path, api_port).await {
                log::error!("HTTP API failed to start: {}", e);
            }
        });
    });
    
    log::info!("Checking for software updates...");
    crate::common::check_software_update();
    
    log::info!("Starting Rendezvous Server...");
    RendezvousServer::start(port, serial, &get_arg_or("key", "-".to_owned()), rmem)?;
    Ok(())
}
