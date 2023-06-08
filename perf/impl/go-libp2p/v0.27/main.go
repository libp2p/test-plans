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
	"github.com/libp2p/go-libp2p/core/peerstore"
	tls "github.com/libp2p/go-libp2p/p2p/security/tls"
	quic "github.com/libp2p/go-libp2p/p2p/transport/quic"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
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

	opts := []libp2p.Option{
		// Use TLS only instead of both TLS and Noise. Removes the
		// additional multistream-select security protocol negotiation.
		// Thus makes it easier to compare with TCP+TLS+HTTP/2
		libp2p.Security(tls.ID, tls.New),

		libp2p.DefaultListenAddrs,
		libp2p.Transport(tcp.NewTCPTransport),
		libp2p.Transport(quic.NewTransport),
		libp2p.DefaultMuxers,
		libp2p.DefaultPeerstore,
		libp2p.DefaultResourceManager,
		libp2p.DefaultConnectionManager,
		libp2p.DefaultMultiaddrResolver,
		libp2p.DefaultPrometheusRegisterer,
	}

	if *runServer {
		opts = append(opts, libp2p.ListenAddrStrings(tcpMultiAddrStr, quicMultiAddrStr))

		// Generate fake identity.
		priv, _, err := crypto.GenerateEd25519Key(&simpleReader{seed: 0})
		if err != nil {
			panic(err)
		}
		opts = append(opts, libp2p.Identity(priv))
	} else {
		opts = append(opts, libp2p.RandomIdentity)
	}

	h, err := libp2p.NewWithoutDefaults(opts...)
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
		panic(err)
	}

	start := time.Now()
	h.Peerstore().AddAddrs(serverInfo.ID, serverInfo.Addrs, peerstore.TempAddrTTL)
	// Use h.Network().DialPeer() instead of h.Connect to skip waiting for
	// identify protocol to finish.
	_, err = h.Network().DialPeer(context.Background(), serverInfo.ID)
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
	DownloadSeconds              float64 `json:"downloadSeconds"`
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
