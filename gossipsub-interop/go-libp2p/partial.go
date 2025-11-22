package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"math/bits"
	"slices"

	"github.com/libp2p/go-libp2p-pubsub/partialmessages"
)

const partLen = 1024

type PartialMessage struct {
	groupID [8]byte
	parts   [8][]byte // each part is partLen sized or nil if empty
}

// PartsMetadata implements partialmessages.PartialMessage.
func (p *PartialMessage) PartsMetadata() partialmessages.PartsMetadata {
	out := partialmessages.PartsMetadata{0}
	for i := range p.parts {
		if len(p.parts[i]) > 0 {
			out[0] |= 1 << i
		}
	}
	return out
}

func MergeMetadata(_topic string, left, right partialmessages.PartsMetadata) partialmessages.PartsMetadata {
	// by convention let the left be the larger one
	if len(right) > len(left) {
		left, right = right, left
	}
	out := slices.Clone(left)
	for i := range right {
		out[i] |= right[i]
	}
	return out
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

// GroupID implements partialmessages.PartialMessage.
func (p *PartialMessage) GroupID() []byte {
	return p.groupID[:]
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

// PartialMessageBytes implements partialmessages.PartialMessage.
func (p *PartialMessage) PartialMessageBytes(metadata partialmessages.PartsMetadata) ([]byte, error) {
	if len(metadata) != 1 {
		return nil, errors.New("invalid metadata length")
	}

	out := make([]byte, 0, 1+1024*(bits.OnesCount8(metadata[0]))+len(p.groupID))
	out = append(out, 0) // This byte will contain the parts we are including in the message
	for i, a := range p.parts {
		if metadata[0]&(1<<i) != 0 {
			// They already have this part
			continue
		}
		if len(a) == 0 {
			continue
		}
		out[0] |= 1 << i
		out = append(out, a...)
	}
	if out[0] == 0 {
		return nil, nil
	}
	out = append(out, p.groupID[:]...)
	return out, nil
}

var _ partialmessages.Message = (*PartialMessage)(nil)
