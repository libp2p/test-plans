use libp2p_gossipsub::partial_messages::{Metadata, Partial, PartialAction, PartialError};

/// A fixed-size bitmap composed of `TOTAL_FIELDS` fields,
/// each field storing `FIELD_SIZE` bytes (i.e., `FIELD_SIZE * 8` bits).
#[derive(Debug, Clone)]
pub(crate) struct Bitmap {
    fields: [[u8; 1024]; 8],
    set: u8,
    group_id: [u8; 8],
}

impl Bitmap {
    pub(crate) fn new(group_id: [u8; 8]) -> Self {
        Self {
            fields: [[0; 1024]; 8],
            set: 0,
            group_id,
        }
    }
    pub(crate) fn fill_parts(&mut self, metadata: u8) {
        let mut parts = [[0u8; 1024]; 8];

        // Convert group_id to u64 using big-endian
        let start = u64::from_be_bytes(self.group_id);
        self.set |= metadata;

        for (i, p) in parts.iter_mut().enumerate() {
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

    pub(crate) fn extend_from_encoded_partial_message(
        &mut self,
        data: &[u8],
    ) -> Result<(), PartialError> {
        if data.len() < 1 + self.group_id.len() {
            return Err(PartialError::InvalidFormat);
        }

        let bitmap = data[0];
        let data = &data[1..];
        let (data, group_id) = data.split_at(data.len() - self.group_id.len());
        if group_id != self.group_id {
            return Err(PartialError::WrongGroup {
                received: group_id.to_vec(),
            });
        }

        if data.len() % 1024 != 0 {
            return Err(PartialError::InvalidFormat);
        }

        let mut offset = 0;
        for (i, field) in self.fields.iter_mut().enumerate() {
            if (bitmap >> i) & 1 == 0 {
                continue;
            }

            if (self.set >> i) & 1 == 1 {
                continue; // we already ahve this
            }

            if offset + 1024 > data.len() {
                return Err(PartialError::InvalidFormat);
            }

            self.set |= 1 << i;
            field.copy_from_slice(&data[offset..offset + 1024]);
            offset += 1024;
        }

        Ok(())
    }
}

// type PeerBitmap = [u8; 1];
#[derive(Debug)]
struct PeerBitmap {
    bitmap: [u8; 1],
}

impl Metadata for PeerBitmap {
    fn as_slice(&self) -> &[u8] {
        self.bitmap.as_slice()
    }

    fn update(&mut self, data: &[u8]) -> Result<bool, PartialError> {
        if data.len() != 1 {
            return Err(PartialError::InvalidFormat);
        }

        let before = self.bitmap[0];
        self.bitmap[0] |= data[0];
        Ok(self.bitmap[0] != before)
    }
}

impl Partial for Bitmap {
    fn group_id(&self) -> Vec<u8> {
        self.group_id.to_vec()
    }

    fn metadata(&self) -> Vec<u8> {
        [self.set; 1].to_vec()
    }

    fn partial_action_from_metadata(
        &self,
        _peer_id: libp2p::PeerId,
        metadata: Option<&[u8]>,
    ) -> Result<PartialAction, PartialError> {
        let metadata = metadata.unwrap_or(&[0u8]);

        if metadata.len() != 1 {
            return Err(PartialError::InvalidFormat);
        }

        let bitmap = metadata[0];
        let mut response_bitmap: u8 = 0;

        // Estimate output size: 1 byte header + FIELD_SIZE * num parts + group_id
        let part_count = bitmap.count_ones() as usize;
        let mut data = Vec::with_capacity(1 + 1024 * part_count + self.group_id.len());

        let mut peer_has_useful_data = false;
        data.push(0);

        for (i, field) in self.fields.iter().enumerate() {
            if (bitmap >> i) & 1 != 0 {
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
            return Ok(PartialAction {
                need: peer_has_useful_data,
                send: None,
            });
        }

        // Set the correct bitmap in the first byte
        data[0] = response_bitmap;
        data.extend_from_slice(&self.group_id);
        let bitmap = PeerBitmap {
            bitmap: [metadata[0] | response_bitmap],
        };

        Ok(PartialAction {
            need: peer_has_useful_data,
            send: Some((data, Box::new(bitmap))),
        })
    }
}
