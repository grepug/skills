// Container inspection adapted from Tell; no application dependencies.
export function inspectGeneratedImage(input) {
  if (input.byteLength > 50 * 1024 * 1024)
    throw new Error('image_too_large');
  const bytes = Buffer.from(input.buffer, input.byteOffset, input.byteLength);
  if (completePng(bytes))
    return {
      bytes,
      contentType: 'image/png',
      width: bytes.readUInt32BE(16),
      height: bytes.readUInt32BE(20),
    };
  if (completeJpeg(bytes)) {
    let offset = 2;
    while (offset + 4 < bytes.length) {
      if (bytes[offset++] !== 0xff) break;
      while (bytes[offset] === 0xff) offset++;
      const marker = bytes[offset++];
      const length = bytes.readUInt16BE(offset);
      if (
        marker >= 0xc0 &&
        marker <= 0xcf &&
        ![0xc4, 0xc8, 0xcc].includes(marker)
      )
        return {
          bytes,
          contentType: 'image/jpeg',
          width: bytes.readUInt16BE(offset + 5),
          height: bytes.readUInt16BE(offset + 3),
        };
      offset += length;
    }
  }
  if (completeWebp(bytes)) {
    let offset = 12;
    while (offset + 8 <= bytes.length) {
      const kind = bytes.toString('ascii', offset, offset + 4);
      const start = offset + 8;
      if (kind === 'VP8 ')
        return {
          bytes,
          contentType: 'image/webp',
          width: bytes.readUInt16LE(start + 6) & 0x3fff,
          height: bytes.readUInt16LE(start + 8) & 0x3fff,
        };
      if (kind === 'VP8L') {
        const packed = bytes.readUInt32LE(start + 1);
        return {
          bytes,
          contentType: 'image/webp',
          width: (packed & 0x3fff) + 1,
          height: ((packed >>> 14) & 0x3fff) + 1,
        };
      }
      const length = bytes.readUInt32LE(offset + 4);
      offset = start + length + (length % 2);
    }
  }
  throw new Error('invalid_image');
}

// Structural checks reject missing/truncated containers without expanding compressed
// pixel data. They intentionally do not certify CRCs or the decodability of the bitstream.
function completePng(bytes) {
  if (
    !bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
  )
    return false;
  let offset = 8;
  let imageBytes = 0;
  while (offset + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(offset);
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    const next = offset + 12 + length;
    if (next > bytes.length) return false;
    if (offset === 8) {
      if (
        type !== 'IHDR' ||
        length !== 13 ||
        !bytes.readUInt32BE(offset + 8) ||
        !bytes.readUInt32BE(offset + 12)
      )
        return false;
    } else if (type === 'IHDR') return false;
    if (type === 'IDAT') imageBytes += length;
    if (type === 'IEND')
      return length === 0 && imageBytes > 0 && next === bytes.length;
    offset = next;
  }
  return false;
}

function completeWebp(bytes) {
  if (
    bytes.length < 20 ||
    bytes.toString('ascii', 0, 4) !== 'RIFF' ||
    bytes.toString('ascii', 8, 12) !== 'WEBP' ||
    bytes.readUInt32LE(4) + 8 !== bytes.length
  )
    return false;
  let offset = 12;
  let hasImage = false;
  while (offset + 8 <= bytes.length) {
    const type = bytes.toString('ascii', offset, offset + 4);
    const length = bytes.readUInt32LE(offset + 4);
    const start = offset + 8;
    const next = start + length + (length % 2);
    if (next > bytes.length) return false;
    if (type === 'VP8 ') {
      if (
        length <= 10 ||
        (bytes[start] & 1) !== 0 ||
        bytes.toString('hex', start + 3, start + 6) !== '9d012a' ||
        !(bytes.readUInt16LE(start + 6) & 0x3fff) ||
        !(bytes.readUInt16LE(start + 8) & 0x3fff)
      )
        return false;
      hasImage = true;
    } else if (type === 'VP8L') {
      if (length <= 5 || bytes[start] !== 0x2f) return false;
      hasImage = true;
    } else if (type === 'VP8X' && length !== 10) return false;
    offset = next;
  }
  return hasImage && offset === bytes.length;
}

function completeJpeg(bytes) {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return false;
  let offset = 2;
  let frame = false;
  let scan = false;
  let inScan = false;
  let scanBytes = false;
  while (offset < bytes.length) {
    if (inScan) {
      const marker = bytes.indexOf(0xff, offset);
      if (marker < 0) return false;
      scanBytes ||= marker > offset;
      offset = marker;
    }
    if (bytes[offset++] !== 0xff) return false;
    while (bytes[offset] === 0xff) offset++;
    const marker = bytes[offset++];
    if (marker === undefined) return false;
    if (inScan && (marker === 0 || (marker >= 0xd0 && marker <= 0xd7))) {
      scanBytes ||= marker === 0;
      continue;
    }
    if (inScan && !scanBytes) return false;
    inScan = false;
    if (marker === 0xd9)
      return frame && scan && scanBytes && offset === bytes.length;
    if (marker === 0 || marker === 0xd8 || offset + 2 > bytes.length)
      return false;
    const length = bytes.readUInt16BE(offset);
    if (length < 2 || offset + length > bytes.length) return false;
    if (
      marker >= 0xc0 &&
      marker <= 0xcf &&
      ![0xc4, 0xc8, 0xcc].includes(marker)
    ) {
      if (
        length < 11 ||
        length !== 8 + 3 * bytes[offset + 7] ||
        !bytes.readUInt16BE(offset + 3) ||
        !bytes.readUInt16BE(offset + 5)
      )
        return false;
      frame = true;
    }
    if (marker === 0xda) {
      if (!frame || length < 8 || length !== 6 + 2 * bytes[offset + 2])
        return false;
      scan = true;
      inScan = true;
      scanBytes = false;
    }
    offset += length;
  }
  return false;
}
