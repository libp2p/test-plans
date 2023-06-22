package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/binary"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"strconv"
	"time"
)

const (
	BlockSize = 64 << 10
)

func handleRequest(w http.ResponseWriter, r *http.Request) {
	// Read the big-endian bytesToSend value
	var bytesToSend uint64
	if err := binary.Read(r.Body, binary.BigEndian, &bytesToSend); err != nil {
		http.Error(w, "failed to read uint64 value", http.StatusBadRequest)
		return
	}

	// Read and discard the remaining bytes in the request
	io.Copy(io.Discard, r.Body)

	// Set content type and length headers
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Length", strconv.FormatUint(bytesToSend, 10))

	// Write the status code explicitly
	w.WriteHeader(http.StatusOK)

	buf := make([]byte, BlockSize)

	for bytesToSend > 0 {
		toSend := buf
		if bytesToSend < BlockSize {
			toSend = buf[:bytesToSend]
		}

		n, err := w.Write(toSend)
		if err != nil {
			http.Error(w, "Failed write", http.StatusInternalServerError)
			return
		}
		bytesToSend -= uint64(n)
	}
}

func newRequestReader(downloadBytes uint64, uploadBytes uint64) io.Reader {
	p := make([]byte, 8)
	binary.BigEndian.PutUint64(p, downloadBytes)

	return io.MultiReader(bytes.NewReader(p), &zeroReader{n: int(uploadBytes)})
}

var zeroSlice = make([]byte, BlockSize)

type zeroReader struct {
	n int
}

func (z *zeroReader) Read(p []byte) (n int, err error) {
	if z.n <= 0 {
		return 0, io.EOF
	}

	// calculate the number of zeros to write
	n = len(p)
	if n > z.n {
		n = int(z.n)
	}
	if n > len(zeroSlice) {
		n = len(zeroSlice)
	}

	// set the necessary bytes to zero
	copy(p, zeroSlice[:n])

	z.n -= n

	if z.n == 0 {
		err = io.EOF
	}

	return n, err
}

func runClient(serverAddr string, uploadBytes, downloadBytes uint64) (time.Duration, time.Duration, error) {
	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true,
			},
		},
	}

	reqBody := newRequestReader(downloadBytes, uploadBytes)

	req, err := http.NewRequest("POST", fmt.Sprintf("https://%s/", serverAddr), reqBody)
	if err != nil {
		return 0, 0, err
	}

	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("Content-Length", strconv.FormatUint(uploadBytes+8, 10))

	startTime := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		return 0, 0, err
	}
	if resp.StatusCode != http.StatusOK {
		return 0, 0, fmt.Errorf("server returned non-OK status: %d %s", resp.StatusCode, resp.Status)
	}
	uploadDoneTime := time.Now()
	defer resp.Body.Close()

	n, err := io.Copy(io.Discard, resp.Body)
	if err != nil {
		return 0, 0, fmt.Errorf("error reading response: %w", err)
	}
	if n != int64(downloadBytes) {
		return 0, 0, fmt.Errorf("expected %d bytes in response, but received %d", downloadBytes, n)
	}

	return uploadDoneTime.Sub(startTime), time.Since(uploadDoneTime), nil
}

func generateEphemeralCertificate() (tls.Certificate, error) {
	// Generate an ECDSA private key
	privKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, err
	}

	// Set up the certificate template
	template := x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject: pkix.Name{
			Organization: []string{"Ephemeral Cert"},
		},
		NotBefore: time.Now(),
		NotAfter:  time.Now().Add(24 * time.Hour),
		KeyUsage:  x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage: []x509.ExtKeyUsage{
			x509.ExtKeyUsageServerAuth,
		},
		BasicConstraintsValid: true,
	}

	// Set the IP address if required
	ip := net.ParseIP("127.0.0.1")
	if ip != nil {
		template.IPAddresses = append(template.IPAddresses, ip)
	}

	// Create a self-signed certificate
	certDER, err := x509.CreateCertificate(rand.Reader, &template, &template, &privKey.PublicKey, privKey)
	if err != nil {
		return tls.Certificate{}, err
	}

	// PEM encode the certificate and private key
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certDER})
	privKeyBytes, err := x509.MarshalECPrivateKey(privKey)
	if err != nil {
		return tls.Certificate{}, err
	}
	privKeyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: privKeyBytes})

	// Create a tls.Certificate from the PEM encoded certificate and private key
	cert, err := tls.X509KeyPair(certPEM, privKeyPEM)
	if err != nil {
		return tls.Certificate{}, err
	}

	return cert, nil
}

type Result struct {
	ConnectionEstablishedSeconds float64 `json:"connectionEstablishedSeconds"`
	UploadSeconds                float64 `json:"uploadSeconds"`
	DownloadSeconds              float64 `json:"downloadSeconds"`
}

func main() {
	runServer := flag.Bool("run-server", false, "Should run as server")
	serverAddr := flag.String("server-address", "", "Server address")
	_ = flag.String("transport", "", "Transport to use")
	uploadBytes := flag.Uint64("upload-bytes", 0, "Upload bytes")
	downloadBytes := flag.Uint64("download-bytes", 0, "Download bytes")
	flag.Parse()

	if *runServer {
		// Generate an ephemeral TLS certificate and private key
		cert, err := generateEphemeralCertificate()
		if err != nil {
			log.Fatalf("Error generating ephemeral certificate: %v\n", err)
		}

		// Parse the server address
		_, port, err := net.SplitHostPort(*serverAddr)
		if err != nil {
			log.Fatalf("Invalid server address: %v\n", err)
		}

		// Create a new HTTPS server with the ephemeral certificate
		tlsConfig := &tls.Config{Certificates: []tls.Certificate{cert}}
		server := &http.Server{
			Addr:      ":" + port,
			TLSConfig: tlsConfig,
		}

		http.HandleFunc("/", handleRequest)

		// Start the HTTPS server
		fmt.Printf("Starting HTTPS server on port %s\n", port)
		err = server.ListenAndServeTLS("", "")
		if err != nil {
			fmt.Printf("Error starting HTTPS server: %v\n", err)
		}
	} else {
		// Client mode
		if *serverAddr == "" {
			flag.Usage()
			log.Fatal("Error: Please provide valid server-address flags for client mode.")
		}

		// Run the client and print the results
		upload, download, err := runClient(*serverAddr, *uploadBytes, *downloadBytes)
		if err != nil {
			log.Fatal(err)
		}

		jsonB, err := json.Marshal(Result{
			// TODO: Ideally we would be able to measure the Go std TCP+TLS connection establishment time.
			ConnectionEstablishedSeconds: 0,
			UploadSeconds:                upload.Seconds(),
			DownloadSeconds:              download.Seconds(),
		})
		if err != nil {
			log.Fatalf("failed to marshal perf result: %s", err)
		}
		fmt.Println(string(jsonB))
	}
}
