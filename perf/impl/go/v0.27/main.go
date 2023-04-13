package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/multiformats/go-multiaddr"
)

func main() {
	runServer := flag.Bool("run-server", false, "Should run as server")
	// --server-address <SERVER_ADDRESS>
	serverAddr := flag.String("server-address", "", "Server address")
	// --secret-key-seed <SEED>
	secretKeySeed := flag.Uint64("secret-key-seed", 0, "Server secret key seed")
	// --upload-bytes <UPLOAD_BYTES>
	uploadBytes := flag.Int("upload-bytes", 0, "Upload bytes")
	// --download-bytes <DOWNLOAD_BYTES>
	downloadBytes := flag.Int("download-bytes", 0, "Download bytes")
	// --n-times <N_TIMES>
	nTimes := flag.Int("n-times", 0, "N times")
	flag.Parse()


	var opts []libp2p.Option
	if *runServer  {
		opts = append(opts, libp2p.ListenAddrStrings("/ip4/0.0.0.0/tcp/4001", "/ip4/0.0.0.0/udp/4001/quic-v1"))

		// TODO: Fake identity. For testing only.
		priv, _, err := crypto.GenerateEd25519Key(&simpleReader{seed:uint8(*secretKeySeed)})
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

	serverInfo, err := peer.AddrInfoFromString(*serverAddr)
	if err != nil {
		panic(err)
	}

	err = h.Connect(context.Background(), *serverInfo)
	if err != nil {
		panic(err)
	}

	times := make([]time.Duration, 0, *nTimes)

	for i := 0; i < *nTimes; i++ {
		start := time.Now()
		err := perf.RunPerf(context.Background(), serverInfo.ID, uint64(*uploadBytes), uint64(*downloadBytes))
		if err != nil {
			panic(err)
		}
		times = append(times, time.Since(start))
	}

	// float32 because json
	timesS := make([]float32, 0, len(times))
	for _, t := range times {
		timesS = append(timesS, float32(t.Nanoseconds())/1_000_000_000)
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

type Latencies struct {
	Latencies []float32 `json:"latencies"`
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
