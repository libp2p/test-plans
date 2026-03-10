package main

import (
	"encoding/binary"
	"testing"
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
