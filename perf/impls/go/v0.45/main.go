package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/perf"
	"github.com/multiformats/go-multiaddr"
)

var (
	runServer      = flag.Bool("run-server", false, "Run as server")
	serverAddr     = flag.String("server-address", "", "Server multiaddr (client mode)")
	transport      = flag.String("transport", "tcp", "Transport to use (tcp, quic-v1, webtransport)")
	uploadBytes    = flag.Int64("upload-bytes", 0, "Bytes to upload")
	downloadBytes  = flag.Int64("download-bytes", 0, "Bytes to download")
	durationSec    = flag.Int("duration", 20, "Duration in seconds")
)

func main() {
	flag.Parse()

	// Log to stderr
	log.SetOutput(os.Stderr)

	if *runServer {
		runServerMode()
	} else {
		runClientMode()
	}
}

func runServerMode() {
	log.Println("Starting perf server...")

	// Create libp2p host
	h, err := libp2p.New(
		libp2p.ListenAddrStrings(
			"/ip4/0.0.0.0/tcp/4001",
			"/ip4/0.0.0.0/udp/4001/quic-v1",
		),
	)
	if err != nil {
		log.Fatal(err)
	}

	log.Printf("Server listening on: %v\n", h.Addrs())
	log.Printf("Peer ID: %s\n", h.ID())

	// Register perf protocol handler
	perf.RegisterPerfService(h)

	log.Println("Perf server ready")

	// Keep server running
	select {}
}

func runClientMode() {
	if *serverAddr == "" {
		log.Fatal("--server-address required in client mode")
	}

	log.Printf("Connecting to server: %s\n", *serverAddr)
	log.Printf("Upload: %d bytes, Download: %d bytes\n", *uploadBytes, *downloadBytes)

	// Create libp2p host
	h, err := libp2p.New()
	if err != nil {
		log.Fatalf("Failed to create host: %v", err)
	}
	defer h.Close()

	// Parse server multiaddr
	addr, err := multiaddr.NewMultiaddr(*serverAddr)
	if err != nil {
		log.Fatalf("Invalid server address: %v", err)
	}

	// Extract peer ID and add addr
	addrInfo, err := peer.AddrInfoFromP2pAddr(addr)
	if err != nil {
		log.Fatalf("Failed to parse addr: %v", err)
	}

	// Connect to server
	ctx := context.Background()
	if err := h.Connect(ctx, *addrInfo); err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}

	log.Printf("Connected to %s\n", addrInfo.ID)

	// Run perf test
	start := time.Now()

	result, err := perf.Send(ctx, h, addrInfo.ID, *uploadBytes, *downloadBytes)
	if err != nil {
		log.Fatalf("Perf test failed: %v", err)
	}

	elapsed := time.Since(start).Seconds()

	// Output results as YAML to stdout
	fmt.Printf("type: final\n")
	fmt.Printf("timeSeconds: %.3f\n", elapsed)
	fmt.Printf("uploadBytes: %d\n", result.UploadBytes)
	fmt.Printf("downloadBytes: %d\n", result.DownloadBytes)

	log.Printf("Test complete: %.3fs\n", elapsed)
}
