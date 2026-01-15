// https://tools.ietf.org/rfc/rfc5128.txt
// https://blog.csdn.net/bytxl/article/details/44344855

use flexi_logger::*;
use hbb_common::{bail, config::RENDEZVOUS_PORT, ResultType};
use hbbs::{common::*, *};
use std::sync::Arc;

mod http_api;

const RMEM: usize = 0;
const API_PORT: u16 = 21120;  // HTTP API port (LAN accessible with X-API-Key auth)

fn main() -> ResultType<()> {
    let _logger = Logger::try_with_env_or_str("info")?
        .log_to_stdout()
        .format(opt_format)
        .write_mode(WriteMode::Async)
        .start()?;
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
        -a, --api-port=[NUMBER(default={API_PORT})] ''Sets the HTTP API port''",
    );
    init_args(&args, "hbbs", "RustDesk ID/Rendezvous Server");
    let port = get_arg_or("port", RENDEZVOUS_PORT.to_string()).parse::<i32>()?;
    if port < 3 {
        bail!("Invalid port");
    }
    let rmem = get_arg("rmem").parse::<usize>().unwrap_or(RMEM);
    let serial: i32 = get_arg("serial").parse().unwrap_or(0);
    let api_port = get_arg("api-port").parse::<u16>().unwrap_or(API_PORT);
    
    // Start HTTP API server in background
    // API reads device status directly from SQLite database
    std::thread::spawn(move || {
        hbb_common::tokio::runtime::Runtime::new().unwrap().block_on(async {
            let db_path = get_arg_or("db", "/opt/rustdesk/db_v2.sqlite3".to_owned());
            if let Err(e) = http_api::start_api_server(db_path, api_port).await {
                hbb_common::log::error!("HTTP API failed to start: {}", e);
            }
        });
    });
    
    crate::common::check_software_update();
    RendezvousServer::start(port, serial, &get_arg_or("key", "-".to_owned()), rmem)?;
    Ok(())
}
