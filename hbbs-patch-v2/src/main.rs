// BetterDesk Enhanced Server v2.0.0
// Based on RustDesk Server 1.1.14 with HTTP API
// https://tools.ietf.org/rfc/rfc5128.txt

use flexi_logger::*;
use hbb_common::{bail, config::RENDEZVOUS_PORT, ResultType, tokio};
use hbbs::{common::*, *};

mod http_api;

const RMEM: usize = 0;
const API_PORT: u16 = 21120;

fn main() -> ResultType<()> {
    let _logger = Logger::try_with_env_or_str("info")?
        .log_to_stdout()
        .format(opt_format)
        .write_mode(WriteMode::Async)
        .start()?;
    
    let args = format!(
        "-c --config=[FILE] +takes_value 'Sets a custom config file'
        -p, --port=[NUMBER(default={RENDEZVOUS_PORT})] 'Sets the listening port'
        -s, --serial=[NUMBER(default=0)] 'Sets configure update serial number'
        -R, --rendezvous-servers=[HOSTS] 'Sets rendezvous servers, separated by comma'
        -u, --software-url=[URL] 'Sets download url of RustDesk software of newest version'
        -r, --relay-servers=[HOST] 'Sets the default relay servers, separated by comma'
        -M, --rmem=[NUMBER(default={RMEM})] 'Sets UDP recv buffer size'
        , --mask=[MASK] 'Determine if the connection comes from LAN'
        -k, --key=[KEY] 'Only allow the client with the same key'
        -a, --api-port=[NUMBER(default={API_PORT})] 'Sets the HTTP API port'",
    );
    init_args(&args, "hbbs", "BetterDesk Enhanced Server v2.0.0");
    
    let port = get_arg_or("port", RENDEZVOUS_PORT.to_string()).parse::<i32>()?;
    if port < 3 {
        bail!("Invalid port");
    }
    let rmem = get_arg("rmem").parse::<usize>().unwrap_or(RMEM);
    let serial: i32 = get_arg("serial").parse().unwrap_or(0);
    let api_port = get_arg("api-port").parse::<u16>().unwrap_or(API_PORT);
    
    hbb_common::log::info!("========================================");
    hbb_common::log::info!("  BetterDesk Enhanced Server v2.0.0");
    hbb_common::log::info!("  Based on RustDesk Server 1.1.14");
    hbb_common::log::info!("========================================");
    hbb_common::log::info!("  Signal Port: {}", port);
    hbb_common::log::info!("  API Port: {}", api_port);
    hbb_common::log::info!("========================================");
    
    // Start HTTP API server in background thread
    let db_path = std::env::current_dir()
        .unwrap_or_default()
        .join("db_v2.sqlite3")
        .to_string_lossy()
        .to_string();
    
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            if let Err(e) = http_api::start_api_server(db_path, api_port).await {
                hbb_common::log::error!("HTTP API failed: {}", e);
            }
        });
    });
    
    crate::common::check_software_update();
    RendezvousServer::start(port, serial, &get_arg_or("key", "-".to_owned()), rmem)?;
    Ok(())
}
