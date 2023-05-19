package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"strings"
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
	secretKeySeed := flag.Uint64("secret-key-seed", 0, "Server secret key seed")
	uploadBytes := flag.Uint64("upload-bytes", 0, "Upload bytes")
	downloadBytes := flag.Uint64("download-bytes", 0, "Download bytes")
	flag.Parse()

	var opts []libp2p.Option
	if *runServer {
		opts = append(opts, libp2p.ListenAddrStrings("/ip4/0.0.0.0/tcp/4001", "/ip4/0.0.0.0/udp/4001/quic-v1"))

		// TODO: Fake identity. For testing only.
		priv, _, err := crypto.GenerateEd25519Key(&simpleReader{seed: uint8(*secretKeySeed)})
		if err != nil {
			panic(err)
		}
		opts = append(opts, libp2p.Identity(priv))
	}

	h, err := libp2p.New(opts...)
	if err != nil {
		panic(err)
	}

	perf := NewPerfService(h)
	if *runServer {
		for _, a := range h.Addrs() {
			fmt.Println(a.Encapsulate(multiaddr.StringCast("/p2p/" + h.ID().String())))
		}

		select {} // run forever, exit on interrupt
	}

	ipPort := strings.Split(*serverAddr, ":")
	if len(ipPort) != 2 {
		fmt.Println("Invalid server address format. Expected format: 'ip:port'")
		return
	}

	ip := ipPort[0]
	port := ipPort[1]

	var multiAddrStr string
	switch *transport {
	case "tcp":
		multiAddrStr = fmt.Sprintf("/ip4/%s/tcp/%s/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", ip, port)
	case "quic-v1":
		multiAddrStr = fmt.Sprintf("/ip4/%s/udp/%s/quic-v1/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN", ip, port)
	default:
		fmt.Println("Invalid transport. Accepted values: 'tcp' or 'quic-v1'")
		return
	}

	serverInfo, err := peer.AddrInfoFromString(multiAddrStr)
	if err != nil {
		panic(err)
	}

	start := time.Now()
	err = h.Connect(context.Background(), *serverInfo)
	if err != nil {
		panic(err)
	}
	connectionEstablished := time.Since(start)

	upload, download, err := perf.RunPerf(context.Background(), serverInfo.ID, uint64(*uploadBytes), uint64(*downloadBytes))
	if err != nil {
		panic(err)
	}

	jsonB, err := json.Marshal(Result{
		ConnectionEstablishedSeconds: connectionEstablished.Seconds(),
		UploadSeconds:                upload.Seconds(),
		DownloadSeconds:              download.Seconds(),
	})
	if err != nil {
		panic(err)
	}

	fmt.Println(string(jsonB))
}

type Result struct {
	ConnectionEstablishedSeconds float64 `json:"connectionEstablishedSeconds"`
	UploadSeconds                float64 `json:"uploadSeconds"`
	DownloadSeconds              float64 `json: "downloadSeconds"`
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
