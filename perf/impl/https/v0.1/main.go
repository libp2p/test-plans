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

const blockSize = 64 << 10

func handleRequest(w http.ResponseWriter, r *http.Request) {
	u64Buf := make([]byte, 8)
	if _, err := io.ReadFull(r.Body, u64Buf); err != nil {
		log.Printf("reading upload size failed: %s", err)
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	bytesToSend := binary.BigEndian.Uint64(u64Buf)

	if _, err := drainStream(r.Body); err != nil {
		log.Printf("draining stream failed: %s", err)
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	r.Header.Set("Content-Type", "application/octet-stream")
	r.Header.Set("Content-Length", strconv.FormatUint(bytesToSend, 10))

	if err := sendBytes(w, bytesToSend); err != nil {
		log.Printf("sending response failed: %s", err)
		return
	}
}

type nullReader struct {
	N    uint64
	read uint64
	LastReportTime time.Time
	lastReportRead uint64
}

var _ io.Reader = &nullReader{}

func (r *nullReader) Read(b []byte) (int, error) {
	if time.Since(r.LastReportTime) > time.Second {
		// TODO
		jsonB, err := json.Marshal(Result{
			TimeSeconds: time.Since(r.LastReportTime).Seconds(),
			UploadBytes: uint(r.lastReportRead),
			Type: "intermediary",
		})
		if err != nil {
			log.Fatalf("failed to marshal perf result: %s", err)
		}
		fmt.Println(string(jsonB))

		r.LastReportTime = time.Now()
		r.lastReportRead = 0
	}

	remaining := r.N - r.read
	l := uint64(len(b))
	if uint64(len(b)) > remaining {
		l = remaining
	}
	r.read += l
	r.lastReportRead += l

	if r.read == r.N {
		return int(l), io.EOF
	}

	return int(l), nil
}

func runClient(serverAddr string, uploadBytes, downloadBytes uint64) (time.Duration, error) {
	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}

	b := make([]byte, 8)
	binary.BigEndian.PutUint64(b, downloadBytes)

	req, err := http.NewRequest(
		http.MethodPost,
		fmt.Sprintf("https://%s/", serverAddr),
		io.MultiReader(
			bytes.NewReader(b),
			&nullReader{N: uploadBytes, LastReportTime: time.Now()},
		),
	)
	if err != nil {
		return 0, err
	}

	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("Content-Length", strconv.FormatUint(uploadBytes+8, 10))

	startTime := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		return 0, err
	}
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("server returned non-OK status: %d %s", resp.StatusCode, resp.Status)
	}
	defer resp.Body.Close()

	n, err := drainStream(resp.Body)
	if err != nil {
		return 0, fmt.Errorf("error reading response: %w", err)
	}
	if n != downloadBytes {
		return 0, fmt.Errorf("expected %d bytes in response, but received %d", downloadBytes, n)
	}

	return time.Since(startTime), nil
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
	Type          string  `json:"type"`
	TimeSeconds   float64 `json:"timeSeconds"`
	UploadBytes   uint    `json:"uploadBytes"`
	DownloadBytes uint    `json:"downloadBytes"`
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
		latency, err := runClient(*serverAddr, *uploadBytes, *downloadBytes)
		if err != nil {
			log.Fatal(err)
		}

		// TODO
		jsonB, err := json.Marshal(Result{
			TimeSeconds: latency.Seconds(),
			Type: "final",
		})
		if err != nil {
			log.Fatalf("failed to marshal perf result: %s", err)
		}
		fmt.Println(string(jsonB))
	}
}

func sendBytes(s io.Writer, bytesToSend uint64) error {
	buf := make([]byte, blockSize)

	for bytesToSend > 0 {
		toSend := buf
		if bytesToSend < blockSize {
			toSend = buf[:bytesToSend]
		}

		n, err := s.Write(toSend)
		if err != nil {
			return err
		}
		bytesToSend -= uint64(n)
	}
	return nil
}

func drainStream(s io.Reader) (uint64, error) {
	var recvd int64
	recvd, err := io.Copy(io.Discard, s)
	if err != nil && err != io.EOF {
		return uint64(recvd), err
	}
	return uint64(recvd), nil
}
