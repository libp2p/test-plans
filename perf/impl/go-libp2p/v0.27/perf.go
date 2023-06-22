package main

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"time"

	logging "github.com/ipfs/go-log/v2"
	pool "github.com/libp2p/go-buffer-pool"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

var log = logging.Logger("perf")

const (
	ID        = "/perf/1.0.0"
	blockSize = 64 << 10
)

type PerfService struct {
	Host host.Host
}

func NewPerfService(h host.Host) *PerfService {
	ps := &PerfService{h}
	h.SetStreamHandler(ID, ps.PerfHandler)
	return ps
}

func (ps *PerfService) PerfHandler(s network.Stream) {
	u64Buf := make([]byte, 8)
	if _, err := io.ReadFull(s, u64Buf); err != nil {
		log.Errorw("err", err)
		s.Reset()
		return
	}

	bytesToSend := binary.BigEndian.Uint64(u64Buf)

	if _, err := drainStream(s); err != nil {
		log.Errorw("err", err)
		s.Reset()
		return
	}

	if err := sendBytes(s, bytesToSend); err != nil {
		log.Errorw("err", err)
		s.Reset()
		return
	}
	s.CloseWrite()
}

func (ps *PerfService) RunPerf(ctx context.Context, p peer.ID, bytesToSend uint64, bytesToRecv uint64) (time.Duration, time.Duration, error) {
	s, err := ps.Host.NewStream(ctx, p, ID)
	if err != nil {
		return 0, 0, err
	}

	sizeBuf := make([]byte, 8)
	binary.BigEndian.PutUint64(sizeBuf, bytesToRecv)

	_, err = s.Write(sizeBuf)
	if err != nil {
		return 0, 0, err
	}

	sendStart := time.Now()
	if err := sendBytes(s, bytesToSend); err != nil {
		return 0, 0, err
	}
	sendDuration := time.Since(sendStart)

	recvStart := time.Now()
	recvd, err := drainStream(s)
	if err != nil {
		return sendDuration, 0, err
	}
	recvDuration := time.Since(recvStart)

	if recvd != bytesToRecv {
		return sendDuration, recvDuration, fmt.Errorf("expected to recv %d bytes, got %d", bytesToRecv, recvd)
	}

	return sendDuration, recvDuration, nil
}

func sendBytes(s io.Writer, bytesToSend uint64) error {
	buf := pool.Get(blockSize)
	defer pool.Put(buf)

	for bytesToSend > 0 {
		toSend := buf
		if bytesToSend < blockSize {
			toSend = buf[:bytesToSend]
		}

		n, err := s.Write(toSend)
		if err != nil {
			return err
		}
		bytesToSend -= uint64(n)
	}
	return nil
}

func drainStream(s io.Reader) (uint64, error) {
	var recvd int64
	recvd, err := io.Copy(io.Discard, s)
	if err != nil && err != io.EOF {
		return uint64(recvd), err
	}
	return uint64(recvd), nil
}
