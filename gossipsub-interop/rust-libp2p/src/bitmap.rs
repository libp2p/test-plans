use libp2p_gossipsub::{Partial, PartialMessageError};

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
}

impl Partial for Bitmap {
    fn group_id(&self) -> impl AsRef<[u8]> {
        &self.group_id
    }

    fn parts_metadata(&self) -> impl AsRef<[u8]> {
        [self.set; 1]
    }

    fn partial_message_bytes_from_metadata(
        &self,
        metadata: impl AsRef<[u8]>,
    ) -> Result<(impl AsRef<[u8]>, Option<impl AsRef<[u8]>>), PartialMessageError> {
        let mut metadata = metadata.as_ref();
        if metadata.is_empty() {
            metadata = &[0xff];
        }

        if metadata.len() != 1 {
            return Err(PartialMessageError::InvalidFormat);
        }

        let bitmap = metadata[0];
        let mut response_bitmap: u8 = 0;
        let mut remaining = bitmap;

        // Estimate output size: 1 byte header + FIELD_SIZE * num parts + group_id
        let part_count = bitmap.count_ones() as usize;
        let mut data = Vec::with_capacity(1 + 1024 * part_count + self.group_id.len());

        data.push(0);

        for (i, field) in self.fields.iter().enumerate() {
            if (bitmap >> i) & 1 == 0 {
                continue;
            }
            if (self.set >> i) & 1 == 0 {
                continue; // Not available
            }

            response_bitmap |= 1 << i;
            remaining ^= 1 << i;

            data.extend_from_slice(field);
        }

        if response_bitmap == 0 {
            return Ok((Vec::<u8>::new(), Some(vec![bitmap])));
        }

        // Set the correct bitmap in the first byte
        data[0] = response_bitmap;
        data.extend_from_slice(&self.group_id);

        let remaining = if remaining == 0 {
            None
        } else {
            Some(vec![remaining])
        };

        Ok((data, remaining))
    }

    fn extend_from_encoded_partial_message(
        &mut self,
        data: &[u8],
    ) -> Result<(), PartialMessageError> {
        if data.len() < 1 + self.group_id.len() {
            return Err(PartialMessageError::InvalidFormat);
        }

        let bitmap = data[0];
        let data = &data[1..];
        let (data, group_id) = data.split_at(data.len() - self.group_id.len());
        if group_id != self.group_id {
            return Err(PartialMessageError::WrongGroup {
                received: group_id.to_vec(),
            });
        }

        if data.len() % 1024 != 0 {
            return Err(PartialMessageError::InvalidFormat);
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
                return Err(PartialMessageError::InvalidFormat);
            }

            self.set |= 1 << i;
            field.copy_from_slice(&data[offset..offset + 1024]);
            offset += 1024;
        }

        Ok(())
    }
}
