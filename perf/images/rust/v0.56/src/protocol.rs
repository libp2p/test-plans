// libp2p perf protocol implementation
// Based on: https://github.com/libp2p/specs/blob/master/perf/perf.md

use libp2p::StreamProtocol;

// Protocol constants
pub const PERF_PROTOCOL: StreamProtocol = StreamProtocol::new("/perf/1.0.0");
pub const BLOCK_SIZE: usize = 64 * 1024; // 64KB blocks

// Perf protocol request
#[derive(Debug, Clone)]
pub struct PerfRequest {
    pub send_bytes: u64,    // Bytes client will send to server
    pub recv_bytes: u64,    // Bytes client wants to receive from server
}

// Perf protocol response
#[derive(Debug, Clone)]
pub struct PerfResponse {
    pub bytes_sent: u64,     // Bytes server sent back
    pub _bytes_received: u64, // Bytes server received from client
}

// Perf protocol codec
#[derive(Debug, Clone, Default)]
pub struct PerfCodec;

#[async_trait::async_trait]
impl libp2p::request_response::Codec for PerfCodec {
    type Protocol = StreamProtocol;
    type Request = PerfRequest;
    type Response = PerfResponse;

    async fn read_request<T>(&mut self, _protocol: &Self::Protocol, io: &mut T)
        -> std::io::Result<Self::Request>
    where
        T: futures::AsyncRead + Unpin + Send,
    {
        use futures::AsyncReadExt;

        let mut buf = [0u8; 8];

        // Read how many bytes client will send (8 bytes, big-endian u64)
        io.read_exact(&mut buf).await?;
        let send_bytes = u64::from_be_bytes(buf);

        // Read how many bytes client wants to receive (8 bytes, big-endian u64)
        io.read_exact(&mut buf).await?;
        let recv_bytes = u64::from_be_bytes(buf);

        // Drain the client's upload data
        let mut total_received = 0u64;
        let mut read_buf = vec![0u8; BLOCK_SIZE];

        while total_received < send_bytes {
            let to_read = std::cmp::min(send_bytes - total_received, BLOCK_SIZE as u64) as usize;
            let n = io.read(&mut read_buf[..to_read]).await?;
            if n == 0 {
                break;  // EOF
            }
            total_received += n as u64;
        }

        Ok(PerfRequest { send_bytes, recv_bytes })
    }

    async fn read_response<T>(&mut self, _protocol: &Self::Protocol, io: &mut T)
        -> std::io::Result<Self::Response>
    where
        T: futures::AsyncRead + Unpin + Send,
    {
        use futures::AsyncReadExt;

        // Read data from server
        let mut total = 0u64;
        let mut buf = vec![0u8; BLOCK_SIZE];

        loop {
            match io.read(&mut buf).await? {
                0 => break,  // EOF
                n => total += n as u64,
            }
        }

        Ok(PerfResponse {
            bytes_sent: 0,
            _bytes_received: total,
        })
    }

    async fn write_request<T>(&mut self, _protocol: &Self::Protocol, io: &mut T, req: Self::Request)
        -> std::io::Result<()>
    where
        T: futures::AsyncWrite + Unpin + Send,
    {
        use futures::AsyncWriteExt;

        // Send BOTH byte counts (16 bytes total)
        // First: how many bytes we will send
        io.write_all(&req.send_bytes.to_be_bytes()).await?;
        // Second: how many bytes we want to receive
        io.write_all(&req.recv_bytes.to_be_bytes()).await?;

        // Send our data
        let mut sent = 0u64;
        let block = vec![0u8; BLOCK_SIZE];

        while sent < req.send_bytes {
            let to_send = std::cmp::min(req.send_bytes - sent, BLOCK_SIZE as u64);
            io.write_all(&block[..to_send as usize]).await?;
            sent += to_send;
        }

        io.flush().await?;
        Ok(())
    }

    async fn write_response<T>(&mut self, _protocol: &Self::Protocol, io: &mut T, res: Self::Response)
        -> std::io::Result<()>
    where
        T: futures::AsyncWrite + Unpin + Send,
    {
        use futures::AsyncWriteExt;

        // Send the requested bytes back
        let mut sent = 0u64;
        let block = vec![0u8; BLOCK_SIZE];

        while sent < res.bytes_sent {
            let to_send = std::cmp::min(res.bytes_sent - sent, BLOCK_SIZE as u64);
            io.write_all(&block[..to_send as usize]).await?;
            sent += to_send;
        }

        io.flush().await?;
        Ok(())
    }
}

