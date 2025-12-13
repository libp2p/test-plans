package main

import (
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"
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
	log.Println("Starting HTTPS server on :4001...")

	http.HandleFunc("/upload", func(w http.ResponseWriter, r *http.Request) {
		io.Copy(io.Discard, r.Body)
		w.WriteHeader(http.StatusOK)
	})

	http.HandleFunc("/download", func(w http.ResponseWriter, r *http.Request) {
		// Send requested bytes
		size := r.URL.Query().Get("bytes")
		// Simplified - would parse size and send that many bytes
		w.Write(make([]byte, 1024))
	})

	log.Fatal(http.ListenAndServeTLS(":4001", "cert.pem", "key.pem", nil))
}

func runClientMode() {
	if *serverAddr == "" {
		log.Fatal("--server-address required")
	}

	log.Printf("Testing HTTPS to %s\n", *serverAddr)

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}

	start := time.Now()

	// Upload test
	if *uploadBytes > 0 {
		resp, err := client.Post(
			fmt.Sprintf("https://%s/upload", *serverAddr),
			"application/octet-stream",
			io.LimitReader(zeroReader{}, *uploadBytes),
		)
		if err != nil {
			log.Fatalf("Upload failed: %v", err)
		}
		resp.Body.Close()
	}

	// Download test
	if *downloadBytes > 0 {
		resp, err := client.Get(
			fmt.Sprintf("https://%s/download?bytes=%d", *serverAddr, *downloadBytes),
		)
		if err != nil {
			log.Fatalf("Download failed: %v", err)
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}

	elapsed := time.Since(start).Seconds()

	// Output YAML
	fmt.Printf("type: final\n")
	fmt.Printf("timeSeconds: %.3f\n", elapsed)
	fmt.Printf("uploadBytes: %d\n", *uploadBytes)
	fmt.Printf("downloadBytes: %d\n", *downloadBytes)

	log.Printf("Test complete: %.3fs\n", elapsed)
}

type zeroReader struct{}

func (zeroReader) Read(p []byte) (n int, err error) {
	return len(p), nil
}
