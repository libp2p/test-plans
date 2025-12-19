package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"math"
	"math/big"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"golang.org/x/net/context"
)

var (
	isDialer      = os.Getenv("IS_DIALER") == "true"
	redisAddr     = getEnvOrDefault("REDIS_ADDR", "redis:6379")
	testKey       = getEnvOrDefault("TEST_KEY", "default")
	listenerIP    = getEnvOrDefault("LISTENER_IP", "10.5.0.10")
	uploadBytes   int64
	downloadBytes int64
	uploadIters   int
	downloadIters int
	latencyIters  int
)

type Stats struct {
	Min      float64
	Q1       float64
	Median   float64
	Q3       float64
	Max      float64
	Outliers []float64
	Samples  []float64
}

func main() {
	log.SetOutput(os.Stderr)

	// Parse environment variables
	uploadBytes, _ = strconv.ParseInt(os.Getenv("UPLOAD_BYTES"), 10, 64)
	downloadBytes, _ = strconv.ParseInt(os.Getenv("DOWNLOAD_BYTES"), 10, 64)
	uploadIters, _ = strconv.Atoi(os.Getenv("UPLOAD_ITERATIONS"))
	downloadIters, _ = strconv.Atoi(os.Getenv("DOWNLOAD_ITERATIONS"))
	latencyIters, _ = strconv.Atoi(os.Getenv("LATENCY_ITERATIONS"))

	// Set defaults
	if uploadBytes == 0 {
		uploadBytes = 1073741824 // 1GB
	}
	if downloadBytes == 0 {
		downloadBytes = 1073741824 // 1GB
	}
	if uploadIters == 0 {
		uploadIters = 10
	}
	if downloadIters == 0 {
		downloadIters = 10
	}
	if latencyIters == 0 {
		latencyIters = 100
	}

	if isDialer {
		runClientMode()
	} else {
		runListenerMode()
	}
}

func runListenerMode() {
	log.Println("Starting HTTPS listener on :4001...")

	// Generate self-signed certificate
	tlsCert := generateTLSCert()

	// Set up HTTP handlers
	http.HandleFunc("/upload", func(w http.ResponseWriter, r *http.Request) {
		io.Copy(io.Discard, r.Body)
		w.WriteHeader(http.StatusOK)
	})

	http.HandleFunc("/download", func(w http.ResponseWriter, r *http.Request) {
		sizeStr := r.URL.Query().Get("bytes")
		size, _ := strconv.ParseInt(sizeStr, 10, 64)
		if size <= 0 {
			size = 1024
		}
		io.Copy(w, io.LimitReader(zeroReader{}, size))
	})

	// Publish listener address to Redis with TEST_KEY namespacing
	multiaddr := fmt.Sprintf("/ip4/%s/tcp/4001/https", listenerIP)
	log.Printf("Publishing listener address to Redis: %s", multiaddr)

	ctx := context.Background()
	rdb := redis.NewClient(&redis.Options{
		Addr: redisAddr,
	})
	defer rdb.Close()

	listenerAddrKey := fmt.Sprintf("%s_listener_multiaddr", testKey)
	err := rdb.Set(ctx, listenerAddrKey, multiaddr, 0).Err()
	if err != nil {
		log.Fatalf("Failed to publish to Redis (key: %s): %v", listenerAddrKey, err)
	}

	log.Printf("Published to Redis (key: %s)", listenerAddrKey)
	log.Println("HTTPS listener ready")

	// Start HTTPS server
	server := &http.Server{
		Addr:      ":4001",
		TLSConfig: &tls.Config{Certificates: []tls.Certificate{tlsCert}},
	}

	log.Fatal(server.ListenAndServeTLS("", ""))
}

func runClientMode() {
	log.Println("Running as dialer/client...")

	// Get listener address from Redis
	ctx := context.Background()
	rdb := redis.NewClient(&redis.Options{
		Addr: redisAddr,
	})
	defer rdb.Close()

	log.Println("Waiting for listener address from Redis...")
	listenerAddrKey := fmt.Sprintf("%s_listener_multiaddr", testKey)
	var listenerAddr string
	for i := 0; i < 60; i++ {
		addr, err := rdb.Get(ctx, listenerAddrKey).Result()
		if err == nil && addr != "" {
			listenerAddr = addr
			break
		}
		time.Sleep(1 * time.Second)
	}

	if listenerAddr == "" {
		log.Fatalf("Timeout waiting for listener address from Redis (key: %s)", listenerAddrKey)
	}

	log.Printf("Got listener address: %s (key: %s)", listenerAddr, listenerAddrKey)

	// Parse multiaddr to get IP and port
	// Format: /ip4/{IP}/tcp/{PORT}/https
	parts := strings.Split(listenerAddr, "/")
	if len(parts) < 5 {
		log.Fatalf("Invalid multiaddr format: %s", listenerAddr)
	}
	serverIP := parts[2]
	serverPort := parts[4]
	serverAddr := fmt.Sprintf("%s:%s", serverIP, serverPort)

	log.Printf("Connecting to HTTPS server: %s", serverAddr)

	// Create HTTP client with TLS
	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
		Timeout: 60 * time.Second,
	}

	// Run upload test
	log.Printf("Running upload test (%d iterations)...", uploadIters)
	uploadStats := runUploadTest(client, serverAddr, uploadBytes, uploadIters)

	// Run download test
	log.Printf("Running download test (%d iterations)...", downloadIters)
	downloadStats := runDownloadTest(client, serverAddr, downloadBytes, downloadIters)

	// Run latency test
	log.Printf("Running latency test (%d iterations)...", latencyIters)
	latencyStats := runLatencyTest(client, serverAddr, latencyIters)

	// Output results as YAML to stdout
	fmt.Println("# Upload measurement")
	fmt.Println("upload:")
	fmt.Printf("  iterations: %d\n", uploadIters)
	fmt.Printf("  min: %.2f\n", uploadStats.Min)
	fmt.Printf("  q1: %.2f\n", uploadStats.Q1)
	fmt.Printf("  median: %.2f\n", uploadStats.Median)
	fmt.Printf("  q3: %.2f\n", uploadStats.Q3)
	fmt.Printf("  max: %.2f\n", uploadStats.Max)
	printOutliers(uploadStats.Outliers, 2)
	printSamples(uploadStats.Samples, 2)
	fmt.Println("  unit: Gbps")
	fmt.Println()

	fmt.Println("# Download measurement")
	fmt.Println("download:")
	fmt.Printf("  iterations: %d\n", downloadIters)
	fmt.Printf("  min: %.2f\n", downloadStats.Min)
	fmt.Printf("  q1: %.2f\n", downloadStats.Q1)
	fmt.Printf("  median: %.2f\n", downloadStats.Median)
	fmt.Printf("  q3: %.2f\n", downloadStats.Q3)
	fmt.Printf("  max: %.2f\n", downloadStats.Max)
	printOutliers(downloadStats.Outliers, 2)
	printSamples(downloadStats.Samples, 2)
	fmt.Println("  unit: Gbps")
	fmt.Println()

	fmt.Println("# Latency measurement")
	fmt.Println("latency:")
	fmt.Printf("  iterations: %d\n", latencyIters)
	fmt.Printf("  min: %.3f\n", latencyStats.Min)
	fmt.Printf("  q1: %.3f\n", latencyStats.Q1)
	fmt.Printf("  median: %.3f\n", latencyStats.Median)
	fmt.Printf("  q3: %.3f\n", latencyStats.Q3)
	fmt.Printf("  max: %.3f\n", latencyStats.Max)
	printOutliers(latencyStats.Outliers, 3)
	printSamples(latencyStats.Samples, 3)
	fmt.Println("  unit: ms")

	log.Println("All measurements complete!")
}

func runUploadTest(client *http.Client, serverAddr string, bytes int64, iterations int) Stats {
	var values []float64

	for i := 0; i < iterations; i++ {
		start := time.Now()

		resp, err := client.Post(
			fmt.Sprintf("https://%s/upload", serverAddr),
			"application/octet-stream",
			io.LimitReader(zeroReader{}, bytes),
		)
		if err != nil {
			log.Printf("Upload iteration %d failed: %v", i+1, err)
			continue
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()

		elapsed := time.Since(start).Seconds()
		gbps := float64(bytes*8) / elapsed / 1e9

		values = append(values, gbps)
		log.Printf("  Iteration %d/%d: %.2f Gbps", i+1, iterations, gbps)
	}

	return calculateStats(values)
}

func runDownloadTest(client *http.Client, serverAddr string, bytes int64, iterations int) Stats {
	var values []float64

	for i := 0; i < iterations; i++ {
		start := time.Now()

		resp, err := client.Get(
			fmt.Sprintf("https://%s/download?bytes=%d", serverAddr, bytes),
		)
		if err != nil {
			log.Printf("Download iteration %d failed: %v", i+1, err)
			continue
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()

		elapsed := time.Since(start).Seconds()
		gbps := float64(bytes*8) / elapsed / 1e9

		values = append(values, gbps)
		log.Printf("  Iteration %d/%d: %.2f Gbps", i+1, iterations, gbps)
	}

	return calculateStats(values)
}

func runLatencyTest(client *http.Client, serverAddr string, iterations int) Stats {
	var values []float64

	for i := 0; i < iterations; i++ {
		start := time.Now()

		resp, err := client.Get(fmt.Sprintf("https://%s/download?bytes=1", serverAddr))
		if err != nil {
			log.Printf("Latency iteration %d failed: %v", i+1, err)
			continue
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()

		elapsed := time.Since(start).Seconds()
		latencyMs := elapsed * 1000.0 // Convert to milliseconds with precision

		values = append(values, latencyMs)
	}

	return calculateStats(values)
}

func calculateStats(values []float64) Stats {
	if len(values) == 0 {
		return Stats{}
	}

	sort.Float64s(values)

	n := len(values)

	// Calculate percentiles
	q1 := percentile(values, 25.0)
	median := percentile(values, 50.0)
	q3 := percentile(values, 75.0)

	// Calculate IQR and identify outliers
	iqr := q3 - q1
	lowerFence := q1 - 1.5*iqr
	upperFence := q3 + 1.5*iqr

	// Separate outliers from non-outliers
	var outliers []float64
	var nonOutliers []float64
	for _, v := range values {
		if v < lowerFence || v > upperFence {
			outliers = append(outliers, v)
		} else {
			nonOutliers = append(nonOutliers, v)
		}
	}

	// Calculate min/max from non-outliers (if any exist)
	var min, max float64
	if len(nonOutliers) > 0 {
		min = nonOutliers[0]
		max = nonOutliers[len(nonOutliers)-1]
	} else {
		// Fallback if all values are outliers
		min = values[0]
		max = values[n-1]
	}

	return Stats{
		Min:      min,
		Q1:       q1,
		Median:   median,
		Q3:       q3,
		Max:      max,
		Outliers: outliers,
		Samples:  values,
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

func printSamples(samples []float64, decimals int) {
	if len(samples) == 0 {
		fmt.Println("  samples: []")
		return
	}

	fmt.Print("  samples: [")
	for i, v := range samples {
		if i > 0 {
			fmt.Print(", ")
		}
		fmt.Printf("%.*f", decimals, v)
	}
	fmt.Println("]")
}

func generateTLSCert() tls.Certificate {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		log.Fatal(err)
	}

	template := x509.Certificate{
		SerialNumber: big.NewInt(1),
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(24 * time.Hour),
	}

	certDER, err := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	if err != nil {
		log.Fatal(err)
	}

	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certDER})

	tlsCert, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		log.Fatal(err)
	}

	return tlsCert
}

func getEnvOrDefault(key, defaultValue string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultValue
}

type zeroReader struct{}

func (zeroReader) Read(p []byte) (n int, err error) {
	return len(p), nil
}
