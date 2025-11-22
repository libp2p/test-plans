package main

import (
	"bytes"
	"crypto/rand"
	"encoding/binary"
	"slices"
	"testing"

	partialmessages "github.com/libp2p/go-libp2p-pubsub/partialmessages"
	"github.com/libp2p/go-libp2p/core/peer"
)

func TestFillParts(t *testing.T) {
	empty := PartialMessage{}
	empty.FillParts(0)
	for _, part := range empty.parts {
		if len(part) != 0 {
			t.Fatal("part should be empty")
		}
	}

	full := PartialMessage{}
	full.FillParts(0xff)
	for _, part := range full.parts {
		if len(part) != partLen {
			t.Fatal("part should be partLen bytes")
		}
	}
	if binary.BigEndian.Uint64(full.parts[0]) != 0 {
		t.Fatal("first part should be zero")
	}
	if binary.BigEndian.Uint64(full.parts[7][1016:]) != 128*8-1 {
		t.Fatal("last part should be 128*8-1")
	}

}

type partialInvariantChecker struct {
	GroupID [8]byte
}

// EmptyMessage implements partialmessages.InvariantChecker.
func (p *partialInvariantChecker) EmptyMessage() *PartialMessage {
	return &PartialMessage{
		groupID: p.GroupID,
	}
}

// Equal implements partialmessages.InvariantChecker.
func (p *partialInvariantChecker) Equal(a *PartialMessage, b *PartialMessage) bool {
	if !bytes.Equal(a.groupID[:], b.groupID[:]) {
		return false
	}
	for i := range a.parts {
		if !bytes.Equal(a.parts[i][:], b.parts[i][:]) {
			return false
		}
	}
	return true
}

// ExtendFromBytes implements partialmessages.InvariantChecker.
func (p *partialInvariantChecker) ExtendFromBytes(a *PartialMessage, data []byte) (*PartialMessage, error) {
	err := a.Extend(data)
	if err != nil {
		return nil, err
	}
	return a, nil
}

// FullMessage implements partialmessages.InvariantChecker.
func (p *partialInvariantChecker) FullMessage() (*PartialMessage, error) {
	out := &PartialMessage{
		groupID: p.GroupID,
	}

	out.FillParts(0xff)
	return out, nil
}

// SplitIntoParts implements partialmessages.InvariantChecker.
func (p *partialInvariantChecker) SplitIntoParts(in *PartialMessage) ([]*PartialMessage, error) {
	var out []*PartialMessage
	for i := range in.parts {
		if len(in.parts[i]) == 0 {
			continue
		}
		p := &PartialMessage{groupID: p.GroupID}
		p.parts[i] = slices.Clone(in.parts[i])
		out = append(out, p)
	}
	return out, nil
}

// ShouldRequest implements partialmessages.InvariantChecker.
func (*partialInvariantChecker) ShouldRequest(a *PartialMessage, _ peer.ID, partsMetadata []byte) bool {
	aHas := a.PartsMetadata()[0]
	return len(partsMetadata) == 1 && aHas != partsMetadata[0]
}

func (*partialInvariantChecker) MergePartsMetadata(left, right partialmessages.PartsMetadata) partialmessages.PartsMetadata {
	res := slices.Clone(left)
	if len(res) == 0 {
		return slices.Clone(right)
	}
	if len(right) > 0 {
		res[0] |= right[0]
	}
	return res
}

var _ partialmessages.InvariantChecker[*PartialMessage] = (*partialInvariantChecker)(nil)

func TestPartialMessageInvariants(t *testing.T) {
	var invariantChecker partialInvariantChecker
	rand.Read(invariantChecker.GroupID[:])
	partialmessages.TestPartialMessageInvariants(t, &invariantChecker)
}
