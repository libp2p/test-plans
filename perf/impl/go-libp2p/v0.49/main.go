package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/multiformats/go-multiaddr"
)

func main() {
	runServer := flag.Bool("run-server", false, "Should run as server")
	serverAddr := flag.String("server-address", "", "Server address")
	transport := flag.String("transport", "tcp", "Transport to use")
	uploadBytes := flag.Uint64("upload-bytes", 0, "Upload bytes")
	downloadBytes := flag.Uint64("download-bytes", 0, "Download bytes")
	flag.Parse()

	host, port, err := net.SplitHostPort(*serverAddr)
	if err != nil {
		log.Fatal(err)
	}

	tcpMultiAddrStr := fmt.Sprintf("/ip4/%s/tcp/%s", host, port)
	quicMultiAddrStr := fmt.Sprintf("/ip4/%s/udp/%s/quic-v1", host, port)

	var opts []libp2p.Option
	if *runServer {
		opts = append(opts, libp2p.ListenAddrStrings(tcpMultiAddrStr, quicMultiAddrStr))

		// Generate stable fake identity.
		//
		// Using a stable identity (i.e. peer ID) allows the client to
		// connect to the server without a prior exchange of the
		// server's peer ID.
		priv, _, err := crypto.GenerateEd25519Key(&simpleReader{seed: 0})
		if err != nil {
			log.Fatalf("failed to generate key: %s", err)
		}
		opts = append(opts, libp2p.Identity(priv))
	}

	h, err := libp2p.New(opts...)
	if err != nil {
		log.Fatalf("failed to instantiate libp2p: %s", err)
	}

	perf := NewPerfService(h)
	if *runServer {
		for _, a := range h.Addrs() {
			fmt.Println(a.Encapsulate(multiaddr.StringCast("/p2p/" + h.ID().String())))
		}

		select {} // run forever, exit on interrupt
	}

	var multiAddrStr string
	switch *transport {
	case "tcp":
		multiAddrStr = tcpMultiAddrStr
	case "quic-v1":
		multiAddrStr = quicMultiAddrStr
	default:
		fmt.Println("Invalid transport. Accepted values: 'tcp' or 'quic-v1'")
		return
	}
	// Peer ID corresponds to the above fake identity.
	multiAddrStr = multiAddrStr + "/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
	serverInfo, err := peer.AddrInfoFromString(multiAddrStr)
	if err != nil {
		log.Fatalf("failed to build address info: %s", err)
	}

	start := time.Now()
	err = h.Connect(context.Background(), *serverInfo)
	if err != nil {
		log.Fatalf("failed to dial peer: %s", err)
	}

	err = perf.RunPerf(context.Background(), serverInfo.ID, uint64(*uploadBytes), uint64(*downloadBytes))
	if err != nil {
		log.Fatalf("failed to execute perf: %s", err)
	}

	jsonB, err := json.Marshal(Result{
		TimeSeconds:   time.Since(start).Seconds(),
		UploadBytes:   *uploadBytes,
		DownloadBytes: *downloadBytes,
		Type:          "final",
	})
	if err != nil {
		log.Fatalf("failed to marshal perf result: %s", err)
	}

	fmt.Println(string(jsonB))
}

type Result struct {
	Type          string  `json:"type"`
	TimeSeconds   float64 `json:"timeSeconds"`
	UploadBytes   uint64  `json:"uploadBytes"`
	DownloadBytes uint64  `json:"downloadBytes"`
}

type simpleReader struct {
	seed uint8
}

func (r *simpleReader) Read(p []byte) (n int, err error) {
	for i := range p {
		p[i] = r.seed
	}
	return len(p), nil
}
