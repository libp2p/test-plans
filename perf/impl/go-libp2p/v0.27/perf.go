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
	msmux "github.com/multiformats/go-multistream"
)

var log = logging.Logger("perf")

const (
	BlockSize = 64 << 10

	ID = "/perf/1.0.0"
)

type PerfService struct {
	Host host.Host
}

func NewPerfService(h host.Host) *PerfService {
	ps := &PerfService{h}
	h.SetStreamHandler(ID, ps.PerfHandler)
	return ps
}

func (p *PerfService) PerfHandler(s network.Stream) {
	buf := pool.Get(BlockSize)
	defer pool.Put(buf)

	u64Buf := make([]byte, 8)
	_, err := io.ReadFull(s, u64Buf)
	if err != nil {
		log.Errorw("err", err)
		s.Reset()
		return
	}

	bytesToSend := binary.BigEndian.Uint64(u64Buf)

	_, err = p.drainStream(context.Background(), s, buf)
	if err != nil {
		log.Errorw("err", err)
		s.Reset()
		return
	}

	err = p.sendBytes(context.Background(), s, bytesToSend, buf)
	if err != nil {
		log.Errorw("err", err)
		s.Reset()
		return
	}

}

func (ps *PerfService) sendBytes(ctx context.Context, s network.Stream, bytesToSend uint64, buf []byte) error {
	for bytesToSend > 0 {
		toSend := buf
		if bytesToSend < BlockSize {
			toSend = buf[:bytesToSend]
		}

		n, err := s.Write(toSend)
		if err != nil {
			return err
		}
		bytesToSend -= uint64(n)
	}
	s.CloseWrite()

	return nil
}

func (ps *PerfService) drainStream(ctx context.Context, s network.Stream, buf []byte) (uint64, error) {
	var recvd uint64
	for {
		n, err := s.Read(buf)
		recvd += uint64(n)
		if err == io.EOF {
			return recvd, nil
		} else if err != nil {
			s.Reset()
			return recvd, err
		}
	}
}

func (ps *PerfService) RunPerf(ctx context.Context, p peer.ID, bytesToSend uint64, bytesToRecv uint64) (time.Duration, time.Duration, error) {
	s, err := ps.Host.Network().NewStream(network.WithNoDial(ctx, "already dialed"), p)
	if err != nil {
		return 0, 0, err
	}
	s.SetProtocol(ID)
	lzcon := msmux.NewMSSelect(s, ID)
	s = &streamWrapper{
		Stream: s,
		rw:     lzcon,
	}

	// s, err := ps.Host.NewStream(ctx, p, ID)
	// if err != nil {
	// 	return 0, 0, err
	// }

	buf := pool.Get(BlockSize)
	defer pool.Put(buf)

	sizeBuf := make([]byte, 8)
	binary.BigEndian.PutUint64(sizeBuf, bytesToRecv)

	_, err = s.Write(sizeBuf)
	if err != nil {
		return 0, 0, err
	}

	sendStart := time.Now()
	err = ps.sendBytes(ctx, s, bytesToSend, buf)
	if err != nil {
		return 0, 0, err
	}
	sendDuration := time.Since(sendStart)

	recvStart := time.Now()
	recvd, err := ps.drainStream(ctx, s, buf)
	if err != nil {
		return sendDuration, 0, err
	}
	recvDuration := time.Since(recvStart)

	if recvd != bytesToRecv {
		return sendDuration, recvDuration, fmt.Errorf("expected to recv %d bytes, got %d", bytesToRecv, recvd)
	}

	return sendDuration, recvDuration, nil
}

type streamWrapper struct {
	network.Stream
	rw io.ReadWriteCloser
}

func (s *streamWrapper) Read(b []byte) (int, error) {
	return s.rw.Read(b)
}

func (s *streamWrapper) Write(b []byte) (int, error) {
	return s.rw.Write(b)
}

func (s *streamWrapper) Close() error {
	return s.rw.Close()
}

func (s *streamWrapper) CloseWrite() error {
	// Flush the handshake before closing, but ignore the error. The other
	// end may have closed their side for reading.
	//
	// If something is wrong with the stream, the user will get on error on
	// read instead.
	if flusher, ok := s.rw.(interface{ Flush() error }); ok {
		_ = flusher.Flush()
	}
	return s.Stream.CloseWrite()
}
