package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"math/bits"

	partialmessages "github.com/libp2p/go-libp2p-pubsub/partialmessages"
	"github.com/libp2p/go-libp2p/core/peer"
)

const partLen = 1024

type PartialMessage struct {
	groupID [8]byte
	parts   [8][]byte // each part is partLen sized or nil if empty
}

// FillParts is used to initialize this PartialMessage for testing by filling in
// the parts it should have. The algorithm is simple:
// - treat the groupID as our starting uint64 number BigEndian
// - every part is viewed as 128 uint64s BigEndian.
// - We count up uint64s starting from the group ID == part[0][0:8] until part[7][1016:1024] == groupID + 1024-1
func (p *PartialMessage) FillParts(bitmap byte) error {
	start := binary.BigEndian.Uint64(p.groupID[:])
	for i := range p.parts {
		if bitmap&(1<<i) == 0 {
			continue
		}
		counter := start + uint64(i)*partLen/8
		for j := range partLen / 8 {
			p.parts[i] = make([]byte, partLen)
			binary.BigEndian.PutUint64(p.parts[i][j*8:], counter)
			counter++
		}
	}
	return nil
}

// AvailableParts implements partialmessages.PartialMessage.
func (p *PartialMessage) AvailableParts() ([]byte, error) {
	out := []byte{0}
	for i := range p.parts {
		if len(p.parts[i]) > 0 {
			out[0] |= 1 << i
		}
	}
	return out, nil
}

// GroupID implements partialmessages.PartialMessage.
func (p *PartialMessage) GroupID() []byte {
	return p.groupID[:]
}

// MissingParts implements partialmessages.PartialMessage.
func (p *PartialMessage) MissingParts() ([]byte, error) {
	b, _ := p.AvailableParts()
	b[0] = ^b[0]
	if b[0] == 0 {
		return nil, nil
	}
	return b, nil
}

func (p *PartialMessage) Extend(data []byte) error {
	if len(data) < 1+len(p.groupID) {
		return errors.New("invalid data length")
	}
	partBitmap := data[0]
	data = data[1:]

	groupID := data[len(data)-len(p.groupID):]
	data = data[:len(data)-len(p.groupID)]
	if !bytes.Equal(p.groupID[:], groupID) {
		return errors.New("invalid group ID")
	}
	if len(data)%partLen != 0 {
		return errors.New("invalid data length")
	}

	for i := range p.parts {
		if len(data) == 0 {
			break
		}
		if partBitmap&(1<<i) == 0 {
			// this part is not present
			continue
		}
		if len(p.parts[i]) != 0 {
			// Already have this data
			continue
		}
		p.parts[i] = data[:partLen]
		data = data[partLen:]
	}
	return nil
}

// PartialMessageBytesFromMetadata implements partialmessages.PartialMessage.
func (p *PartialMessage) PartialMessageBytesFromMetadata(metadata []byte) ([]byte, []byte, error) {
	if len(metadata) == 0 {
		// Treat this as the same as a request for all parts
		metadata = []byte{0xff}
	}
	if len(metadata) != 1 {
		return nil, nil, errors.New("invalid metadata length")
	}

	out := make([]byte, 0, 1+1024*(bits.OnesCount8(metadata[0]))+len(p.groupID))
	out = append(out, 0) // This byte will contain the parts we are including in the message
	remaining := []byte{metadata[0]}
	for i := range p.parts {
		if metadata[0]&(1<<i) == 0 {
			continue
		}
		if len(p.parts[i]) == 0 {
			continue
		}
		remaining[0] ^= (1 << i)
		out[0] |= 1 << i
		out = append(out, p.parts[i]...)
	}
	if out[0] == 0 {
		return nil, metadata, nil
	}
	out = append(out, p.groupID[:]...)
	if remaining[0] == 0 {
		remaining = nil
	}

	return out, remaining, nil
}

// ShouldRequest implements partialmessages.PartialMessage.
func (p *PartialMessage) ShouldRequest(_ peer.ID, peerHasMetadata []byte) bool {
	wants, _ := p.MissingParts()
	if len(wants) == 0 || len(peerHasMetadata) == 0 {
		return false
	}
	return wants[0]&peerHasMetadata[0] != 0
}

var _ partialmessages.PartialMessage = (*PartialMessage)(nil)
