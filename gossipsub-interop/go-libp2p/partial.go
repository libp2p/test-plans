package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"iter"
	"maps"
	"math/bits"

	"github.com/libp2p/go-libp2p-pubsub/partialmessages"
	"github.com/libp2p/go-libp2p/core/peer"
)

const partLen = 1024

type peerState struct {
	hasReceivedInitialPartsMetadata bool
	recvdPartsMetadata              byte
	hasSentInitialPartsMetadata     bool
	sentPartsMetadata               byte
}

type PartialMessage struct {
	groupID [8]byte
	parts   [8][]byte // each part is partLen sized or nil if empty

	// peersToPublishTo overrides who we publish to. If unset publishes to
	// peers gossipsub is tracking.
	peersToPublishTo iter.Seq[peer.ID]
}

func (p *PartialMessage) PartsMetadata() byte {
	var out byte
	for i := range p.parts {
		if len(p.parts[i]) > 0 {
			out |= 1 << i
		}
	}
	return out
}

func (p *PartialMessage) complete() bool {
	for i := range p.parts {
		if len(p.parts[i]) == 0 {
			return false
		}
	}
	return true
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
func (p *PartialMessage) PartialMessageBytes(peerParts byte) ([]byte, error) {
	out := make([]byte, 0, 1+1024*(bits.OnesCount8(peerParts))+len(p.groupID))
	out = append(out, 0) // This byte will contain the parts we are including in the message
	for i, a := range p.parts {
		if peerParts&(1<<i) != 0 {
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

func (p *PartialMessage) PublishActions(peerStates map[peer.ID]peerState, peerRequestsPartial func(peer.ID) bool) iter.Seq2[peer.ID, partialmessages.PublishAction] {
	return func(yield func(peer.ID, partialmessages.PublishAction) bool) {
		peersToPublishTo := p.peersToPublishTo
		if peersToPublishTo == nil {
			peersToPublishTo = maps.Keys(peerStates)
		}

		for peer := range peersToPublishTo {
			fmt.Println("xxxxxxxxpublishing to", peer)
			pState := peerStates[peer]
			myParts := p.PartsMetadata()
			var action partialmessages.PublishAction
			fmt.Println("peer state", pState, peerRequestsPartial(peer), (myParts & ^pState.recvdPartsMetadata))
			if peerRequestsPartial(peer) && pState.hasReceivedInitialPartsMetadata && (myParts & ^pState.recvdPartsMetadata) != 0 {
				action.EncodedPartialMessage, action.Err = p.PartialMessageBytes(pState.recvdPartsMetadata)
				fmt.Println("action", action)
				if action.Err != nil {
					if !yield(peer, action) {
						return
					}
					continue
				}
				// They can infer we have these parts from the message we are sending
				pState.sentPartsMetadata |= myParts
				// We can infer they have these parts from the message we are sending
				pState.recvdPartsMetadata |= myParts
			}
			if !pState.hasSentInitialPartsMetadata || (myParts & ^pState.sentPartsMetadata) != 0 {
				pState.hasSentInitialPartsMetadata = true
				// We are checking if myParts is not a subset of
				// sentPartsMetadata. If it isn't we should send them an update.
				pState.sentPartsMetadata |= myParts
				action.EncodedPartsMetadata = []byte{pState.sentPartsMetadata}
			}

			// Persist our state update
			peerStates[peer] = pState
			if !yield(peer, action) {
				return
			}
		}
	}
}

var _ partialmessages.PublishActionsFn[peerState] = (*PartialMessage)(nil).PublishActions
