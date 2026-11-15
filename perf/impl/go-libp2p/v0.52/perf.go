package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
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

func (ps *PerfService) RunPerf(ctx context.Context, p peer.ID, bytesToSend uint64, bytesToRecv uint64) error {
	s, err := ps.Host.NewStream(ctx, p, ID)
	if err != nil {
		return err
	}

	sizeBuf := make([]byte, 8)
	binary.BigEndian.PutUint64(sizeBuf, bytesToRecv)

	_, err = s.Write(sizeBuf)
	if err != nil {
		return err
	}

	if err := sendBytes(s, bytesToSend); err != nil {
		return err
	}
	s.CloseWrite()

	recvd, err := drainStream(s)
	if err != nil {
		return err
	}

	if recvd != bytesToRecv {
		return fmt.Errorf("expected to recv %d bytes, got %d", bytesToRecv, recvd)
	}

	return nil
}

func sendBytes(s io.Writer, bytesToSend uint64) error {
	buf := pool.Get(blockSize)
	defer pool.Put(buf)

	lastReportTime := time.Now()
	lastReportWrite := uint64(0)

	for bytesToSend > 0 {
		now := time.Now()
		if now.Sub(lastReportTime) >= time.Second {
			jsonB, err := json.Marshal(Result{
				TimeSeconds: now.Sub(lastReportTime).Seconds(),
				UploadBytes: lastReportWrite,
				Type:        "intermediary",
			})
			if err != nil {
				log.Fatalf("failed to marshal perf result: %s", err)
			}
			fmt.Println(string(jsonB))

			lastReportTime = now
			lastReportWrite = 0
		}

		toSend := buf
		if bytesToSend < blockSize {
			toSend = buf[:bytesToSend]
		}

		n, err := s.Write(toSend)
		if err != nil {
			return err
		}
		bytesToSend -= uint64(n)
		lastReportWrite += uint64(n)
	}
	return nil
}

func drainStream(s io.Reader) (uint64, error) {
	var recvd int64
	recvd, err := io.Copy(io.Discard, &reportingReader{orig: s, LastReportTime: time.Now()})
	if err != nil && err != io.EOF {
		return uint64(recvd), err
	}
	return uint64(recvd), nil
}

type reportingReader struct {
	orig           io.Reader
	LastReportTime time.Time
	lastReportRead uint64
}

var _ io.Reader = &reportingReader{}

func (r *reportingReader) Read(b []byte) (int, error) {
	n, err := r.orig.Read(b)
	r.lastReportRead += uint64(n)

	now := time.Now()
	if now.Sub(r.LastReportTime) >= time.Second {
		result := Result{
			TimeSeconds:   now.Sub(r.LastReportTime).Seconds(),
			Type:          "intermediary",
			DownloadBytes: r.lastReportRead,
		}

		jsonB, err := json.Marshal(result)
		if err != nil {
			log.Fatalf("failed to marshal perf result: %s", err)
		}
		fmt.Println(string(jsonB))

		r.LastReportTime = now
		r.lastReportRead = 0
	}

	return n, err
}
