package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strconv"
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
	ma "github.com/multiformats/go-multiaddr"
)

func main() {
	var (
		transport      = os.Getenv("transport")
		muxer          = os.Getenv("muxer")
		secureChannel  = os.Getenv("security")
		isDialerStr    = os.Getenv("is_dialer")
		ip             = os.Getenv("ip")
		redisAddr      = os.Getenv("redis_addr")
		testTimeoutStr = os.Getenv("test_timeout_seconds")
	)

	var testTimeout = 3 * time.Minute
	if testTimeoutStr != "" {
		secs, err := strconv.ParseInt(testTimeoutStr, 10, 32)
		if err == nil {
			testTimeout = time.Duration(secs) * time.Second
		}
	}

	if ip == "" {
		ip = "0.0.0.0"
	}

	if redisAddr == "" {
		redisAddr = "redis:6379"
	}

	ctx, cancel := context.WithTimeout(context.Background(), testTimeout)
	defer cancel()

	// Get peer information via redis
	rClient := redis.NewClient(&redis.Options{
		Addr:     redisAddr,
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
	default:
		log.Fatalf("Unsupported transport: %s", transport)
	}
	options = append(options, libp2p.ListenAddrStrings(listenAddr))

	// Skipped for certain transports
	var skipMuxer bool
	var skipSecureChannel bool
	switch transport {
	case "quic":
		fallthrough
		skipMuxer = true
		skipSecureChannel = true
	}

	if !skipSecureChannel {
		switch secureChannel {
		case "tls":
			options = append(options, libp2p.Security(libp2ptls.ID, libp2ptls.New))
		case "noise":
			options = append(options, libp2p.Security(noise.ID, noise.New))
		default:
			log.Fatalf("Unsupported secure channel: %s", secureChannel)
		}
	}

	if !skipMuxer {
		switch muxer {
		case "yamux":
			options = append(options, libp2p.Muxer("/yamux/1.0.0", yamux.DefaultTransport))
		case "mplex":
			options = append(options, libp2p.Muxer("/mplex/6.7.0", mplex.DefaultTransport))
		default:
			log.Fatalf("Unsupported muxer: %s", muxer)
		}
	}

	host, err := libp2p.New(options...)

	if err != nil {
		log.Fatalf("failed to instantiate libp2p instance: %s", err)
	}
	defer host.Close()

	log.Println("My multiaddr is: ", host.Addrs())

	if is_dialer {
		val, err := rClient.BLPop(ctx, testTimeout, "listenerAddr").Result()
		if err != nil {
			log.Fatal("Failed to wait for listener to be ready")
		}
		otherMa := ma.StringCast(val[1])
		log.Println("Other peer multiaddr is: ", otherMa)
		otherMa, p2pComponent := ma.SplitLast(otherMa)
		otherPeerId, err := peer.Decode(p2pComponent.Value())
		if err != nil {
			log.Fatal("Failed to get peer id from multiaddr")
		}

		handshakeStartInstant := time.Now()
		err = host.Connect(ctx, peer.AddrInfo{
			ID:    otherPeerId,
			Addrs: []ma.Multiaddr{otherMa},
		})
		if err != nil {
			log.Fatal("Failed to connect to other peer")
		}

		ping := ping.NewPingService(host)

		res := <-ping.Ping(ctx, otherPeerId)
		if res.Error != nil {
			panic(res.Error)
		}
		handshakePlusOneRTT := time.Since(handshakeStartInstant)

		testResult := struct {
			HandshakePlusOneRTTMillis float32 `json:"handshakePlusOneRTTMillis"`
			PingRTTMilllis            float32 `json:"pingRTTMilllis"`
		}{
			HandshakePlusOneRTTMillis: float32(handshakePlusOneRTT.Microseconds()) / 1000,
			PingRTTMilllis:            float32(res.RTT.Microseconds()) / 1000,
		}

		testResultJSON, err := json.Marshal(testResult)
		if err != nil {
			log.Fatalf("Failed to marshal test result: %v", err)
		}
		fmt.Println(string(testResultJSON))
	} else {
		_, err := rClient.RPush(ctx, "listenerAddr", host.Addrs()[0].Encapsulate(ma.StringCast("/p2p/"+host.ID().String())).String()).Result()
		if err != nil {
			log.Fatal("Failed to send listener address")
		}
		time.Sleep(testTimeout)
		os.Exit(1)
	}
}
