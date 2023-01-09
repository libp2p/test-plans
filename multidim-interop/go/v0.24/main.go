package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/muxer/mplex"
	"github.com/libp2p/go-libp2p/p2p/muxer/yamux"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
	noise "github.com/libp2p/go-libp2p/p2p/security/noise"
	libp2ptls "github.com/libp2p/go-libp2p/p2p/security/tls"
	libp2pquic "github.com/libp2p/go-libp2p/p2p/transport/quic"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
	"github.com/libp2p/go-libp2p/p2p/transport/websocket"
	libp2pwebtransport "github.com/libp2p/go-libp2p/p2p/transport/webtransport"
	ma "github.com/multiformats/go-multiaddr"
)

func main() {
	var (
		transport     = os.Getenv("transport")
		secureChannel = os.Getenv("security")
		muxer         = os.Getenv("muxer")
		isDialerStr   = os.Getenv("is_dialer")
		ip            = os.Getenv("ip")
		redis_addr    = os.Getenv("REDIS_ADDR")
	)

	if redis_addr == "" {
		redis_addr = "redis:6379"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Get peer information via redis
	rClient := redis.NewClient(&redis.Options{
		Addr:     redis_addr,
		Password: "",
		DB:       0,
	})
	defer rClient.Close()

	for {
		// Wait for redis to be ready
		_, err := rClient.Ping(ctx).Result()
		if err == nil {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	is_dialer := isDialerStr == "true"

	options := []libp2p.Option{}

	var listenAddr string
	switch transport {
	case "ws":
		options = append(options, libp2p.Transport(websocket.New))
		listenAddr = fmt.Sprintf("/ip4/%s/tcp/0/ws", ip)
	case "tcp":
		options = append(options, libp2p.Transport(tcp.NewTCPTransport))
		listenAddr = fmt.Sprintf("/ip4/%s/tcp/0", ip)
	case "quic":
		options = append(options, libp2p.Transport(libp2pquic.NewTransport))
		listenAddr = fmt.Sprintf("/ip4/%s/udp/0/quic", ip)
	case "quic-v1":
		options = append(options, libp2p.Transport(libp2pquic.NewTransport))
		listenAddr = fmt.Sprintf("/ip4/%s/udp/0/quic-v1", ip)
	case "webtransport":
		options = append(options, libp2p.Transport(libp2pwebtransport.New))
		listenAddr = fmt.Sprintf("/ip4/%s/udp/0/quic-v1/webtransport", ip)
	default:
		panic("Unsupported transport")
	}
	options = append(options, libp2p.ListenAddrStrings(listenAddr))

	switch secureChannel {
	case "tls":
		options = append(options, libp2p.Security(libp2ptls.ID, libp2ptls.New))
	case "noise":
		options = append(options, libp2p.Security(noise.ID, noise.New))
	case "quic":
	default:
		panic("Unsupported secure channel")
	}

	switch muxer {
	case "yamux":
		options = append(options, libp2p.Muxer("/yamux/1.0.0", yamux.DefaultTransport))
	case "mplex":
		options = append(options, libp2p.Muxer("/mplex/6.7.0", mplex.DefaultTransport))
	case "quic":
	default:
		panic("Unsupported muxer")
	}

	host, err := libp2p.New(options...)

	if err != nil {
		panic(fmt.Sprintf("failed to instantiate libp2p instance: %s", err))
	}
	defer host.Close()

	fmt.Println("My multiaddr is: ", host.Addrs())

	if is_dialer {
		val, err := rClient.BLPop(ctx, 10*time.Second, "listenerAddr").Result()
		if err != nil {
			panic("Failed to wait for listener to be ready")
		}
		otherMa := ma.StringCast(val[1])
		fmt.Println("Other peer multiaddr is: ", otherMa)
		otherMa, p2pComponent := ma.SplitLast(otherMa)
		otherPeerId, err := peer.Decode(p2pComponent.Value())
		if err != nil {
			panic("Failed to get peer id from multiaddr")
		}
		err = host.Connect(ctx, peer.AddrInfo{
			ID:    otherPeerId,
			Addrs: []ma.Multiaddr{otherMa},
		})
		if err != nil {
			panic("Failed to connect to other peer")
		}

		ping := ping.NewPingService(host)

		res := <-ping.Ping(ctx, otherPeerId)
		if res.Error != nil {
			panic(res.Error)
		}

		fmt.Println("Ping successful: ", res.RTT)

		rClient.RPush(ctx, "dialerDone", "").Result()
	} else {
		_, err := rClient.RPush(ctx, "listenerAddr", host.Addrs()[0].Encapsulate(ma.StringCast("/p2p/"+host.ID().String())).String()).Result()
		if err != nil {
			panic("Failed to send listener address")
		}
		_, err = rClient.BLPop(ctx, 10*time.Second, "dialerDone").Result()
		if err != nil {
			panic("Failed to wait for dialer conclusion")
		}
	}
}
