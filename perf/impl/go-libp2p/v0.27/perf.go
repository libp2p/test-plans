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
	u64Buf := make([]byte, 8)
	_, err := io.ReadFull(s, u64Buf)
	if err != nil {
		log.Errorw("err", err)
		s.Reset()
		return
	}

	bytesToSend := binary.BigEndian.Uint64(u64Buf)

	_, err = p.drainStream(context.Background(), s)
	if err != nil {
		log.Errorw("err", err)
		s.Reset()
		return
	}

	err = p.sendBytes(context.Background(), s, bytesToSend)
	if err != nil {
		log.Errorw("err", err)
		s.Reset()
		return
	}

}

func (ps *PerfService) sendBytes(ctx context.Context, s network.Stream, bytesToSend uint64) error {
	buf := pool.Get(BlockSize)
	defer pool.Put(buf)

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

func (ps *PerfService) drainStream(ctx context.Context, s network.Stream) (uint64, error) {
	var recvd int64
	recvd, err := io.Copy(io.Discard, s)
	if err != nil && err != io.EOF {
		s.Reset()
		return uint64(recvd), err
	}
	return uint64(recvd), nil
}

func (ps *PerfService) RunPerf(ctx context.Context, p peer.ID, bytesToSend uint64, bytesToRecv uint64) (time.Duration, time.Duration, error) {
	// Use ps.Host.Network().NewStream() instead of ps.Host.NewStream() to
	// skip waiting for identify protocol to finish.
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

	sizeBuf := make([]byte, 8)
	binary.BigEndian.PutUint64(sizeBuf, bytesToRecv)

	_, err = s.Write(sizeBuf)
	if err != nil {
		return 0, 0, err
	}

	sendStart := time.Now()
	err = ps.sendBytes(ctx, s, bytesToSend)
	if err != nil {
		return 0, 0, err
	}
	sendDuration := time.Since(sendStart)

	recvStart := time.Now()
	recvd, err := ps.drainStream(ctx, s)
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
