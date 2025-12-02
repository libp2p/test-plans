#!/usr/bin/env python3
"""
Simple TCP relay for hole punch interop tests.
Accepts two connections and bidirectionally relays data between them.
"""

import socket
import threading
import sys
import time
from datetime import datetime

def log(msg):
    timestamp = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%fZ')[:-3]
    print(f"[RELAY-PY] {timestamp} {msg}", file=sys.stderr, flush=True)

def relay_data(source, dest, label):
    """Relay data from source socket to dest socket."""
    try:
        while True:
            data = source.recv(4096)
            if not data:
                log(f"{label}: Connection closed")
                break
            log(f"{label}: Relaying {len(data)} bytes")
            dest.sendall(data)
    except Exception as e:
        log(f"{label}: Error - {e}")
    finally:
        try:
            source.close()
        except:
            pass
        try:
            dest.close()
        except:
            pass

def run_relay(relay_ip, relay_port):
    """Run the relay server."""
    log(f"Starting relay server on {relay_ip}:{relay_port}")

    # Create server socket
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((relay_ip, relay_port))
    server.listen(2)

    log(f"Listening for connections...")

    # Accept first connection (listener)
    log("Waiting for first peer (listener)...")
    conn1, addr1 = server.accept()
    log(f"First peer connected from {addr1}")

    # Read identification
    ident1 = conn1.recv(1024).decode().strip()
    log(f"First peer identified as: {ident1}")

    # Accept second connection (dialer)
    log("Waiting for second peer (dialer)...")
    conn2, addr2 = server.accept()
    log(f"Second peer connected from {addr2}")

    # Read identification
    ident2 = conn2.recv(1024).decode().strip()
    log(f"Second peer identified as: {ident2}")

    log("Both peers connected, starting bidirectional relay...")

    # Start relay threads
    thread1 = threading.Thread(
        target=relay_data,
        args=(conn1, conn2, f"{ident1} -> {ident2}"),
        daemon=True
    )
    thread2 = threading.Thread(
        target=relay_data,
        args=(conn2, conn1, f"{ident2} -> {ident1}"),
        daemon=True
    )

    thread1.start()
    thread2.start()

    # Wait for threads to complete
    thread1.join()
    thread2.join()

    log("Relay completed")
    server.close()

if __name__ == "__main__":
    if len(sys.argv) != 3:
        log("ERROR: Usage: relay.py <ip> <port>")
        sys.exit(1)

    relay_ip = sys.argv[1]
    relay_port = int(sys.argv[2])

    try:
        run_relay(relay_ip, relay_port)
    except Exception as e:
        log(f"ERROR: {e}")
        sys.exit(1)
