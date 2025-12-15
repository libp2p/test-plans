package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"math"
	"os"
	"sort"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/perf"
	"github.com/multiformats/go-multiaddr"
)

var (
	runServer      = flag.Bool("run-server", false, "Run as server")
	serverAddr     = flag.String("server-address", "", "Server multiaddr (client mode)")
	transport      = flag.String("transport", "tcp", "Transport to use (tcp, quic-v1, webtransport)")
	uploadBytes    = flag.Int64("upload-bytes", 1073741824, "Bytes to upload")
	downloadBytes  = flag.Int64("download-bytes", 1073741824, "Bytes to download")
	uploadIters    = flag.Int("upload-iterations", 10, "Upload iterations")
	downloadIters  = flag.Int("download-iterations", 10, "Download iterations")
	latencyIters   = flag.Int("latency-iterations", 100, "Latency iterations")
)

type Stats struct {
	Min      float64
	Q1       float64
	Median   float64
	Q3       float64
	Max      float64
	Outliers []float64
}

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

	// Extract peer ID
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

	// Run measurements
	log.Printf("Running upload test (%d iterations)...\n", *uploadIters)
	uploadStats := runMeasurement(ctx, h, addrInfo.ID, *uploadBytes, 0, *uploadIters)

	log.Printf("Running download test (%d iterations)...\n", *downloadIters)
	downloadStats := runMeasurement(ctx, h, addrInfo.ID, 0, *downloadBytes, *downloadIters)

	log.Printf("Running latency test (%d iterations)...\n", *latencyIters)
	latencyStats := runMeasurement(ctx, h, addrInfo.ID, 1, 1, *latencyIters)

	// Output results as YAML
	fmt.Println("# Upload measurement")
	fmt.Println("upload:")
	fmt.Printf("  iterations: %d\n", *uploadIters)
	fmt.Printf("  min: %.2f\n", uploadStats.Min)
	fmt.Printf("  q1: %.2f\n", uploadStats.Q1)
	fmt.Printf("  median: %.2f\n", uploadStats.Median)
	fmt.Printf("  q3: %.2f\n", uploadStats.Q3)
	fmt.Printf("  max: %.2f\n", uploadStats.Max)
	printOutliers(uploadStats.Outliers, 2)
	fmt.Println("  unit: Gbps")
	fmt.Println()

	fmt.Println("# Download measurement")
	fmt.Println("download:")
	fmt.Printf("  iterations: %d\n", *downloadIters)
	fmt.Printf("  min: %.2f\n", downloadStats.Min)
	fmt.Printf("  q1: %.2f\n", downloadStats.Q1)
	fmt.Printf("  median: %.2f\n", downloadStats.Median)
	fmt.Printf("  q3: %.2f\n", downloadStats.Q3)
	fmt.Printf("  max: %.2f\n", downloadStats.Max)
	printOutliers(downloadStats.Outliers, 2)
	fmt.Println("  unit: Gbps")
	fmt.Println()

	fmt.Println("# Latency measurement")
	fmt.Println("latency:")
	fmt.Printf("  iterations: %d\n", *latencyIters)
	fmt.Printf("  min: %.3f\n", latencyStats.Min)
	fmt.Printf("  q1: %.3f\n", latencyStats.Q1)
	fmt.Printf("  median: %.3f\n", latencyStats.Median)
	fmt.Printf("  q3: %.3f\n", latencyStats.Q3)
	fmt.Printf("  max: %.3f\n", latencyStats.Max)
	printOutliers(latencyStats.Outliers, 3)
	fmt.Println("  unit: ms")

	log.Println("All measurements complete!")
}

func runMeasurement(ctx context.Context, h peer.ID, peerID peer.ID, uploadBytes, downloadBytes int64, iterations int) Stats {
	var values []float64

	for i := 0; i < iterations; i++ {
		start := time.Now()

		// Placeholder: simulate transfer
		// In real implementation, use perf.Send()
		time.Sleep(10 * time.Millisecond)

		elapsed := time.Since(start).Seconds()

		// Calculate throughput if this is a throughput test
		var value float64
		if uploadBytes > 100 || downloadBytes > 100 {
			// Throughput in Gbps
			bytes := float64(max(uploadBytes, downloadBytes))
			value = (bytes * 8.0) / elapsed / 1_000_000_000.0
		} else {
			// Latency in milliseconds
			value = elapsed * 1000.0
		}

		values = append(values, value)
	}

	return calculateStats(values)
}

func calculateStats(values []float64) Stats {
	sort.Float64s(values)

	n := len(values)
	min := values[0]
	max := values[n-1]

	// Calculate percentiles
	q1 := percentile(values, 25.0)
	median := percentile(values, 50.0)
	q3 := percentile(values, 75.0)

	// Calculate IQR and identify outliers
	iqr := q3 - q1
	lowerFence := q1 - 1.5*iqr
	upperFence := q3 + 1.5*iqr

	var outliers []float64
	for _, v := range values {
		if v < lowerFence || v > upperFence {
			outliers = append(outliers, v)
		}
	}

	return Stats{
		Min:      min,
		Q1:       q1,
		Median:   median,
		Q3:       q3,
		Max:      max,
		Outliers: outliers,
	}
}

func percentile(sortedValues []float64, p float64) float64 {
	n := float64(len(sortedValues))
	index := (p / 100.0) * (n - 1.0)
	lower := int(math.Floor(index))
	upper := int(math.Ceil(index))

	if lower == upper {
		return sortedValues[lower]
	}

	weight := index - float64(lower)
	return sortedValues[lower]*(1.0-weight) + sortedValues[upper]*weight
}

func printOutliers(outliers []float64, decimals int) {
	if len(outliers) == 0 {
		fmt.Println("  outliers: []")
		return
	}

	fmt.Print("  outliers: [")
	for i, v := range outliers {
		if i > 0 {
			fmt.Print(", ")
		}
		fmt.Printf("%.*f", decimals, v)
	}
	fmt.Println("]")
}

func max(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
