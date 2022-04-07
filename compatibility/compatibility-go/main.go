package main

import (
	"context"
	"fmt"
	"net"
	"time"

	"github.com/testground/sdk-go/network"
	"github.com/testground/sdk-go/run"
	"github.com/testground/sdk-go/runtime"
)

var testcases = map[string]interface{}{
	"tcp-connect":       run.InitializedTestCaseFn(tcpconnect),
}

func main() {
	run.InvokeMap(testcases)
}

func tcpconnect(runenv *runtime.RunEnv, initCtx *run.InitContext) error {
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Second)
	defer cancel()

	client := initCtx.SyncClient
	netclient := initCtx.NetClient

	seq := client.MustSignalAndWait(ctx, "ip-allocation", runenv.TestInstanceCount)

	config := &network.Config{
		// Control the "default" network. At the moment, this is the only network.
		Network: "default",

		// Enable this network. Setting this to false will disconnect this test
		// instance from this network. You probably don't want to do that.
		Enable: true,
		Default: network.LinkShape{
			Latency:   100 * time.Millisecond,
			Bandwidth: 1 << 20, // 1Mib
		},
		RoutingPolicy: network.AllowAll,
	}

	ipC := byte((seq >> 8) + 1)
	ipD := byte(seq)
	config.IPv4 = runenv.TestSubnet
	config.IPv4.IP = append(config.IPv4.IP[0:2:2], ipC, ipD)
	config.IPv4.Mask = []byte{255, 255, 255, 0}
	config.CallbackState = "ip-changed"

	netclient.MustConfigureNetwork(ctx, config)

	var (
		err      error
		listener *net.TCPListener
		conn     *net.TCPConn
	)

	if seq == 1 {
		fmt.Println("Test instance, listening for incoming connections.")
		listener, err = net.ListenTCP("tcp4", &net.TCPAddr{Port: 1234})
		if err != nil {
			return err
		}
		defer listener.Close()
		client.MustSignalEntry(ctx, "listening")
		for i := 0; i < runenv.TestInstanceCount -1; i++ {
			conn, err = listener.AcceptTCP()
			fmt.Println("Established inbound TCP connection.")
		}
	} else {
		fmt.Println("Test instance, connecting to listening instance.")
		client.MustBarrier(ctx, "listening", 1)

		conn, err = net.DialTCP("tcp4", nil, &net.TCPAddr{
			IP:   append(config.IPv4.IP[:3:3], 1),
			Port: 1234,
		})
		fmt.Println("Established outbound TCP connection.")
	}

	defer conn.Close()

	return nil
}
