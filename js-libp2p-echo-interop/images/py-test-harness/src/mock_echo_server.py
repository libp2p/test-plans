"""Mock Echo server for testing purposes."""

import trio
import structlog
from typing import Optional

logger = structlog.get_logger(__name__)


class MockEchoServer:
    """Mock Echo server that implements the basic echo functionality."""
    
    def __init__(self, host: str = "127.0.0.1", port: int = 0):
        self.host = host
        self.port = port
        self.server_socket: Optional[trio.SocketListener] = None
        self.actual_port: Optional[int] = None
        self.nursery: Optional[trio.Nursery] = None
        self.running = False
    
    async def start(self) -> str:
        """Start the mock echo server and return its multiaddr."""
        try:
            # Create server socket
            self.server_socket = await trio.open_tcp_listeners(self.port, host=self.host)
            if isinstance(self.server_socket, list):
                self.server_socket = self.server_socket[0]
            
            self.actual_port = self.server_socket.socket.getsockname()[1]
            self.running = True
            
            # Generate a mock multiaddr
            multiaddr = f"/ip4/{self.host}/tcp/{self.actual_port}/p2p/12D3KooWMockPeerID123456789"
            
            logger.info(
                "Mock Echo server started",
                host=self.host,
                port=self.actual_port,
                multiaddr=multiaddr
            )
            
            return multiaddr
            
        except Exception as e:
            logger.error("Failed to start mock echo server", error=str(e))
            raise
    
    async def serve_forever(self) -> None:
        """Serve connections forever."""
        if not self.server_socket:
            raise RuntimeError("Server not started")
        
        async with trio.open_nursery() as nursery:
            self.nursery = nursery
            nursery.start_soon(self._accept_connections)
    
    async def _accept_connections(self) -> None:
        """Accept and handle incoming connections."""
        while self.running:
            try:
                stream = await self.server_socket.accept()
                # Handle each connection in a separate task
                if self.nursery:
                    self.nursery.start_soon(self._handle_connection, stream)
            except trio.ClosedResourceError:
                break
            except Exception as e:
                logger.error("Error accepting connection", error=str(e))
                break
    
    async def _handle_connection(self, stream: trio.SocketStream) -> None:
        """Handle a single connection."""
        try:
            logger.debug("Handling new connection")
            
            while True:
                # Read length prefix (4 bytes)
                try:
                    length_bytes = await self._receive_exactly(stream, 4)
                except trio.EndOfChannel:
                    break
                
                length = int.from_bytes(length_bytes, byteorder='big')
                
                if length == 0:
                    # Echo empty data
                    await stream.send_all(length_bytes)
                    continue
                
                # Read the actual data
                data = await self._receive_exactly(stream, length)
                
                # Echo the data back (send length prefix + data)
                await stream.send_all(length_bytes + data)
                
                logger.debug(
                    "Echoed data",
                    data_length=length,
                    data_preview=data[:50] if len(data) > 50 else data
                )
                
        except Exception as e:
            logger.debug("Connection handling error", error=str(e))
        finally:
            await stream.aclose()
            logger.debug("Connection closed")
    
    async def _receive_exactly(self, stream: trio.SocketStream, n: int) -> bytes:
        """Receive exactly n bytes from the socket."""
        data = b""
        while len(data) < n:
            chunk = await stream.receive_some(n - len(data))
            if not chunk:
                raise trio.EndOfChannel("Connection closed")
            data += chunk
        return data
    
    async def stop(self) -> None:
        """Stop the mock echo server."""
        self.running = False
        if self.server_socket:
            await self.server_socket.aclose()
            self.server_socket = None
        logger.info("Mock Echo server stopped")


async def run_mock_server(host: str = "127.0.0.1", port: int = 0) -> None:
    """Run the mock echo server."""
    server = MockEchoServer(host, port)
    multiaddr = await server.start()
    
    # Print multiaddr to stdout for coordination
    print(multiaddr)
    
    try:
        await server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Received interrupt, shutting down")
    finally:
        await server.stop()


if __name__ == "__main__":
    trio.run(run_mock_server)