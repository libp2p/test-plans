package main

import (
	"context"
	"fmt"
	"net"
	"time"

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

	iface, err := net.InterfaceByName("eth1")
	if err != nil {
		return err
	}

	addrs, err := iface.Addrs()
	if err != nil {
		return err
	}

	var ip net.IP
        switch v := addrs[0].(type) {
        case *net.IPNet:
		if !v.IP.IsLoopback() {
			if v.IP.To4() != nil {
				ip = v.IP
			}
		}
        }
	runenv.RecordMessage("eth1 ip: ", ip)

	var (
		listener *net.TCPListener
		conn     *net.TCPConn
	)

	// If the last octet of the IP is even, act as a listener. If it is odd,
	// act as a dialer.
	//
	// TODO: This is a hack.
	if ip[15] % 2 == 0 {
		fmt.Println("Test instance, listening for incoming connections.")
		listener, err = net.ListenTCP("tcp4", &net.TCPAddr{Port: 1234})
		if err != nil {
			return err
		}
		defer listener.Close()
		client.MustSignalEntry(ctx, "listening")
		conn, err = listener.AcceptTCP()
		fmt.Println("Established inbound TCP connection.")
	} else {
		fmt.Println("Test instance, connecting to listening instance.")
		client.MustBarrier(ctx, "listening", 1)

		remoteAddr := ip
		ip[15] = ip[15] -1

		conn, err = net.DialTCP("tcp4", nil, &net.TCPAddr{
			IP:   remoteAddr,
			Port: 1234,
		})
		fmt.Println("Established outbound TCP connection.")
	}

	defer conn.Close()

	return nil
}
