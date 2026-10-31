// Rotates a JPEG by rewriting its EXIF orientation tag in place: no decode,
// no re-encode, so a landscape shot is saved instantly at full quality.
import 'dart:typed_data';

/// Clockwise display rotation (degrees) for the non-mirrored EXIF values.
const _cwByValue = {1: 0, 6: 90, 3: 180, 8: 270};
const _valueByCw = {0: 1, 90: 6, 180: 3, 270: 8};

/// Returns a copy of [jpeg] whose EXIF orientation is turned like
/// `copyRotate(angle: -90 * quarterTurns)` would turn the displayed photo
/// (1 = phone top to the left → rotate counter-clockwise). Returns null when
/// there is no usable orientation tag (no EXIF, mirrored value, malformed),
/// so the caller can fall back to pixel rotation.
Uint8List? rotateExifOrientation(Uint8List jpeg, int quarterTurns) {
  if (quarterTurns == 0) return Uint8List.fromList(jpeg);
  final at = _orientationOffset(jpeg);
  if (at == null) return null;
  final (offset, littleEndian) = at;
  final data = ByteData.sublistView(jpeg);
  final current = data.getUint16(
    offset,
    littleEndian ? Endian.little : Endian.big,
  );
  final cw = _cwByValue[current];
  if (cw == null) return null;
  final next = _valueByCw[((cw - 90 * quarterTurns) % 360 + 360) % 360]!;
  final out = Uint8List.fromList(jpeg);
  ByteData.sublistView(
    out,
  ).setUint16(offset, next, littleEndian ? Endian.little : Endian.big);
  return out;
}

/// Byte offset of the orientation value (tag 0x0112 in IFD0) and the TIFF
/// byte order, or null.
(int, bool)? _orientationOffset(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    if (marker == 0xDA || marker == 0xD9) return null; // image data / end
    final length = (b[i + 2] << 8) | b[i + 3];
    final segment = i + 4;
    if (marker == 0xE1 &&
        segment + 14 <= b.length &&
        b[segment] == 0x45 && // "Exif\0\0"
        b[segment + 1] == 0x78 &&
        b[segment + 2] == 0x69 &&
        b[segment + 3] == 0x66 &&
        b[segment + 4] == 0 &&
        b[segment + 5] == 0) {
      final tiff = segment + 6;
      final little = b[tiff] == 0x49 && b[tiff + 1] == 0x49; // "II"
      final big = b[tiff] == 0x4D && b[tiff + 1] == 0x4D; // "MM"
      if (!little && !big) return null;
      final endian = little ? Endian.little : Endian.big;
      final data = ByteData.sublistView(b);
      final ifd0 = tiff + data.getUint32(tiff + 4, endian);
      if (ifd0 + 2 > b.length) return null;
      final count = data.getUint16(ifd0, endian);
      for (var e = 0; e < count; e++) {
        final entry = ifd0 + 2 + e * 12;
        if (entry + 12 > b.length) return null;
        if (data.getUint16(entry, endian) == 0x0112) {
          return (entry + 8, little);
        }
      }
      return null;
    }
    i = segment + length - 2;
  }
  return null;
}
