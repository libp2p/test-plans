#!/usr/bin/env python3

"""
Python test harness for js-libp2p Echo protocol interoperability tests
"""

import os
import sys
import json
import time
import trio
import redis
import structlog
from libp2p import new_host
from libp2p.network.stream.net_stream_interface import INetStream

logger = structlog.get_logger(__name__)

# Configuration from environment
TRANSPORT = os.getenv('TRANSPORT', 'tcp')
SECURITY = os.getenv('SECURITY', 'noise')
MUXER = os.getenv('MUXER', 'yamux')
REDIS_ADDR = os.getenv('REDIS_ADDR', 'redis://localhost:6379')
ECHO_PROTOCOL = '/echo/1.0.0'

async def get_server_multiaddr():
    """Get JS echo server multiaddr from Redis"""
    try:
        r = redis.from_url(REDIS_ADDR)
        
        # Wait for server to publish multiaddr
        for _ in range(30):  # 30 second timeout
            multiaddrs = r.lrange('js-echo-server-multiaddr', 0, -1)
            if multiaddrs:
                return multiaddrs[-1].decode('utf-8')
            await trio.sleep(1)
        
        raise Exception("Timeout waiting for server multiaddr")
        
    except Exception as e:
        logger.error("Failed to get server multiaddr", error=str(e))
        raise

async def echo_test(multiaddr: str, test_data: bytes):
    """Perform echo test with the JS server"""
    try:
        # Create libp2p host
        host = new_host()
        await host.get_network().listen(multiaddr_list=[])
        
        # Connect to server
        server_info = host.get_network().multiaddr_to_peer_info(multiaddr)
        await host.connect(server_info)
        
        # Open echo protocol stream
        stream: INetStream = await host.new_stream(
            server_info.peer_id, 
            [ECHO_PROTOCOL]
        )
        
        # Send test data
        await stream.write(test_data)
        await stream.close()
        
        # Read response
        response = await stream.read()
        
        # Verify echo
        if response == test_data:
            return {"status": "passed", "data_length": len(test_data)}
        else:
            return {"status": "failed", "error": "Echo mismatch"}
            
    except Exception as e:
        logger.error("Echo test failed", error=str(e))
        return {"status": "failed", "error": str(e)}

async def main():
    """Main test function"""
    start_time = time.time()
    
    try:
        # Get server multiaddr
        multiaddr = await get_server_multiaddr()
        logger.info("Got server multiaddr", multiaddr=multiaddr)
        
        # Test cases
        test_cases = [
            b"Hello, Echo!",
            b"\x00\x01\x02\x03\x04",  # Binary data
            b"A" * 1024,  # Larger payload
        ]
        
        results = []
        for i, test_data in enumerate(test_cases):
            logger.info(f"Running test case {i+1}")
            result = await echo_test(multiaddr, test_data)
            results.append(result)
        
        # Output results as JSON
        output = {
            "test": "echo-protocol",
            "transport": TRANSPORT,
            "security": SECURITY,
            "muxer": MUXER,
            "duration": time.time() - start_time,
            "results": results,
            "passed": all(r["status"] == "passed" for r in results)
        }
        
        print(json.dumps(output))
        
        # Exit with appropriate code
        sys.exit(0 if output["passed"] else 1)
        
    except Exception as e:
        logger.error("Test failed", error=str(e))
        output = {
            "test": "echo-protocol",
            "transport": TRANSPORT,
            "security": SECURITY,
            "muxer": MUXER,
            "duration": time.time() - start_time,
            "error": str(e),
            "passed": False
        }
        print(json.dumps(output))
        sys.exit(1)

if __name__ == "__main__":
    trio.run(main)