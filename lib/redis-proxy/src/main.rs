use std::env;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

/// RESP Redis proxy that translates legacy key names to modern format.
///
/// Legacy libp2p implementations use the hardcoded key `listenerAddr` for
/// RPUSH/BLPOP coordination. Modern implementations use `{TEST_KEY}_listener_multiaddr`.
/// This proxy intercepts Redis commands and rewrites key names so legacy and
/// modern containers can share a single global Redis instance.

const LEGACY_KEY: &[u8] = b"listenerAddr";

fn modern_key(test_key: &str) -> Vec<u8> {
    format!("{}_listener_multiaddr", test_key).into_bytes()
}

#[tokio::main]
async fn main() {
    let test_key = env::var("TEST_KEY").expect("TEST_KEY env var required");
    let redis_addr = env::var("REDIS_ADDR").expect("REDIS_ADDR env var required");
    let modern = modern_key(&test_key);

    let listener = TcpListener::bind("0.0.0.0:6379")
        .await
        .expect("failed to bind 0.0.0.0:6379");

    eprintln!(
        "redis-proxy: listening on :6379, upstream={}, test_key={}",
        redis_addr, test_key
    );

    loop {
        let (client, addr) = match listener.accept().await {
            Ok(v) => v,
            Err(e) => {
                eprintln!("redis-proxy: accept error: {}", e);
                continue;
            }
        };
        eprintln!("redis-proxy: new connection from {}", addr);

        let upstream_addr = redis_addr.clone();
        let modern = modern.clone();

        tokio::spawn(async move {
            if let Err(e) = handle_connection(client, &upstream_addr, &modern).await {
                eprintln!("redis-proxy: connection error: {}", e);
            }
        });
    }
}

async fn handle_connection(
    mut client: TcpStream,
    upstream_addr: &str,
    modern_key: &[u8],
) -> Result<(), Box<dyn std::error::Error>> {
    let mut upstream = TcpStream::connect(upstream_addr).await?;

    let mut client_buf = vec![0u8; 8192];
    let mut upstream_buf = vec![0u8; 8192];

    // Accumulation buffers for partial RESP messages
    let mut client_acc = Vec::new();
    let mut upstream_acc = Vec::new();

    loop {
        tokio::select! {
            n = client.read(&mut client_buf) => {
                let n = n?;
                if n == 0 {
                    return Ok(());
                }
                client_acc.extend_from_slice(&client_buf[..n]);

                // Try to parse and rewrite complete RESP messages
                let mut offset = 0;
                while offset < client_acc.len() {
                    match parse_resp(&client_acc[offset..]) {
                        Some((msg, consumed)) => {
                            let rewritten = rewrite_client_command(&msg, modern_key);
                            let out = serialize_resp(&rewritten);
                            upstream.write_all(&out).await?;
                            offset += consumed;
                        }
                        None => break, // incomplete message, wait for more data
                    }
                }
                if offset > 0 {
                    client_acc.drain(..offset);
                }
            }
            n = upstream.read(&mut upstream_buf) => {
                let n = n?;
                if n == 0 {
                    return Ok(());
                }
                upstream_acc.extend_from_slice(&upstream_buf[..n]);

                // Try to parse and rewrite complete RESP responses
                let mut offset = 0;
                while offset < upstream_acc.len() {
                    match parse_resp(&upstream_acc[offset..]) {
                        Some((msg, consumed)) => {
                            let rewritten = rewrite_upstream_response(&msg, modern_key);
                            let out = serialize_resp(&rewritten);
                            client.write_all(&out).await?;
                            offset += consumed;
                        }
                        None => break,
                    }
                }
                if offset > 0 {
                    upstream_acc.drain(..offset);
                }
            }
        }
    }
}

/// Minimal RESP value representation.
#[derive(Debug, Clone)]
enum Resp {
    Simple(Vec<u8>),       // +OK\r\n
    Error(Vec<u8>),        // -ERR ...\r\n
    Integer(i64),          // :123\r\n
    Bulk(Option<Vec<u8>>), // $N\r\n...\r\n or $-1\r\n
    Array(Option<Vec<Resp>>), // *N\r\n... or *-1\r\n
}

/// Parse one RESP value from the buffer. Returns (value, bytes_consumed) or None if incomplete.
fn parse_resp(buf: &[u8]) -> Option<(Resp, usize)> {
    if buf.is_empty() {
        return None;
    }
    match buf[0] {
        b'+' => parse_simple_line(buf, false),
        b'-' => parse_simple_line(buf, true),
        b':' => parse_integer(buf),
        b'$' => parse_bulk(buf),
        b'*' => parse_array(buf),
        _ => {
            // Inline command: treat entire line as a simple string
            let end = find_crlf(buf)?;
            Some((Resp::Simple(buf[..end].to_vec()), end + 2))
        }
    }
}

fn find_crlf(buf: &[u8]) -> Option<usize> {
    for i in 0..buf.len().saturating_sub(1) {
        if buf[i] == b'\r' && buf[i + 1] == b'\n' {
            return Some(i);
        }
    }
    None
}

fn parse_simple_line(buf: &[u8], is_error: bool) -> Option<(Resp, usize)> {
    let end = find_crlf(buf)?;
    let data = buf[1..end].to_vec();
    let consumed = end + 2;
    if is_error {
        Some((Resp::Error(data), consumed))
    } else {
        Some((Resp::Simple(data), consumed))
    }
}

fn parse_integer(buf: &[u8]) -> Option<(Resp, usize)> {
    let end = find_crlf(buf)?;
    let s = std::str::from_utf8(&buf[1..end]).ok()?;
    let n: i64 = s.parse().ok()?;
    Some((Resp::Integer(n), end + 2))
}

fn parse_bulk(buf: &[u8]) -> Option<(Resp, usize)> {
    let end = find_crlf(buf)?;
    let s = std::str::from_utf8(&buf[1..end]).ok()?;
    let len: i64 = s.parse().ok()?;
    let header_len = end + 2;

    if len < 0 {
        return Some((Resp::Bulk(None), header_len));
    }
    let len = len as usize;
    let total = header_len + len + 2;
    if buf.len() < total {
        return None; // incomplete
    }
    let data = buf[header_len..header_len + len].to_vec();
    Some((Resp::Bulk(Some(data)), total))
}

fn parse_array(buf: &[u8]) -> Option<(Resp, usize)> {
    let end = find_crlf(buf)?;
    let s = std::str::from_utf8(&buf[1..end]).ok()?;
    let count: i64 = s.parse().ok()?;
    let mut offset = end + 2;

    if count < 0 {
        return Some((Resp::Array(None), offset));
    }

    let mut items = Vec::with_capacity(count as usize);
    for _ in 0..count {
        let (item, consumed) = parse_resp(&buf[offset..])?;
        items.push(item);
        offset += consumed;
    }
    Some((Resp::Array(Some(items)), offset))
}

fn serialize_resp(val: &Resp) -> Vec<u8> {
    let mut out = Vec::new();
    serialize_into(&mut out, val);
    out
}

fn serialize_into(out: &mut Vec<u8>, val: &Resp) {
    match val {
        Resp::Simple(s) => {
            out.push(b'+');
            out.extend_from_slice(s);
            out.extend_from_slice(b"\r\n");
        }
        Resp::Error(s) => {
            out.push(b'-');
            out.extend_from_slice(s);
            out.extend_from_slice(b"\r\n");
        }
        Resp::Integer(n) => {
            out.push(b':');
            out.extend_from_slice(n.to_string().as_bytes());
            out.extend_from_slice(b"\r\n");
        }
        Resp::Bulk(None) => {
            out.extend_from_slice(b"$-1\r\n");
        }
        Resp::Bulk(Some(data)) => {
            out.push(b'$');
            out.extend_from_slice(data.len().to_string().as_bytes());
            out.extend_from_slice(b"\r\n");
            out.extend_from_slice(data);
            out.extend_from_slice(b"\r\n");
        }
        Resp::Array(None) => {
            out.extend_from_slice(b"*-1\r\n");
        }
        Resp::Array(Some(items)) => {
            out.push(b'*');
            out.extend_from_slice(items.len().to_string().as_bytes());
            out.extend_from_slice(b"\r\n");
            for item in items {
                serialize_into(out, item);
            }
        }
    }
}

/// Check if a bulk string equals the legacy key.
fn is_legacy_key(val: &Resp) -> bool {
    matches!(val, Resp::Bulk(Some(data)) if data == LEGACY_KEY)
}

/// Replace legacy key with modern key in a bulk string.
fn replace_key(val: &Resp, modern: &[u8]) -> Resp {
    if is_legacy_key(val) {
        Resp::Bulk(Some(modern.to_vec()))
    } else {
        val.clone()
    }
}

/// Extract command name from an array command (uppercase for comparison).
fn get_command_name(items: &[Resp]) -> Option<Vec<u8>> {
    match items.first()? {
        Resp::Bulk(Some(data)) => Some(data.to_ascii_uppercase()),
        _ => None,
    }
}

/// Rewrite client→upstream commands, translating legacy keys to modern.
fn rewrite_client_command(msg: &Resp, modern: &[u8]) -> Resp {
    let items = match msg {
        Resp::Array(Some(items)) if items.len() >= 2 => items,
        _ => return msg.clone(),
    };

    let cmd = match get_command_name(items) {
        Some(c) => c,
        None => return msg.clone(),
    };

    match cmd.as_slice() {
        // RPUSH key value [value ...]
        b"RPUSH" => {
            let mut new_items = vec![items[0].clone(), replace_key(&items[1], modern)];
            new_items.extend_from_slice(&items[2..]);
            Resp::Array(Some(new_items))
        }
        // BLPOP key [key ...] timeout
        b"BLPOP" => {
            let mut new_items = vec![items[0].clone()];
            // Keys are args 1..N-1, last arg is timeout
            for i in 1..items.len() - 1 {
                new_items.push(replace_key(&items[i], modern));
            }
            // Timeout (last arg)
            new_items.push(items[items.len() - 1].clone());
            Resp::Array(Some(new_items))
        }
        // DEL key [key ...]
        b"DEL" => {
            let mut new_items = vec![items[0].clone()];
            for item in &items[1..] {
                new_items.push(replace_key(item, modern));
            }
            Resp::Array(Some(new_items))
        }
        // Everything else: passthrough
        _ => msg.clone(),
    }
}

/// Rewrite upstream→client responses, translating modern keys back to legacy.
/// This is needed for BLPOP responses which include the key name.
fn rewrite_upstream_response(msg: &Resp, modern: &[u8]) -> Resp {
    // BLPOP returns: *2\r\n $<keylen>\r\n<key>\r\n $<vallen>\r\n<val>\r\n
    // We need to translate the key back from modern to legacy.
    match msg {
        Resp::Array(Some(items)) if items.len() == 2 => {
            if let Resp::Bulk(Some(key)) = &items[0] {
                if key == modern {
                    return Resp::Array(Some(vec![
                        Resp::Bulk(Some(LEGACY_KEY.to_vec())),
                        items[1].clone(),
                    ]));
                }
            }
            msg.clone()
        }
        _ => msg.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_bulk_string() {
        let input = b"$12\r\nlistenerAddr\r\n";
        let (resp, consumed) = parse_resp(input).unwrap();
        assert_eq!(consumed, input.len());
        assert!(matches!(resp, Resp::Bulk(Some(ref d)) if d == LEGACY_KEY));
    }

    #[test]
    fn test_parse_array() {
        let input = b"*3\r\n$5\r\nRPUSH\r\n$12\r\nlistenerAddr\r\n$5\r\nvalue\r\n";
        let (resp, consumed) = parse_resp(input).unwrap();
        assert_eq!(consumed, input.len());
        assert!(matches!(resp, Resp::Array(Some(ref items)) if items.len() == 3));
    }

    #[test]
    fn test_rewrite_rpush() {
        let modern = b"abc12345_listener_multiaddr";
        let cmd = Resp::Array(Some(vec![
            Resp::Bulk(Some(b"RPUSH".to_vec())),
            Resp::Bulk(Some(b"listenerAddr".to_vec())),
            Resp::Bulk(Some(b"/ip4/10.0.0.1/tcp/1234".to_vec())),
        ]));
        let rewritten = rewrite_client_command(&cmd, modern);
        if let Resp::Array(Some(items)) = rewritten {
            assert!(matches!(&items[1], Resp::Bulk(Some(k)) if k == modern));
        } else {
            panic!("expected array");
        }
    }

    #[test]
    fn test_rewrite_blpop() {
        let modern = b"abc12345_listener_multiaddr";
        let cmd = Resp::Array(Some(vec![
            Resp::Bulk(Some(b"BLPOP".to_vec())),
            Resp::Bulk(Some(b"listenerAddr".to_vec())),
            Resp::Bulk(Some(b"0".to_vec())),
        ]));
        let rewritten = rewrite_client_command(&cmd, modern);
        if let Resp::Array(Some(items)) = rewritten {
            assert!(matches!(&items[1], Resp::Bulk(Some(k)) if k == modern));
            // Timeout should be unchanged
            assert!(matches!(&items[2], Resp::Bulk(Some(v)) if v == b"0"));
        } else {
            panic!("expected array");
        }
    }

    #[test]
    fn test_rewrite_blpop_response() {
        let modern = b"abc12345_listener_multiaddr";
        let resp = Resp::Array(Some(vec![
            Resp::Bulk(Some(modern.to_vec())),
            Resp::Bulk(Some(b"/ip4/10.0.0.1/tcp/1234".to_vec())),
        ]));
        let rewritten = rewrite_upstream_response(&resp, modern);
        if let Resp::Array(Some(items)) = rewritten {
            assert!(matches!(&items[0], Resp::Bulk(Some(k)) if k == LEGACY_KEY));
        } else {
            panic!("expected array");
        }
    }

    #[test]
    fn test_passthrough_ping() {
        let modern = b"abc12345_listener_multiaddr";
        let cmd = Resp::Array(Some(vec![Resp::Bulk(Some(b"PING".to_vec()))]));
        let rewritten = rewrite_client_command(&cmd, modern);
        let serialized = serialize_resp(&rewritten);
        assert_eq!(serialized, b"*1\r\n$4\r\nPING\r\n");
    }

    #[test]
    fn test_roundtrip_serialize() {
        let msg = Resp::Array(Some(vec![
            Resp::Bulk(Some(b"SET".to_vec())),
            Resp::Bulk(Some(b"key".to_vec())),
            Resp::Bulk(Some(b"value".to_vec())),
        ]));
        let bytes = serialize_resp(&msg);
        let (parsed, _) = parse_resp(&bytes).unwrap();
        let bytes2 = serialize_resp(&parsed);
        assert_eq!(bytes, bytes2);
    }
}
