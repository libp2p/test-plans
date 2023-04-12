package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/multiformats/go-multiaddr"
)

func main() {
	runServer := flag.Bool("run-server", false, "Should run as server")
	// --server-address <SERVER_ADDRESS>
	serverAddr := flag.String("server-address", "", "Server address")
	// --upload-bytes <UPLOAD_BYTES>
	uploadBytes := flag.Int("upload-bytes", 0, "Upload bytes")
	// --download-bytes <DOWNLOAD_BYTES>
	downloadBytes := flag.Int("download-bytes", 0, "Download bytes")
	// --n-times <N_TIMES>
	nTimes := flag.Int("n-times", 0, "N times")
	flag.Parse()
	fmt.Fprintf(os.Stderr, "Hello, playground", *serverAddr, uploadBytes, downloadBytes, nTimes)

	// var opts []libp2p.Option
	// if *runServer != "" {
	// 	opts = append(opts, libp2p.ListenAddrStrings(*runServer))
	// }

	h, err := libp2p.New()
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
	timesMs := make([]float32, 0, len(times))
	for _, t := range times {
		timesMs = append(timesMs, float32(t.Nanoseconds())/1_000_000)
	}

	jsonB, err := json.Marshal(timesMs)
	if err != nil {
		panic(err)
	}

	fmt.Println(string(jsonB))
}
