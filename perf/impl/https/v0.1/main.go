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
	err := binary.Read(r.Body, binary.BigEndian, &bytesToSend)
	if err != nil {
		http.Error(w, "Failed to read u64 value", http.StatusBadRequest)
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

func runClient(serverAddr string, uploadBytes, downloadBytes uint64) ([]time.Duration, error) {
	durations := make([]time.Duration, 1)

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
		return durations, err
	}

	respBody, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("Error reading response: %v\n", err)
		return durations, err
	} else if uint64(len(respBody)) != downloadBytes {
		fmt.Printf("Expected %d bytes in response, but received %d\n", downloadBytes, len(respBody))
		return durations, err
	}
	resp.Body.Close()

	durations[0] = time.Since(startTime)

	return durations, nil
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

type Latencies struct {
	Latencies []float32 `json:"latencies"`
}

func main() {
	runServer := flag.Bool("run-server", false, "Should run as server")
	serverIPAddr := flag.String("server-ip-address", "", "Server address")
	_ = flag.String("transport", "", "Transport to use")
	_ = flag.Uint64("secret-key-seed", 0, "Server secret key seed")
	uploadBytes := flag.Uint64("upload-bytes", 0, "Upload bytes")
	downloadBytes := flag.Uint64("download-bytes", 0, "Download bytes")
	flag.Parse()

	if *runServer {
		// Generate an ephemeral TLS certificate and private key
		cert, err := generateEphemeralCertificate()
		if err != nil {
			fmt.Printf("Error generating ephemeral certificate: %v\n", err)
			return
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
		if *serverIPAddr == "" {
			fmt.Println("Error: Please provide valid server-address flags for client mode.")
			return
		}

		// Run the client and print the results
		durations, err := runClient(fmt.Sprintf("%s:%d", *serverIPAddr, 4001), *uploadBytes, *downloadBytes)
		if err != nil {
			panic(err)
		}

		// Convert durations to seconds and marshal as JSON
		timesS := make([]float32, 0, len(durations))
		for _, d := range durations {
			timesS = append(timesS, float32(d.Seconds()))
		}

		latencies := Latencies{
			Latencies: timesS,
		}

		jsonB, err := json.Marshal(latencies)
		if err != nil {
			panic(err)
		}

		fmt.Println(string(jsonB))
	}
}
