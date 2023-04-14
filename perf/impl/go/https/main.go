package main

import (
	"bytes"
	"encoding/json"
	"io/ioutil"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/binary"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"strconv"
	"time"

	"github.com/multiformats/go-multiaddr"
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

	// Generate random bytes and write the response
	responseBytes := make([]byte, bytesToSend)
	_, err = rand.Read(responseBytes)
	if err != nil {
		http.Error(w, "Failed to generate random bytes", http.StatusInternalServerError)
		return
	}

	w.Write(responseBytes)
}

func runClient(serverAddr string, uploadBytes, downloadBytes, nTimes int) []time.Duration {
	durations := make([]time.Duration, nTimes)

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true,
			},
		},
	}

	for i := 0; i < nTimes; i++ {
		reqBody := make([]byte, 8+uploadBytes)
		binary.BigEndian.PutUint64(reqBody, uint64(downloadBytes))
		rand.Read(reqBody[8:])

		startTime := time.Now()
		resp, err := client.Post(fmt.Sprintf("https://%s/", serverAddr), "application/octet-stream", bytes.NewReader(reqBody))
		if err != nil {
			fmt.Printf("Error sending request: %v\n", err)
			continue
		}

		respBody, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			fmt.Printf("Error reading response: %v\n", err)
		} else if len(respBody) != downloadBytes {
			fmt.Printf("Expected %d bytes in response, but received %d\n", downloadBytes, len(respBody))
		}
		resp.Body.Close()

		durations[i] = time.Since(startTime)
	}

	return durations
}

func generateEphemeralCertificate() (tls.Certificate, error) {
	// Generate a private key
	privKey, err := rsa.GenerateKey(rand.Reader, 2048)
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
	privKeyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(privKey)})

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
	// --server-address <SERVER_ADDRESS>
	serverAddr := flag.String("server-address", "", "Server address")
	// --secret-key-seed <SEED>
	_ = flag.Uint64("secret-key-seed", 0, "Server secret key seed")
	// --upload-bytes <UPLOAD_BYTES>
	uploadBytes := flag.Int("upload-bytes", 0, "Upload bytes")
	// --download-bytes <DOWNLOAD_BYTES>
	downloadBytes := flag.Int("download-bytes", 0, "Download bytes")
	// --n-times <N_TIMES>
	nTimes := flag.Int("n-times", 0, "N times")
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
		if *serverAddr == "" || *nTimes <= 0 {
			fmt.Println("Error: Please provide valid server-address and n-times flags for client mode.")
			return
		}

		// Parse the multiaddr and extract the IP address and TCP port
		serverAddr, err := multiaddr.NewMultiaddr(*serverAddr)
		if err != nil {
			fmt.Printf("Error parsing server-address: %v\n", err)
			return
		}
		ipBytes, err := serverAddr.ValueForProtocol(multiaddr.P_IP4)
		if err != nil {
			ipBytes, err = serverAddr.ValueForProtocol(multiaddr.P_IP6)
			if err != nil {
				fmt.Printf("Error getting IP address from multiaddr: %v\n", err)
				return
			}
		}
		ip := net.ParseIP(ipBytes)
		portStr, err := serverAddr.ValueForProtocol(multiaddr.P_TCP)
		if err != nil {
			fmt.Printf("Error getting TCP port from multiaddr: %v\n", err)
			return
		}
		port, err := strconv.Atoi(portStr)
		if err != nil {
			fmt.Printf("Error parsing TCP port: %v\n", err)
			return
		}
		// Run the client and print the results
		durations := runClient(fmt.Sprintf("%s:%d", ip.String(), port), *uploadBytes, *downloadBytes, *nTimes)

		// Convert durations to seconds and marshal as JSON
		timesS := make([]float32, 0, len(durations))
		for _, d := range durations {
			timesS = append(timesS, float32(d.Nanoseconds())/1_000_000_000)
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
