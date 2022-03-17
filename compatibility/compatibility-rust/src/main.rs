use env_logger::Env;
use std::net::{Ipv4Addr, TcpListener, TcpStream};

const LISTENING_PORT: u16 = 1234;

#[async_std::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(Env::default().default_filter_or("debug")).init();

    let mut sync_client = testground::sync::Client::new().await?;

    let local_addr = &if_addrs::get_if_addrs()
        .unwrap()
        .into_iter()
        .find(|iface| iface.name == "eth1")
        .unwrap()
        .addr
        .ip();

    match local_addr {
        std::net::IpAddr::V4(addr) if addr.octets()[3] % 2 == 0 => {
            println!("Test instance, listening for incoming connections.");

            let listener = TcpListener::bind((*addr, LISTENING_PORT))?;

            sync_client.signal("listening".to_string()).await?;

            listener
                .incoming()
                .next()
                .expect("Listener not to close.")?;
            println!("Established inbound TCP connection.");
        }
        std::net::IpAddr::V4(addr) if addr.octets()[3] % 2 != 0 => {
            println!("Test instance, connecting to listening instance.");

            sync_client
                .wait_for_barrier("listening".to_string(), 1)
                .await?;

            let remote_addr: Ipv4Addr = {
                let mut octets = addr.octets();
                octets[3] = octets[3] - 1;
                octets.into()
            };
            let _stream = TcpStream::connect((remote_addr, LISTENING_PORT)).unwrap();
            println!("Established outbound TCP connection.");
        }
        addr => {
            panic!("Unexpected local IP address {:?}", addr);
        }
    }

    sync_client.publish_success().await?;

    Ok(())
}
