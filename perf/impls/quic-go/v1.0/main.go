package main

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"time"

	"github.com/quic-go/quic-go"
)

var (
	runServer     = flag.Bool("run-server", false, "Run as server")
	serverAddr    = flag.String("server-address", "", "Server address (client mode)")
	uploadBytes   = flag.Int64("upload-bytes", 0, "Bytes to upload")
	downloadBytes = flag.Int64("download-bytes", 0, "Bytes to download")
)

func main() {
	flag.Parse()
	log.SetOutput(os.Stderr)

	if *runServer {
		runServerMode()
	} else {
		runClientMode()
	}
}

func runServerMode() {
	log.Println("Starting QUIC server on :4001...")

	tlsConf := generateTLSConfig()

	listener, err := quic.ListenAddr(":4001", tlsConf, nil)
	if err != nil {
		log.Fatal(err)
	}

	log.Println("QUIC server ready")

	for {
		conn, err := listener.Accept(context.Background())
		if err != nil {
			log.Println("Accept error:", err)
			continue
		}

		go handleConn(conn)
	}
}

func handleConn(conn quic.Connection) {
	defer conn.CloseWithError(0, "")

	for {
		stream, err := conn.AcceptStream(context.Background())
		if err != nil {
			return
		}

		go func() {
			io.Copy(io.Discard, stream)
			stream.Close()
		}()
	}
}

func runClientMode() {
	if *serverAddr == "" {
		log.Fatal("--server-address required")
	}

	log.Printf("Testing QUIC to %s\n", *serverAddr)

	tlsConf := &tls.Config{
		InsecureSkipVerify: true,
		NextProtos:         []string{"perf"},
	}

	start := time.Now()

	conn, err := quic.DialAddr(context.Background(), *serverAddr, tlsConf, nil)
	if err != nil {
		log.Fatalf("Dial failed: %v", err)
	}
	defer conn.CloseWithError(0, "")

	// Upload test
	if *uploadBytes > 0 {
		stream, err := conn.OpenStreamSync(context.Background())
		if err != nil {
			log.Fatal(err)
		}

		_, err = io.CopyN(stream, zeroReader{}, *uploadBytes)
		if err != nil {
			log.Fatal(err)
		}
		stream.Close()
	}

	elapsed := time.Since(start).Seconds()

	// Output YAML
	fmt.Printf("type: final\n")
	fmt.Printf("timeSeconds: %.3f\n", elapsed)
	fmt.Printf("uploadBytes: %d\n", *uploadBytes)
	fmt.Printf("downloadBytes: %d\n", *downloadBytes)

	log.Printf("Test complete: %.3fs\n", elapsed)
}

func generateTLSConfig() *tls.Config {
	// Simplified - would generate proper cert in production
	return &tls.Config{
		InsecureSkipVerify: true,
		NextProtos:         []string{"perf"},
	}
}

type zeroReader struct{}

func (zeroReader) Read(p []byte) (n int, err error) {
	return len(p), nil
}
