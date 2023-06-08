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
	"io/ioutil"
	"log"
	"math/big"
	"net"
	"net/http"
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

func runClient(serverAddr string, uploadBytes, downloadBytes uint64) (time.Duration, time.Duration, error) {
	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true,
			},
		},
	}

	reqBody := make([]byte, 8+uploadBytes)
	binary.BigEndian.PutUint64(reqBody, uint64(downloadBytes))

	startTime := time.Now()
	resp, err := client.Post(fmt.Sprintf("https://%s/", serverAddr), "application/octet-stream", bytes.NewReader(reqBody))
	if err != nil {
		return 0, 0, err
	}
	uploadDoneTime := time.Now()

	respBody, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return 0, 0, fmt.Errorf("error reading response: %w\n", err)
	}
	defer resp.Body.Close()
	if uint64(len(respBody)) != downloadBytes {
		return 0, 0, fmt.Errorf("expected %d bytes in response, but received %d\n", downloadBytes, len(respBody))
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

		// Create a new HTTPS server with the ephemeral certificate
		tlsConfig := &tls.Config{Certificates: []tls.Certificate{cert}}
		server := &http.Server{
			Addr:      ":4001",
			TLSConfig: tlsConfig,
		}

		http.HandleFunc("/", handleRequest)

		// Start the HTTPS server
		fmt.Println("Starting HTTPS server on port 4001")
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
