use libp2p::swarm::ConnectionId;
use waggle::shard::{Action, Error as ShardError, Metadata, Shard};

/// A fixed-size bitmap composed of 8 fields,
/// each field storing 1024 bytes.
#[derive(Debug, Clone)]
pub(crate) struct Bitmap {
    fields: [[u8; 1024]; 8],
    set: u8,
    object_id: [u8; 8],
}

impl Bitmap {
    pub(crate) fn new(object_id: [u8; 8]) -> Self {
        Self {
            fields: [[0; 1024]; 8],
            set: 0,
            object_id,
        }
    }

    pub(crate) fn fill_parts(&mut self, metadata: u8) {
        // Convert object_id to u64 using big-endian
        let start = u64::from_be_bytes(self.object_id);
        self.set |= metadata;

        for (i, p) in self.fields.iter_mut().enumerate() {
            if (metadata & (1 << i)) == 0 {
                continue;
            }

            let mut counter = start + (i as u64) * (1024 / 8);
            let mut part = [0u8; 1024];

            for j in 0..(1024 / 8) {
                let bytes = counter.to_be_bytes();
                let offset = j * 8;
                part[offset..offset + 8].copy_from_slice(&bytes);
                counter += 1;
            }

            *p = part;
        }
    }

    /// Extends this `Bitmap` with the pieces in `data`.
    ///
    /// `data` is the `pieces` payload of an `ObjectPieces` message: a leading
    /// bitmap byte followed by the concatenated 1024 byte piece payloads, in
    /// ascending piece order. Pieces already present are skipped.
    pub(crate) fn extend_from_pieces(&mut self, data: &[u8]) -> Result<(), ShardError> {
        if data.is_empty() {
            return Ok(());
        }
        let bitmap = data[0];
        let data = &data[1..];

        if data.len() % 1024 != 0 {
            return Err(ShardError::InvalidFormat);
        }

        let mut offset = 0;
        for (i, field) in self.fields.iter_mut().enumerate() {
            if (bitmap >> i) & 1 == 0 {
                continue;
            }

            if (self.set >> i) & 1 == 1 {
                offset += 1024; // we already have this
                continue;
            }

            if offset + 1024 > data.len() {
                return Err(ShardError::InvalidFormat);
            }

            self.set |= 1 << i;
            field.copy_from_slice(&data[offset..offset + 1024]);
            offset += 1024;
        }

        Ok(())
    }

    pub(crate) fn complete(&self) -> bool {
        self.set == 0xFF
    }
}

/// The piece metadata: a single byte whose bit `i` is set when the node holds
/// piece `i`.
#[derive(Debug, Clone)]
pub(crate) struct PeerBitmap {
    bitmap: [u8; 1],
}

impl PeerBitmap {
    pub(crate) fn from_slice(data: &[u8]) -> Result<Self, ShardError> {
        if data.len() != 1 {
            return Err(ShardError::InvalidFormat);
        }
        Ok(Self { bitmap: [data[0]] })
    }
}

impl Metadata for PeerBitmap {
    fn as_slice(&self) -> &[u8] {
        self.bitmap.as_slice()
    }

    fn update(&mut self, data: &[u8]) -> Result<bool, ShardError> {
        if data.len() != 1 {
            return Err(ShardError::InvalidFormat);
        }

        let before = self.bitmap[0];
        self.bitmap[0] |= data[0];
        Ok(self.bitmap[0] != before)
    }
}

impl Shard for Bitmap {
    fn object_id(&self) -> Vec<u8> {
        self.object_id.to_vec()
    }

    fn metadata(&self) -> Box<dyn Metadata> {
        Box::new(PeerBitmap {
            bitmap: [self.set; 1],
        })
    }

    fn action_from_metadata(
        &self,
        _peer_id: libp2p::PeerId,
        _connection: ConnectionId,
        metadata: Option<&[u8]>,
    ) -> Result<Action, ShardError> {
        let metadata = match metadata {
            Some(m) => PeerBitmap::from_slice(m)?.bitmap[0],
            None => 0,
        };

        let mut response_bitmap: u8 = 0;
        let part_count = metadata.count_ones() as usize;
        let mut data = Vec::with_capacity(1 + 1024 * part_count);

        let mut peer_has_useful_data = false;
        data.push(0);

        for (i, field) in self.fields.iter().enumerate() {
            if (metadata >> i) & 1 != 0 {
                if !peer_has_useful_data && (self.set >> i) & 1 == 0 {
                    // They have something we don't
                    peer_has_useful_data = true;
                }

                // They have this part
                continue;
            }
            if (self.set >> i) & 1 == 0 {
                continue; // Not available
            }

            response_bitmap |= 1 << i;

            data.extend_from_slice(field);
        }

        if response_bitmap == 0 {
            return Ok(Action {
                need: peer_has_useful_data,
                send: None,
            });
        }

        // Set the correct bitmap in the first byte
        data[0] = response_bitmap;
        let bitmap = PeerBitmap {
            bitmap: [metadata | response_bitmap],
        };

        Ok(Action {
            need: peer_has_useful_data,
            send: Some((data, Box::new(bitmap))),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fill_parts_and_metadata() {
        let mut bitmap = Bitmap::new(0u64.to_be_bytes());
        assert_eq!(bitmap.metadata().as_slice(), &[0]);
        assert!(!bitmap.complete());

        bitmap.fill_parts(0xFF);
        assert_eq!(bitmap.metadata().as_slice(), &[0xFF]);
        assert!(bitmap.complete());

        // First part starts with the big-endian object id.
        let start = u64::from_be_bytes(bitmap.fields[0][0..8].try_into().unwrap());
        assert_eq!(start, 0);
        // Last part ends with start + 8*128 - 1.
        let end = u64::from_be_bytes(bitmap.fields[7][1016..1024].try_into().unwrap());
        assert_eq!(end, 128 * 8 - 1);
    }

    #[test]
    fn test_action_from_metadata_none() {
        let mut bitmap = Bitmap::new(1u64.to_be_bytes());
        bitmap.fill_parts(0b0101);

        // No metadata: peer has nothing. We send all our parts.
        let action = bitmap.action_from_metadata(libp2p::PeerId::random(), ConnectionId::new_unchecked(0), None).unwrap();
        assert!(action.send.is_some());
        let (data, updated) = action.send.unwrap();
        assert_eq!(data[0], 0b0101);
        assert_eq!(data.len(), 1 + 2 * 1024);
        assert_eq!(updated.as_slice(), &[0b0101]);
    }

    #[test]
    fn test_action_from_metadata_partial_overlap() {
        let mut ours = Bitmap::new(1u64.to_be_bytes());
        ours.fill_parts(0b0101);
        let mut theirs = Bitmap::new(1u64.to_be_bytes());
        theirs.fill_parts(0b0011);

        let action = ours
            .action_from_metadata(
                libp2p::PeerId::random(),
                ConnectionId::new_unchecked(0),
                Some(theirs.metadata().as_slice()),
            )
            .unwrap();
        assert!(action.need); // They have piece 0 which we don't.
        let (data, updated) = action.send.unwrap();
        // We send the piece they're missing: piece 2.
        assert_eq!(data[0], 0b0100);
        assert_eq!(data.len(), 1 + 1024);
        assert_eq!(updated.as_slice(), &[0b0111]);
    }

    #[test]
    fn test_extend_from_pieces() {
        let mut bitmap = Bitmap::new(2u64.to_be_bytes());
        bitmap.fill_parts(0b0001);

        let mut other = Bitmap::new(2u64.to_be_bytes());
        other.fill_parts(0b1010);

        // The pieces payload built by `other` for `bitmap`.
        let action = other
            .action_from_metadata(
                libp2p::PeerId::random(),
                ConnectionId::new_unchecked(0),
                Some(bitmap.metadata().as_slice()),
            )
            .unwrap();
        let (data, _) = action.send.unwrap();

        bitmap.extend_from_pieces(&data).unwrap();
        assert_eq!(bitmap.metadata().as_slice(), &[0b1011]);
    }

    #[test]
    fn test_extend_from_pieces_skips_duplicates() {
        let mut bitmap = Bitmap::new(3u64.to_be_bytes());
        bitmap.fill_parts(0xFF);
        let original = bitmap.clone();

        // A payload that redundantly includes parts we already have: bit i set
        // for every part and every part payload present. Extension must skip
        // the ones we hold and leave the metadata unchanged.
        let mut data = vec![0xFF];
        let mut other = Bitmap::new(3u64.to_be_bytes());
        other.fill_parts(0xFF);
        for field in other.fields.iter() {
            data.extend_from_slice(field);
        }
        bitmap.extend_from_pieces(&data).unwrap();
        assert_eq!(bitmap.metadata().as_slice(), original.metadata().as_slice());
    }

    #[test]
    fn test_extend_from_pieces_invalid_length() {
        let mut bitmap = Bitmap::new(4u64.to_be_bytes());
        let err = bitmap.extend_from_pieces(&[0b1, 0, 1, 2]).unwrap_err();
        assert_eq!(err, ShardError::InvalidFormat);
    }
}