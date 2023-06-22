package main

import (
	"encoding/binary"
	"io/ioutil"
	"testing"
	"testing/quick"
)

func TestNewRequestReaderSmallP(t *testing.T) {
	reader := newRequestReader(0, 0)
	reader.Read([]byte{})
}

func TestNewRequestReader(t *testing.T) {
	f := func(downloadBytes uint64, uploadBytes uint64) bool {
		const MaxUploadBytes = 64 * 1024 * 1024 // 64 megabytes

		// Skip if uploadBytes is too large
		if uploadBytes > MaxUploadBytes {
			return true
		}

		// Create a new reader
		r := newRequestReader(downloadBytes, uploadBytes)

		// Read everything from the reader
		data, err := ioutil.ReadAll(r)
		if err != nil {
			t.Fatalf("Failed to read from the reader: %v", err)
		}

		// The length of data should be 8 (for downloadBytes) + uploadBytes
		if len(data) != int(8+uploadBytes) {
			return false
		}

		// The first 8 bytes should represent downloadBytes
		readDownloadBytes := binary.BigEndian.Uint64(data[:8])
		if readDownloadBytes != downloadBytes {
			return false
		}

		// The rest of the bytes should all be zero
		for i := 8; i < len(data); i++ {
			if data[i] != 0 {
				return false
			}
		}

		return true
	}

	if err := quick.Check(f, nil); err != nil {
		t.Error(err)
	}
}
